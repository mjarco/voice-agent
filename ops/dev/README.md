# ops/dev — local dev-flavor observability

Operational config for the P039 dev-flavor telemetry pipeline. Two
deployable stacks live here; pick the one that matches what you're
doing today.

| Compose | Services | When to use |
|---|---|---|
| `collector-only.docker-compose.yml` | OTel Collector with stdout debug exporter only | Spike + plumbing checks. Verify Dart → Collector works without standing up Tempo. ~30 LOC. |
| `telemetry.docker-compose.yml` | OTel Collector + Tempo (single binary) | Real deployment. Traces land in Tempo, metrics remote-write to the home Prometheus. Pair with the dashboard provisioning under `ops/dev/grafana/`. |

## Spike: Collector only

```bash
cd ops/dev
docker compose -f collector-only.docker-compose.yml up -d
```

Verify the OTLP HTTP endpoint:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
    -X POST http://localhost:4318/v1/traces \
    -H 'Content-Type: application/json' \
    --data '{"resourceSpans":[]}'
# expect: 200
```

The Collector logs every received OTLP request to stdout via the `debug`
exporter — useful for `docker logs voice-agent-otel-spike` live tailing.

Stop:

```bash
docker compose -f collector-only.docker-compose.yml down
```

## Full deployment

```bash
cd ops/dev
docker compose -f telemetry.docker-compose.yml up -d
```

Verify everything is healthy:

```bash
# Collector OTLP receiver
curl -s -o /dev/null -w "Collector %{http_code}\n" \
    -X POST http://localhost:4318/v1/traces \
    -H 'Content-Type: application/json' -d '{}'
# expect: Collector 200

# Tempo API
curl -s -o /dev/null -w "Tempo %{http_code}\n" http://localhost:3200/ready
# expect: Tempo 200
```

This stack assumes the home Prometheus + Grafana are already running
on the same host (or reachable over the docker network). For the
home Prometheus to receive metrics from the Collector, point its
`remote_write` URL config or check that
`http://host.docker.internal:9090/api/v1/write` is accessible from
within the Collector container.

Two additional one-time installs into the home Grafana for the dashboard
to work — see [`../../docs/observability.md`](../../docs/observability.md)
for the step-by-step.

Stop:

```bash
docker compose -f telemetry.docker-compose.yml down
```

## Files

- `collector-only.docker-compose.yml` — single-service spike compose
- `telemetry.docker-compose.yml` — full stack (Collector + Tempo)
- `otel-collector-config.yml` — Collector config for the spike (debug exporter only)
- `otel-collector-full-config.yml` — Collector config for the full stack (Tempo + Prometheus remote-write + debug)
- `tempo/tempo.yaml` — Tempo single-binary config
- `grafana/provisioning/datasources/voice-agent.yml` — Grafana data source provisioning, drop into the home Grafana once
- `grafana/provisioning/dashboards/voice-agent.yml` — Grafana dashboard provider config; the actual dashboard JSON lives at `../grafana/voice-agent-dev.json`
