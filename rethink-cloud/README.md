# rethink-cloud — local LG ThinQ server

Runs [**anszom/rethink**](https://github.com/anszom/rethink), a local
re-implementation of the LG ThinQ cloud, as a Home Assistant add-on. Your LG
appliances (washers, dryers, ACs, …) connect to this add-on instead of LG's
servers, and their state is bridged into Home Assistant over MQTT.

This add-on builds rethink **from upstream source at install time** — the
upstream project does not publish Docker images. The first install therefore
takes a few minutes while it clones and compiles the project.

> **Not an official anszom project.** This is an independently maintained
> wrapper by **The-sultan**. All credit for rethink itself goes to
> [anszom](https://github.com/anszom/rethink).

---

## Prerequisites

1. **An MQTT broker.** Install and start the official **Mosquitto broker**
   add-on, and create a Home Assistant user for it (or enable anonymous
   access). rethink publishes device state to this broker, and HA's MQTT
   integration consumes it via discovery.
2. **The MQTT integration** configured in Home Assistant, pointed at the same
   broker, with discovery enabled (it is by default).

---

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `hostname` | `homeassistant` | Hostname the LG appliance will connect to. **Must not be an IP address** — it ends up in the generated TLS certificate. |
| `mqtt_url` | `mqtt://localhost:1883` | URL of your MQTT broker. See the note below. |
| `mqtt_user` | _(empty)_ | MQTT username (leave empty for anonymous brokers). |
| `mqtt_pass` | _(empty)_ | MQTT password. |
| `discovery_prefix` | `homeassistant` | Must match `discovery.prefix` of HA's MQTT integration (default `homeassistant`). |
| `rethink_prefix` | `rethink` | Topic prefix for rethink's own MQTT topics. |
| `log_level` | all topics | Which log topics to print: `status`, `incoming`, `HTTPS`, `publish`, `MGMT`. Remove entries to make the log quieter. |

### ⚠️ Important: `mqtt_url` and the Mosquitto add-on

The default `mqtt://localhost:1883` only works if the broker is reachable on
`localhost` from **inside the add-on container** — which is usually **not** the
case. When you run the official **Mosquitto broker** add-on, reach it at its
internal hostname instead:

```
mqtt://core-mosquitto:1883
```

with the `mqtt_user` / `mqtt_pass` of the HA user you created for MQTT.

### Persistence

State is stored in the add-on's `/data` volume and survives restarts and
rebuilds:

- `/data/ca.key`, `/data/ca.cert` — the CA / server certificate, generated on
  first run (this is why `openssl` is installed in the image).
- `/data/state/` — the rethink bridge state (paired devices, credentials).
- `/data/config.json` — regenerated from your options on every start.

If you ever need a clean slate (e.g. to re-pair appliances from scratch), stop
the add-on and delete these files.

---

## 🔑 The port 443 bootstrap (read this!)

This is the part that trips everyone up.

During its **initial setup**, an LG appliance/Wi-Fi module reaches out to LG's
provisioning endpoint, **`common.lgthinq.com` on port 443**, to discover where
its "cloud" lives. rethink listens on **4433**, not 443, and a Home Assistant
add-on **cannot** rebind port 443 on the host or touch the host's `iptables`
— so you must redirect that bootstrap traffic at the **network level**.

The goal: make `common.lgthinq.com` (and the per-region hosts it returns)
resolve/redirect to your Home Assistant host, on port **4433** instead of 443.

### Option A — dnsmasq during bootstrap (recommended)

Run a temporary `dnsmasq` (on any always-on box, or even the HA host via the
[dnsmasq add-on]) that, **only while you are pairing the appliance**:

1. Answers DNS for `common.lgthinq.com` (and the regional `*.lgthinq.com`
   hosts) with your HA host's IP.
2. Combine with a port redirect `443 → 4433` on that same box
   (e.g. `iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 4433`),
   **or** point the appliance at a box where rethink itself can listen on 443.

Once the appliance is paired and has stored rethink as its cloud, you can tear
the dnsmasq/redirect down — subsequent connections go straight to the ports
this add-on exposes.

Example `dnsmasq.conf` snippet (replace `192.168.1.10` with your HA host IP):

```
address=/common.lgthinq.com/192.168.1.10
address=/lgthinq.com/192.168.1.10
```

### Option B — router-level control

If you control your router/DNS:

- Add a **DNS override / rewrite** for `common.lgthinq.com` (and `*.lgthinq.com`)
  pointing to your HA host, and a **NAT/port-forward or redirect** sending
  `:443 → HA-host:4433`.
- On OPNsense/pfWall/AdGuard/Pi-hole this is a DNS rewrite plus a NAT rule.

> You generally only need the 443 redirect for the **one-time bootstrap**. After
> pairing, the appliance talks to the add-on's own ports
> (`4433/8884/1884/46030/47878`) directly.

---

## Ports

| Port | Purpose |
| --- | --- |
| `4433/tcp` | HTTPS — ThinQ2 cloud API (point the appliance's 443 here) |
| `8884/tcp` | MQTTS — ThinQ2 device MQTT over TLS |
| `1884/tcp` | MQTT — ThinQ2 device MQTT (plain) |
| `46030/tcp` | ThinQ1 HTTPS API |
| `47878/tcp` | ThinQ1 device port |
| `44401/tcp` | Management / web UI |

---

## Links & references

- Upstream project: <https://github.com/anszom/rethink>
- Upstream discussion on Home Assistant deployment / port 443:
  <https://github.com/anszom/rethink/discussions/61>

## License

rethink is GPL-2.0 (see upstream `COPYING`). This packaging is provided as-is.
