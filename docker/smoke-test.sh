#!/usr/bin/env bash
# Release smoke test — run this before every `docker buildx build --push`
# release (see CLAUDE.md §16 for why there's no CI: releases are manual,
# triggered by a new Archi version, not by every git push).
#
# Builds the image for the *host* platform only (buildx --load can't load a
# multi-arch manifest list — that's fine, this script exists to catch
# regressions in generate.sh/entrypoint.sh/Caddyfile/webhook logic, which are
# arch-independent; §20/M4 already separately verified that the arm64 Tycho
# build itself produces a byte-identical report to amd64 on real arm64
# hardware, so this script doesn't need to re-run that part every time).
#
# What it checks, against two known public test repos (same ones used
# throughout M1-M5, see CLAUDE.md §17-§21):
#   1. plain-format repo + explicit MODEL_PATH  -> HTTP 200, non-empty report
#   2. coArchi-format repo, auto-detected       -> HTTP 200, non-empty report
#   3. /status endpoint responds with valid JSON on both
#   4. webhook round-trip (generic provider) triggers a real regeneration
#
# Usage:
#   ./docker/smoke-test.sh                       # build + test, ARCHI_VERSION=latest
#   ARCHI_VERSION=5.9.0 ./docker/smoke-test.sh    # pin a version
#   SKIP_BUILD=1 IMAGE=archi-report:m5 ./docker/smoke-test.sh   # reuse an existing image
#
# Exit code 0 = all checks passed. Non-zero = something regressed; read the
# log above the failing check before doing a real --push release.

set -euo pipefail

log() { printf '%s [smoke-test] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() {
    log "FAIL: $*"
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-archi-report:smoke-test}"
ARCHI_VERSION="${ARCHI_VERSION:-latest}"
PLAIN_REPO="https://github.com/archimatetool/ArchiModels.git"
PLAIN_MODEL_PATH="Archisurance/Archisurance.archimate"
COARCHI_REPO="https://github.com/GLYCAM-Web/coArchi-GLYCAM-Web.git"

CONTAINERS=()
cleanup() {
    local c
    for c in "${CONTAINERS[@]:-}"; do
        [ -n "$c" ] && docker rm -f "$c" > /dev/null 2>&1 || true
    done
}
trap cleanup EXIT

if [ -z "${SKIP_BUILD:-}" ]; then
    log "building $IMAGE (ARCHI_VERSION=$ARCHI_VERSION, host platform only)"
    docker buildx build \
        --load \
        --build-arg "ARCHI_VERSION=$ARCHI_VERSION" \
        -t "$IMAGE" \
        "$SCRIPT_DIR" \
        || die "docker build failed"
else
    log "SKIP_BUILD set — reusing existing image $IMAGE"
fi

wait_for_http() {
    # wait_for_http <url> <timeout_seconds>
    local url="$1" timeout="$2" waited=0
    while ! curl -fsS -o /dev/null "$url" 2> /dev/null; do
        waited=$((waited + 1))
        [ "$waited" -ge "$timeout" ] && return 1
        sleep 1
    done
    return 0
}

check_report() {
    # check_report <label> <port> <expect_title_substring>
    local label="$1" port="$2" expect="$3"
    log "[$label] waiting for report on :$port"
    wait_for_http "http://127.0.0.1:$port/status" 60 || {
        docker logs "${CONTAINERS[-1]}" 2>&1 | tail -50
        die "[$label] container never became reachable (30s+)"
    }

    local status_json body_bytes
    status_json=$(curl -fsS "http://127.0.0.1:$port/status") || die "[$label] /status did not respond"
    printf '%s\n' "$status_json" | grep -q '"generating"' || die "[$label] /status response missing expected field: $status_json"
    log "[$label] /status OK: $status_json"

    curl -fsS -o /dev/null "http://127.0.0.1:$port/" || die "[$label] report root did not respond HTTP 200"
    body_bytes=$(curl -fsS "http://127.0.0.1:$port/" | wc -c)
    [ "$body_bytes" -gt 0 ] || die "[$label] index.html served empty (see archi#980, CLAUDE.md §25)"
    curl -fsS "http://127.0.0.1:$port/" | grep -qi "$expect" || die "[$label] report body missing expected title substring: $expect"
    log "[$label] report OK: $body_bytes bytes, title contains '$expect'"
}

# --- Test 1: plain format, explicit MODEL_PATH ---
log "[plain] starting container"
C1=$(docker run -d \
    -p 3101:3000 \
    -e GIT_URL="$PLAIN_REPO" \
    -e MODEL_PATH="$PLAIN_MODEL_PATH" \
    "$IMAGE")
CONTAINERS+=("$C1")
check_report "plain" 3101 "Archisurance"

# --- Test 2: coArchi format, auto-detected, webhook enabled (generic) ---
log "[coarchi] starting container"
C2=$(docker run -d \
    -p 3102:3000 \
    -e GIT_URL="$COARCHI_REPO" \
    -e WEBHOOK_SECRET="smoke-test-secret" \
    -e WEBHOOK_PROVIDER="generic" \
    "$IMAGE")
CONTAINERS+=("$C2")
check_report "coarchi" 3102 "GLYCAM-Web"

log "[coarchi] triggering webhook"
WEBHOOK_RESP=$(curl -fsS -o /dev/null -w '%{http_code}' -X POST \
    -H "X-Webhook-Secret: smoke-test-secret" \
    "http://127.0.0.1:3102/webhook")
[ "$WEBHOOK_RESP" = "202" ] || die "[coarchi] webhook trigger expected HTTP 202, got $WEBHOOK_RESP"
log "[coarchi] webhook accepted (202), waiting for regeneration to finish"
sleep 5
curl -fsS "http://127.0.0.1:3102/status" | grep -q '"generating":false' || die "[coarchi] regeneration still running after 5s — check container logs"
log "[coarchi] webhook regeneration OK"

# --- Test 2b: wrong webhook secret must be rejected ---
WEBHOOK_REJECT=$(curl -fsS -o /dev/null -w '%{http_code}' -X POST \
    -H "X-Webhook-Secret: wrong-secret" \
    "http://127.0.0.1:3102/webhook")
[ "$WEBHOOK_REJECT" = "401" ] || die "[coarchi] webhook with wrong secret expected HTTP 401, got $WEBHOOK_REJECT"
log "[coarchi] webhook auth rejection OK (401)"

log "ALL CHECKS PASSED — image $IMAGE looks safe to publish"
