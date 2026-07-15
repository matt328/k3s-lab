# k3s Multi-Cluster Lab (Vagrant edition)

Local lab on a Fedora 44 host to test east/west multi-cluster Kubernetes patterns.

## Topology

The default local footprint is now just the two k3s servers, sized at 4 vCPU / 4 GB each:

| Hostname       | Cluster   | Role   | IP (default)   | MAC (default)     |
| -------------- | --------- | ------ | -------------- | ----------------- |
| k3s-a-server-1 | cluster-a | server | 192.168.50.100 | 52:54:00:a1:00:01 |
| k3s-b-server-1 | cluster-b | server | 192.168.50.102 | 52:54:00:b1:00:01 |

IPs and MACs are configurable via `.env.local`. All VMs are bridged onto their host bridge (default `br0`) and are
first-class LAN citizens.

For the full migration/observability topology, enable remote workers on two additional libvirt hosts:

| Host profile | Hostname       | Cluster   | Role  | IP (default)   | MAC (default)     | Size    |
| ------------ | -------------- | --------- | ----- | -------------- | ----------------- | ------- |
| `HOST_1`     | k3s-a-worker-1 | cluster-a | agent | 192.168.50.104 | 52:54:00:a1:00:11 | 4c/6 GB |
| `HOST_1`     | k3s-a-worker-2 | cluster-a | agent | 192.168.50.105 | 52:54:00:a1:00:12 | 4c/6 GB |
| `HOST_2`     | k3s-b-worker-1 | cluster-b | agent | 192.168.50.106 | 52:54:00:b1:00:21 | 4c/6 GB |
| `HOST_2`     | k3s-b-worker-2 | cluster-b | agent | 192.168.50.107 | 52:54:00:b1:00:22 | 4c/6 GB |
| `HOST_2`     | k3s-b-worker-3 | cluster-b | agent | 192.168.50.108 | 52:54:00:b1:00:23 | 4c/6 GB |

`HOST_LOCAL_WORKERS_ENABLED=true` can add local `k3s-a-local-worker-1` and `k3s-b-local-worker-1` VMs for a temporary
local-only fallback, but that is disabled by default to avoid workstation RAM pressure.

## Host prerequisites

```bash
sudo dnf install -y @virtualization libvirt-client virt-install qemu-img \
                    vagrant vagrant-libvirt
sudo usermod -aG libvirt "$USER"   # log out / back in for this to take effect
```

The bridge `br0` (or whatever you set `LAB_BRIDGE` to in `.env.local`) must already exist on the host with your wired
NIC enslaved to it, so VMs get real LAN IPs. See **Host bridge setup** below.

## Configuration

The lab has two configuration paths because some values are consumed by local shell/Vagrant scripts, while other values
must be committed so Argo CD can render GitOps manifests from the repository.

| File                                            | Committed? | Used by                          | Purpose                                                                                                      |
| ----------------------------------------------- | ---------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `.env.example`                                  | yes        | humans and local scripts         | Documented defaults for local shell/Vagrant configuration.                                                   |
| `.env.local`                                    | no         | `Vagrantfile` and `scripts/*.sh` | Your real local values: LAN settings, VM IPs/MACs, k3s tokens, repo URL, registry URLs, and script defaults. |
| `gitops/bootstrap/repo-config.env`              | yes        | Kustomize/Argo CD                | Repo URL injected into Argo CD `Application`, `ApplicationSet`, and `AppProject` manifests.                  |
| `gitops/components/lab-network/lab-network.env` | yes        | Kustomize/Argo CD                | GitOps-facing LAN, DNS, registry, artifact, and observability endpoint defaults.                             |

For a personal local run, copy `.env.example` to `.env.local` and edit only `.env.local` for your machine-specific
values. For a shared org import, also edit and commit the two GitOps config files before bootstrapping Argo CD. Argo CD
does not read `.env.local`; it only sees committed Git files.

This repository is intended to serve as a baseline. Since one GitOps repo/branch represents one environment, anyone who
wants to stand up a separate personal lab should fork the repo and commit their own `gitops/bootstrap/repo-config.env`
and `gitops/components/lab-network/lab-network.env` values to that fork.

Local scripts use `scripts/lib/env.sh` and resolve values in this order:

