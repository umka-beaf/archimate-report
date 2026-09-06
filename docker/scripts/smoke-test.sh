#!/usr/bin/env bash
# Release smoke test — run this before every `docker buildx build --push`
# release (releases are manual, triggered by a new Archi version, not by
# every git push — see the README's "Building and publishing the image" section).
#
# Builds the image for the *host* platform only (buildx --load can't load a
# multi-arch manifest list — that's fine, this script exists to catch
# regressions in generate.sh/entrypoint.sh/Caddyfile/webhook logic, which are
# arch-independent; §20/M4 already separately verified that the arm64 Tycho
# build itself produces a byte-identical report to amd64 on real arm64
# hardware, so this script doesn't need to re-run that part every time).
#
# What it checks, against two known public test repos (same ones used
# throughout the project's testing):
#   1. plain-format repo + explicit MODEL_PATH  -> HTTP 200, non-empty report
#   2. coArchi-format repo, auto-detected       -> HTTP 200, non-empty report
#   3. /status endpoint responds with valid JSON on both
#   4. webhook round-trip (generic provider) triggers a real regeneration
#   5. multi-model mode (see docs/MULTI_MODEL.md): three MODEL_<N>_* models (one
#      plain, one coArchi, one deliberately broken) -> root placeholder
#      doesn't leak slugs, per-slug reports/stubs/webhooks/status routes all
#      work, an unknown slug 404s, and one model failing at startup doesn't
#      take the container down with it
#
# Usage:
#   ./docker/scripts/smoke-test.sh                       # build + test, ARCHI_VERSION=latest
#   ARCHI_VERSION=5.9.0 ./docker/scripts/smoke-test.sh    # pin a version
#   SKIP_BUILD=1 IMAGE=archi-report:m5 ./docker/scripts/smoke-test.sh   # reuse an existing image
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
# Build context is the repo root, same as the real release build (see
# README.md "Building and publishing the image") — the Dockerfile pulls
# favicon assets from assets/favicon/, one level up from docker/. This script
# lives in docker/scripts/, two levels below the repo root.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE="${IMAGE:-archi-report:smoke-test}"
ARCHI_VERSION="${ARCHI_VERSION:-latest}"
PLAIN_REPO="https://github.com/archimatetool/ArchiModels.git"
PLAIN_MODEL_PATH="Archisurance/Archisurance.archimate"
COARCHI_REPO="https://github.com/GLYCAM-Web/coArchi-GLYCAM-Web.git"

CONTAINERS=()
cleanup() {
    local c
    for c in "${CONTAINERS[@]:-}"; do
        if [ -n "$c" ]; then docker rm -f "$c" > /dev/null 2>&1 || true; fi
    done
}
trap cleanup EXIT

if [ -z "${SKIP_BUILD:-}" ]; then
    log "building $IMAGE (ARCHI_VERSION=$ARCHI_VERSION, host platform only)"
    docker buildx build \
        --load \
        -f "$REPO_ROOT/docker/Dockerfile" \
        --build-arg "ARCHI_VERSION=$ARCHI_VERSION" \
        -t "$IMAGE" \
        "$REPO_ROOT" \
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

    # Below, grep -q against a variable's content uses a herestring
    # (`grep ... <<<"$x"`), never a pipe (`printf ... | grep -q ...`).
    # grep -q exits the instant it finds a match, which - piped from a
    # live writer - sends that writer SIGPIPE if it's still writing; under
    # `set -o pipefail` (enabled above) that writer's non-zero exit status
    # wins over grep's own success, failing the check even though the match
    # was found. A herestring has no separate writer process racing grep,
    # so it doesn't hit this. Found running this script for real for the
    # first time — it had been silently broken since it was written until then.
    local status_json body_bytes
    status_json=$(curl -fsS "http://127.0.0.1:$port/status") || die "[$label] /status did not respond"
    grep -q '"generating"' <<< "$status_json" || die "[$label] /status response missing expected field: $status_json"
    log "[$label] /status OK: $status_json"

    curl -fsS -o /dev/null "http://127.0.0.1:$port/" || die "[$label] report root did not respond HTTP 200"
    body=$(curl -fsS "http://127.0.0.1:$port/")
    body_bytes=${#body}
    [ "$body_bytes" -gt 0 ] || die "[$label] index.html served empty (see archi#980: https://github.com/archimatetool/archi/issues/980)"
    grep -qi "$expect" <<< "$body" || die "[$label] report body missing expected title substring: $expect"
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
# Poll instead of a single fixed sleep+check - a flat "sleep 5" is a flaky
# test under host load (observed one run take just over 5s here for a repo
# that normally finishes in ~2s), and there's no reason to hard-fail just
# because the box was briefly busy.
WEBHOOK_DONE=0
for _ in $(seq 1 20); do
    STATUS_AFTER_WEBHOOK=$(curl -fsS "http://127.0.0.1:3102/status")
    if grep -q '"generating":false' <<< "$STATUS_AFTER_WEBHOOK" && grep -q '"last_run_at":"20' <<< "$STATUS_AFTER_WEBHOOK"; then
        WEBHOOK_DONE=1
        break
    fi
    sleep 1
done
[ "$WEBHOOK_DONE" = "1" ] || die "[coarchi] regeneration still running after 20s — check container logs"
log "[coarchi] webhook regeneration OK"

# --- Test 2b: wrong webhook secret must be rejected ---
# No -f here (unlike the 202 check above): -f makes curl itself treat a 4xx
# response as an error and exit non-zero before -w can report the code, which
# under `set -e` aborts the whole script on the very rejection we're testing
# for. Without -f, curl exits 0 for any HTTP status and just reports it.
WEBHOOK_REJECT=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
    -H "X-Webhook-Secret: wrong-secret" \
    "http://127.0.0.1:3102/webhook")
