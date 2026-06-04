# Open questions

These questions should be answered as the Spring app platform design becomes
implementation work.

## API contract structure

Decision: use separate API artifacts per service.

Implications:

- Order owns and publishes the Order API artifact.
- Payment owns and publishes the Payment API artifact.
- If Order calls Payment, Order consumes the Payment API artifact to generate a
  client.
- If Payment calls Order, Payment consumes the Order API artifact to generate a
  client.
- Neither service consumes the other's implementation source.

Follow-up decision: whether the existing `openapi-demo-order-service` project
should stay Order-specific and a new Payment API project should be created, or
whether both should move into a consistently named multi-repo/module layout.

## Service call direction

Decision: implement `client -> order-service -> payment-service` first.

Implications:

- Order is the initial ingress-facing service.
- Payment is initially cluster-internal.
- Order consumes Payment through the versioned Payment API artifact and a
  generated client.
- Payment should not call Order in the first implementation.
- A later Payment-to-Order call can be added if it demonstrates a specific
  concept such as cyclic dependency risk, trace propagation across multiple
  hops, failure isolation, or multicluster service discovery.

## Artifact repository

Decision: deploy Reposilite as the lab-local Maven artifact repository into
cluster B for OpenAPI artifacts.

The repository can be simple and single-replica, but it should not be treated as
strictly stateless if it is the source used by builds. Use persistent storage so
artifacts survive pod restarts. It is acceptable for the lab repository to be
rebuildable from source and not production-HA.

Reposilite is exposed at `http://maven.b.lab.home`. Its `local-path` PVC keeps
artifacts through pod restarts, but it is disposable with the lab.

## Image registry and deployment flow

Decision: deploy a lab-local OCI image registry into the cluster for app images.

The image registry can also be simple and single-replica. Like the Maven
repository, it should use persistent storage if it is expected to survive pod
restarts. If the cluster is torn down, images can be rebuilt and repushed as
part of the lab workflow.

The current service builds use Paketo `bootBuildImage` with `publish = false`,
so image publishing still needs to be added before Argo CD can deploy these apps
from fresh builds.

## Dynamic configuration approach

Which model should become the reference?

- Spring Cloud Config Server with Spring Cloud Bus
- Spring Cloud Kubernetes ConfigMap/Secret integration
- GitOps-managed ConfigMaps with restart/rollout automation
- a hybrid of central config for app behavior and GitOps for deployment config

The desired outcome is Git-backed config changes that reach running pods without
manual restarts, but only settings designed for runtime refresh should use that
path.

## Multicluster migration target

Which service should be moved first across clusters?

- Payment, because it can stay behind Order and demonstrate backend migration
- Order, because Payment already has a generated Order client

This decision determines service names, Linkerd service mirror usage, and the
traffic-splitting design.

## State and persistence

Decision: keep Order and Payment stateless or in-memory for the first lab
implementation.

Add persistence as a later phase so data migration does not obscure deployment,
observability, and service-mesh traffic shifting.

## Observability standard

Should tracing be implemented with application dependencies or the OpenTelemetry
Java agent?

- app dependencies give explicit Spring/Micrometer control
- the Java agent reduces code changes and can be injected by deployment config

Either choice should still produce Tempo traces, Prometheus metrics, and log
correlation fields.
