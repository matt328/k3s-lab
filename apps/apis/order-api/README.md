# Order API

This is the lab-local Order API artifact project. It publishes the OpenAPI
contract consumed by `order-service` and, later, any other service that needs an
Order client.

The production target is one repository per API artifact. For this lab, the
project is vendored under `apps/apis/order-api` so the platform can be rebuilt
and demonstrated without external CI access to the LAN-only artifact registry.

## Artifact

```text
group:    dev.teeter.demos.apis
artifact: order-api-spec
type:     yaml
```

The CI simulation script publishes immutable feature/main versions to the
lab-local Reposilite registry:

```text
http://maven.b.lab.home/releases
```

## Local CI simulation

From the repo root:

```bash
./scripts/ci-order-api.sh feature feature/order-api-change
./scripts/ci-order-api.sh main
```

The script uses this project's checked-in Gradle wrapper. The Foojay toolchain
resolver is configured for Gradle Java toolchains, so Gradle can provision the
requested JDK for Java-based tasks when needed. A Java runtime is still required
to launch Gradle itself.

