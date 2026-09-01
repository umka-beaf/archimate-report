## Caddy setup

archimate-report has a single public-facing process: [Caddy](https://caddyserver.com/),
listening on `$PORT` (default `3000`). Everything else in the container —
report generation, the webhook listener — is internal.

### What Caddy does

`docker/Caddyfile` (baked into the image, not user-editable at runtime):

```caddyfile
:{$PORT} {
	handle {$WEBHOOK_PATH:/webhook}* {
		reverse_proxy 127.0.0.1:8088
	}
	handle /status {
		reverse_proxy 127.0.0.1:8088
	}
	handle {
		root * /data/report
		file_server
	}
	encode gzip
}
```

- `handle {$WEBHOOK_PATH:/webhook}*` and `handle /status` proxy to the Go
  webhook listener (`archi-webhook`), which binds **only** to
  `127.0.0.1:8088` — it's never reachable directly, only through this proxy.
  If `WEBHOOK_SECRET` isn't set, the listener itself answers 404 on the
  webhook path (see [README](../README.md#webhook)) — Caddy's config doesn't
  change either way.
- Everything else falls through to `file_server` on `/data/report` — the
  report [generate.sh](../docker/generate.sh) atomically publishes into.
- `encode gzip` compresses the static HTML/CSS/JS on the way out — the report
  is generated fresh with no persistent compressed variants on disk.

### What Caddy deliberately doesn't do

- **No TLS termination.** `auto_https off`, plain HTTP on `$PORT`. This
  image is meant to sit behind your own reverse proxy (another Caddy
  instance, Traefik, nginx, a cloud load balancer) if you need HTTPS — see
  the `docker-compose.yml` example in the [README](../README.md#docker-compose)
  (Russian section — the example itself isn't duplicated in English), which
  assumes exactly that setup (external `common` network, no published
  `ports:`).
- **No log files.** `log { output stdout; format console }` at the global
  level, and no `log` directive at all inside the site block — everything
  goes to `docker logs`, nothing is ever written to `/data` or anywhere else
  on disk. There's no log file to rotate or grow unbounded.
- **No admin API.** `admin off` — the config is static for the container's
  lifetime, there's no runtime reconfiguration surface to expose or secure.

### Why atomic publishing matters here

`file_server` reads `/data/report` directly off disk on every request — there's
no in-memory cache to invalidate. If a regeneration (webhook-triggered or
otherwise) replaced files in place while Caddy was serving them, a request
could race a half-written report. `generate.sh` avoids this by generating
into a temporary directory, validating it (non-empty `index.html` — see
[archi#980](https://github.com/archimatetool/archi/issues/980)), and only
then replacing the contents of `/data/report` — see the "Volumes" section in
the [README](../README.md#volumes) for the mount-point-safe version of that
swap.
