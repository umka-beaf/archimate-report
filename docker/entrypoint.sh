#!/usr/bin/env bash
set -euo pipefail

log() { echo "[entrypoint] $*" >&2; }

: "${GIT_URL:?GIT_URL is required}"
REGENERATE_ON_START="${REGENERATE_ON_START:-true}"

if [ "$REGENERATE_ON_START" = "true" ]; then
    log "running initial generation"
    /usr/local/bin/generate.sh
elif [ ! -f /data/report/index.html ]; then
    log "REGENERATE_ON_START=false but /data/report is empty — generating anyway (nothing to serve otherwise)"
    /usr/local/bin/generate.sh
else
    log "REGENERATE_ON_START=false, reusing existing /data/report"
fi

log "starting archi-webhook (internal, proxied by caddy at ${WEBHOOK_PATH:-/webhook} and /status)"
/usr/local/bin/archi-webhook &
WEBHOOK_PID=$!

# CADDY_PID is not set yet at this point — default it to empty so the trap
# (which may fire before the caddy launch below) doesn't hit an unbound
# variable under `set -u`.
CADDY_PID=""
trap 'kill "$WEBHOOK_PID" 2>/dev/null || true; [ -n "$CADDY_PID" ] && kill "$CADDY_PID" 2>/dev/null || true' TERM INT

log "starting caddy on :${PORT:-3000}"
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY_PID=$!

# Either process exiting is fatal for the container — fail fast rather than
# run half-alive (e.g. caddy up but webhook-listener dead, silently dropping
# regeneration requests).
wait -n "$WEBHOOK_PID" "$CADDY_PID"
STATUS=$?
kill "$WEBHOOK_PID" 2>/dev/null || true
kill "$CADDY_PID" 2>/dev/null || true
exit "$STATUS"
