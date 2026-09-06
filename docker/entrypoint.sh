#!/usr/bin/env bash
set -euo pipefail

# Timestamp format matches generate.sh's log() and archi-webhook's logf()
# (see webhook/main.go) so `docker logs` output from all three processes
# sorts/greps consistently — deliberately not full JSON, this is a
# single-container service with no downstream log aggregator, plain
# timestamped prefixes are enough to correlate events across processes.
log() { printf '%s [entrypoint] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }

# shellcheck source=docker/lib/model-config.sh
source /usr/local/lib/model-config.sh
# shellcheck source=docker/lib/report-stub.sh
source /usr/local/lib/report-stub.sh

REGENERATE_ON_START="${REGENERATE_ON_START:-true}"

# run_initial_generation <report_dir> <generate.sh args...> — shared between
# legacy and multi-model modes below, just varies which REPORT_DIR to check
# and what to pass to generate.sh (nothing, or a model index).
run_initial_generation() {
    local report_dir="$1"
    shift
    if [ "$REGENERATE_ON_START" = "true" ]; then
        /usr/local/bin/generate.sh "$@"
    elif [ ! -f "$report_dir/index.html" ]; then
        log "REGENERATE_ON_START=false but $report_dir is empty — generating anyway (nothing to serve otherwise)"
        /usr/local/bin/generate.sh "$@"
    else
        log "REGENERATE_ON_START=false, reusing existing $report_dir"
    fi
}

# Deliberately not `mapfile -t ... < <(mc_model_indices)` — that reads
# through process substitution, which runs in a subshell whose exit status
# is invisible to the parent. If mc_model_indices dies (e.g. on a duplicate
# slug), the subshell exit would be silently swallowed and we'd wrongly fall
# through to legacy mode instead of failing the whole container loudly.
if ! MODEL_INDICES_OUTPUT="$(mc_model_indices)"; then
    exit 1 # mc_model_indices already logged the reason via mc_die
fi
MODEL_INDICES=()
[ -n "$MODEL_INDICES_OUTPUT" ] && mapfile -t MODEL_INDICES <<< "$MODEL_INDICES_OUTPUT"

if [ "${#MODEL_INDICES[@]}" -eq 0 ]; then
    # Legacy single-model mode — unchanged behavior from before multi-model
    # support existed.
    : "${GIT_URL:?GIT_URL is required}"
    log "running initial generation"
    run_initial_generation /data/report
else
    [ -z "${GIT_URL:-}" ] || log "WARNING: GIT_URL is set but MODEL_<N>_SLUG vars were found — running in multi-model mode, bare GIT_URL is ignored (see CLAUDE.md §32.2)"
    log "multi-model mode: found ${#MODEL_INDICES[@]} model(s): ${MODEL_INDICES[*]}"

    # Root landing page (§32.4) — deliberately overwritten unconditionally on
    # every start: in multi-model mode /data/report itself is never a real
    # report (generate.sh only ever writes into /data/report/<slug>/), so
    # there's nothing of value to preserve here between restarts.
    mc_publish_stub /data/report "ArchiMate Report Service" \
        "<p>This instance serves multiple ArchiMate model reports, each published under its own path. Ask your administrator for the direct link to the report you need.</p>"

    for n in "${MODEL_INDICES[@]}"; do
        slug="$(mc_model_slug "$n")"
        report_dir="/data/report/$slug"

        # Give a stub page to anything hitting this model's path before its
        # first successful generation exists — otherwise it's a bare Caddy
        # 404 with no indication of whether the slug is wrong or generation
        # just hasn't finished/succeeded yet. Only written when no report is
        # present yet (e.g. a persisted /data/report volume from a previous
        # run keeps its real report across restarts, stub or not).
        if [ ! -f "$report_dir/index.html" ]; then
            mc_publish_stub "$report_dir" "Report not yet available" \
                "<p>This model's report has not been generated yet, or the last generation attempt failed. Check <code>docker logs</code> or <code>/status</code> for details.</p>"
        fi

        log "running initial generation for model $n (slug: $slug)"
        # A single model failing to generate at startup must not take down
        # the whole container (§32.6) — the other models, if any, may still
        # be perfectly fine to serve. `if ! cmd; then ...; fi` is exempt from
        # `set -e`'s errexit (commands in an if/while/until condition never
        # trigger it), so this needs no extra `|| true` workaround.
        if ! run_initial_generation "$report_dir" "$n"; then
            log "WARNING: initial generation for model $n (slug: $slug) failed — continuing with other models, see $report_dir for its stub/previous state"
        fi
    done
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

kill "$WEBHOOK_PID" 2> /dev/null || true
kill "$CADDY_PID" 2> /dev/null || true
exit "$STATUS"