1. Environment variables already set by the caller.
2. `.env.local`.
3. `.env.example`.

The `Vagrantfile` follows the same effective order. This lets you keep durable local settings in `.env.local` and still
use one-off shell overrides when needed, for example:

```bash
HTTP_TRAFFIC_URL_TEMPLATE=http://order.a.lab.home/orders/{id} ./scripts/generate-http-traffic.sh
```

The default VM IPs use `192.168.50.100`-`192.168.50.108`, leaving the `192.168.50.2`-`192.168.50.99` DHCP pool and
MetalLB pools untouched.

```bash
cp .env.example .env.local
# edit .env.local for your LAN. At minimum, set:
#   LAB_BRIDGE, LAB_GATEWAY, LAB_DNS, LAB_DOMAIN, the CLUSTER_*_IP values,
#   and generate fresh K3S_TOKEN_A / K3S_TOKEN_B with:
#     openssl rand -hex 32
```

`GITOPS_REPO_URL`, `GHCR_OWNER`, and the script CI/image variables are not needed until Phase 1+ and can be left as the
documented defaults until you bootstrap GitOps and publish the sample apps.

GitOps-managed network and DNS defaults live in:

```text
gitops/components/lab-network/lab-network.env
```

Update that file before bootstrapping Argo CD if your LAN, MetalLB pools, ingress hostnames, or lab registry/artifact
hostnames differ from the checked-in defaults. Kustomize injects those values into the GitOps manifests at render time,
so the concrete IPs and hostnames are not repeated across each Argo-managed application. Keep matching values in
`.env.local` for local scripts that talk to the same endpoints.

## Host bridge (`br0`) setup

Fedora 44 (KDE included) uses NetworkManager. Use `nmcli` — the Plasma applet doesn't expose bridge-slave configuration
well.

> ⚠️ Will briefly drop your network. Run from a local console.

1. Find your wired interface and current connection:

   ```bash
   nmcli -t -f DEVICE,TYPE,STATE device | grep ethernet
   nmcli -t -f NAME,DEVICE,TYPE connection show --active
   ```

   Assume device `enp0s31f6` and active connection `"Wired connection 1"`.

2. Create the bridge and enslave the NIC:

   ```bash
   sudo nmcli connection add type bridge ifname br0 con-name br0 \
        bridge.stp no ipv4.method auto ipv6.method auto

   sudo nmcli connection add type ethernet ifname enp0s31f6 con-name br0-slave-enp0s31f6
   sudo nmcli connection modify br0-slave-enp0s31f6 \
        connection.controller br0 \
        connection.port-type bridge

   sudo nmcli connection modify "Wired connection 1" connection.autoconnect no
   sudo nmcli connection down "Wired connection 1" || true
   sudo nmcli connection up br0-slave-enp0s31f6
   sudo nmcli connection up br0
   ```

3. Verify:
   ```bash
   bridge link               # enp0s31f6 should show "master br0 state forwarding"
   ip -br addr show br0      # br0 should hold your LAN IP
   ```

## Usage

```bash
./scripts/up.sh                         # provision configured VMs and install k3s
./scripts/fetch-kubeconfigs.sh          # writes kubeconfigs/cluster-{a,b}.yaml
                                        # AND merges them into ~/.kube/config
                                        # (existing config is backed up first)

kubectl config use-context cluster-a
kubectl get nodes
kubectl config use-context cluster-b
kubectl get nodes

vagrant ssh k3s-a-server-1              # shell into a specific VM
vagrant status                          # show VM states
vagrant provision                       # re-run provisioners (idempotent)
vagrant reload --provision              # reboot + re-provision
vagrant destroy -f                      # tear everything down
```

Cross-cutting follow-up work is tracked in [`docs/todo.md`](docs/todo.md).

Use `./scripts/up.sh` instead of plain `vagrant up`. Vagrant may provision machines in parallel, which can race an agent
ahead of its master. The wrapper uses `vagrant up --no-parallel` so each master installs k3s before its agent tries to
join.

Bring up a single VM:

```bash
vagrant up k3s-a-server-1
```

## Local DNS

Register the VM hostnames in your local DNS server (`LAB_DNS` in `.env.local`):

