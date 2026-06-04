# Spring application platform planning

This planning area expands the original Phase 5 "sample app" idea into a
Spring Boot microservices reference architecture for this lab.

The goal is to use the existing two-cluster k3s platform to develop and
demonstrate production-shaped Spring services with:

- contract-first APIs published as versioned artifacts
- generated server and client code from OpenAPI contracts
- loose coupling between services through API contracts, not shared internals
- GitOps-managed Kubernetes deployment
- Linkerd service mesh readiness for later cross-cluster migration
- first-class logs, metrics, traces, health checks, and dashboards
- simple per-deployment Helm values first, with dynamic configuration deferred

## Source projects

The initial application inputs live outside this repo:

| Project                                                           | Purpose                                                                                                            |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `/home/matt/Projects/demo/spring-demos/openapi-demo-order-service` | Publishes `order-api.yaml` as the `dev.teeter.demos.apis:order-api-spec` Maven artifact.                                |
| `/home/matt/Projects/demo/spring-demos/demo-order-service`         | Generates the Order service server API from `order-api-spec`.                                                      |
| `/home/matt/Projects/demo/spring-demos/demo-payment-service`       | Generates the Payment service server from its local `payments-api.yaml` and an Order client from `order-api-spec`. |
| `/home/matt/Projects/demo/k8s/helm-charts/helm-charts-spring-boot` | Generic Spring Boot Helm chart that will be modernized before becoming the deployment standard.                    |

The Order API has been vendored into this lab at `apps/apis/order-api` so local
scripts can simulate the CI publish flow against `maven.b.lab.home`.

## Current-state snapshot

The current projects already demonstrate the beginning of the desired pattern:

- the Order API is published separately from either runtime service
- Order service generates its server delegate interface from that artifact
- Payment service generates an Order Feign client from that same artifact
- Payment service also generates its own server API from a local OpenAPI file
- the Helm chart supports Deployment, Service, Ingress, HTTPRoute, and HPA

Important gaps to close before treating these as reference implementations:

- the Order service does not yet include Spring Boot Actuator
- neither service exposes Prometheus metrics
- neither service emits application traces to Tempo
- Payment exposes only the health actuator endpoint
- the chart's default probes are not rendered because the template checks
  `.Values.*Probe.enabled`, but the values file does not define `enabled`
- fixing probe rendering before adding Actuator health groups would make the
  Order deployment fail readiness/liveness checks
- the OpenAPI artifact currently resolves from AWS CodeArtifact, so the lab
  needs a reproducible artifact access strategy
- image build and publish flow is not yet wired into the k3s-lab GitOps flow

## Planning documents

- [Reference architecture](reference-architecture.md) describes the desired
  service, deployment, observability, configuration, and migration model.
- [Migration plan](migration-plan.md) breaks the path from today's projects to
  the reference architecture into executable phases.
- [Open questions](open-questions.md) tracks the remaining unresolved decisions.

## Working assumptions

- Application manifests should be Argo CD-managed once secrets and image
  publishing are handled.
- Linkerd remains script-managed for now, but meshed workloads should be
  deployed through GitOps.
- Application identity and routing should use Kubernetes service names and
  Linkerd service mirror names, not hard-coded pod IPs.
- The first app phase should prefer clarity and observability over feature
  richness.
- Dynamic configuration is deferred; app config should live in the deployment's
  Helm `values.yaml` until the base platform is stable.
