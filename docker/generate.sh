#!/usr/bin/env bash
# M2 scope: plain + coArchi auto-detection, all three auth methods
# (token / SSH key / username+password), MODEL_FORMAT override.
set -euo pipefail

log() { echo "[generate] $*" >&2; }
die() {
    log "ERROR: $*"
    exit 1
}
urlencode() {
    local s="$1" out="" c
    local i
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    printf '%s' "$out"
}

: "${GIT_URL:?GIT_URL is required}"
GIT_REF="${GIT_REF:-}"
MODEL_PATH="${MODEL_PATH:-}"
MODEL_FORMAT="${MODEL_FORMAT:-auto}"
REPO_DIR="/data/repo"
REPORT_DIR="/data/report"
REPORT_TMP_DIR="/data/report.new"
SECRETS_DIR="/data/secrets"

case "$MODEL_FORMAT" in
    auto | plain | coarchi) ;;
    *) die "MODEL_FORMAT must be one of: auto, plain, coarchi (got: $MODEL_FORMAT)" ;;
esac

# --- Count how many auth methods were supplied; reject more than one ---
AUTH_METHODS=0
[ -n "${GIT_TOKEN:-}" ] && AUTH_METHODS=$((AUTH_METHODS + 1))
[ -n "${GIT_SSH_PRIVATE_KEY:-}" ] && AUTH_METHODS=$((AUTH_METHODS + 1))
if [ -n "${GIT_USERNAME:-}" ] || [ -n "${GIT_PASSWORD:-}" ]; then
    AUTH_METHODS=$((AUTH_METHODS + 1))
fi
[ "$AUTH_METHODS" -le 1 ] || die "set at most one auth method: GIT_TOKEN, GIT_SSH_PRIVATE_KEY, or GIT_USERNAME+GIT_PASSWORD"

# --- Build an auth-aware clone URL / SSH command, without ever putting the
# secret in argv (visible via ps/docker top) longer than one variable
# assignment. GIT_SSH_COMMAND is exported for git to pick up automatically. ---
CLONE_URL="$GIT_URL"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [ -n "${GIT_TOKEN:-}" ]; then
    case "$GIT_URL" in
        https://*)
            CLONE_URL="https://${GIT_TOKEN}@${GIT_URL#https://}"
            ;;
        *)
            die "GIT_TOKEN is set but GIT_URL is not an https:// URL (got: $GIT_URL)"
            ;;
    esac
elif [ -n "${GIT_USERNAME:-}" ] || [ -n "${GIT_PASSWORD:-}" ]; then
    [ -n "${GIT_USERNAME:-}" ] || die "GIT_PASSWORD is set but GIT_USERNAME is missing"
    [ -n "${GIT_PASSWORD:-}" ] || die "GIT_USERNAME is set but GIT_PASSWORD is missing"
    case "$GIT_URL" in
        https://*)
            ENC_USER=$(urlencode "$GIT_USERNAME")
            ENC_PASS=$(urlencode "$GIT_PASSWORD")
            CLONE_URL="https://${ENC_USER}:${ENC_PASS}@${GIT_URL#https://}"
            ;;
        *)
            die "GIT_USERNAME/GIT_PASSWORD are set but GIT_URL is not an https:// URL (got: $GIT_URL)"
            ;;
    esac