```
k3s-a-server-1.lab.home        192.168.50.100
k3s-b-server-1.lab.home        192.168.50.102
k3s-a-local-worker-1.lab.home  192.168.50.101  # only if HOST_LOCAL_WORKERS_ENABLED=true
k3s-b-local-worker-1.lab.home  192.168.50.103  # only if HOST_LOCAL_WORKERS_ENABLED=true
k3s-a-worker-1.lab.home        192.168.50.104
k3s-a-worker-2.lab.home        192.168.50.105
k3s-b-worker-1.lab.home        192.168.50.106
k3s-b-worker-2.lab.home        192.168.50.107
k3s-b-worker-3.lab.home        192.168.50.108
```

For application access, configure wildcard ingress zones on your Raspberry Pi DNS server:

```
*.a.lab.home  192.168.50.240
*.b.lab.home  192.168.50.245
```

Those IPs are the default `CLUSTER_A_INGRESS_IP` and `CLUSTER_B_INGRESS_IP` values in `.env.example`; they will be
assigned to each cluster's Traefik LoadBalancer by MetalLB. See `docs/local-dns.md` for the Raspberry Pi / dnsmasq
setup.

## What gets provisioned

For each VM, in order:

1. **`scripts/configure-static-ip.sh`** — finds the bridged NIC by MAC and pins it to its static LAN IP via
   NetworkManager.
2. **`scripts/install-k3s-server.sh`** (masters) or **`scripts/install-k3s-agent.sh`** (agents) — runs the official k3s
   installer. Servers are configured with bundled Traefik and ServiceLB disabled (both are GitOps-managed later) and the
   Gateway API standard CRDs (`GATEWAY_API_VERSION`) applied. Agents wait for their master's API to be reachable before
   joining.

The server provisioner reconciles `/etc/rancher/k3s/config.yaml` on reruns. If server config changes after k3s is
already installed, re-run:

```bash
vagrant provision k3s-a-server-1 k3s-b-server-1
```

The provisioner restarts `k3s` only when the config changed.

Each script is otherwise idempotent and can be re-run via `vagrant provision`.

## Optional remote worker hosts

If the local machine is short on RAM, `.env.local` can enable agent VMs on remote libvirt hosts. They join the existing
clusters as agents; they do not create new control planes. The intended full lab topology is:

- `HOST_1`: two 4 vCPU / 6 GB cluster-A agents
- `HOST_2`: three 4 vCPU / 6 GB cluster-B agents for Argo CD target workloads and observability

Hard prerequisites:

- each remote host runs libvirt and is reachable by SSH from the local machine
- each remote host has a bridge, usually `br0`, on the same L2 LAN/subnet as the local bridge
- the remote worker IPs are free, outside DHCP, and outside the MetalLB pools
- the remote libvirt user can access `qemu:///system` and write to the default storage pool
- guest SSH must be proxied through the remote host because Vagrant provisions over libvirt's management network before
  the bridged static IP exists

On each Fedora remote host, run the setup helper from a local console because creating the bridge can briefly drop the
wired network.

For the first remote worker host:

```bash
./scripts/setup-remote-libvirt-host.sh --iface enp0s31f6 --bridge br0
```

For the second remote worker host:

```bash
./scripts/setup-remote-libvirt-host.sh --iface enp0s31f6 --bridge br0 \
  --env-prefix HOST_2
```

If you want either remote host itself to use the lab DNS resolver:

```bash
./scripts/setup-remote-libvirt-host.sh --iface enp0s31f6 --bridge br0 \
  --dns "192.168.50.210" --dns-search lab.home --ignore-auto-dns
```

Example `.env.local`:

```bash
HOST_1_ENABLED=true
HOST_1_LABEL=host-1
HOST_1_URI=qemu+ssh://lab-user@host-1.example.com/system
HOST_1_SSH_PROXY_COMMAND="ssh -W %h:%p lab-user@host-1.example.com"
HOST_1_BRIDGE=br0

HOST_2_ENABLED=true
HOST_2_LABEL=host-2
HOST_2_URI=qemu+ssh://lab-user@host-2.example.com/system
HOST_2_SSH_PROXY_COMMAND="ssh -W %h:%p lab-user@host-2.example.com"
HOST_2_BRIDGE=br0

CLUSTER_A_WORKER_1_IP=192.168.50.104
CLUSTER_A_WORKER_2_IP=192.168.50.105
CLUSTER_B_WORKER_1_IP=192.168.50.106
CLUSTER_B_WORKER_2_IP=192.168.50.107
CLUSTER_B_WORKER_3_IP=192.168.50.108
```

