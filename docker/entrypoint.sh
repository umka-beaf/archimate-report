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

log "starting caddy on :${PORT:-3000}"
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
