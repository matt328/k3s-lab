# Argo CD Helm wrapper

This directory installs Argo CD using the community `argo/argo-cd` Helm chart
through Kustomize's `helmCharts` integration:

```bash
kubectl kustomize --enable-helm argocd
```

`scripts/bootstrap-argocd.sh` renders this directory once from the workstation
to bootstrap Argo CD on cluster A. After that, the `argocd` Application in
`gitops/bootstrap/applications/argocd.yaml` points Argo CD back at this same
directory so Argo CD manages itself from Git.

The bootstrap script installs a repo-local Helm v3 binary under `.tools/` if
the host's `helm` command is incompatible with Kustomize's Helm integration.