Then run the normal deterministic provisioner:

```bash
./scripts/up.sh
```

Remote workers are labeled when they join:

```text
lab.k3s.io/placement=remote
lab.k3s.io/cluster=cluster-a|cluster-b
lab.k3s.io/host=host-1|host-2
```

Adding workers increases scheduling capacity, but it does not automatically move already-running stateful workloads such
as MinIO, Loki, Tempo, Prometheus, or Grafana. Those pods keep their existing PVC/node placement unless you
intentionally reschedule or reconfigure them.

If you want to remove remote workers, destroy them before disabling the option; otherwise Vagrant will hide those
machines from this Vagrantfile while they may still be running on the remote host:

```bash
vagrant destroy -f k3s-a-worker-1 k3s-a-worker-2 \
  k3s-b-worker-1 k3s-b-worker-2 k3s-b-worker-3
```

## Migration phases (planned)

This lab walks through a full app + control-plane migration from cluster A to cluster B, using GitOps and a service
mesh. Each phase is codified as a script so the whole sequence is replayable.

| Phase | What                                                                                           |
| ----- | ---------------------------------------------------------------------------------------------- |
| 0     | **(done by this Vagrantfile)** Provision configured VMs, install k3s, install Gateway API CRDs |
| 1     | Bootstrap Argo CD on cluster A; declaratively register cluster B                               |
| 2     | Argo CD installs MetalLB and Traefik on both clusters; Argo CD gets LAN ingress                |
| 3     | Install MinIO + observability stack on cluster B; install Alloy agents on both clusters        |
| 4     | Install Linkerd control plane + multicluster on both clusters                                  |
| 5     | Deploy Spring Boot `order-service → payment-service` reference apps to cluster A               |
| 6     | Deploy the selected backend service to cluster B; export it via Linkerd service mirror         |
| 7     | Weighted east/west traffic shift for the selected backend service                              |
| 8     | Remove the migrated backend service from cluster A                                             |
| 9     | Install Argo CD on cluster B; orphan apps from A's Argo; adopt in B's Argo; delete A's Argo    |
| 10    | DNS cutover: point ingress hostnames at cluster B (manual, on your local resolver)             |
| 11    | Halt cluster A VMs                                                                             |

See `docs/phase-walkthrough.md` for the narrative version and `docs/spring-app-platform/` for the expanded Spring Boot
application-platform plan.

## Phase 1: Bootstrap Argo CD

Argo CD is installed on **cluster A** using the community Helm chart (`argo/argo-cd`) rendered by
`kubectl kustomize --enable-helm`, matching the pattern in the reference EKS develop-tools repo. The checked-in
`argocd/` directory is the chart wrapper; Argo CD then manages that same directory from Git.

Argo CD reads this repository over HTTPS without a repository credential secret. Your local git remote can still use
SSH.

1. Ensure `.env.local` points at this repo:

   ```bash
   GITOPS_REPO_URL=https://github.com/YOUR_ORG/k3s-lab.git
   GITOPS_REPO_REVISION=main
   GITOPS_REPO_PATH=gitops
   GHCR_OWNER=YOUR_ORG
   ```

2. Set the same committed repo URL in `gitops/bootstrap/repo-config.env`:

   ```bash
   GITOPS_REPO_URL=https://github.com/YOUR_ORG/k3s-lab.git
   ```

   Kustomize injects that value into the Argo CD `Application`, `ApplicationSet`, and `AppProject` manifests at render
   time so the URL is not repeated across every Argo file.

3. If you changed LAN/DNS/registry defaults, update and commit `gitops/components/lab-network/lab-network.env`.

   `.env.local` drives local scripts; `gitops/components/lab-network/lab-network.env` drives Argo-rendered manifests.
   Keep them aligned for values that exist in both places, such as the MetalLB ingress IPs and lab registry host.

4. Commit and push any GitOps changes. Argo CD can only sync what exists in GitHub.

