# shellcheck shell=bash
# Shared level-aware logging, sourced by entrypoint.sh, generate.sh, and
# model-config.sh — see docs/LOGGING.md. All three (plus archi-webhook,
# which mirrors this same scheme in webhook/main.go, since it can't source
# a bash file) filter on the same LOG_LEVEL env var and print the same
# "<UTC timestamp> [component] LEVEL message" shape, so `docker logs`
# output from every process sorts/greps consistently.
#
# Each sourcing script sets LOG_COMPONENT (e.g. "entrypoint",
# "generate:myslug", "model-config") before calling log_debug/log_info/
# log_warn/log_error — those four are the only entry points meant to be
# called from outside this file.

_log_level_num() {
    case "$1" in
        DEBUG) echo 10 ;;
        INFO) echo 20 ;;
        WARNING) echo 30 ;;
        ERROR) echo 40 ;;
        *) echo 20 ;; # unreachable once LOG_LEVEL itself is validated below
    esac
}

# Validated once, at source time, in every process that sources this file —
# fail fast with a clear message rather than silently falling back to INFO,
# same pattern as WEBHOOK_PROVIDER validation in webhook/main.go.
LOG_LEVEL="${LOG_LEVEL:-INFO}"
case "$LOG_LEVEL" in
    DEBUG | INFO | WARNING | ERROR) ;;
    *)
        printf '%s [log] ERROR LOG_LEVEL must be one of DEBUG, INFO, WARNING, ERROR, got: %s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LOG_LEVEL" >&2
        exit 1
        ;;
esac
_LOG_THRESHOLD="$(_log_level_num "$LOG_LEVEL")"

_log_at() {
    local level="$1"
    shift
    [ "$(_log_level_num "$level")" -ge "$_LOG_THRESHOLD" ] || return 0
    printf '%s [%s] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${LOG_COMPONENT:-?}" "$level" "$*" >&2
}

log_debug() { _log_at DEBUG "$@"; }
log_info() { _log_at INFO "$@"; }
log_warn() { _log_at WARNING "$@"; }
log_error() { _log_at ERROR "$@"; }
