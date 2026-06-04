# Migration plan for the Spring app platform

This plan moves from the current Spring demo projects and generic Helm chart to
the target reference architecture in small, verifiable steps.

## Phase 5.0: planning and current-state alignment

Status: in progress.

Outputs:

- dedicated planning area in `docs/spring-app-platform/`
- current-state inventory of the three Spring projects and Helm chart
- initial architecture principles and open decisions

Acceptance criteria:

- the k3s-lab docs clearly replace the old generic sample-app idea with the
  Spring Boot reference-app effort
- key blockers are documented before implementation begins

## Phase 5.1: contract strategy

Purpose: make the OpenAPI artifact model reproducible and explicit.

Work items:

- vendor Order API into `apps/apis/order-api` as the first self-contained lab
  API artifact project
- simulate one-repository-per-API CI locally with `scripts/ci-order-api.sh`
- publish Payment API as a reusable artifact before Payment becomes a provider
  consumed by Order
- deploy Reposilite as the lab-local Maven-compatible artifact repository in
  cluster B
- define artifact coordinates and versioning policy
- define compatibility rules and release workflow
- redirect local builds to publish and consume OpenAPI artifacts through the
  lab-local repository instead of an interactive CodeArtifact token

Acceptance criteria:

- both services generate server/client code only from versioned per-service
  OpenAPI artifacts
- each API artifact is published from its own repository
- no service depends on another service's implementation source
- a fresh build can resolve contracts from `http://maven.b.lab.home`

## Phase 5.2: application cloud-native baseline

Status: complete for Order and Payment services.

Purpose: make the Spring services deployable and observable before tuning the
platform around them.

Work items for every service:

- add Spring Boot Actuator
- expose Kubernetes liveness and readiness health groups
- expose Prometheus metrics
- add Micrometer Tracing and OpenTelemetry OTLP exporter dependencies
- configure trace propagation through generated Feign clients
- emit structured JSON logs with trace/span correlation fields
- expose build, git, image, and contract version information through Actuator
- configure bounded HTTP client timeouts
- add graceful shutdown settings

Acceptance criteria:

- each service responds on `/actuator/health/liveness`
- each service responds on `/actuator/health/readiness`
- each service exposes `/actuator/prometheus`
- a request crossing service boundaries appears as a correlated trace in Tempo
- app logs in Loki can be filtered by service and trace ID

## Phase 5.3: Helm chart modernization

Status: pending. The first Order and Payment deployments use raw Kustomize as
interim manifests so the app baseline can be exercised before the chart is
modernized.

Purpose: turn the existing generic Spring Boot chart into a safe app-platform
default for these services.

Required fixes:

- fix probe rendering so configured probes are actually emitted
- add startup probe support
- avoid enabling probes for services that do not expose the matching Actuator
  endpoints
- add env and envFrom support
- add Linkerd injection annotations
- add Prometheus scrape annotations or compatible metadata
- add pod labels for app, version, component, and observability
- add PodDisruptionBudget support
- add topology spread constraints
- add non-root security context defaults
- document per-app values files

Acceptance criteria:

- `helm template` renders valid probes when probes are enabled
- generated deployments include Linkerd injection when requested
- generated deployments include observability labels and scrape metadata
- services can be deployed without editing chart templates per app

## Phase 5.4: cluster A deployment through GitOps

Status: in progress; Order and Payment are wired as GitOps-managed Spring
workloads in cluster A.

Purpose: deploy the first real Spring topology into the existing lab.

Recommended initial topology:

```text
client -> order-service -> payment-service
```

Work items:

- create app namespaces and Argo CD Applications for cluster A
- deploy a lab-local OCI image registry in cluster B at `registry.b.lab.home`
- configure k3s nodes to pull from the HTTP lab registry
- vendor Order service into `apps/services/order-service`
- publish the Order service image to the lab-local registry with
  `scripts/ci-order-service.sh`
- publish container images for both services to the lab-local registry
- document the image publish command used by local builds and CI
- publish immutable tags and deploy by digest from Helm values
- publish CycloneDX SBOMs alongside images as OCI artifacts/referrers
- add build-time image scanning that blocks Critical vulnerabilities and warns
  on High vulnerabilities
- plan Trivy Operator installation for in-cluster continuous scanning
- create per-service values files in this repo
- expose Order service through Traefik using HTTPRoute or Ingress
- keep Payment service cluster-internal initially
- mesh both workloads with Linkerd
- verify Order can call Payment by Kubernetes service name
- defer Payment-to-Order calls until a later scenario needs them

Acceptance criteria:

- Argo CD reports the app Applications as Synced and Healthy
- Order endpoint is reachable through the cluster A ingress hostname
- Payment remains internal
- Payment does not call Order in the first deployment
- Linkerd shows meshed traffic between Order and Payment
- Grafana has logs, metrics, and traces for a successful request
- deployed images are pinned by digest in GitOps values

## Phase 5.5: observability tuning

Purpose: make the lab excellent for diagnosing service behavior.

Work items:

- add Grafana dashboards for Spring service health and latency
- add dashboards or panels for JVM metrics
- add LogQL examples for service errors and trace correlation
- add Tempo queries for slow traces and failed traces
- add Prometheus recording rules or saved queries if useful
- tune Alloy scrape/log pipelines for application labels
- document a request-debugging workflow from ingress to service dependency

Acceptance criteria:

- a single request can be followed from ingress to logs to trace to service
  metrics
- failed requests are visible in logs, traces, and metrics
- dashboards distinguish Order from Payment and cluster A from cluster B

## Deferred: dynamic configuration prototype

Purpose: explicitly defer restartless config changes until the base app platform
is working.

Current decision:

- put app configuration in each deployment's Helm `values.yaml`
- render config through normal Kubernetes environment variables, ConfigMaps, and
  Secrets
- let Argo CD/Kubernetes rollouts apply config changes for now
- do not introduce Spring Cloud Config, Spring Cloud Bus, or restartless reload
  behavior in the first implementation

Later, revisit:

- which settings are safe to refresh at runtime
- whether Spring Cloud Config Server, Spring Cloud Kubernetes, or another model
  is the right fit
- whether a broker such as RabbitMQ or Kafka is worth adding for config refresh
- how dynamic app config should coexist with GitOps-managed deployment config

## Phase 6+: multicluster migration demo

Purpose: reuse the real Spring services for the original migration narrative.
Payment is the first migration target because it is the leaf service behind
Order in the initial call graph.

Work items:

- deploy Payment service to cluster B
- export Payment with Linkerd multicluster
- configure Order to target the correct local or mirrored Payment service name
- introduce explicit traffic-splitting resources or a stable parent service
- shift Payment traffic gradually from cluster A to cluster B
- validate traces, logs, and metrics across the shift

Acceptance criteria:

- both clusters serve Payment during the overlap phase
- traffic weights can be changed deliberately and observed in Grafana
- no callers use hard-coded IPs
- cross-cluster failures are visible and recoverable
