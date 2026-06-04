# Order Service

This is the lab-local Order service project. It is vendored here so the lab can
simulate a service CI pipeline against the local Reposilite and OCI registries.

This step only wires build and image publishing. Cloud-native runtime changes
such as Actuator, metrics, tracing, and structured logging are intentionally
deferred until they are reviewed separately.

## Build inputs

- Order API artifact:
  `dev.teeter.demos.apis:order-api-spec:0.1.0@yaml`
- Maven repository:
  `http://maven.b.lab.home/releases`
- Image repository:
  `registry.b.lab.home/k3s-lab/order-service`

## Local CI simulation

From the repo root:

```bash
./scripts/ci-order-service.sh feature feature/order-service-build
./scripts/ci-order-service.sh main
```

The project uses its checked-in Gradle wrapper and Gradle Java toolchains. Image
publishing uses Jib, so it does not require a local Docker daemon.