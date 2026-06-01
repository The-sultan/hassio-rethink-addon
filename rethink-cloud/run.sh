#!/usr/bin/env bashio
# shellcheck shell=bash
#
# Entrypoint for the rethink-cloud add-on.
#
# Reads the add-on options (set in the HA UI, written by Supervisor to
# /data/options.json) via bashio, renders a rethink config.json into the
# persistent /data volume, then execs the server.
#
# PORT INVARIANT -------------------------------------------------------------
# rethink uses each port value BOTH to bind a listener AND to tell the device
# where to connect (cloud/thinq2/provisioning.ts builds
#   apiServer  = https://<hostname>:<https_port>
#   mqttServer = ssl://<hostname>:<mqtts_port>
# from the very same config values it binds with). So the port the add-on
# exposes on the LAN must equal the port written into config.json.
#
# We achieve that with host_network: true (see config.yaml) + reading the
# user-assigned ports from the Supervisor here. Whatever the user sets in the
# add-on's Network section is the port rethink binds on the host AND the port
# advertised to the device — no NAT, no mismatch.
#
# Why /data: rethink-cloud.ts resolves ca_key_file, ca_cert_file and
# bridge.storage_path RELATIVE TO THE CONFIG FILE'S DIRECTORY, so keeping
# config.json in /data persists the CA and bridge state across rebuilds.

set -e

CONFIG_PATH="/data/config.json"
APP_DIR="/opt/rethink/rethink"

# --- Resolve the real (Supervisor-assigned) ports ---------------------------
# bashio::addon.port "<internal>/tcp" returns the port the user configured in
# the Network section. If empty/null (field cleared), fall back to the default.
addon_port() {
    local key="${1}"
    local fallback="${2}"
    local value
    value="$(bashio::addon.port "${key}")"
    if bashio::var.has_value "${value}" && [[ "${value}" != "null" ]]; then
        echo "${value}"
    else
        echo "${fallback}"
    fi
}

HTTPS_PORT="$(addon_port '4433/tcp' 4433)"
MQTTS_PORT="$(addon_port '8884/tcp' 8884)"
MQTT_PORT="$(addon_port '1884/tcp' 1884)"
THINQ1_HTTPS_PORT="$(addon_port '46030/tcp' 46030)"
THINQ1_PORT="$(addon_port '47878/tcp' 47878)"
MANAGEMENT_PORT="$(addon_port '44401/tcp' 44401)"

# --- Read options -----------------------------------------------------------
HOSTNAME="$(bashio::config 'hostname')"
MQTT_URL="$(bashio::config 'mqtt_url')"
MQTT_USER="$(bashio::config 'mqtt_user')"
MQTT_PASS="$(bashio::config 'mqtt_pass')"
DISCOVERY_PREFIX="$(bashio::config 'discovery_prefix')"
RETHINK_PREFIX="$(bashio::config 'rethink_prefix')"

# log_level is an array option; read it as raw JSON and fall back to a sane
# default if it is empty or unset.
LOG_JSON="$(jq -c '(.log_level // []) | if length == 0 then ["status","incoming","HTTPS"] else . end' /data/options.json)"

bashio::log.info "Configuring rethink-cloud"
bashio::log.info "  hostname:         ${HOSTNAME}"
bashio::log.info "  mqtt_url:         ${MQTT_URL}"
bashio::log.info "  discovery_prefix: ${DISCOVERY_PREFIX}"
bashio::log.info "  rethink_prefix:   ${RETHINK_PREFIX}"
bashio::log.info "  log:              ${LOG_JSON}"
bashio::log.info "Ports (host network — bound AND advertised to device):"
bashio::log.info "  https=${HTTPS_PORT} mqtts=${MQTTS_PORT} mqtt=${MQTT_PORT}"
bashio::log.info "  thinq1_https=${THINQ1_HTTPS_PORT} thinq1=${THINQ1_PORT} mgmt=${MANAGEMENT_PORT}"

# --- Render config.json -----------------------------------------------------
# Relative file paths resolve against /data (see note above). Ports come from
# the Supervisor so they match what is exposed on the LAN.
jq -n \
  --arg hostname "${HOSTNAME}" \
  --arg mqtt_url "${MQTT_URL}" \
  --arg mqtt_user "${MQTT_USER}" \
  --arg mqtt_pass "${MQTT_PASS}" \
  --arg discovery_prefix "${DISCOVERY_PREFIX}" \
  --arg rethink_prefix "${RETHINK_PREFIX}" \
  --argjson log "${LOG_JSON}" \
  --argjson https_port "${HTTPS_PORT}" \
  --argjson mqtts_port "${MQTTS_PORT}" \
  --argjson mqtt_port "${MQTT_PORT}" \
  --argjson thinq1_https_port "${THINQ1_HTTPS_PORT}" \
  --argjson thinq1_port "${THINQ1_PORT}" \
  --argjson management_port "${MANAGEMENT_PORT}" \
  '{
    hostname: $hostname,
    homeassistant: {
      mqtt_url: $mqtt_url,
      discovery_prefix: $discovery_prefix,
      rethink_prefix: $rethink_prefix,
      mqtt_user: $mqtt_user,
      mqtt_pass: $mqtt_pass
    },
    ca_key_file: "ca.key",
    ca_cert_file: "ca.cert",
    https_port: $https_port,
    mqtts_port: $mqtts_port,
    mqtt_port: $mqtt_port,
    thinq1_https_port: $thinq1_https_port,
    thinq1_port: $thinq1_port,
    management_port: $management_port,
    bridge: { storage_path: "state" },
    log: $log
  }' > "${CONFIG_PATH}"

bashio::log.info "Wrote ${CONFIG_PATH}, starting rethink-cloud..."

# --- Run --------------------------------------------------------------------
# NOTE: the LG appliance bootstraps against common.lgthinq.com:443. With host
# network you may set the HTTPS port (4433/tcp) to 443 directly to avoid any
# port redirect — see README. DNS still has to point the device here.
cd "${APP_DIR}"
exec node dist/rethink-cloud.js "${CONFIG_PATH}"
