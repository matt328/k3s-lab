# Phase walkthrough

This document is the narrative companion to the executable scripts and GitOps manifests in this repository.

## Phase 0: local clusters

Phase 0 provisions two k3s clusters with Vagrant and libvirt. The default local footprint is intentionally small:

- `cluster-a`: `k3s-a-server-1`
- `cluster-b`: `k3s-b-server-1`

Each local VM is bridged to the LAN, statically addressed, and sized at 4 vCPU / 4 GB by default. k3s bundled Traefik
and ServiceLB are disabled because both are managed later by Argo CD. Gateway API standard CRDs are installed up front
on both clusters.

For the full migration/observability lab, the Vagrantfile can add remote worker capacity on two physical libvirt hosts:

- `cluster-a`: `k3s-a-worker-1`, `k3s-a-worker-2`
- `cluster-b`: `k3s-b-worker-1`, `k3s-b-worker-2`, `k3s-b-worker-3`

This mode is disabled by default and controlled by `.env.local`. Each remote host must bridge onto the same LAN as the
local host so the remote agents can reach the local masters and advertise normal LAN IPs. Remote agents get
`lab.k3s.io/placement=remote` and `lab.k3s.io/host=<host>` labels for future workload placement.

`HOST_LOCAL_WORKERS_ENABLED=true` can temporarily add `k3s-a-local-worker-1` and `k3s-b-local-worker-1` VMs, but the
normal full-stack shape keeps those off the workstation.

## Phase 1: Argo CD bootstrap

Phase 1 installs Argo CD on cluster A using the community Helm chart through Kustomize:

```bash
./scripts/bootstrap-argocd.sh
```

The bootstrap script is intentionally the only manual install step. It renders `argocd/`, applies it to cluster A,
registers cluster B by applying a generated Argo CD cluster Secret, then applies the root `bootstrap` Application.

After this point, Argo CD manages itself from Git via:

- `argocd/` — the Helm chart wrapper and values
- `gitops/bootstrap/` — the root project and self-management Application
- `gitops/bootstrap/repo-config.env` — the committed repo URL Kustomize injects into Argo CD resources
- `gitops/components/lab-network/lab-network.env` — the committed GitOps-facing network/DNS/registry defaults Kustomize
  injects into Argo-managed manifests

Cluster credentials are not committed. `scripts/register-cluster-b.sh` generates and applies them directly.

## Phase 2: cluster ingress and platform networking

Before installing Traefik for real application access, configure local DNS as documented in `docs/local-dns.md`. If you
change the default LAN or DNS names, update both `.env.local` for local scripts and
`gitops/components/lab-network/lab-network.env` for Argo-rendered manifests.

The intended model is:

- MetalLB assigns a stable LoadBalancer IP to Traefik in each cluster.
- Raspberry Pi DNS has wildcard records:
  - `*.a.lab.home -> cluster A Traefik IP`
  - `*.b.lab.home -> cluster B Traefik IP`
- Applications declare hostnames such as `argocd.a.lab.home` or `frontend.b.lab.home` through Ingress or HTTPRoute.

That lets the lab stop relying on port-forwarding while keeping DNS setup simple and reproducible.

Phase 2a installs:

- MetalLB in L2 mode on both clusters
- cluster A pool: `192.168.50.240-192.168.50.244`
- cluster B pool: `192.168.50.245-192.168.50.249`
- Traefik in a dedicated `traefik` namespace on both clusters
- `argocd.a.lab.home` pointing to the Argo CD server through Traefik

k3s ServiceLB must be disabled before this phase. Otherwise k3s' built-in `svclb-*` controller and MetalLB will both try
to satisfy `LoadBalancer` Services. Re-run the master provisioners after pulling this phase:

```bash
vagrant provision k3s-a-server-1 k3s-b-server-1
```

The phase has been verified from a clean rebuild:

```bash
vagrant destroy -f
./scripts/up.sh
./scripts/fetch-kubeconfigs.sh
./scripts/bootstrap-argocd.sh
```

Result: all Argo CD Applications are `Synced` / `Healthy`, Traefik receives `192.168.50.240` in cluster A and
`192.168.50.245` in cluster B, and `http://argocd.a.lab.home` returns HTTP 200.

## Phase 3: observability foundation

Phase 3a puts the shared observability backends in cluster B before workload migration begins. This keeps telemetry
available while cluster A is later drained or shut down.

Installed on cluster B:

- MinIO, using local-path storage, with `loki-chunks`, `loki-ruler`, `loki-admin`, and `tempo-traces` buckets
- Loki, configured to use MinIO object storage
- Tempo, configured to use MinIO object storage and receive OTLP/HTTP traces
- Prometheus, with local-path persistence and remote-write receiver enabled
- Grafana, with provisioned Loki, Prometheus, and Tempo datasources
- Ingress for `grafana.b.lab.home`, `loki.b.lab.home`, `prometheus.b.lab.home`, and `tempo.b.lab.home`

Installed on both clusters:

- Grafana Alloy as a DaemonSet
- Pod log collection to Loki
- annotation-based Prometheus scraping to cluster-B Prometheus

