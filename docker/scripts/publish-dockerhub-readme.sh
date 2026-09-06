#!/usr/bin/env bash
# Publish docs/DOCKERHUB.md as the "full description" (the long, rendered
# README-like body) of the Docker Hub repository page. Triggered by hand, not
# on every commit — either as a step in .github/workflows/docker-publish.yml
# (runs automatically alongside a real image push, via workflow_dispatch), or
# by running this script directly yourself whenever you only need to update
# the description without rebuilding the image.
#
# Docker Hub's current official OpenAPI spec (docs.docker.com/reference/api/hub/latest.yaml)
# documents `full_description` only as a field you can set at repository
# *creation* time (POST /v2/namespaces/{namespace}/repositories) or read back
# via GET — it does not document an update endpoint. The endpoint used below
# (PATCH /v2/repositories/{namespace}/{repository}/) is the long-standing,
# widely-used *legacy* v2 route (same one every "sync Docker Hub description"
# GitHub Action out there relies on, e.g. peter-evans/dockerhub-description) —
# confirmed live in this session via a plain GET against it, but it is not
# part of the current official spec, so Docker could change/retire it without
# notice. If this script starts failing, check for a new documented
# equivalent first.
#
# Usage:
#   DOCKERHUB_USERNAME=your-dockerhub-user DOCKERHUB_TOKEN=dckr_pat_xxx \
#     ./docker/scripts/publish-dockerhub-readme.sh
#
# DOCKERHUB_TOKEN must be a Docker Hub Personal Access Token (Account Settings
# -> Security -> New Access Token) with at least "Read & Write" repo scope —
# not your account password (PATs are revocable/scoped, so prefer them).

set -euo pipefail

log() { printf '%s [publish-dockerhub-readme] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() {
    log "FAIL: $*"
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# This script lives in docker/scripts/, two levels below the repo root.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DESCRIPTION_FILE="${DESCRIPTION_FILE:-$REPO_ROOT/docs/DOCKERHUB.md}"

: "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required}"
: "${DOCKERHUB_TOKEN:?DOCKERHUB_TOKEN is required (a Docker Hub PAT, not your password)}"

# No project-specific default here on purpose — forks publishing their own
# copy under a different Docker Hub account/org shouldn't have to remember to
# override a hardcoded namespace. Defaults to DOCKERHUB_USERNAME (true for
# any personal-account namespace; set DOCKERHUB_NAMESPACE explicitly if
# publishing under an org instead).
NAMESPACE="${DOCKERHUB_NAMESPACE:-$DOCKERHUB_USERNAME}"
REPOSITORY="${DOCKERHUB_REPOSITORY:-archimate-report}"
[ -f "$DESCRIPTION_FILE" ] || die "description file not found: $DESCRIPTION_FILE"

command -v curl > /dev/null || die "curl is required"
command -v python3 > /dev/null || die "python3 is required (used for safe JSON encoding)"

log "requesting access token for $DOCKERHUB_USERNAME"
TOKEN_RESPONSE="$(curl -fsS -X POST https://hub.docker.com/v2/auth/token \
    -H 'Content-Type: application/json' \
    -d "$(python3 -c '
import json, os, sys
json.dump({"identifier": os.environ["DOCKERHUB_USERNAME"], "secret": os.environ["DOCKERHUB_TOKEN"]}, sys.stdout)
')")" || die "login request failed"

ACCESS_TOKEN="$(printf '%s' "$TOKEN_RESPONSE" | python3 -c '
import json, sys
data = json.load(sys.stdin)
token = data.get("access_token") or data.get("token")
if not token:
    sys.exit("no access_token/token field in response: " + json.dumps(data))
print(token)
')" || die "could not extract access token from login response"
[ -n "$ACCESS_TOKEN" ] || die "empty access token"

log "read $(wc -l < "$DESCRIPTION_FILE") lines from $DESCRIPTION_FILE"

# Build the PATCH body out-of-band via python so we never have to worry about
# escaping the Markdown body (headings, backticks, RU/EN text) into a shell
# string ourselves.
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
python3 -c '
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    text = f.read()
json.dump({"full_description": text}, sys.stdout)
' "$DESCRIPTION_FILE" > "$BODY_FILE"

log "publishing full_description to docker.io/$NAMESPACE/$REPOSITORY"
HTTP_CODE="$(curl -sS -o /tmp/dockerhub-patch-response.json -w '%{http_code}' \
    -X PATCH "https://hub.docker.com/v2/repositories/${NAMESPACE}/${REPOSITORY}/" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H 'Content-Type: application/json' \
    --data-binary @"$BODY_FILE")"

if [ "$HTTP_CODE" != "200" ]; then
    log "response body:"
    cat /tmp/dockerhub-patch-response.json >&2 || true
    die "PATCH returned HTTP $HTTP_CODE (expected 200)"
fi

rm -f /tmp/dockerhub-patch-response.json
log "done — https://hub.docker.com/r/${NAMESPACE}/${REPOSITORY}"
