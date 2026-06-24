# Supervisor 2026.04+ no longer injects BUILD_FROM automatically, so the base
# image is pinned explicitly here. bashio + jq + tempio ship in this image.
FROM ghcr.io/home-assistant/base:latest

# Build dependencies: node + npm to build, git to clone, openssl for the CA the
# server generates at runtime (rethink-cloud.ts shells out to `openssl`).
RUN apk add --no-cache nodejs npm git openssl

# Build at image build time from a fork branch that carries the F_V7 washer driver
# (The-sultan/rethink @ f7-remote-start-config) as a real committed file — no more
# sed injection. Override RETHINK_REPO/RETHINK_REF to build from a different source;
# pin RETHINK_REF to a SHA/tag if you want reproducible builds.
ARG RETHINK_REPO=https://github.com/The-sultan/rethink.git
ARG RETHINK_REF=f7-remote-start-config
# Cache-bust: the git clone command is byte-identical across add-on versions, so
# Docker would reuse a stale cloned layer even after the branch moves. Bump this to
# the target fork commit on every change; it is referenced in the RUN below, so it
# is part of that layer's cache key and forces a fresh clone of the branch HEAD.
ARG RETHINK_COMMIT=1f1e3ea
RUN echo "rethink fork commit: ${RETHINK_COMMIT}" \
 && git clone --depth 1 --branch "${RETHINK_REF}" \
        "${RETHINK_REPO}" /opt/rethink

# Upstream removed the nested rethink/ directory on 2026-06-04 (commit 10271b2);
# the Node project is at the repo root. run.sh's APP_DIR must match (/opt/rethink).
WORKDIR /opt/rethink
RUN npm ci --ignore-scripts \
    && npm run build \
    && npm prune --omit=dev \
    && npm cache clean --force

# Add-on entrypoint: reads HA options via bashio, writes /data/config.json,
# then execs the server.
COPY run.sh /run.sh
RUN chmod a+x /run.sh

# Standard Home Assistant add-on labels.
ARG BUILD_ARCH=amd64
ARG BUILD_VERSION=0.1.0
LABEL \
  io.hass.name="rethink-cloud — local LG ThinQ server" \
  io.hass.description="Local LG ThinQ cloud emulator (anszom/rethink) packaged as a HA add-on" \
  io.hass.type="addon" \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.arch="${BUILD_ARCH}" \
  maintainer="The-sultan <farid.elias@gmail.com>"

CMD [ "/run.sh" ]
