# Phase walkthrough

This document is the narrative companion to the executable scripts and GitOps
manifests in this repository.

## Phase 0: local clusters

Phase 0 provisions two k3s clusters with Vagrant and libvirt:

- `cluster-a`: `k3s-a-master`, `k3s-a-agent`
- `cluster-b`: `k3s-b-master`, `k3s-b-agent`

Each VM is bridged to the LAN, statically addressed, and sized at 4 vCPU /
6 GB by default. k3s bundled Traefik and ServiceLB are disabled because both
are managed later by Argo CD. Gateway API standard CRDs are installed up front
on both clusters.

## Phase 1: Argo CD bootstrap

Phase 1 installs Argo CD on cluster A using the community Helm chart through
Kustomize:

```bash
./scripts/bootstrap-argocd.sh
```

The bootstrap script is intentionally the only manual install step. It renders
`argocd/`, applies it to cluster A, registers cluster B by applying a generated
Argo CD cluster Secret, then applies the root `bootstrap` Application.

After this point, Argo CD manages itself from Git via:

- `argocd/` — the Helm chart wrapper and values
- `gitops/bootstrap/` — the root project and self-management Application

Cluster credentials are not committed. `scripts/register-cluster-b.sh`
generates and applies them directly.

## Phase 2: cluster ingress and platform networking

Before installing Traefik for real application access, configure local DNS as
documented in `docs/local-dns.md`.

The intended model is:

- MetalLB assigns a stable LoadBalancer IP to Traefik in each cluster.
- Raspberry Pi DNS has wildcard records:
  - `*.a.lab.home -> cluster A Traefik IP`
  - `*.b.lab.home -> cluster B Traefik IP`
- Applications declare hostnames such as `argocd.a.lab.home` or
  `frontend.b.lab.home` through Ingress or HTTPRoute.

That lets the lab stop relying on port-forwarding while keeping DNS setup
simple and reproducible.

Phase 2a installs:

- MetalLB in L2 mode on both clusters
- cluster A pool: `192.168.50.240-192.168.50.244`
- cluster B pool: `192.168.50.245-192.168.50.249`
- Traefik in a dedicated `traefik` namespace on both clusters
- `argocd.a.lab.home` pointing to the Argo CD server through Traefik

k3s ServiceLB must be disabled before this phase. Otherwise k3s' built-in
`svclb-*` controller and MetalLB will both try to satisfy `LoadBalancer`
Services. Re-run the master provisioners after pulling this phase:

```bash
vagrant provision k3s-a-master k3s-b-master
```

The phase has been verified from a clean rebuild:

```bash
vagrant destroy -f
./scripts/up.sh
./scripts/fetch-kubeconfigs.sh
./scripts/bootstrap-argocd.sh
```

Result: all Argo CD Applications are `Synced` / `Healthy`, Traefik receives
`192.168.50.240` in cluster A and `192.168.50.245` in cluster B, and
`http://argocd.a.lab.home` returns HTTP 200.

## Phase 3: observability foundation

Phase 3a puts the shared observability backends in cluster B before workload
migration begins. This keeps telemetry available while cluster A is later
drained or shut down.

Installed on cluster B:

- MinIO, using local-path storage, with `loki-chunks`, `loki-ruler`,
  `loki-admin`, and `tempo-traces` buckets
- Loki, configured to use MinIO object storage
- Tempo, configured to use MinIO object storage and receive OTLP/HTTP traces
- Prometheus, with local-path persistence and remote-write receiver enabled
- Grafana, with provisioned Loki, Prometheus, and Tempo datasources
- Ingress for `grafana.b.lab.home`, `loki.b.lab.home`,
  `prometheus.b.lab.home`, and `tempo.b.lab.home`

Installed on both clusters:

- Grafana Alloy as a DaemonSet
- Pod log collection to Loki
- annotation-based Prometheus scraping to cluster-B Prometheus

This phase is intentionally "prod-shaped" rather than production HA. It uses
real persistent stores and object-storage-backed logs/traces, but the storage is
still local-path and single-replica for lab simplicity.

The current verification state:

```bash
kubectl --context cluster-a -n argocd get applications
kubectl --context cluster-b -n observability get pods,pvc,ingress
kubectl --context cluster-a -n observability get pods
curl -I http://grafana.b.lab.home
curl http://loki.b.lab.home/ready
curl http://prometheus.b.lab.home/-/ready
curl -o /dev/null -s -w '%{http_code}\n' http://tempo.b.lab.home/v1/traces
```

Expected:

- all Argo CD Applications are `Synced` / `Healthy`
- all cluster-B observability pods are Running
- Alloy pods are Running on both clusters
- Grafana returns a login redirect at `http://grafana.b.lab.home`
- Loki and Prometheus readiness endpoints are ready
- Tempo's OTLP/HTTP endpoint returns `405` to GET and accepts POSTed traces
