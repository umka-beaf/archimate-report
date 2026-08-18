# M0 spike: validate box64-based ARM64 execution of Archi CLI on Debian trixie (arm64)
FROM debian:trixie-slim

ARG ARCHI_VERSION=5.9.0

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      box64 \
      ca-certificates curl tar \
      xvfb xauth dbus dbus-x11 \
      libgtk-3-0 libxext6 libxrender1 libxi6 libxtst6 \
      libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libglib2.0-0 ; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSL -o /tmp/archi.tgz \
      "https://github.com/archimatetool/archi.io/releases/download/${ARCHI_VERSION}/Archi-Linux64-${ARCHI_VERSION}.tgz"; \
    tar -xzf /tmp/archi.tgz -C /opt/; \
    rm -f /tmp/archi.tgz; \
    chmod +x /opt/Archi/Archi

COPY model.archimate /data/model.archimate
COPY archisurance.archimate /data/archisurance.archimate

WORKDIR /opt/Archi
