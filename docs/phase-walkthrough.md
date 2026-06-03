# Phase walkthrough

This document is the narrative companion to the executable scripts and GitOps
manifests in this repository.

## Phase 0: local clusters

Phase 0 provisions two k3s clusters with Vagrant and libvirt:

- `cluster-a`: `k3s-a-master`, `k3s-a-agent`
- `cluster-b`: `k3s-b-master`, `k3s-b-agent`

Each VM is bridged to the LAN, statically addressed, and sized at 4 vCPU /
6 GB by default. k3s bundled Traefik is disabled because Traefik will be
managed later by Argo CD. Gateway API standard CRDs are installed up front on
both clusters.

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
