# Logging: LOG_LEVEL

🇬🇧 English · 🇷🇺 [Русский](LOGGING.ru.md)

---

### One shared scheme across three separate processes

`entrypoint.sh`, `generate.sh`, and `archi-webhook` (the Go binary) all write
to the same `docker logs` stream, so they share one format and one filtering
rule rather than each inventing their own:

```
<UTC RFC3339 timestamp> [component] LEVEL message
```

Example: `2026-09-06T16:34:30Z WARNING [webhook] rejected: bad signature (provider=generic, slug="")`

`component` is `entrypoint`, `generate` (or `generate:<slug>` in
[multi-model mode](MULTI_MODEL.md)), or `webhook` (`webhook:<slug>` for
per-model log lines). Archi CLI's own console output (`[HTMLReport] ...`) and
Caddy's own JSON access logs are left exactly as they print them — they're
not "ours" to reformat or filter, only the three processes above follow this
scheme.

### `LOG_LEVEL` — one env var, four levels

| Level | When to use it |
|---|---|
| `DEBUG` | Currently unused by any log line in this project — reserved for future fine-grained tracing |
| `INFO` (default) | Normal operational messages: startup, clone/generation progress, successful publishes |
| `WARNING` | Recoverable problems: a retried git operation, a rejected webhook request, an initial generation that failed for one model in multi-model mode (the container keeps running) |
| `ERROR` | Fatal problems: invalid configuration, a generation that failed and aborted the whole container |

Setting `LOG_LEVEL=WARNING` hides `INFO` lines (startup/progress noise) while
keeping anything that actually needs attention. Setting an invalid value
(anything other than the four above) is a hard, fail-fast startup error —
same pattern as an invalid `WEBHOOK_PROVIDER`:

```
2026-09-06T16:34:39Z [log] ERROR LOG_LEVEL must be one of DEBUG, INFO, WARNING, ERROR, got: TRACE
```

Default, if unset, is `INFO`.

### Implementation notes

- The shell side (`entrypoint.sh`, `generate.sh`, `docker/lib/model-config.sh`)
  shares one library, `docker/lib/log.sh`: it validates `LOG_LEVEL` once at
  source time and exposes `log_debug`/`log_info`/`log_warn`/`log_error`. Each
  sourcing script sets its own `LOG_COMPONENT` variable beforehand (e.g.
  `"generate:myslug"`), which the library reads to fill in the `[component]`
  tag.
- The Go webhook can't `source` a bash file, so `docker/webhook/main.go`
  reimplements the same validation and the same four-level filtering natively
  (`initLogLevel()`, `logDebug`/`logInfo`/`logWarn`/`logError`) — it keeps its
  pre-existing convention of embedding the `[webhook]`/`[webhook:slug]` tag as
  literal text inside each message, rather than as a separate field.
- `initLogLevel()` runs as the very first statement of the Go binary's
  `main()`, before anything that could log an error (e.g. a bad
  `MODEL_<N>_SLUG`) — the level filter has to be live before the first
  possible log call.
