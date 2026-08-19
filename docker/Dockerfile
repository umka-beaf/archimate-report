# M3 — webhook-listener for on-push regeneration, on top of M1/M2 (clone +
# format auto-detection + Archi CLI report generation + Caddy). See CLAUDE.md
# for the full milestone history.

FROM golang:1.23-alpine AS webhook-builder
ARG TARGETARCH
WORKDIR /src
COPY webhook/go.mod webhook/main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -o /out/archi-webhook .


FROM debian:trixie-slim AS archi-amd64

# "latest" resolves via the GitHub Releases API at build time. Pin an exact
# version (e.g. 5.9.0) for reproducible builds; note that with "latest" the
# resolved version is only as fresh as Docker's layer cache — pass
# --no-cache (or bump this arg) to actually pick up a new Archi release.
ARG ARCHI_VERSION=latest

# coArchi (org.archicontribs.modelrepository) is NOT bundled in the plain
# Archi-Linux64 tgz — it's a separate plugin, distributed only as a versioned
# .archiplugin (a zip) from archimatetool.com, with no "latest" API to query.
# Pin and bump manually; check https://www.archimatetool.com/plugins/ for
# the current release. Without it, --modelrepository.loadModel silently
# fails to load any model (see CLAUDE.md M2 notes on the "Model was not
# loaded" investigation).
ARG COARCHI_VERSION=0.9.6

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl tar unzip; \
    rm -rf /var/lib/apt/lists/*; \
    if [ "$ARCHI_VERSION" = "latest" ]; then \
        LATEST_JSON=$(curl -fsSL https://api.github.com/repos/archimatetool/archi.io/releases/latest); \
        ARCHI_VERSION=$(printf '%s' "$LATEST_JSON" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'); \
    fi; \
    echo "Resolved ARCHI_VERSION=${ARCHI_VERSION}"; \
    curl -fsSL -o /tmp/archi.tgz \
      "https://github.com/archimatetool/archi.io/releases/download/${ARCHI_VERSION}/Archi-Linux64-${ARCHI_VERSION}.tgz"; \
    mkdir -p /opt/archi; \
    tar -xzf /tmp/archi.tgz -C /opt/archi --strip-components=1; \
    rm -f /tmp/archi.tgz; \
    chmod +x /opt/archi/Archi; \
    echo "${ARCHI_VERSION}" > /opt/archi/.archi_version; \
    curl -fsSL -o /tmp/coarchi.zip \
      "https://www.archimatetool.com/downloads/coarchi/coArchi_${COARCHI_VERSION}.archiplugin"; \
    mkdir -p /opt/archi/dropins; \
    unzip -q /tmp/coarchi.zip -d /opt/archi/dropins; \
    rm -f /tmp/coarchi.zip; \
    echo "${COARCHI_VERSION}" > /opt/archi/.coarchi_version


FROM debian:trixie-slim

# See the ARCHI_VERSION comment above — same "latest" + cache caveat applies.
ARG CADDY_VERSION=latest
# TARGETARCH is auto-populated by buildx; for M1 we only build amd64 so this
# is informational — the arm64 branch is added in M4 (see CLAUDE.md §5/§16).
ARG TARGETARCH=amd64

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl tar git openssh-client \
        xvfb xauth dbus dbus-x11 \
        libgtk-3-0 libxext6 libxrender1 libxi6 libxtst6 \
        libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libglib2.0-0 ; \
    rm -rf /var/lib/apt/lists/*; \
    if [ "$CADDY_VERSION" = "latest" ]; then \
        LATEST_JSON=$(curl -fsSL https://api.github.com/repos/caddyserver/caddy/releases/latest); \
        CADDY_VERSION=$(printf '%s' "$LATEST_JSON" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"v?([^"]+)".*/\1/'); \
    fi; \
    echo "Resolved CADDY_VERSION=${CADDY_VERSION}"; \
    curl -fsSL -o /tmp/caddy.tar.gz \
      "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin caddy; \
    rm -f /tmp/caddy.tar.gz; \
    chmod +x /usr/local/bin/caddy

COPY --from=archi-amd64 /opt/archi /opt/archi
COPY --from=webhook-builder /out/archi-webhook /usr/local/bin/archi-webhook

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY generate.sh /usr/local/bin/generate.sh
COPY Caddyfile /etc/caddy/Caddyfile
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/generate.sh /usr/local/bin/archi-webhook

# /data/repo    — working copy of the git repository
# /data/report  — generated HTML report, served by Caddy
# /data/secrets — temp auth material (token/key/pass), 600 perms
RUN mkdir -p /data/repo /data/report /data/secrets

ENV PORT=3000
EXPOSE 3000

WORKDIR /opt/archi
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
