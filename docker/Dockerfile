# M4 — native arm64 build (Tycho/Maven from source) alongside the amd64
# official-tgz path, on top of M1/M2/M3 (clone + format auto-detection +
# Archi CLI report generation + webhook + Caddy). See CLAUDE.md for the full
# milestone history — §5/§15.9-§15.10 explain why arm64 is a native Tycho
# build and not box64 emulation (open upstream box64 bug at the JVM/SWT/GTK3
# boundary), §16 records the integration decisions this stage layout follows.

# Shared across archi-linux-amd64 and archi-linux-arm64 so both branches of a
# single `docker buildx build --platform linux/amd64,linux/arm64` build the
# same Archi version. "latest" resolves via the GitHub Releases API at build
# time in each stage independently (see the ARCHI_VERSION comment further
# down for the layer-cache caveat that implies).
ARG ARCHI_VERSION=latest
ARG TARGETARCH

FROM golang:1.23-alpine AS webhook-builder
ARG TARGETARCH
WORKDIR /src
COPY webhook/go.mod webhook/main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -o /out/archi-webhook .


FROM debian:trixie-slim AS archi-linux-amd64

# "latest" resolves via the GitHub Releases API at build time. Pin an exact
# version (e.g. 5.9.0) for reproducible builds; note that with "latest" the
# resolved version is only as fresh as Docker's layer cache — pass
# --no-cache (or bump this arg) to actually pick up a new Archi release.
ARG ARCHI_VERSION

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl tar; \
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
    echo "${ARCHI_VERSION}" > /opt/archi/.archi_version


FROM maven:3.9-eclipse-temurin-21 AS archi-linux-arm64

# Same resolution semantics as archi-linux-amd64 above, but the source repo
# (archimatetool/archi) tags releases as "release_<version>", not the bare
# version string the amd64 tgz download URL uses (archimatetool/archi.io) —
# both must still land on the same ARCHI_VERSION so the two arch branches of
# one image build never publish mismatched Archi versions.
ARG ARCHI_VERSION

COPY patches/archi-pom-add-linux-gtk-aarch64.patch /tmp/archi-pom-add-linux-gtk-aarch64.patch

