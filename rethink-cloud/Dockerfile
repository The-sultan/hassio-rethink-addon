# Supervisor 2026.04+ no longer injects BUILD_FROM automatically, so the base
# image is pinned explicitly here. bashio + jq + tempio ship in this image.
FROM ghcr.io/home-assistant/base:latest

# Build dependencies: node + npm to build, git to clone, openssl for the CA the
# server generates at runtime (rethink-cloud.ts shells out to `openssl`).
RUN apk add --no-cache nodejs npm git openssl

# "Zero commitment" build: clone upstream at image build time. Pin to a tag/SHA
# here if you want reproducible builds; HEAD of master is used by default.
ARG RETHINK_REF=master
RUN git clone --depth 1 --branch "${RETHINK_REF}" \
        https://github.com/anszom/rethink.git /opt/rethink

# The actual Node project lives in the rethink/ subdirectory of the repo.
WORKDIR /opt/rethink/rethink
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
