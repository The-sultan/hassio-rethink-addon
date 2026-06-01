<p align="center">
  <img src="rethink-cloud/logo.png" alt="rethink-cloud add-on" width="640">
</p>

# The-sultan's Home Assistant Add-ons

A Home Assistant add-on repository. Currently ships one add-on that packages
[**anszom/rethink**](https://github.com/anszom/rethink) — a local LG ThinQ
cloud emulator — as an installable HA add-on.

## Add this repository to Home Assistant

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**.
2. Open the **⋮** menu (top right) → **Repositories**.
3. Add this URL:

   ```
   https://github.com/The-sultan/hassio-rethink-addon
   ```

4. Close the dialog. The add-on below appears in the store under
   *"The-sultan's Home Assistant Add-ons"*.

> Or click:
> [![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FThe-sultan%2Fhassio-rethink-addon)

## Available add-ons

| Add-on | Description |
| --- | --- |
| [**rethink-cloud — local LG ThinQ server**](./rethink-cloud) | Runs the [anszom/rethink](https://github.com/anszom/rethink) local LG ThinQ cloud emulator so your LG appliances talk to Home Assistant over MQTT instead of LG's cloud. Built from upstream source at install time. |

See each add-on's own README for prerequisites, configuration, and the
important **port 443 bootstrap** procedure.

## Disclaimer

This repository is **not** an official anszom/rethink project. It is an
independently maintained wrapper by **The-sultan** that packages upstream
rethink as a Home Assistant add-on. All credit for rethink itself goes to
[anszom](https://github.com/anszom/rethink). The add-on is versioned
independently of upstream and clones upstream source at build time.