# Build-speed trim, deliberately NOT part of the committed patch (see
# CLAUDE.md §16 decision #5 — the patch itself stays additive/portable).
# This container build only ever needs the linux.gtk.aarch64 product, so
# comment out the other 4 <environment> blocks just for this stage —
# matches the ~3.5min single-target build already validated in
# spikes/archi-source (CLAUDE.md §15.10), instead of a full 4-platform
# Tycho reactor on every `docker buildx build`. Done via a perl one-liner
# (not a python heredoc) because Dockerfile's `\`-continued RUN syntax
# doesn't mix with heredocs, and inline `#` comments aren't valid mid-RUN.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends git unzip patch perl; \
    rm -rf /var/lib/apt/lists/*; \
    if [ "$ARCHI_VERSION" = "latest" ]; then \
        LATEST_JSON=$(curl -fsSL https://api.github.com/repos/archimatetool/archi.io/releases/latest); \
        ARCHI_VERSION=$(printf '%s' "$LATEST_JSON" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'); \
    fi; \
    echo "Resolved ARCHI_VERSION=${ARCHI_VERSION} (source tag release_${ARCHI_VERSION})"; \
    git clone --branch "release_${ARCHI_VERSION}" --depth 1 \
      https://github.com/archimatetool/archi.git /src; \
    cd /src; \
    patch -p1 < /tmp/archi-pom-add-linux-gtk-aarch64.patch; \
    perl -0777 -pi -e 's{(<environments>\s*)(.*?)(\s*<environment>\s*<os>linux</os>\s*<ws>gtk</ws>\s*<arch>aarch64</arch>\s*</environment>\s*</environments>)}{$1<!--\n$2\n-->$3}s or die "failed to locate <environments> block to trim for build speed"' pom.xml; \
    echo "ARCHI_VERSION=${ARCHI_VERSION}" > /tmp/archi_version.env

RUN --mount=type=cache,target=/root/.m2 \
    set -eux; \
    cd /src; \
    mvn -B -P '!tests,product' clean verify

RUN set -eux; \
    cd /src; \
    mkdir -p /tmp/extract; \
    unzip -q com.archimatetool.editor.product/target/products/Archi-linux.gtk.aarch64.zip -d /tmp/extract; \
    mv /tmp/extract/Archi /opt/archi; \
    rm -rf /tmp/extract; \
    chmod +x /opt/archi/Archi; \
    . /tmp/archi_version.env; \
    echo "${ARCHI_VERSION}" > /opt/archi/.archi_version


# Arch-selecting stage: buildx resolves this per platform during a
# `--platform linux/amd64,linux/arm64` build, so each platform only ever
# executes its own archi-linux-* stage above — the amd64 build never pays
# the Tycho cost, and vice versa.
FROM archi-linux-${TARGETARCH} AS archi-final


FROM debian:trixie-slim

# See the ARCHI_VERSION comment above — same "latest" + cache caveat applies.
ARG CADDY_VERSION=latest
ARG TARGETARCH

# coArchi (org.archicontribs.modelrepository) is NOT bundled in either Archi
# distribution (plain amd64 tgz or the arm64 Tycho build) — it's a separate
# plugin, distributed only as a versioned .archiplugin (a zip) from
# archimatetool.com, with no "latest" API to query. Pin and bump manually;
# check https://www.archimatetool.com/plugins/ for the current release.
# Without it, --modelrepository.loadModel silently fails to load any model
# (see CLAUDE.md M2 notes on the "Model was not loaded" investigation). It's
# pure Java (no native code) so it's installed once here, arch-independently,
# rather than duplicated in both archi-linux-amd64 and archi-linux-arm64.
ARG COARCHI_VERSION=0.9.7

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl tar unzip git openssh-client \
        xvfb xauth dbus dbus-x11 \
        libgtk-3-0 libxext6 libxrender1 libxi6 libxtst6 \
        libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libglib2.0-0; \
    # The amd64 Archi-Linux64 tgz bundles its own JRE (confirmed in M1 — the
    # container runs without installing Java separately). The arm64 Tycho
    # product does not bundle one (confirmed on a Raspberry Pi 5 in
    # CLAUDE.md §15.10) — install a native arm64 JRE only on that arch.
    if [ "$TARGETARCH" = "arm64" ]; then \
        apt-get install -y --no-install-recommends openjdk-21-jre-headless; \
    fi; \
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

COPY --from=archi-final /opt/archi /opt/archi

RUN set -eux; \
    curl -fsSL -o /tmp/coarchi.zip \
      "https://www.archimatetool.com/downloads/coarchi/coArchi_${COARCHI_VERSION}.archiplugin"; \
    mkdir -p /opt/archi/dropins; \
    unzip -q /tmp/coarchi.zip -d /opt/archi/dropins; \
    rm -f /tmp/coarchi.zip; \
    echo "${COARCHI_VERSION}" > /opt/archi/.coarchi_version

COPY --from=webhook-builder /out/archi-webhook /usr/local/bin/archi-webhook

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY generate.sh /usr/local/bin/generate.sh
COPY Caddyfile /etc/caddy/Caddyfile
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/generate.sh /usr/local/bin/archi-webhook

# RU/EN + light/dark report theme, overlaid onto Archi's generated report by
# generate.sh after each run (see REPORT_THEME_DIR there) - overwrites just
# the 4 static asset files every generated page references, so the whole
# report is themed/localized without templating the hundreds of per-element/
# per-view pages Archi itself generates.
COPY report-theme /opt/report-theme

# /data/repo    — working copy of the git repository
# /data/report  — generated HTML report, served by Caddy
# /data/secrets — temp auth material (token/key/pass), 600 perms
RUN mkdir -p /data/repo /data/report /data/secrets

ENV PORT=3000
EXPOSE 3000

# /status is served by archi-webhook (reverse-proxied through Caddy on $PORT,
# see Caddyfile) and always answers — regardless of WEBHOOK_SECRET — with
# JSON {generating, last_run_at, last_success, last_error}. A plain 200 is
# enough here: it proves both Caddy and archi-webhook are alive and Caddy's
# reverse_proxy to 127.0.0.1:8088 is working, without parsing the body.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT}/status" || exit 1

WORKDIR /opt/archi
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
