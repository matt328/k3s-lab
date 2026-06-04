# Payment Service

This is the lab-local Payment service project. It is a leaf service in the
initial reference topology:

```text
client -> order-service -> payment-service
```

The service generates its server API from
`dev.teeter.demos.apis:payment-api-spec:0.1.0@yaml` and includes the same
cloud-native runtime baseline as Order: Actuator probes, Prometheus metrics,
Micrometer/OpenTelemetry tracing, structured JSON logs, graceful shutdown,
build/git metadata, and bounded Feign timeout defaults.

From the repo root:

```bash
./scripts/ci-payment-service.sh feature feature/payment-service
./scripts/ci-payment-service.sh main
```
