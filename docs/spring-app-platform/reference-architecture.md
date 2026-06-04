# Spring Boot reference architecture

This document describes the target architecture for the Spring Boot sample
applications that will replace the original generic `frontend -> backend` Phase
5 sample.

## Goals

The sample applications should be useful as exemplars, not just as deployment
smoke tests. They should show how to build, release, deploy, observe, and evolve
Spring Boot services in a Kubernetes and service-mesh environment.

Primary goals:

- API contracts are explicit, versioned, and published independently.
- Providers generate server interfaces from their published contracts.
- Consumers generate clients from provider contracts.
- Services depend on contracts and protocols, not each other's source code.
- Runtime configuration is externalized and environment-specific.
- Every service is observable by default.
- Kubernetes deployment defaults are safe for Spring Boot workloads.
- The same app topology can later be used for Linkerd multicluster migration.

## Logical services

The initial domain contains two services:

| Service | Responsibility | Contract role |
| --- | --- | --- |
| Order service | Owns order state and order lifecycle APIs. | Provider of the Order API; may consume Payment API if order orchestration calls payment. |
| Payment service | Owns payment authorization/capture APIs. | Provider of the Payment API; may consume Order API if payment needs order validation or lookup. |

The first topology is one synchronous business call direction:

```text
client -> order-service -> payment-service
```

That demonstrates request propagation, tracing, retries, timeouts, and service
mesh traffic policy without creating an unnecessary synchronous cycle.

Payment should not call Order in the first implementation. A Payment-to-Order
call can be added later if it demonstrates a specific concept such as cyclic
dependency risk, trace propagation across multiple hops, failure isolation, or
multicluster service discovery. If both services eventually call each other, the
calls should be narrow, read-only where possible, and explicitly protected with
timeouts, retries, and circuit-breaking behavior. Cyclic synchronous
dependencies are useful to demonstrate failure modes, but they are not a default
best practice.

## Contract-first API model

The contract layer is the boundary between services.

Target pattern:

```text
OpenAPI contract artifact
  -> provider generates Spring server interfaces/delegates
  -> consumers generate typed clients
  -> services implement behavior behind generated boundaries
```

Rules:

- Services must not depend on another service's implementation classes.
- Generated DTOs and clients come from versioned OpenAPI artifacts.
- Contracts use semantic versioning:
  - patch: documentation or compatible schema clarifications
  - minor: backward-compatible endpoints, fields, or enum values
  - major: breaking request/response/behavior changes
- Consumers pin a contract version and upgrade deliberately.
- CI should validate generated code and contract compatibility before release.
- Runtime service version and contract artifact version should be visible in
  `/actuator/info`, logs, metrics labels, and image metadata.

Current implementation:

- `openapi-demo-order-service` publishes `order-api.yaml` as
  `dev.teeter.demos.apis:order-api-spec`.
- `demo-order-service` uses that artifact to generate its server API.
- `demo-payment-service` uses that artifact to generate an Order Feign client.
- `demo-payment-service` has its own local `payments-api.yaml`, but that
  contract is not yet published as a reusable artifact.

Decision: each service should own and publish its own API artifact. Order
publishes an Order API artifact; Payment should publish a Payment API artifact
before Order consumes Payment through generated code.

## Runtime topology in this lab

Initial Phase 5 deployment should run both services in cluster A:

```text
client
  |
  v
Traefik / HTTPRoute or Ingress
  |
  v
order-service namespace/app
  |
  v
payment-service namespace/app
```

After the local topology is stable, later phases can introduce cluster B:

```text
cluster A order-service
  |
  | Linkerd service mirror / traffic policy
  v
cluster A payment-service + cluster B payment-service
```

or, if Order becomes the migration target:

```text
cluster A payment-service
  |
  | Linkerd service mirror / traffic policy
  v
cluster A order-service + cluster B order-service
```

The migration target should be selected before implementation, because Linkerd
service mirroring exposes remote services under distinct names and the generated
Feign client must be configured to call the intended Kubernetes service name.

## Kubernetes deployment model

Application deployment should be Argo CD-managed through this repo once image
publishing and secrets are defined.

Recommended shape:

```text
gitops/apps/spring-demo/
  cluster-a/
    order-service/
    payment-service/
  cluster-b/
    order-service/ or payment-service/
```

The app manifests should consume the reusable Spring Boot chart, with per-app
values checked into Git and environment-specific runtime config separated from
the chart itself.

The Helm chart should support:

- Linkerd injection annotations
- standard app, version, and component labels
- configurable env vars and envFrom sources
- ConfigMap and Secret references
- startup, readiness, and liveness probes
- service ports and optional management port
- Prometheus scrape annotations or ServiceMonitor-compatible labels
- HTTPRoute and Ingress options
- PodDisruptionBudget
- topology spread constraints and affinity
- resource requests and limits
- security context defaults for non-root containers
- lifecycle-safe rolling updates