This phase is intentionally "prod-shaped" rather than production HA. It uses real persistent stores and
object-storage-backed logs/traces, but the storage is still local-path and single-replica for lab simplicity.

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

## Phase 4: Linkerd control plane and multicluster

Phase 4 prepares the service mesh layer used by the later migration phases. Both clusters get a Linkerd control plane
and the multicluster extension, then the clusters are linked in both directions so services exported from one side can
be mirrored into the other.

Unlike most platform components in this lab, Linkerd is intentionally script-managed instead of Argo CD-managed. The
Linkerd Helm chart needs the identity issuer private key while rendering the control plane manifests. Since this
repository is public, those keys must never be committed. The bootstrap script generates and reuses them from
`.secrets/linkerd/`, which is gitignored.

Run:

```bash
./scripts/bootstrap-linkerd.sh
```

The script:

- installs the pinned Linkerd CLI under `.tools/`
- generates one shared trust anchor and per-cluster issuer certificates
- installs `linkerd-crds` and `linkerd-control-plane` on both clusters
- installs `linkerd-multicluster` on both clusters
- reserves MetalLB gateway IPs `192.168.50.241` and `192.168.50.246`
- creates bidirectional multicluster links
- runs Linkerd control plane and multicluster checks

Verification:

```bash
linkerd --context cluster-a check
linkerd --context cluster-b check
linkerd --context cluster-a multicluster check
linkerd --context cluster-b multicluster check
linkerd --context cluster-a multicluster gateways
linkerd --context cluster-b multicluster gateways
```

Do not delete `.secrets/linkerd/` while the clusters are still using this mesh. Regenerating the trust anchor means
reinstalling Linkerd on both clusters together and restarting any meshed workloads.

## Phase 5: Spring Boot reference applications

Phase 5 has expanded from a generic `frontend -> backend` smoke test into a Spring Boot application-platform reference
architecture.

The initial application candidates have been vendored into this repo:

- `apps/apis/order-api`
- `apps/apis/payment-api`
- `apps/services/order-service`
- `apps/services/payment-service`
- `charts/spring-boot`

The intended direction is:

- publish OpenAPI contracts as versioned artifacts
- generate provider server interfaces and consumer clients from those contracts
- deploy `order-service -> payment-service` to cluster A first
- modernize the Spring Boot Helm chart before relying on it
- tune the existing Loki, Tempo, Prometheus, Grafana, and Alloy stack around the real application behavior
- later reuse the same services for Linkerd multicluster service mirroring and traffic shifting

Planning now lives in `docs/spring-app-platform/`.

### Phase 6: marker-based multicluster migration

The lab migration flow now follows the same shape as the real on-premises to EKS plan. Spring app definitions are not
duplicated per cluster. Instead:

- `gitops/apps/spring-demo/applications/*` is the single source of truth for each app.
- `spring-demo-cluster-a` is an ApplicationSet with a directory generator, so cluster A deploys every app directory.
- `spring-demo-cluster-b-enabled` is an ApplicationSet with a file generator, so cluster B deploys only apps containing
  `.eks-enabled`.
- `payment-service` is currently opted into cluster B.
- `spring-demo-migration-routes-cluster-a` deploys source-cluster-only HTTPRoutes for Linkerd service-to-service traffic
  shifting.

The initial Payment migration route is intentionally safe:

```text
payment-service: 100
payment-service-cluster-b: 0
```

After confirming baseline traffic and dashboards, shift traffic by editing the weights in
`gitops/apps/spring-demo/migration-routes/payment-service/httproute.yaml` and pushing the change through GitOps.

### Phase 5.1: lab-local Maven artifact registry

The first implementation step is a Maven-compatible artifact repository for OpenAPI contract artifacts. The lab uses
Reposilite in cluster B at `http://maven.b.lab.home`.

Reposilite stores data on a `local-path` PVC. Artifacts survive pod restarts, but the registry is disposable with the
rest of the lab and does not need to survive `vagrant destroy`.

The write token is generated locally and applied as a Kubernetes Secret instead of being committed:

```bash
./scripts/bootstrap-artifact-registry.sh
```

Verify:

```bash
kubectl --context cluster-b -n artifact-registry get pods,pvc,ingress
curl -I http://maven.b.lab.home
```

### Phase 5.2: lab-local OCI image registry

Spring application images are published to a disposable OCI registry in cluster B at `registry.b.lab.home`.

The registry uses `local-path` PVC storage. Images survive registry pod restarts but do not need to survive a full lab
teardown. It is HTTP-only and unauthenticated for this LAN lab.

k3s nodes need containerd registry mirror configuration before they can pull images from the HTTP endpoint. Provisioned
nodes get that config automatically; for existing nodes, run:

```bash
./scripts/configure-oci-registry-nodes.sh
```

Verify:

```bash
kubectl --context cluster-b -n container-registry get pods,pvc,ingress
curl -I http://registry.b.lab.home/v2/
```

Example publish command:

```bash
skopeo copy --dest-tls-verify=false \
  docker://docker.io/library/busybox:1.37.0 \
  docker://registry.b.lab.home/k3s-lab/registry-probe:busybox
```
