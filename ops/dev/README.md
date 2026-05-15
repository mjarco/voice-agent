# ops/dev — local dev-flavor observability

This directory holds operational config for the dev-flavor telemetry pipeline
introduced by P039. Two files at the time of writing:

- `collector-only.docker-compose.yml` — minimal OTel Collector for the **T1
  spike**. Only an OTLP HTTP receiver + debug stdout exporter. ~30 LOC.
- `otel-collector-config.yml` — Collector pipeline config used by the
  spike compose.

A full backend stack (Collector → Tempo → Prometheus remote-write + Grafana
data sources) lands in T2 as `telemetry.docker-compose.yml`. Until that
ships, only the spike compose is here.

## Running the spike Collector locally

```bash
cd ops/dev
docker compose -f collector-only.docker-compose.yml up
```

Verify it's listening:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
    -X POST http://localhost:4318/v1/traces \
    -H 'Content-Type: application/json' \
    --data '{"resourceSpans":[]}'
# expect: 200
```

The Collector logs every received OTLP request to stdout via the `debug`
exporter, so you can watch it process spans live.

## Stopping

```bash
docker compose -f collector-only.docker-compose.yml down
```

## Deploying to `laptop.lan`

The Collector binds to `0.0.0.0`, so when this compose runs on the
laptop host (the one resolved by `laptop.lan`) the phone on the same
LAN can POST to `http://laptop.lan:4318/v1/traces` directly. No
auth — see P039 §Wire format and transport for the rationale.