5. Bootstrap Argo CD and register cluster B:

   ```bash
   ./scripts/bootstrap-argocd.sh
   ```

   The script:
   - installs/upgrades Argo CD from `argocd/`
   - waits for the core Argo CD deployments
   - creates an `argocd-manager` service account in cluster B
   - applies a generated cluster-B registration Secret into cluster A
   - applies the root `bootstrap` Application

   The cluster-B token Secret is applied directly to the clusters and is not committed to this repository.

6. Optional UI access before Phase 2a installs ingress:

   ```bash
   kubectl --context cluster-a -n argocd port-forward svc/argocd-server 8080:80
   kubectl --context cluster-a -n argocd get secret argocd-initial-admin-secret \
     -o jsonpath='{.data.password}' | base64 -d; echo
   ```

   Open <http://localhost:8080>, username `admin`.

## Phase 2a: MetalLB, Traefik, and Argo CD ingress

Phase 2a installs the ingress foundation through Argo CD:

- MetalLB on both clusters
- a per-cluster MetalLB IP pool
- Traefik on both clusters
- an Argo CD Ingress at `argocd.a.lab.home`

Before syncing this phase, make sure k3s ServiceLB is disabled on both masters:

```bash
vagrant provision k3s-a-server-1 k3s-b-server-1
kubectl --context cluster-a -n kube-system get pods | grep svclb || echo "cluster-a: no ServiceLB"
kubectl --context cluster-b -n kube-system get pods | grep svclb || echo "cluster-b: no ServiceLB"
```

Then commit/push the GitOps manifests. Argo CD will create the child Applications automatically from `gitops/bootstrap`.

Verify:

```bash
kubectl --context cluster-a -n argocd get applications

kubectl --context cluster-a -n metallb-system get pods,ipaddresspools,l2advertisements
kubectl --context cluster-b -n metallb-system get pods,ipaddresspools,l2advertisements

kubectl --context cluster-a -n traefik get svc traefik
kubectl --context cluster-b -n traefik get svc traefik

curl -I http://argocd.a.lab.home
```

Expected Traefik `EXTERNAL-IP` values:

```text
cluster-a: 192.168.50.240
cluster-b: 192.168.50.245
```

After Phase 2a, Argo CD is available without port-forwarding:

```bash
kubectl --context cluster-a -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
open http://argocd.a.lab.home
```

## Phase 3a: Observability foundation

Phase 3a installs the observability backends on **cluster B** and lightweight Alloy collectors on both clusters:

- MinIO object storage with lab buckets for Loki and Tempo
- Loki for logs
- Tempo for traces over OTLP/HTTP
- Prometheus for metrics, with remote-write receiver enabled
- Grafana with Loki, Prometheus, and Tempo datasources
- Ingress hosts under `*.b.lab.home`

Grafana is available at:

```bash
kubectl --context cluster-b -n observability get secret grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
open http://grafana.b.lab.home
```

Username is `admin`. Intake endpoints for collectors and later apps:

```text
Loki:       http://loki.b.lab.home/loki/api/v1/push
Prometheus: http://prometheus.b.lab.home/api/v1/write
Tempo:      http://tempo.b.lab.home/v1/traces
```

Verify:

```bash
kubectl --context cluster-a -n argocd get applications
kubectl --context cluster-b -n observability get pods,pvc,ingress
kubectl --context cluster-a -n observability get pods

curl -I http://grafana.b.lab.home
curl http://loki.b.lab.home/ready
curl http://prometheus.b.lab.home/-/ready
curl -o /dev/null -s -w '%{http_code}\n' http://tempo.b.lab.home/v1/traces
```

Expected Tempo result is `405` for a GET request; the OTLP/HTTP endpoint only accepts POST.

## Phase 4: Linkerd control plane and multicluster

Phase 4 installs Linkerd on both clusters and links them bidirectionally for later service mirroring:

- Linkerd CRDs and control plane on cluster A and cluster B
- one shared trust anchor with per-cluster issuer certificates
- Linkerd multicluster extension and gateway on both clusters
- bidirectional cluster links for future exported services

This phase is script-managed rather than Argo-managed because Linkerd's Helm chart requires private identity issuer keys
at render time. The script stores that material under `.secrets/linkerd/`, which is gitignored.

```bash
./scripts/bootstrap-linkerd.sh
```

Default Linkerd gateway `EXTERNAL-IP` values:

```text
cluster-a: 192.168.50.241
cluster-b: 192.168.50.246
```