elif [ -n "${GIT_SSH_PRIVATE_KEY:-}" ]; then
    case "$GIT_URL" in
        ssh://* | *@*:*) ;;
        *) die "GIT_SSH_PRIVATE_KEY is set but GIT_URL doesn't look like an SSH URL (got: $GIT_URL)" ;;
    esac
    KEY_FILE="$SECRETS_DIR/id_ssh"
    # Accept either a raw multi-line PEM or a base64-encoded blob.
    if printf '%s' "$GIT_SSH_PRIVATE_KEY" | grep -q '^-----BEGIN'; then
        printf '%s\n' "$GIT_SSH_PRIVATE_KEY" > "$KEY_FILE"
    else
        printf '%s' "$GIT_SSH_PRIVATE_KEY" | base64 -d > "$KEY_FILE"
    fi
    chmod 600 "$KEY_FILE"

    SSH_OPTS="-i $KEY_FILE -o IdentitiesOnly=yes"
    if [ -n "${GIT_SSH_KNOWN_HOSTS:-}" ]; then
        KNOWN_HOSTS_FILE="$SECRETS_DIR/known_hosts"
        printf '%s\n' "$GIT_SSH_KNOWN_HOSTS" > "$KNOWN_HOSTS_FILE"
        chmod 600 "$KNOWN_HOSTS_FILE"
        SSH_OPTS="$SSH_OPTS -o UserKnownHostsFile=$KNOWN_HOSTS_FILE -o StrictHostKeyChecking=yes"
    else
        log "WARNING: GIT_SSH_KNOWN_HOSTS not set — using StrictHostKeyChecking=accept-new (TOFU, no pinned host key)"
        SSH_OPTS="$SSH_OPTS -o UserKnownHostsFile=$SECRETS_DIR/known_hosts -o StrictHostKeyChecking=accept-new"
    fi
    export GIT_SSH_COMMAND="ssh $SSH_OPTS"
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

# --- Locate the model and decide plain vs coArchi (see plan.md §6/§15.7) ---
#
# coArchi's own loader (ArchiRepository.locateModel()) hardcodes the relative
# path "model/folder.xml" under whatever directory it's given — it does NOT
# accept the model/ directory itself. So --modelrepository.loadModel must be
# pointed at the REPO ROOT (the directory containing model/folder.xml, i.e.
# the parent of "model/"), not at the model/ subdirectory. Confirmed by
# decompiling org.archicontribs.modelrepository_0.9.6's ArchiRepository.class
# after --modelrepository.loadModel "<repo>/model" failed with
# "java.io.IOException: Model was not found at <repo>/model" (it was actually
# looking for <repo>/model/model/folder.xml).
find_coarchi_dir() {
    # Prints the directory containing "model/folder.xml" whose root element
    # is <archimate:ArchimateModel ...> (i.e. the coArchi repo root, the
    # parent of the matched folder.xml's "model" parent), or nothing if none
    # found.
    local f dir parent
    while IFS= read -r f; do
        dir="$(dirname "$f")"
        [ "$(basename "$dir")" = "model" ] || continue
        if head -c 4096 "$f" | grep -q '<archimate:ArchimateModel'; then
            parent="$(dirname "$dir")"
            printf '%s\n' "$parent"
            return 0
        fi
    done < <(find "$REPO_DIR" -name 'folder.xml' -not -path '*/.git/*' | sort)
    return 1
}

MODEL_MODE="" # plain | coarchi
MODEL_FILE="" # set for plain
MODEL_DIR=""  # set for coarchi

