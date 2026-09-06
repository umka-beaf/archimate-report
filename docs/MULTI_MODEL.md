# Multi-model mode

🇬🇧 English · 🇷🇺 [Русский](MULTI_MODEL.ru.md)

---

A single service instance can serve reports for several ArchiMate models at
once (different repositories, or different models within one repository),
each under its own URL path `/<slug>/`. This document is the practical
contract: how to turn it on, what changes, what doesn't.

### How to enable it

There's no explicit switch — the mode is auto-detected. If the container's
environment has at least one `MODEL_<N>_SLUG` variable (`<N>` any integer),
the service runs entirely in multi-model mode. If none is present, it works
exactly as before — a single model via a bare `GIT_URL` (see the main
README).

`<N>` doesn't need to be sequential or start at 1 — models can be added one
at a time without renumbering neighbors: `MODEL_1_*`/`MODEL_2_*` today,
`MODEL_7_*` added six months later, nothing about 1 or 2 needs to change.

### Environment variables

**Per model** (replace `<N>` with the model's number) — the same contract as
a single model, just prefixed with `MODEL_<N>_`:

| Variable | Required | Description |
|---|---|---|
| `MODEL_<N>_SLUG` | yes (marks the model) | URL path segment: ASCII letters/digits/hyphens only (`^[A-Za-z0-9-]+$`) |
| `MODEL_<N>_GIT_URL` | yes | Repository URL |
| `MODEL_<N>_GIT_REF` | no | branch/tag/commit |
| `MODEL_<N>_MODEL_PATH` | no | path to the `.archimate` file or coArchi repo root |
| `MODEL_<N>_MODEL_FORMAT` | no | `auto` / `plain` / `coarchi` |
| `MODEL_<N>_GIT_TOKEN` | no* | HTTPS token |
| `MODEL_<N>_GIT_USERNAME` / `MODEL_<N>_GIT_PASSWORD` | no* | login+password for HTTPS |
| `MODEL_<N>_GIT_SSH_PRIVATE_KEY` | no* | private SSH key |
| `MODEL_<N>_GIT_SSH_KNOWN_HOSTS` | no | known_hosts for this model |
| `MODEL_<N>_GENERATION_TIMEOUT` | no | generation timeout for this model, seconds (default `600`) |

`*` — exactly one git auth method per model (or none, for public
repositories). Different models can use different auth methods and
different `GIT_REF`/`MODEL_FORMAT` independently of each other.

**Instance-wide** (unprefixed, as before) — `WEBHOOK_SECRET`, `PORT`, `TZ`,
`REGENERATE_ON_START`, `USE_MODERN_CSS`. The service has a single owner, so
one webhook secret and one theme apply to all models — a deliberate
trade-off, not an oversight (a future per-model override for the latter two
isn't ruled out, but isn't implemented). `WEBHOOK_PATH` isn't consulted at
all in multi-model mode — a model's webhook path is always
`/<slug>/webhook`, not separately configurable.

A bare `GIT_URL` (unprefixed) in multi-model mode is **not** treated as a
"model zero" — it's simply ignored, with a warning logged
(`GIT_URL is set but MODEL_<N>_SLUG vars were found — ...`). Migrating from
a single model to multiple is manual: move the old `GIT_*` vars into
`MODEL_1_*` and give it a `MODEL_1_SLUG`.

### Example

```bash
docker run -d \
  --name archimate-report \
  -p 3000:3000 \
  -e MODEL_1_SLUG=archisurance \
  -e MODEL_1_GIT_URL=https://github.com/archimatetool/ArchiModels.git \
  -e MODEL_1_MODEL_PATH=Archisurance/Archisurance.archimate \
  -e MODEL_2_SLUG=glycam \
  -e MODEL_2_GIT_URL=https://github.com/GLYCAM-Web/coArchi-GLYCAM-Web.git \
  -e WEBHOOK_SECRET=change-me \
  -e WEBHOOK_PROVIDER=generic \
  umkabeaf/archimate-report:latest
```

Reports will be available at `http://localhost:3000/archisurance/` and
`http://localhost:3000/glycam/`.

### docker-compose example

<details>
<summary>Three models in one instance, YAML anchors for the shared bits</summary>

```yaml
x-image: &image umkabeaf/archimate-report:latest
x-tz: &tz Europe/Moscow

services:
  archi-report:
    restart: unless-stopped
    image: *image
    hostname: archi-report
    container_name: archi-report
    ports:
      - "3000:3000"
    environment:
      TZ: *tz
      WEBHOOK_SECRET: replace-me
      WEBHOOK_PROVIDER: generic
      # ── Model 1: plain .archimate file, token auth ──
      MODEL_1_SLUG: archisurance
      MODEL_1_GIT_URL: https://github.com/archimatetool/ArchiModels.git
      MODEL_1_MODEL_PATH: Archisurance/Archisurance.archimate
      MODEL_1_GIT_TOKEN: ghp_xxx
      # ── Model 2: coArchi repo, auto-detected format, public ──
      MODEL_2_SLUG: glycam
      MODEL_2_GIT_URL: https://github.com/GLYCAM-Web/coArchi-GLYCAM-Web.git
      # ── Model 3: private repo over SSH ──
      MODEL_3_SLUG: internal-arch
      MODEL_3_GIT_URL: git@git.example.com:team/internal-model.git
      MODEL_3_GIT_SSH_PRIVATE_KEY: |
        -----BEGIN OPENSSH PRIVATE KEY-----
        ...
        -----END OPENSSH PRIVATE KEY-----
    volumes:
      - archi-report-data:/data/report
      - archi-report-repo:/data/repo
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:3000/status"]
      interval: 30s
      timeout: 3s
      start_period: 10s
      retries: 3

volumes:
  archi-report-data:
  archi-report-repo:
```

One instance, one `WEBHOOK_SECRET`/`WEBHOOK_PROVIDER` for all three models
(see [docs/SECURITY.md](SECURITY.md) for why that's a deliberate trade-off,
not an oversight). Reports end up at `/archisurance/`, `/glycam/`, and
`/internal-arch/`. As with the single-model compose example in the main
README, this container isn't behind a reverse-proxy here — add the same
`x-network`/external-network pattern from there if you need path-based
forward-auth (see [docs/SECURITY.md](SECURITY.md)).

</details>

### File layout

The same three volumes as single-model mode (see the README's "Volumes"
section), each with a slug subdirectory — mounting `/data` as a whole still
works:

```
/data/repo/<slug>/
/data/report/<slug>/
/data/secrets/<slug>/
```

### `/` and placeholder pages

In multi-model mode, `/` serves a static, deliberately anonymous placeholder
page — it **doesn't list** the configured slugs: the model list is a
potential information leak around an external auth layer, so discovering a
given model's URL is left to the administrator/this document, not the
service itself. The same placeholder mechanism
(different text) is served at `/<slug>/` until that model has had at least
one successful generation — not a bare 404, but a clear message pointing at
`docker logs`/`/<slug>/status`. Once a real report exists
(`index.html` under `/data/report/<slug>/`), the placeholder no longer
overwrites it — including across a container restart with a persistent
volume.

A path that doesn't match any known model (e.g. `/nosuchmodel/`) gets a
plain Caddy 404 — the placeholders don't intercept arbitrary paths.

### Per-model webhook and `/status`

Every discovered model gets its own `/<slug>/webhook` and `/<slug>/status`
— the verification schemes are the same as documented in
[docs/WEBHOOK.md](WEBHOOK.md), just with the slug as a path prefix. The root
`GET /status` is simplified to `{"generating": bool}` in multi-model mode —
not tied to any specific model (same rationale as the `/` placeholder: don't
give a way to guess/confirm the model list via a shared endpoint). For a
given model's detailed status, use `GET /<slug>/status`, the full JSON
`{generating, last_run_at, last_success, last_error}`, same shape as
single-model mode.

### Generation queue

One shared sequential worker for the whole container, not one per model —
different models' generations never run in parallel. Debouncing is
per-slug: a repeated trigger for a model that's already queued or already
running doesn't add a second entry, it just "catches up" after the current
run finishes. A trigger for a different model isn't blocked meanwhile — it
joins the same queue and is processed in turn. Example: three webhooks in a
row (model A, model B, model A again) produce a strictly sequential
`A → B → A` processing order, never in parallel, and the last A trigger is
never dropped.

On container start (`REGENERATE_ON_START=true`, the default), every
discovered model is queued in ascending `<N>` order — on an instance with
20+ models, the combined startup time can be noticeable; this is an
accepted trade-off, there's no "skip this model at startup" flag.

### Startup failure handling

Unlike single-model mode (where a failed startup generation kills the whole
container — there's nothing else to serve anyway), in multi-model mode one
model failing to generate at startup does **not** stop the container — a
warning is logged for that model specifically, the rest still come up and
publish normally. For a model that has generated successfully before and
fails on a later webhook trigger, behavior matches single-model mode — the
previous valid report stays in place (see the README's notes on protecting
the report across a failed regeneration).

### Authentication

The service doesn't implement authentication itself in either mode — see
[docs/SECURITY.md](SECURITY.md), especially the section on not breaking
real webhooks with an external proxy rule applied to all of `/<slug>/*`.
