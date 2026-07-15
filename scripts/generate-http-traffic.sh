#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/env.sh
source "${script_dir}/lib/env.sh"

url_template="${HTTP_TRAFFIC_URL_TEMPLATE:?}"
method="GET"
body=""
duration_seconds=1200
rate_per_second=2
concurrency=1
timeout_seconds=5
headers=()

usage() {
  cat <<EOF
usage: scripts/generate-http-traffic.sh [options]

Generate steady HTTP traffic and print success/failure/latency statistics.

Options:
  --url URL             Target URL. Use {id} to inject a generated request id.
                        Default: ${HTTP_TRAFFIC_URL_TEMPLATE}
  --method METHOD      HTTP method. Default: GET
  --body BODY          Request body for POST/PUT/PATCH style requests.
  --header HEADER      Header to pass to curl. May be repeated.
  --duration SECONDS   How long to run. Default: 300
  --rate RPS           Best-effort total request rate. Default: 2
  --concurrency N      Number of worker loops. Default: 1
  --timeout SECONDS    Per-request curl timeout. Default: 5
  -h, --help           Show this help.

Examples:
  scripts/generate-http-traffic.sh --duration 600 --rate 5
  scripts/generate-http-traffic.sh --url http://app.example.test/health --rate 1
  scripts/generate-http-traffic.sh --method POST --url http://api/items --body '{"name":"demo"}' --header 'Content-Type: application/json'
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      url_template="${2:?--url requires a value}"
      shift 2
      ;;
    --method)
      method="${2:?--method requires a value}"
      shift 2
      ;;
    --body)
      body="${2:?--body requires a value}"
      shift 2
      ;;
    --header)
      headers+=("${2:?--header requires a value}")
      shift 2
      ;;
    --duration)
      duration_seconds="${2:?--duration requires a value}"
      shift 2
      ;;
    --rate)
      rate_per_second="${2:?--rate requires a value}"
      shift 2
      ;;
    --concurrency)
      concurrency="${2:?--concurrency requires a value}"
      shift 2
      ;;
    --timeout)
      timeout_seconds="${2:?--timeout requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "${duration_seconds}" in ''|*[!0-9]*) echo "error: --duration must be a positive integer" >&2; exit 1 ;; esac
case "${concurrency}" in ''|*[!0-9]*) echo "error: --concurrency must be a positive integer" >&2; exit 1 ;; esac
if [ "${duration_seconds}" -lt 1 ] || [ "${concurrency}" -lt 1 ]; then
  echo "error: --duration and --concurrency must be greater than zero" >&2
  exit 1
fi
if ! awk -v rate="${rate_per_second}" 'BEGIN { exit !(rate >= 0) }'; then
  echo "error: --rate must be a non-negative number" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

end_epoch=$(( $(date +%s) + duration_seconds ))
sleep_interval="$(awk -v rate="${rate_per_second}" -v workers="${concurrency}" 'BEGIN { if (rate <= 0) print 0; else printf "%.6f", workers / rate }')"

echo "HTTP traffic generation"
echo "  url:         ${url_template}"
echo "  method:      ${method}"
echo "  duration:    ${duration_seconds}s"
echo "  rate:        ${rate_per_second}/s best-effort"
echo "  concurrency: ${concurrency}"
echo "  timeout:     ${timeout_seconds}s"

worker() {
  local worker_id="$1"
  local results_file="${tmp_dir}/worker-${worker_id}.tsv"
  local counter=0

  while [ "$(date +%s)" -lt "${end_epoch}" ]; do
    counter=$((counter + 1))
    local request_id="${worker_id}-$(date +%s%N)-${counter}"
    local url="${url_template//\{id\}/${request_id}}"
    local curl_args=(-sS -o /dev/null -w "%{http_code}\t%{time_total}" --max-time "${timeout_seconds}" -X "${method}")

    for header in "${headers[@]}"; do
      curl_args+=(-H "${header}")
    done
    if [ -n "${body}" ]; then
      curl_args+=(--data "${body}")
    fi

    local output
    if output="$(curl "${curl_args[@]}" "${url}" 2>/dev/null)"; then
      printf '%s\t%s\n' "${output}" "${request_id}" >>"${results_file}"
    else
      printf '000\t%s\t%s\n' "${timeout_seconds}" "${request_id}" >>"${results_file}"
    fi

    if awk -v interval="${sleep_interval}" 'BEGIN { exit !(interval > 0) }'; then
      sleep "${sleep_interval}"
    fi
  done
}

for worker_id in $(seq 1 "${concurrency}"); do
  worker "${worker_id}" &
done
wait

cat "${tmp_dir}"/worker-*.tsv >"${tmp_dir}/results.tsv" 2>/dev/null || true

if [ ! -s "${tmp_dir}/results.tsv" ]; then
  echo "No requests completed."
  exit 1
fi

awk -F '\t' '{ print $2 }' "${tmp_dir}/results.tsv" | sort -n >"${tmp_dir}/latencies.txt"

awk -F '\t' -v "latencies_file=${tmp_dir}/latencies.txt" '
  {
    code = $1 + 0
    latency = $2 + 0
    total++
    sum += latency
    if (total == 1 || latency < min) min = latency
    if (latency > max) max = latency
    if (code >= 200 && code < 400) success++
    else failure++
    status[code]++
  }
  END {
    while ((getline value < latencies_file) > 0) {
      sorted[++count] = value
    }
    close(latencies_file)

    p50_index = int(0.50 * count + 0.999999)
    p95_index = int(0.95 * count + 0.999999)
    p99_index = int(0.99 * count + 0.999999)
    if (p50_index < 1) p50_index = 1
    if (p95_index < 1) p95_index = 1
    if (p99_index < 1) p99_index = 1

    printf "\nSummary\n"
    printf "  requests:     %d\n", total
    printf "  success:      %d\n", success + 0
    printf "  failure:      %d\n", failure + 0
    printf "  failure rate: %.2f%%\n", total ? (failure / total) * 100 : 0
    printf "  latency min:  %.3fs\n", min
    printf "  latency avg:  %.3fs\n", total ? sum / total : 0
    printf "  latency p50:  %.3fs\n", sorted[p50_index]
    printf "  latency p95:  %.3fs\n", sorted[p95_index]
    printf "  latency p99:  %.3fs\n", sorted[p99_index]
    printf "  latency max:  %.3fs\n", max
    printf "\nStatus codes\n"
    for (code in status) {
      printf "  %s: %d\n", code, status[code]
    }
  }
' "${tmp_dir}/results.tsv"