Verify:

```bash
export PATH="$(./scripts/ensure-linkerd-cli.sh):$PATH"

linkerd --context cluster-a check
linkerd --context cluster-b check
linkerd --context cluster-a multicluster check
linkerd --context cluster-b multicluster check
linkerd --context cluster-a multicluster gateways
linkerd --context cluster-b multicluster gateways
```

## Phase 5.1: Lab-local Maven artifact registry

The Spring reference-app phases use a lab-local Maven-compatible repository for OpenAPI contract artifacts. This avoids
depending on an interactive CodeArtifact token while keeping the lab disposable.

Reposilite runs in **cluster B**:

```text
URL:       http://maven.b.lab.home
releases:  http://maven.b.lab.home/releases
snapshots: http://maven.b.lab.home/snapshots
```

The registry uses a `local-path` PVC, so artifacts survive pod restarts but are not expected to survive
`vagrant destroy`.

Create or refresh the local admin token Secret:

```bash
./scripts/bootstrap-artifact-registry.sh
```

The generated token is stored under `.secrets/reposilite/`, which is ignored by git. The registry manifests are
GitOps-managed from:

```text
gitops/infra/artifact-registry/cluster-b
```

Verify:

```bash
kubectl --context cluster-b -n artifact-registry get pods,pvc,ingress
curl -I http://maven.b.lab.home
```

## Phase 5.2: Lab-local OCI image registry

Spring app images are published to a lab-local OCI registry in **cluster B**:

```text
registry.b.lab.home
```

The registry is intentionally HTTP-only and unauthenticated for this LAN lab. It uses a `local-path` PVC, so images
survive pod restarts but are rebuilt and repushed after `vagrant destroy`.

k3s containerd must be configured to pull from this HTTP registry. New or reprovisioned nodes get
`/etc/rancher/k3s/registries.yaml` from the k3s install provisioners. For already-running nodes, run this to configure
the containerd mirror and an `/etc/hosts` mapping from `registry.b.lab.home` to the cluster B ingress IP:

```bash
./scripts/configure-oci-registry-nodes.sh
```

The registry manifests are GitOps-managed from:

```text
gitops/infra/container-registry/cluster-b
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

## Phase 5.3: API CI simulation

The API contract projects are vendored under:

```text
apps/apis/order-api
apps/apis/payment-api
```

This keeps the lab self-contained while preserving the target architecture of one repository per API artifact. The
checked-in Gradle wrappers publish `dev.teeter.demos.apis:*:<version>@yaml` artifacts to Reposilite.

Simulate feature-branch publishes:

```bash
./scripts/ci-order-api.sh feature feature/order-api-change
./scripts/ci-payment-api.sh feature feature/payment-api-change
```

Simulate main-branch releases:

```bash
./scripts/ci-order-api.sh main
./scripts/ci-payment-api.sh main
```

## Phase 5.4: Spring service cloud-native baseline and deployment

The first Spring services are vendored under:

```text
apps/services/order-service
apps/services/payment-service
```

Both services include the Spring cloud-native baseline:

- Actuator health groups for Kubernetes startup, readiness, and liveness probes
- Prometheus metrics at `/actuator/prometheus`
- Micrometer Tracing with OpenTelemetry OTLP export to Tempo
- structured JSON stdout logs with Micrometer trace/span MDC fields for Loki
- graceful shutdown and bounded Feign client timeout defaults
- Actuator build, Git, image, and API contract metadata

The local CI simulations resolve OpenAPI artifacts from Reposilite, build with each service's Gradle wrapper, and
publish with Jib to:

```text
registry.b.lab.home/k3s-lab/order-service
registry.b.lab.home/k3s-lab/payment-service
```

Jib pushes directly to the registry, so this script does not require a local Docker daemon.

Simulate a feature-branch image publish:

```bash
./scripts/ci-order-service.sh feature feature/order-service-build
./scripts/ci-payment-service.sh feature feature/payment-service-build
```

Simulate a main-branch image release:

```bash
./scripts/ci-order-service.sh main
./scripts/ci-payment-service.sh main
```

The Spring app deployments are checked in under:

```text
gitops/apps/spring-demo/applications/order-service
gitops/apps/spring-demo/applications/payment-service
```

They render the vendored reusable Spring Boot Helm chart at `charts/spring-boot` through Kustomize. Per-service image,
env, probe, ingress, mesh, and observability settings live in each app's `values.yaml`. The rendered Deployments pin
images by digest, enable Linkerd injection on the pod template, and add Alloy-compatible Prometheus scrape annotations.
Order is exposed through Traefik at `http://order.a.lab.home`; Payment is cluster-internal and is called by Order at
`http://payment-service`.