[ "$WEBHOOK_REJECT" = "401" ] || die "[coarchi] webhook with wrong secret expected HTTP 401, got $WEBHOOK_REJECT"
log "[coarchi] webhook auth rejection OK (401)"

# --- Test 3: multi-model mode (see docs/MULTI_MODEL.md) ---
# Three models: one plain, one coArchi (reusing the repos above), one with a
# deliberately bogus GIT_URL so we can confirm a single model failing at
# startup logs a warning instead of taking the whole container down (§32.6) —
# and that its placeholder page is served instead of a bare 404 in the
# meantime (§32.4).
log "[multi] starting container (archisurance, glycam, broken)"
C3=$(docker run -d \
    -p 3103:3000 \
    -e MODEL_1_SLUG=archisurance \
    -e MODEL_1_GIT_URL="$PLAIN_REPO" \
    -e MODEL_1_MODEL_PATH="$PLAIN_MODEL_PATH" \
    -e MODEL_2_SLUG=glycam \
    -e MODEL_2_GIT_URL="$COARCHI_REPO" \
    -e MODEL_3_SLUG=broken \
    -e MODEL_3_GIT_URL="https://github.com/umka-beaf/this-repo-does-not-exist.git" \
    -e WEBHOOK_SECRET="smoke-test-secret" \
    -e WEBHOOK_PROVIDER="generic" \
    "$IMAGE")
CONTAINERS+=("$C3")

# The broken model retries 3x with backoff (3s+6s, see generate.sh) before
# giving up, on top of the two real generations ahead of it in the startup
# queue — give this one more time than the single-model checks above before
# declaring the container unreachable.
log "[multi] waiting for container to come up (startup queue: archisurance -> glycam -> broken)"
wait_for_http "http://127.0.0.1:3103/status" 90 || {
    docker logs "$C3" 2>&1 | tail -80
    die "[multi] container never became reachable (90s+)"
}

RUNNING=$(docker inspect -f '{{.State.Running}}' "$C3")
[ "$RUNNING" = "true" ] || die "[multi] container is not running — a single model's startup failure must not take the whole container down (§32.6)"
log "[multi] container survived the broken model's startup failure — OK"

# Root: anonymous placeholder, must not leak configured slugs (§32.4).
ROOT_BODY=$(curl -fsS "http://127.0.0.1:3103/") || die "[multi] root / did not respond"
grep -qi "ArchiMate Report Service" <<< "$ROOT_BODY" || die "[multi] root placeholder missing expected title"
for leaked in archisurance glycam broken; do
    grep -qi "$leaked" <<< "$ROOT_BODY" && die "[multi] root placeholder leaks slug '$leaked' — should not enumerate models (§32.4)"
done
log "[multi] root placeholder OK (no slugs leaked)"

# Simplified root /status — boolean only, no per-slug detail (§32.4).
ROOT_STATUS=$(curl -fsS "http://127.0.0.1:3103/status") || die "[multi] root /status did not respond"
grep -q '"generating"' <<< "$ROOT_STATUS" || die "[multi] root /status missing 'generating' field: $ROOT_STATUS"
grep -q '"last_run_at"' <<< "$ROOT_STATUS" && die "[multi] root /status leaks per-model detail (last_run_at) — should be simplified in multi-model mode"
log "[multi] root /status OK (simplified): $ROOT_STATUS"

