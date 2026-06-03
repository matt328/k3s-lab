# k3s Multi-Cluster Lab (Vagrant edition)

Local lab on a Fedora 44 host to test east/west multi-cluster Kubernetes
patterns.

## Topology

| Hostname     | Cluster   | Role   | IP (default) | MAC (default)     |
| ------------ | --------- | ------ | ------------ | ----------------- |
| k3s-a-master | cluster-a | server | 192.168.50.4 | 52:54:00:a1:00:01 |
| k3s-a-agent  | cluster-a | agent  | 192.168.50.5 | 52:54:00:a1:00:02 |
| k3s-b-master | cluster-b | server | 192.168.50.6 | 52:54:00:b1:00:01 |
| k3s-b-agent  | cluster-b | agent  | 192.168.50.7 | 52:54:00:b1:00:02 |

IPs and MACs are configurable via `.env.local`. All 4 VMs are bridged onto
the host bridge (default `br0`) and are first-class LAN citizens.

## Host prerequisites

```bash
sudo dnf install -y @virtualization libvirt-client virt-install qemu-img \
                    vagrant vagrant-libvirt
sudo usermod -aG libvirt "$USER"   # log out / back in for this to take effect
```

The bridge `br0` (or whatever you set `LAB_BRIDGE` to in `.env.local`) must
already exist on the host with your wired NIC enslaved to it, so VMs get
real LAN IPs. See **Host bridge setup** below.

## Configuration

All environment-specific values (IPs, MACs, networking, k3s tokens, GitOps
repo URL, GHCR namespace) live in `.env.local`, which is gitignored.

```bash
cp .env.example .env.local
# edit .env.local for your LAN. At minimum, set:
#   LAB_BRIDGE, LAB_GATEWAY, LAB_DNS, LAB_DOMAIN, the VM_*_IP values,
#   and generate fresh K3S_TOKEN_A / K3S_TOKEN_B with:
#     openssl rand -hex 32
```

`GITOPS_REPO_URL` and `GHCR_OWNER` are not needed until Phase 1 (GitOps
bootstrap) and can be left blank for now.

## Host bridge (`br0`) setup

Fedora 44 (KDE included) uses NetworkManager. Use `nmcli` — the Plasma applet
doesn't expose bridge-slave configuration well.

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
./scripts/up.sh                         # provision all 4 VMs and install k3s
./scripts/fetch-kubeconfigs.sh          # writes kubeconfigs/cluster-{a,b}.yaml
                                        # AND merges them into ~/.kube/config
                                        # (existing config is backed up first)

kubectl config use-context cluster-a
kubectl get nodes
kubectl config use-context cluster-b
kubectl get nodes

vagrant ssh k3s-a-master                # shell into a specific VM
vagrant status                          # show VM states
vagrant provision                       # re-run provisioners (idempotent)
vagrant reload --provision              # reboot + re-provision
vagrant destroy -f                      # tear everything down
```

Use `./scripts/up.sh` instead of plain `vagrant up`. Vagrant may provision
machines in parallel, which can race an agent ahead of its master. The wrapper
uses `vagrant up --no-parallel` so each master installs k3s before its agent
tries to join.

Bring up a single VM:

```bash
vagrant up k3s-a-master
```

## Optional: DNS

Nothing in the lab requires DNS — all internal references use IPs. For
convenience you can register the VM hostnames in your local DNS server
(`LAB_DNS` in `.env.local`):

```
k3s-a-master.lab.home  192.168.50.4
k3s-a-agent.lab.home   192.168.50.5
k3s-b-master.lab.home  192.168.50.6
k3s-b-agent.lab.home   192.168.50.7
```

## What gets provisioned

For each VM, in order:

1. **`scripts/configure-static-ip.sh`** — finds the bridged NIC by MAC and
   pins it to its static LAN IP via NetworkManager.
2. **`scripts/install-k3s-server.sh`** (masters) or
   **`scripts/install-k3s-agent.sh`** (agents) — runs the official k3s
   installer. Servers are installed with bundled Traefik disabled (it will
   be GitOps-managed in Phase 1) and the Gateway API standard CRDs
   (`GATEWAY_API_VERSION`) applied. Agents wait for their master's API to
   be reachable before joining.

> ⚠️ **k3s install args (e.g. `--disable=traefik`) are baked in at install
> time.** Changing `scripts/install-k3s-server.sh` after k3s is already
> installed has no effect on existing nodes. To pick up server-arg changes
> you must `vagrant destroy -f && vagrant up`.

Each script is otherwise idempotent and can be re-run via `vagrant provision`.

## Migration phases (planned)

This lab walks through a full app + control-plane migration from cluster A
to cluster B, using GitOps and a service mesh. Each phase is codified as a
script so the whole sequence is replayable.

| Phase | What                                                                                        |
| ----- | ------------------------------------------------------------------------------------------- |
| 0     | **(done by this Vagrantfile)** Provision 4 VMs, install k3s, install Gateway API CRDs       |
| 1     | Bootstrap Argo CD on cluster A; declaratively register cluster B                            |
| 2     | Argo CD installs Traefik and Linkerd (control plane + multicluster) on both clusters        |
| 3     | Install MinIO + LGTM stack on cluster B; install Alloy agents on both clusters              |
| 4     | Deploy `frontend → backend` sample apps to cluster A only                                   |
| 5     | Deploy `backend` to cluster B too; export it via Linkerd service mirror                     |
| 6     | Weighted east/west traffic shift for `backend`: 100/0 → 75/25 → 50/50 → 25/75 → 0/100       |
| 7     | Remove `backend` from cluster A                                                             |
| 8     | Install Argo CD on cluster B; orphan apps from A's Argo; adopt in B's Argo; delete A's Argo |
| 9     | DNS cutover: point ingress hostnames at cluster B (manual, on your local resolver)          |
| 10    | Halt cluster A VMs                                                                          |

See `docs/phase-walkthrough.md` for the narrative version (forthcoming).

## Phase 1: Bootstrap Argo CD

Argo CD is installed on **cluster A** using the community Helm chart
(`argo/argo-cd`) rendered by `kubectl kustomize --enable-helm`, matching the
pattern in the reference EKS develop-tools repo. The checked-in `argocd/` directory
is the chart wrapper; Argo CD then manages that same directory from Git.

This repository is public, so Argo CD reads it over HTTPS without a repository
credential secret. Your local git remote can still use SSH.

1. Ensure `.env.local` points at this repo:
   ```bash
   GITOPS_REPO_URL=https://github.com/matt328/k3s-lab.git
   GITOPS_REPO_REVISION=main
   GITOPS_REPO_PATH=gitops
   GHCR_OWNER=matt328
   ```

2. Commit and push any GitOps changes. Argo CD can only sync what exists in
   GitHub.

3. Bootstrap Argo CD and register cluster B:
   ```bash
   ./scripts/bootstrap-argocd.sh
   ```

   The script:
   - installs/upgrades Argo CD from `argocd/`
   - waits for the core Argo CD deployments
   - creates an `argocd-manager` service account in cluster B
   - applies a generated cluster-B registration Secret into cluster A
   - applies the root `bootstrap` Application

   The cluster-B token Secret is applied directly to the clusters and is not
   committed to this repository.

4. Optional UI access:
   ```bash
   kubectl --context cluster-a -n argocd port-forward svc/argocd-server 8080:80
   kubectl --context cluster-a -n argocd get secret argocd-initial-admin-secret \
     -o jsonpath='{.data.password}' | base64 -d; echo
   ```

   Open <http://localhost:8080>, username `admin`.
