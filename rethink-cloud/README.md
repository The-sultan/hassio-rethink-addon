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

---

## How ports work (since 0.1.1)

**Design invariant:** *the port the add-on exposes on the LAN is exactly the
port the device is told to connect to.*

rethink uses each port number for **two** things at once: it `.listen()`s on
that port **and** it advertises that same port to the appliance during
provisioning (`apiServer = https://<hostname>:<https_port>`,
`mqttServer = ssl://<hostname>:<mqtts_port>`). If the externally-reachable port
ever differed from the one written into rethink's config, the device would be
told to connect to a port that isn't actually there.

To guarantee they're equal, the add-on runs on **`host_network: true`** and
reads the ports you set in its **Network** section, then hands those exact
numbers to rethink. There is no Docker NAT in between:

- **You configure ports in the add-on's _Network_ section** (Settings →
  Add-ons → rethink-cloud → **Network**), **not** in the Options. The defaults
  are `4433 / 8884 / 1884 / 46030 / 47878 / 44401`.
- Whatever you set there is the port rethink **binds on the host** *and* the
  port it **tells the device** to use. Change `8884 → 18884` (e.g. to avoid a
  clash) and rethink will both listen on `18884` and advertise `18884`.
- If you clear a port field, the add-on falls back to that port's default.

### 🔒 Security implication of host network

`host_network: true` means the add-on **shares the Home Assistant host's
network namespace** — it has **no network isolation**: it can bind any host
port (including privileged ports like 443), sees all host interfaces, and its
listeners are reachable on every address the host has. This is required for the
invariant above (binding privileged/host ports and matching them 1:1), but it
is a broader privilege than a normal bridged add-on. Only install it on a
trusted LAN, and pick ports that don't collide with Home Assistant itself
(the HA UI on `8123`, and `443` if you've enabled SSL for the frontend).

### ⚠️ Important: `mqtt_url` and the Mosquitto add-on

This add-on runs on the **host network** (see *How ports work* below), so
`localhost` inside the container **is** the Home Assistant host. The official
**Mosquitto broker** add-on exposes `1883` on the host, so the default

```
mqtt://localhost:1883
```

reaches it directly — set `mqtt_user` / `mqtt_pass` to the HA user you created
for MQTT.

> On host network the Docker-internal hostname `core-mosquitto` may **not**
> resolve. Prefer `localhost` (or the host's LAN IP). If Mosquitto listens on a
> non-default port, set it in `mqtt_url` accordingly.

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
its "cloud" lives. You must point that name at your HA host (DNS), and the HTTPS
service has to answer on the port the device dials.

In every case you need a **DNS override**: make `common.lgthinq.com` (and the
regional `*.lgthinq.com` hosts) resolve to your Home Assistant host's IP. What
you do about the **port** is where the options differ.

### Option A — bind 443 directly (simplest, since 0.1.1)

Because the add-on runs on the host network, you can simply set the **HTTPS port
(`4433/tcp`) to `443`** in the add-on's **Network** section. rethink then binds
`443` on the host directly and advertises `443` to the device, so **no port
redirect is needed at all** — only the DNS override above.

Caveats: `443` must be free on the host (don't use this if you've enabled SSL
for the HA frontend on `443`), and binding it requires the host-network
privilege this add-on already has.

### Option B — dnsmasq + redirect during bootstrap

If you'd rather leave the add-on's HTTPS port at `4433`, run a temporary
`dnsmasq` (on any always-on box, or even the HA host via the
[dnsmasq add-on]) that, **only while you are pairing the appliance**:

1. Answers DNS for `common.lgthinq.com` (and the regional `*.lgthinq.com`
   hosts) with your HA host's IP.
2. Combine with a port redirect `443 → 4433` on that same box
   (e.g. `iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 4433`).

Once the appliance is paired and has stored rethink as its cloud, you can tear
the dnsmasq/redirect down — subsequent connections go straight to the ports
this add-on exposes.

Example `dnsmasq.conf` snippet (replace `192.168.1.10` with your HA host IP):

```
address=/common.lgthinq.com/192.168.1.10
address=/lgthinq.com/192.168.1.10
```

### Option C — router-level control

If you control your router/DNS and don't want to bind `443` on the host:

- Add a **DNS override / rewrite** for `common.lgthinq.com` (and `*.lgthinq.com`)
  pointing to your HA host, and a **NAT/port-forward or redirect** sending
  `:443 → HA-host:4433` (or whatever you set the HTTPS port to).
- On OPNsense/pfWall/AdGuard/Pi-hole this is a DNS rewrite plus a NAT rule.

> The 443 redirect is only for the **one-time bootstrap**. After pairing, the
> appliance talks to the add-on's own ports directly.

---

## Ports

Configure these in the add-on's **Network** section (not Options). The default
is shown; rethink binds and advertises whatever you set — see *How ports work*.

| Default | Purpose |
| --- | --- |
| `4433/tcp` | HTTPS — ThinQ2 cloud API (set to `443` to skip the redirect) |
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
