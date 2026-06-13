# Moonstat

Moonstat is the MoonBit-native local proxy/statistics gateway for the Moon
suite. It is a standalone app and also fits beside:

- MoonClaw: agent runtime and job executor
- MoonBook: durable books, wiki, and output workspace
- Moontown: scheduler and town control plane
- Moondesk: desktop operator shell

The proxy listens on the same default address as ccs: `127.0.0.1:15721`.

## Run

```sh
moon run cmd/main -- start
```

Use a custom bind address or port:

```sh
moon run cmd/main -- start --host 127.0.0.1 --port 15721
```

Login uses Codex OAuth credentials:

```sh
moon run cmd/main -- login
```

Status and counters:

```sh
moon run cmd/main -- health
moon run cmd/main -- status
moon run cmd/main -- stats
```

## Proxy Surface

Moonstat currently exposes the ccs-compatible local routes below:

- `GET /health`
- `GET /status`
- `GET /stats`
- `GET /models`
- `GET /v1/models`
- `GET /claude-desktop/v1/models`
- `POST /v1/messages`
- `POST /claude/v1/messages`
- `POST /claude-desktop/v1/messages`
- `POST /responses`
- `POST /v1/responses`
- `POST /v1/v1/responses`
- `POST /codex/v1/responses`
- `POST /responses/compact`
- `POST /v1/responses/compact`
- `POST /v1/v1/responses/compact`
- `POST /codex/v1/responses/compact`
- `POST /chat/completions`
- `POST /v1/chat/completions`
- `POST /v1/v1/chat/completions`
- `POST /codex/v1/chat/completions`

`/status` and `/stats` include ccs-style request counts, success/failure
counts, active connections, token totals, cache token totals, last request time,
last error, current provider metadata, and success rate.

## Suite Role

Moonstat is the network edge for local Moon apps. Point Codex-style clients,
MoonClaw provider checks, or Moondesk/Moontown integration probes at
`http://127.0.0.1:15721` and use `/status` or `/stats` for health dashboards.

MoonBook remains the durable output owner, Moontown owns scheduling and standing
goals, MoonClaw owns execution, and Moondesk owns the local operator UI.
Moonstat owns local traffic rerouting and usage/statistics accounting.
