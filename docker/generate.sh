#!/usr/bin/env bash
# M1 scope: plain repo (single .archimate file), token auth only.
# coArchi / SSH / username+password / MODEL_FORMAT overrides come in M2.
set -euo pipefail

log() { echo "[generate] $*" >&2; }
die() {
    log "ERROR: $*"
    exit 1
}

: "${GIT_URL:?GIT_URL is required}"
GIT_REF="${GIT_REF:-}"
MODEL_PATH="${MODEL_PATH:-}"
REPO_DIR="/data/repo"
REPORT_DIR="/data/report"
REPORT_TMP_DIR="/data/report.new"

# --- Build an auth-aware clone URL, without ever putting the secret in argv
# (visible via ps/docker top) longer than this one variable assignment. ---
CLONE_URL="$GIT_URL"
if [ -n "${GIT_TOKEN:-}" ]; then
    case "$GIT_URL" in
        https://*)
            CLONE_URL="https://${GIT_TOKEN}@${GIT_URL#https://}"
            ;;
        *)
            die "GIT_TOKEN is set but GIT_URL is not an https:// URL (got: $GIT_URL)"
            ;;
    esac
elif [ -n "${GIT_SSH_PRIVATE_KEY:-}" ] || [ -n "${GIT_USERNAME:-}" ]; then
    die "SSH key / username+password auth is not implemented yet (M2, see plan.md §7)"
fi

git config --global advice.detachedHead false

if [ -d "$REPO_DIR/.git" ]; then
    log "updating existing clone in $REPO_DIR"
    git -C "$REPO_DIR" remote set-url origin "$CLONE_URL"
    git -C "$REPO_DIR" fetch --depth 1 origin "${GIT_REF:-HEAD}"
    git -C "$REPO_DIR" reset --hard FETCH_HEAD
else
    log "cloning $GIT_URL into $REPO_DIR"
    rm -rf "$REPO_DIR"
    if [ -n "$GIT_REF" ]; then
        git clone --depth 1 --branch "$GIT_REF" "$CLONE_URL" "$REPO_DIR"
    else
        git clone --depth 1 "$CLONE_URL" "$REPO_DIR"
    fi
fi

# --- Locate the model file (M1: plain format only) ---
if [ -n "$MODEL_PATH" ]; then
    MODEL_FILE="$REPO_DIR/$MODEL_PATH"
    [ -f "$MODEL_FILE" ] || die "MODEL_PATH set but not found: $MODEL_FILE"
else
    mapfile -t CANDIDATES < <(find "$REPO_DIR" -maxdepth 3 -name '*.archimate' -not -path '*/.git/*' | sort)
    case "${#CANDIDATES[@]}" in
        0) die "no *.archimate file found in repo (checked depth<=3); set MODEL_PATH explicitly" ;;
        1) MODEL_FILE="${CANDIDATES[0]}" ;;
        *) die "multiple *.archimate files found, set MODEL_PATH to disambiguate: ${CANDIDATES[*]}" ;;
    esac
fi
log "using model file: $MODEL_FILE"

# --- Generate into a scratch dir, then atomically swap into place ---
rm -rf "$REPORT_TMP_DIR"
mkdir -p "$REPORT_TMP_DIR"

xvfb-run -a /opt/archi/Archi -consoleLog -nosplash \
    -application com.archimatetool.commandline.app \
    --loadModel "$MODEL_FILE" \
    --html.createReport "$REPORT_TMP_DIR" \
    1>&2

[ -f "$REPORT_TMP_DIR/index.html" ] || die "generation finished but $REPORT_TMP_DIR/index.html is missing"
[ -s "$REPORT_TMP_DIR/index.html" ] || die "generation finished but index.html is empty (see archi issue #980)"

# Atomic-ish swap: both renames are fast, so Caddy never serves a
# half-written report dir (worst case it briefly serves the previous one).
rm -rf "$REPORT_DIR.old"
[ -d "$REPORT_DIR" ] && mv "$REPORT_DIR" "$REPORT_DIR.old"
mv "$REPORT_TMP_DIR" "$REPORT_DIR"
rm -rf "$REPORT_DIR.old"
log "report published to $REPORT_DIR"