if [ -n "$MODEL_PATH" ]; then
    CANDIDATE="$REPO_DIR/$MODEL_PATH"
    if [ "$MODEL_FORMAT" = "coarchi" ]; then
        # MODEL_PATH for coarchi is the repo root that CONTAINS "model/", not
        # the model/ directory itself (see find_coarchi_dir comment above).
        [ -d "$CANDIDATE" ] || die "MODEL_FORMAT=coarchi but MODEL_PATH is not a directory: $CANDIDATE"
        [ -f "$CANDIDATE/model/folder.xml" ] || die "MODEL_FORMAT=coarchi but $CANDIDATE/model/folder.xml is missing (MODEL_PATH must point at the repo root containing model/, not at model/ itself)"
        MODEL_MODE="coarchi"
        MODEL_DIR="$CANDIDATE"
    elif [ "$MODEL_FORMAT" = "plain" ]; then
        [ -f "$CANDIDATE" ] || die "MODEL_FORMAT=plain but MODEL_PATH is not a file: $CANDIDATE"
        MODEL_MODE="plain"
        MODEL_FILE="$CANDIDATE"
    else
        # auto: infer from whether MODEL_PATH points at a file or a directory.
        # For a directory, be forgiving of MODEL_PATH pointing at either the
        # coArchi repo root or straight at its model/ subdirectory.
        if [ -f "$CANDIDATE" ]; then
            MODEL_MODE="plain"
            MODEL_FILE="$CANDIDATE"
        elif [ -f "$CANDIDATE/model/folder.xml" ]; then
            MODEL_MODE="coarchi"
            MODEL_DIR="$CANDIDATE"
        elif [ "$(basename "$CANDIDATE")" = "model" ] && [ -f "$CANDIDATE/folder.xml" ]; then
            MODEL_MODE="coarchi"
            MODEL_DIR="$(dirname "$CANDIDATE")"
        elif [ -d "$CANDIDATE" ]; then
            die "MODEL_PATH is a directory but no model/folder.xml found under it: $CANDIDATE"
        else
            die "MODEL_PATH not found: $CANDIDATE"
        fi
    fi
else
    if [ "$MODEL_FORMAT" != "coarchi" ]; then
        mapfile -t PLAIN_CANDIDATES < <(find "$REPO_DIR" -name '*.archimate' -not -path '*/.git/*' | sort)
    else
        PLAIN_CANDIDATES=()
    fi

    case "${#PLAIN_CANDIDATES[@]}" in
        1)
            MODEL_MODE="plain"
            MODEL_FILE="${PLAIN_CANDIDATES[0]}"
            ;;
        0)
            if [ "$MODEL_FORMAT" = "plain" ]; then
                die "MODEL_FORMAT=plain but no *.archimate file found in repo"
            fi
            if COARCHI_DIR=$(find_coarchi_dir); then
                MODEL_MODE="coarchi"
                MODEL_DIR="$COARCHI_DIR"
            else
                die "no *.archimate file and no coArchi folder.xml found in repo; set MODEL_PATH explicitly"
            fi
            ;;
        *)
            die "multiple *.archimate files found, set MODEL_PATH to disambiguate: ${PLAIN_CANDIDATES[*]}"
            ;;
    esac
fi

# --- Generate into a scratch dir, then atomically swap into place ---
rm -rf "$REPORT_TMP_DIR"
mkdir -p "$REPORT_TMP_DIR"

if [ "$MODEL_MODE" = "plain" ]; then
    log "using plain model file: $MODEL_FILE"
    xvfb-run -a /opt/archi/Archi -consoleLog -nosplash \
        -application com.archimatetool.commandline.app \
        --loadModel "$MODEL_FILE" \
        --html.createReport "$REPORT_TMP_DIR" \
        1>&2
else
    log "using coArchi model directory: $MODEL_DIR"
    xvfb-run -a /opt/archi/Archi -consoleLog -nosplash \
        -application com.archimatetool.commandline.app \
        --modelrepository.loadModel "$MODEL_DIR" \
        --html.createReport "$REPORT_TMP_DIR" \
        1>&2
fi

[ -f "$REPORT_TMP_DIR/index.html" ] || die "generation finished but $REPORT_TMP_DIR/index.html is missing"
[ -s "$REPORT_TMP_DIR/index.html" ] || die "generation finished but index.html is empty (see archi issue #980)"

# Atomic-ish swap: both renames are fast, so Caddy never serves a
# half-written report dir (worst case it briefly serves the previous one).
rm -rf "$REPORT_DIR.old"
[ -d "$REPORT_DIR" ] && mv "$REPORT_DIR" "$REPORT_DIR.old"
mv "$REPORT_TMP_DIR" "$REPORT_DIR"
rm -rf "$REPORT_DIR.old"
log "report published to $REPORT_DIR"
