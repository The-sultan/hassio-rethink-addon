#!/usr/bin/env bashio
# shellcheck shell=bash
#
# Entrypoint for the rethink-cloud add-on.
#
# Reads the add-on options (set in the HA UI, written by Supervisor to
# /data/options.json) via bashio, renders a rethink config.json into the
# persistent /data volume, then execs the server.
#
# Why /data: rethink-cloud.ts resolves ca_key_file, ca_cert_file and
# bridge.storage_path RELATIVE TO THE CONFIG FILE'S DIRECTORY. By keeping
# config.json in /data with relative paths, the generated CA (ca.key/ca.cert)
# and the bridge state (state/) all land in /data, which Supervisor persists
# across restarts and rebuilds. No extra volume mapping is required.

set -e

CONFIG_PATH="/data/config.json"
APP_DIR="/opt/rethink/rethink"

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

# --- Render config.json -----------------------------------------------------
# Relative file paths resolve against /data (see note above).
jq -n \
  --arg hostname "${HOSTNAME}" \
  --arg mqtt_url "${MQTT_URL}" \
  --arg mqtt_user "${MQTT_USER}" \
  --arg mqtt_pass "${MQTT_PASS}" \
  --arg discovery_prefix "${DISCOVERY_PREFIX}" \
  --arg rethink_prefix "${RETHINK_PREFIX}" \
  --argjson log "${LOG_JSON}" \
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
    https_port: 4433,
    mqtts_port: 8884,
    mqtt_port: 1884,
    thinq1_https_port: 46030,
    thinq1_port: 47878,
    management_port: 44401,
    bridge: { storage_path: "state" },
    log: $log
  }' > "${CONFIG_PATH}"

bashio::log.info "Wrote ${CONFIG_PATH}, starting rethink-cloud..."

# --- Run --------------------------------------------------------------------
# NOTE: rethink does NOT bind to :443. The LG appliance bootstraps against
# common.lgthinq.com:443; redirecting that traffic to this add-on's :4433 is a
# network-side concern (dnsmasq / router), NOT something the add-on can do --
# add-ons have no access to the host's iptables. See README for the procedure.
cd "${APP_DIR}"
exec node dist/rethink-cloud.js "${CONFIG_PATH}"