The service CI scripts print the image values shape after pushing. Copy the fresh `repository`, `tag`, and `digest` into
the matching GitOps `values.yaml`, then commit and push so Argo CD deploys images that exist in this lab's disposable
registry:

```text
gitops/apps/spring-demo/applications/order-service/values.yaml
gitops/apps/spring-demo/applications/payment-service/values.yaml
```

## Application observability baseline

The lab provisions generic application observability dashboards in Grafana, not only migration-specific views. The
baseline uses common labels from Kubernetes app metadata so the same dashboards can monitor many services:

```text
cluster, namespace, workload, component, part_of, version, pod, container
```

Grafana dashboards are provisioned from `gitops/infra/grafana/cluster-b/dashboards`:

- Application Fleet Overview
- Service Drilldown
- Migration Watch

Alloy enriches Prometheus metrics and Loki logs with the app labels, Spring apps publish HTTP histogram buckets for
p50/p95/p99 latency, and the local traffic generator can create steady request load:

```bash
scripts/generate-http-traffic.sh --duration 600 --rate 5
```

The default target is `http://order.a.lab.home/orders/{id}`, which exercises the current
`client -> order-service -> payment-service` path. See `docs/spring-app-platform/observability.md` for the full label
contract, dashboard catalog, onboarding checklist, and migration monitoring workflow.

## Clean rebuild smoke test

This is the current end-to-end reproducibility check:

```bash
vagrant destroy -f
./scripts/up.sh
./scripts/fetch-kubeconfigs.sh
./scripts/bootstrap-argocd.sh
./scripts/bootstrap-artifact-registry.sh
./scripts/configure-oci-registry-nodes.sh
./scripts/bootstrap-linkerd.sh
./scripts/ci-order-api.sh main
./scripts/ci-payment-api.sh main
./scripts/ci-order-service.sh main
./scripts/ci-payment-service.sh main
```

Copy the fresh image `repository`, `tag`, and `digest` values printed by the service CI scripts into:

```text
gitops/apps/spring-demo/applications/order-service/values.yaml
gitops/apps/spring-demo/applications/payment-service/values.yaml
```

Then commit and push those GitOps changes and wait for Argo CD to sync. A fresh lab registry starts empty, so the Spring
applications cannot become healthy until the published image digests match the committed GitOps values.

Verify:

```bash
kubectl --context cluster-a -n argocd get applications
kubectl --context cluster-a -n traefik get svc traefik
kubectl --context cluster-b -n traefik get svc traefik
kubectl --context cluster-b -n artifact-registry get pods,pvc,ingress
kubectl --context cluster-b -n container-registry get pods,pvc,ingress
kubectl --context cluster-a -n linkerd-multicluster get svc linkerd-gateway
kubectl --context cluster-b -n linkerd-multicluster get svc linkerd-gateway
curl -I http://argocd.a.lab.home
curl -I http://maven.b.lab.home
curl -I http://registry.b.lab.home/v2/
curl -I http://grafana.b.lab.home
curl http://order.a.lab.home/orders/smoke
```

Expected:

- all Argo CD Applications are `Synced` / `Healthy`
- cluster A Traefik has `EXTERNAL-IP` `192.168.50.240`
- cluster B Traefik has `EXTERNAL-IP` `192.168.50.245`
- Reposilite is reachable at `http://maven.b.lab.home`
- the OCI registry is reachable at `http://registry.b.lab.home/v2/`
- cluster A Linkerd gateway has `EXTERNAL-IP` `192.168.50.241`
- cluster B Linkerd gateway has `EXTERNAL-IP` `192.168.50.246`
- `http://argocd.a.lab.home` returns `HTTP/1.1 200 OK`
- `http://grafana.b.lab.home` returns `HTTP/1.1 302 Found` to `/login`
- `http://order.a.lab.home/orders/smoke` returns a confirmed order JSON response
