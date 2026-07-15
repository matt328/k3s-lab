# Spring application platform planning

This planning area expands the original Phase 5 "sample app" idea into a Spring Boot microservices reference
architecture for this lab.

The goal is to use the existing two-cluster k3s platform to develop and demonstrate production-shaped Spring services
with:

- contract-first APIs published as versioned artifacts
- generated server and client code from OpenAPI contracts
- loose coupling between services through API contracts, not shared internals
- GitOps-managed Kubernetes deployment
- Linkerd service mesh readiness for later cross-cluster migration
- first-class logs, metrics, traces, health checks, and dashboards
- simple per-deployment Helm values first, with dynamic configuration deferred

## Source projects

The application inputs are vendored into this repo:

| Project                         | Purpose                                                                                                 |
| ------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `apps/apis/order-api`           | Publishes `order-api.yaml` as the `dev.teeter.demos.apis:order-api-spec` Maven artifact.                |
| `apps/apis/payment-api`         | Publishes `payment-api.yaml` as the `dev.teeter.demos.apis:payment-api-spec` Maven artifact.            |
| `apps/services/order-service`   | Generates the Order service server API from `order-api-spec`.                                           |
| `apps/services/payment-service` | Generates the Payment service server from `payment-api-spec` and an Order client from `order-api-spec`. |
| `charts/spring-boot`            | Generic Spring Boot Helm chart used by the GitOps application manifests.                                |

The Order API has been vendored into this lab at `apps/apis/order-api` so local scripts can simulate the CI publish flow
against `maven.b.lab.home`.

The Order and Payment services have been vendored into this lab at `apps/services/order-service` and
`apps/services/payment-service` so local scripts can simulate image publishing to `registry.b.lab.home`. They now
include the cloud-native Spring baseline: Actuator probes, Prometheus metrics, Micrometer/OpenTelemetry tracing, JSON
logs, graceful shutdown, bounded Feign timeouts, and Actuator build/Git/contract metadata. The image publish simulations
use Jib through the Gradle wrapper, so they do not require a local Docker daemon.

## Current-state snapshot

The current projects already demonstrate the beginning of the desired pattern:

- the Order API is published separately from either runtime service
- Order service generates its server delegate interface from that artifact
- the Payment API is published separately as a reusable artifact
- Payment service generates its server delegate interface from the Payment API
- Order service generates a Payment Feign client from the Payment API artifact
- the vendored Helm chart supports Deployment, Service, Ingress, HTTPRoute, HPA, and PodDisruptionBudget rendering for
  the lab services

Important gaps to close before treating these as reference implementations:

- the OpenAPI artifact currently resolves from AWS CodeArtifact, so the lab needs a reproducible artifact access
  strategy

## Planning documents

- [Reference architecture](reference-architecture.md) describes the desired service, deployment, observability,
  configuration, and migration model.
- [Migration plan](migration-plan.md) breaks the path from today's projects to the reference architecture into
  executable phases.
- [Observability baseline](observability.md) documents the generic labels, dashboards, traffic generator, and migration
  monitoring workflow.
- [Open questions](open-questions.md) tracks the remaining unresolved decisions.

## Working assumptions

- Application manifests should be Argo CD-managed once secrets and image publishing are handled.
- Linkerd remains script-managed for now, but meshed workloads should be deployed through GitOps.
- Application identity and routing should use Kubernetes service names and Linkerd service mirror names, not hard-coded
  pod IPs.
- The first app phase should prefer clarity and observability over feature richness.
- Dynamic configuration is deferred; app config should live in the deployment's Helm `values.yaml` until the base
  platform is stable.