# Working models: real reports.
curl -fsS -o /dev/null "http://127.0.0.1:3103/archisurance/" || die "[multi] /archisurance/ did not respond HTTP 200"
grep -qi "Archisurance" <<< "$(curl -fsS "http://127.0.0.1:3103/archisurance/")" || die "[multi] /archisurance/ missing expected title"
log "[multi] /archisurance/ OK"

curl -fsS -o /dev/null "http://127.0.0.1:3103/glycam/" || die "[multi] /glycam/ did not respond HTTP 200"
grep -qi "GLYCAM-Web" <<< "$(curl -fsS "http://127.0.0.1:3103/glycam/")" || die "[multi] /glycam/ missing expected title"
log "[multi] /glycam/ OK"

# Broken model: stub page, not a bare 404 (§32.4).
BROKEN_BODY=$(curl -fsS "http://127.0.0.1:3103/broken/") || die "[multi] /broken/ did not respond HTTP 200 (should be a stub, not a 404)"
grep -qi "not yet available" <<< "$BROKEN_BODY" || die "[multi] /broken/ missing expected stub-page text"
log "[multi] /broken/ stub page OK"

# Unknown slug: a plain 404, distinct from the "known slug, not generated
# yet" stub above — placeholders don't intercept arbitrary paths (§32.4).
UNKNOWN_CODE=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:3103/nosuchmodel/")
[ "$UNKNOWN_CODE" = "404" ] || die "[multi] unknown slug expected HTTP 404, got $UNKNOWN_CODE"
log "[multi] unknown slug 404 OK"

# Per-slug /status — full JSON shape, same as legacy mode.
ARCHISURANCE_STATUS=$(curl -fsS "http://127.0.0.1:3103/archisurance/status") || die "[multi] /archisurance/status did not respond"
grep -q '"generating"' <<< "$ARCHISURANCE_STATUS" || die "[multi] /archisurance/status missing 'generating' field: $ARCHISURANCE_STATUS"
log "[multi] /archisurance/status OK: $ARCHISURANCE_STATUS"

# Per-slug webhook round-trip on the model that already succeeded at startup.
WEBHOOK_RESP=$(curl -fsS -o /dev/null -w '%{http_code}' -X POST \
    -H "X-Webhook-Secret: smoke-test-secret" \
    "http://127.0.0.1:3103/archisurance/webhook")
[ "$WEBHOOK_RESP" = "202" ] || die "[multi] /archisurance/webhook expected HTTP 202, got $WEBHOOK_RESP"
log "[multi] /archisurance/webhook accepted (202), waiting for regeneration to finish"
WEBHOOK_DONE=0
for _ in $(seq 1 20); do
    STATUS_AFTER_WEBHOOK=$(curl -fsS "http://127.0.0.1:3103/archisurance/status")
    if grep -q '"generating":false' <<< "$STATUS_AFTER_WEBHOOK" && grep -q '"last_success":true' <<< "$STATUS_AFTER_WEBHOOK"; then
        WEBHOOK_DONE=1
        break
    fi
    sleep 1
done
[ "$WEBHOOK_DONE" = "1" ] || die "[multi] /archisurance/webhook regeneration still not done after 20s — check container logs"
log "[multi] /archisurance/webhook regeneration OK"

# Wrong secret on a real slug's webhook -> 401 (auth still enforced per-slug).
WRONG_SECRET_CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
    -H "X-Webhook-Secret: wrong-secret" \
    "http://127.0.0.1:3103/archisurance/webhook")
[ "$WRONG_SECRET_CODE" = "401" ] || die "[multi] /archisurance/webhook with wrong secret expected HTTP 401, got $WRONG_SECRET_CODE"
log "[multi] /archisurance/webhook auth rejection OK (401)"

# Webhook for an unrecognized slug -> 404 (route never registered, distinct
# from the 401 above — auth isn't even reached for a slug that doesn't exist).
UNKNOWN_WEBHOOK_CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
    -H "X-Webhook-Secret: smoke-test-secret" \
    "http://127.0.0.1:3103/nosuchmodel/webhook")
[ "$UNKNOWN_WEBHOOK_CODE" = "404" ] || die "[multi] webhook for unknown slug expected HTTP 404, got $UNKNOWN_WEBHOOK_CODE"
log "[multi] webhook for unknown slug 404 OK"

log "ALL CHECKS PASSED — image $IMAGE looks safe to publish"
