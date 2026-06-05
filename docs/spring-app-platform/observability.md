# Spring app observability baseline

This lab treats observability as an application platform capability, not as a
one-off migration dashboard. The baseline is intended to work for dozens of
applications that follow the same Kubernetes label, metrics, logs, and tracing
contract.

## Platform components

The observability stack runs in cluster B:

| Component  | Purpose                                      |
| ---------- | -------------------------------------------- |
| Prometheus | Metrics storage and PromQL queries           |
| Loki       | Pod log storage and LogQL queries            |
| Tempo      | Distributed trace storage                    |
| Grafana    | Dashboards and logs/metrics/traces drilldown |
| Alloy      | Log collection and annotated pod scraping    |

Grafana is available at `http://grafana.b.lab.home`. Its datasources are
provisioned with stable UIDs:

| Datasource | UID          |
| ---------- | ------------ |
| Prometheus | `prometheus` |
| Loki       | `loki`       |
| Tempo      | `tempo`      |

## Label contract

Dashboards rely on a small set of stable labels. The Spring Boot Helm chart
applies the Kubernetes app labels to pod templates, and Alloy copies those
labels onto scraped metrics and log streams.

| Label       | Source Kubernetes label                 | Used for                                      |
| ----------- | --------------------------------------- | --------------------------------------------- |
| `cluster`   | Alloy cluster config                    | Separating cluster A, cluster B, and future envs |
| `namespace` | Kubernetes namespace                    | Team/app grouping                             |
| `workload`  | `app.kubernetes.io/name`                | Application or service name                   |
| `component` | `app.kubernetes.io/component`           | API, worker, frontend, etc.                   |
| `part_of`   | `app.kubernetes.io/part-of`             | Product or application family                 |
| `version`   | `app.kubernetes.io/version`             | Metrics-only version grouping                 |
| `pod`       | Kubernetes pod name                     | Pod-level debugging                           |
| `container` | Kubernetes container name               | Container-level debugging                     |

`version` is intentionally not added as a Loki stream label. Versions change on
every rollout and would create unnecessary Loki stream churn. Logs still include
pod/container metadata and application JSON fields for detailed drilldown.

## Metrics contract

Spring services should expose `/actuator/prometheus` and opt into scraping with
pod annotations:

```yaml
prometheus.io/scrape: "true"
prometheus.io/path: /actuator/prometheus
prometheus.io/port: "8080"
```

The Spring reference services publish:

- HTTP server request metrics
- HTTP client request metrics
- JVM memory, GC, thread, and classloader metrics
- process and system metrics
- health and build metadata through Actuator

HTTP histograms are enabled so dashboards can calculate p50/p95/p99 latency:

```properties
management.metrics.distribution.percentiles-histogram.http.server.requests=true
management.metrics.distribution.percentiles-histogram.http.client.requests=true
management.metrics.distribution.minimum-expected-value.http.server.requests=1ms
management.metrics.distribution.maximum-expected-value.http.server.requests=10s
management.metrics.distribution.minimum-expected-value.http.client.requests=1ms
management.metrics.distribution.maximum-expected-value.http.client.requests=10s
```

The expected Prometheus labels for HTTP metrics are:

```text
cluster, namespace, workload, component, part_of, version,
method, uri, status, outcome, exception, error
```

Keep URI labels low-cardinality. Prefer framework-provided route templates such
as `/orders/{id}` over raw paths containing user or entity IDs.

## Logs and traces contract

Applications write JSON logs to stdout. Alloy collects pod logs and sends them
to Loki with the platform labels above. Spring Micrometer Tracing sends OTLP
traces to Tempo and propagates W3C trace context across service calls.

For a normal request, the intended workflow is:

1. Use the dashboard to find a workload with elevated errors or latency.
2. Drill into the service by `cluster`, `namespace`, and `workload`.
3. Inspect logs for the same workload and time range.
4. Use trace IDs from logs, or Tempo search, to inspect the request path.
5. Compare application metrics with Kubernetes pod health and restarts.

## Provisioned dashboards

Grafana dashboards are provisioned by the Grafana sidecar from labeled
ConfigMaps in `gitops/infra/grafana/cluster-b/dashboards`.

| Dashboard | Purpose |
| --------- | ------- |
| Application Fleet Overview | Generic RED/golden-signal view across all app workloads |
| Service Drilldown | Per-service request, latency, JVM, pod, and log drilldown |
| Migration Watch | Focused migration view using the same generic labels |

Dashboard variables are based on the generic label contract:

```text
cluster -> namespace -> workload -> uri
```

The migration dashboard defaults to the current Spring demo pair, but the panels
are intentionally built from generic workload and cluster labels.

## Traffic generation

Use the local traffic generator to create steady signals while observing normal
operation or a migration step:

```bash
scripts/generate-http-traffic.sh --duration 600 --rate 5
```

The default target is:

```text
http://order.a.lab.home/orders/{id}
```

`{id}` is replaced with a generated request ID. In the current Spring demo this
drives the full `client -> order-service -> payment-service` path, so one Order
request should normally produce one Payment request.

The script is generic and can target any HTTP endpoint:

```bash
scripts/generate-http-traffic.sh \
  --url http://some-app.a.lab.home/health \
  --duration 300 \
  --rate 1
```

It prints request totals, success/failure counts, failure rate, and latency
min/avg/p50/p95/p99/max from the local client perspective.

## Onboarding another app

To make another workload show up in the generic dashboards:

1. Apply the Kubernetes app labels:
   - `app.kubernetes.io/name`
   - `app.kubernetes.io/component`
   - `app.kubernetes.io/part-of`
   - `app.kubernetes.io/version`
2. Expose Prometheus metrics on a stable endpoint.
3. Add the `prometheus.io/*` pod annotations.
4. Emit structured logs to stdout.
5. Propagate trace context and export traces to Tempo.
6. Keep metric labels low-cardinality, especially HTTP `uri`.

The vendored `charts/spring-boot` chart handles these settings for the Spring
reference services through per-app `values.yaml` files.

## Migration monitoring workflow

Before each migration step:

1. Start traffic generation.
2. Confirm the fleet dashboard shows stable request rate, low errors, and normal
   p95 latency.
3. Open the Service Drilldown dashboard for the service being moved.
4. Open the Migration Watch dashboard for the workload pair.

During the migration step:

1. Watch request rate split by `cluster` and `workload`.
2. Watch p95 latency and 5xx error rate.
3. Check pod restarts and readiness if latency or errors move.
4. Use logs and traces to determine whether failures are app, mesh, DNS, or
   infrastructure related.

After the step:

1. Keep traffic running long enough to see steady-state behavior.
2. Record whether rates, errors, and latency returned to baseline.
3. Roll forward or roll back based on the same generic signals.