## Observability model

The existing k3s-lab observability platform provides:

- Loki for logs
- Tempo for traces
- Prometheus for metrics
- Grafana for visualization
- Alloy agents for log collection and metrics forwarding

The Spring reference apps should make those backends useful.

### Logs

Target:

- write structured JSON logs to stdout
- include service name, version, environment, trace ID, span ID, request ID, and
  Kubernetes metadata
- avoid multiline stack traces when possible, or use encoder settings that keep
  stack traces parseable
- do not log secrets or tokens

Alloy already collects pod logs, so app changes should focus on log shape and
correlation fields.

### Metrics

Target:

- include `spring-boot-starter-actuator`
- include `micrometer-registry-prometheus`
- expose `/actuator/prometheus`
- expose `/actuator/health`, `/actuator/health/liveness`, and
  `/actuator/health/readiness`
- include JVM, HTTP server, HTTP client, process, and custom business metrics
- allow Prometheus scraping through pod annotations or ServiceMonitor-like
  metadata supported by the lab stack

The chart should make scrape configuration opt-in per workload, with good
defaults for Spring Boot.

### Traces

Target:

- use Micrometer Tracing with OpenTelemetry export, or the OpenTelemetry Java
  agent if that becomes the preferred standard
- send OTLP traces to Tempo
- propagate W3C trace context across generated Feign clients
- include spans for inbound HTTP requests, outbound service calls, and important
  business operations
- ensure logs include trace and span IDs so Grafana can correlate logs and traces

Linkerd can provide mesh-level request metrics, mTLS, and cross-cluster routing,
but application traces still require Spring/OpenTelemetry instrumentation.

### Dashboards

Grafana should eventually include dashboards for:

- service health and availability
- request rate, error rate, and duration by service and endpoint
- JVM memory, GC, threads, and CPU
- outbound dependency latency and errors
- Linkerd service-to-service traffic
- log volume and error logs by service
- trace exemplars for slow or failing requests

## Configuration model

Short-term:

- use environment variables and Kubernetes ConfigMaps/Secrets through Helm values
- keep non-secret app config in Git
- keep secrets out of Git unless a sealed/encrypted secret workflow is added
- use profiles only for broad environment selection, not for every setting

Target direction:

- Git-backed central config for app behavior
- controlled runtime refresh for values that are safe to refresh
- clear separation between app config, deployment config, and secrets

Candidate approaches:

| Option | Fit |
| --- | --- |
| Spring Cloud Config Server + Spring Cloud Bus | Strong Git-backed Spring-native model; needs a broker such as RabbitMQ or Kafka for broadcast refresh. |
| Spring Cloud Kubernetes ConfigMap/Secret integration | More Kubernetes-native; fits GitOps-managed ConfigMaps but refresh semantics need careful validation. |
| Argo CD-managed ConfigMaps plus pod restart/reloader | Operationally simple and GitOps-native, but does not satisfy restartless config refresh. |

Important constraint: restartless refresh does not apply to every setting.
Connection pools, ports, logging appenders, bean construction, and third-party
client configuration may require explicit refresh-scoped beans or a pod rollout.

## Build and release model

Each service should have a reproducible path from source to image:

```text
source commit
  -> test
  -> generate OpenAPI code
  -> build artifact
  -> build image
  -> publish image
  -> update GitOps image tag
  -> Argo CD syncs deployment
```

The lab will use cluster-local repository services:

- Reposilite as a simple Maven-compatible artifact repository for OpenAPI spec
  artifacts
- a simple OCI image registry for Spring Boot application images

These services can be single-replica and lab-grade, but they should use
persistent storage if builds and deployments depend on them across pod restarts.
If the whole lab is torn down, artifacts and images can be rebuilt and repushed
from source.

Remaining decisions:

- exact OCI registry implementation
- tag strategy
- SBOM publishing
- vulnerability scanning
- how this repo references app image versions

Current projects use AWS CodeArtifact for the OpenAPI artifact and Paketo
`bootBuildImage` with `publish = false`, so the lab is not yet fully
reproducible until publishing is redirected to the lab-local repositories.

## Application state model

Order and Payment should remain stateless or in-memory for the first
implementation. That keeps Phase 5 focused on contract generation, deployment,
observability, and service-mesh behavior. Persistent application databases can
be added later when the lab is ready to demonstrate data ownership, backup,
schema migration, and stateful service migration.

## Resilience expectations

The reference apps should demonstrate safe defaults:

- bounded HTTP client timeouts
- conservative retries only for idempotent operations
- no infinite retry loops
- graceful shutdown
- readiness drops before shutdown
- startup probes for slow JVM startup
- idempotency keys or request IDs where duplicate calls are possible
- clear error responses from generated API boundaries

Linkerd can help with transport security and routing, but service-level
timeouts, retries, and idempotency still belong in application code and client
configuration.
