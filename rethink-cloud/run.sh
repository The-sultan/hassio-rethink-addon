#!/usr/bin/env bashio
# shellcheck shell=bash
#
# Entrypoint for the rethink-cloud add-on.
#
# DESIGN: no Supervisor API.
# Everything is read directly from /data/options.json (which the Supervisor
# always writes before starting the add-on) using jq. We do NOT use
# bashio::config or bashio::addon.port, because those call the Supervisor API,
# which repeatedly failed with "403 forbidden / no token" on host_network
# installs. bashio is still used for log formatting only (that needs no API).
#
# PORT INVARIANT -------------------------------------------------------------
# rethink uses each port value BOTH to bind a listener AND to tell the device
# where to connect (cloud/thinq2/provisioning.ts builds
#   apiServer  = https://<hostname>:<https_port>
#   mqttServer = ssl://<hostname>:<mqtts_port>
# from the very same config values it binds with). With host_network: true the
# bound port equals the host port equals the advertised port, so the port you
# set in Options is exactly what the device is told to use.
#
# Why /data: rethink-cloud.ts resolves ca_key_file, ca_cert_file and
# bridge.storage_path RELATIVE TO THE CONFIG FILE'S DIRECTORY, so keeping
# config.json in /data persists the CA and bridge state across rebuilds.

set -e

CONFIG_PATH="/data/config.json"
OPTIONS="/data/options.json"
APP_DIR="/opt/rethink"

# Defensive: if the Supervisor wrote no options file, fall back to an empty
# object so the jq defaults below apply.
if [[ ! -f "${OPTIONS}" ]]; then
    echo '{}' > "${OPTIONS}"
fi

# get <key> <default> — read a scalar option, falling back to <default> when the
# key is absent or null. (Empty strings are preserved.)
get() {
    jq -r --arg k "${1}" --arg d "${2}" '.[$k] // $d' "${OPTIONS}"
}

HOSTNAME="$(get hostname homeassistant)"
MQTT_URL="$(get mqtt_url 'mqtt://localhost:1883')"
MQTT_USER="$(get mqtt_user '')"
MQTT_PASS="$(get mqtt_pass '')"
DISCOVERY_PREFIX="$(get discovery_prefix homeassistant)"
RETHINK_PREFIX="$(get rethink_prefix rethink)"

HTTPS_PORT="$(get https_port 4433)"
MQTTS_PORT="$(get mqtts_port 8884)"
MQTT_PORT="$(get mqtt_port 1884)"
THINQ1_HTTPS_PORT="$(get thinq1_https_port 46030)"
THINQ1_PORT="$(get thinq1_port 47878)"
MANAGEMENT_PORT="$(get management_port 44401)"

# log_level is an array option; read it as raw JSON, defaulting if empty/unset.
LOG_JSON="$(jq -c '(.log_level // []) | if length == 0 then ["status","incoming","HTTPS"] else . end' "${OPTIONS}")"

bashio::log.info "Configuring rethink-cloud (reading /data/options.json directly)"
bashio::log.info "  hostname:         ${HOSTNAME}"
bashio::log.info "  mqtt_url:         ${MQTT_URL}"
bashio::log.info "  discovery_prefix: ${DISCOVERY_PREFIX}"
bashio::log.info "  rethink_prefix:   ${RETHINK_PREFIX}"
bashio::log.info "  log:              ${LOG_JSON}"
bashio::log.info "Ports (host network — bound AND advertised to device):"
bashio::log.info "  https=${HTTPS_PORT} mqtts=${MQTTS_PORT} mqtt=${MQTT_PORT}"
bashio::log.info "  thinq1_https=${THINQ1_HTTPS_PORT} thinq1=${THINQ1_PORT} mgmt=${MANAGEMENT_PORT}"

# --- Render config.json -----------------------------------------------------
# Relative file paths resolve against /data (see note above). Ports are JSON
# numbers via --argjson.
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
# network you may set the HTTPS port (Options -> https_port) to 443 to avoid any
# port redirect — see README. DNS still has to point the device here.
cd "${APP_DIR}"
exec node dist/rethink-cloud.js "${CONFIG_PATH}"
