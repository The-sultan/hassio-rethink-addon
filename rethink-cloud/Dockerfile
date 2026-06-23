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

# Inject support for the LG WM12WVC4S6 (UY) washer (kind F_V7_Y___W.B__QEUK),
# which upstream does not know (logs it as "unknown"). Verified by traffic
# capture to use the same AABB frame layout as F_V8, so we reuse F_V8's parser
# class — exactly the pattern upstream already uses for F_V__Y___W. Anchored on
# the F_V__Y___W line, NOT a line number. Fail-loud: the first grep aborts the
# build if upstream renames/removes the anchor; the second grep aborts if the
# insert silently no-ops — so we never ship an add-on missing the washer.
RUN F=/opt/rethink/cloud/ha_bridge.ts \
 && grep -q "F_V__Y___W.B_2QEUK" "$F" \
 && sed -i "/F_V__Y___W\.B_2QEUK/a\\    ['F_V7_Y___W.B__QEUK']: F_V8_Y___W_B_2QEUK, // WM12WVC4S6 (UY) — same AABB layout as F_V8, verified by capture" "$F" \
 && grep -q "F_V7_Y___W.B__QEUK" "$F"

# Upstream removed the nested rethink/ directory on 2026-06-04 (commit 10271b2);
# on master the Node project is at the repo root.
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
