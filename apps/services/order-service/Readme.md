# Order Service

This is the lab-local Order service project. It is vendored here so the lab can
simulate a service CI pipeline against the local Reposilite and OCI registries.

The service includes the baseline cloud-native runtime wiring used by the lab:
Actuator health probes, Prometheus metrics, Micrometer/OpenTelemetry tracing,
structured JSON logs, graceful shutdown, build/git metadata, and bounded Feign
timeouts.

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

## Runtime endpoints

- `/actuator/health/liveness`
- `/actuator/health/readiness`
- `/actuator/prometheus`
- `/actuator/info`

Set `MANAGEMENT_OTLP_TRACING_ENDPOINT` to the OTLP/HTTP traces endpoint for the
target environment. The lab default is `http://tempo.b.lab.home/v1/traces`.