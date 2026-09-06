# shellcheck shell=bash
# Shared multi-model discovery/validation, sourced by both entrypoint.sh and
# generate.sh (see docs/MULTI_MODEL.md for the design this implements). Not
# meant to be executed directly.
#
# Discovery is env-var-name-based, not a counter (MODEL_COUNT) — models are
# expected to be added one at a time over time, possibly with gaps in
# numbering (MODEL_1_*, MODEL_7_*, ... is fine).
#
# Relies on the caller having already sourced docker/lib/log.sh (and set its
# own LOG_COMPONENT) before this file — mc_die() logs under whatever
# component tag the caller is currently using, rather than a separate
# "[model-config]" tag, since a config error here is really an error in the
# caller's own startup path.

mc_die() {
    log_error "$*"
    exit 1
}

# Prints the sorted (numeric) list of <N> for every MODEL_<N>_SLUG found in
# the environment, one per line. Empty output (exit 0, nothing printed) means
# no multi-model config is present — callers should fall back to legacy
# single-model behavior (§32.2).
#
# Dies with a clear message on:
#   - MODEL_<N>_SLUG set but empty
#   - a slug containing anything other than ASCII letters/digits/hyphens
#   - two different <N> resolving to the same slug value
#
# Deliberately enumerates variable *names* via `compgen -v` rather than
# parsing `env`'s NAME=value output line by line — a per-model secret
# (e.g. MODEL_2_GIT_SSH_PRIVATE_KEY) can legitimately contain embedded
# newlines, which would corrupt line-based env parsing. compgen -v never
# touches values, so it can't be confused by what's inside them.
mc_model_indices() {
    local -A seen_slugs=()
    local -a indices=()
    local var n slug

    while IFS= read -r var; do
        [[ "$var" =~ ^MODEL_([0-9]+)_SLUG$ ]] || continue
        n="${BASH_REMATCH[1]}"
        slug="${!var}"
        [ -n "$slug" ] || mc_die "MODEL_${n}_SLUG is set but empty"
        [[ "$slug" =~ ^[A-Za-z0-9-]+$ ]] || mc_die "MODEL_${n}_SLUG=\"$slug\" is invalid — only ASCII letters, digits, and hyphens are allowed"
        if [ -n "${seen_slugs[$slug]:-}" ]; then
            mc_die "duplicate slug \"$slug\": used by both MODEL_${seen_slugs[$slug]}_SLUG and MODEL_${n}_SLUG"
        fi
        seen_slugs["$slug"]="$n"
        indices+=("$n")
    done < <(compgen -v)

    [ "${#indices[@]}" -eq 0 ] && return 0

    printf '%s\n' "${indices[@]}" | sort -n
}

# Prints the value of MODEL_<n>_<key> (e.g. `mc_model_var 1 GIT_URL` reads
# MODEL_1_GIT_URL), or an empty string if it's unset — mirrors how the
# legacy single-model script reads GIT_URL/GIT_REF/... via "${VAR:-}".
mc_model_var() {
    local n="$1" key="$2" var
    var="MODEL_${n}_${key}"
    printf '%s' "${!var:-}"
}

# Prints the slug for model index <n> (i.e. MODEL_<n>_SLUG). Assumes <n> came
# from mc_model_indices, so no re-validation here.
mc_model_slug() {
    mc_model_var "$1" SLUG
}
