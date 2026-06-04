# Payment API

This project publishes the Payment OpenAPI contract as a Maven-compatible YAML
artifact for the lab.

Artifact coordinates:

```text
dev.teeter.demos.apis:payment-api-spec:<version>@yaml
```

From the repository root, simulate CI with:

```bash
./scripts/ci-payment-api.sh feature feature/payment-api
./scripts/ci-payment-api.sh main
```
