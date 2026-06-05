# k3s lab todo list

This is the living backlog for cross-cutting lab work that does not belong to a
single phase walkthrough. Keep items concise, update them as requirements
change, and move detailed designs into focused docs when work starts.

## Open

- [ ] Define and enforce an Observability Contract v0.1.
  - Document the required application label, metric, log, trace, and health
    endpoint shape.
  - Add validation that checks rendered manifests for required labels,
    annotations, probes, and scrape settings.
  - Add optional live checks that query Prometheus/Loki for expected labels on a
    deployed workload.
  - Treat the contract, chart defaults, dashboards, and checks as versioned
    living artifacts that evolve together.

- [ ] Define and enforce a Logging Contract v0.1.
  - Document required common fields such as timestamp, level, message, logger,
    trace ID, span ID, service name, service version, environment, and exception
    fields.
  - Align field names with OpenTelemetry semantic conventions where practical.
  - Keep stable platform dimensions as Loki labels and high-cardinality values
    inside structured log content or metadata.
  - Extend Alloy to parse JSON logs and normalize common legacy formats such as
    WildFly/JBoss text logs, logfmt, Go text logs, and multiline Java stack
    traces.
  - Add runtime conformance dashboards for parseable logs, missing levels,
    missing trace IDs, and top unstructured workloads.
  - Add CI or runtime checks for apps that claim logging-contract compliance.

## Done
