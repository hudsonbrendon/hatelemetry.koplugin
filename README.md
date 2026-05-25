<p align="center">
  <img src="logo.png" alt="KOReader" width="320">
</p>

# HA Telemetry — KOReader plugin

[![CI](https://github.com/hudsonbrendon/hatelemetry.koplugin/actions/workflows/ci.yml/badge.svg)](https://github.com/hudsonbrendon/hatelemetry.koplugin/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/hudsonbrendon/hatelemetry.koplugin)](https://github.com/hudsonbrendon/hatelemetry.koplugin/releases)

KOReader plugin that pushes reading and device **telemetry** from a Kindle (or any
KOReader device) to **Home Assistant**, and **applies commands** sent back from Home
Assistant — frontlight, warmth, wifi, page turns, on-screen messages and more.

Companion Home Assistant integration: **[ha-koreader](https://github.com/hudsonbrendon/ha-koreader)**
— the native integration that receives this telemetry and exposes the entities/controls.

## How it works

On each check-in (sleep/wake, open/close a book, or a periodic loop) the plugin builds a
snapshot and sends it to Home Assistant. There are two modes:

- **Webhook (native, recommended)** — sends the snapshot to the
  [ha-koreader](https://github.com/hudsonbrendon/ha-koreader) integration, which exposes
  all entities **and** returns control commands in the response. Full telemetry + control.
- **REST (legacy)** — writes sensors directly to Home Assistant's `/api/states` using a
  long-lived token. Telemetry only; no control from Home Assistant.

> **e-ink note:** commands from Home Assistant are applied on the device's next check-in
> with WiFi on — not instant while the screen is off.

## Installation

Copy this folder into KOReader's plugins directory, keeping the `.koplugin` suffix:

```
koreader/plugins/hatelemetry.koplugin/
```

- **USB:** mount the device and copy to `/<device>/koreader/plugins/`.
- **SSH:** `scp -r` the folder to `/mnt/us/koreader/plugins/` (path may vary).
- **Release zip:** download the latest [release](https://github.com/hudsonbrendon/hatelemetry.koplugin/releases)
  and unzip into the plugins directory.

Then restart KOReader. The plugin appears under **Tools → HA Telemetry**.

## Configuration

Copy `ha_config.sample.lua` to `ha_config.lua` (gitignored) and fill it in:

| Field | Description |
|---|---|
| `host` | Home Assistant host (e.g. `homeassistant.local`) |
| `port` | Port (e.g. `8123`, or `443` behind TLS) |
| `https` | `true` if Home Assistant uses HTTPS |
| `webhook_id` | **Webhook mode:** the id from the integration's webhook URL. Leave empty for REST mode. |
| `token` | **REST mode:** a Home Assistant long-lived access token. Leave `""` for webhook mode. |

The mode is chosen automatically: a non-empty `webhook_id` enables webhook mode, otherwise
the plugin falls back to REST with `token`.

## Menu (Tools → HA Telemetry)

- **Send telemetry on sleep/wake & open/close** — push on lifecycle events.
- **Periodic updates while awake** — push on a timed loop.
- **Test connection** — send one snapshot now and report success/failure.
- **Show current snapshot** — preview the data that would be sent.

## Telemetry sent

| Field | Description | HA entity (ha-koreader) |
|---|---|---|
| `reading` | Book open / reading | `binary_sensor.koreader_reading` |
| `is_charging` | Device charging | `binary_sensor.koreader_charging` |
| `wifi_connected` | Wi-Fi connected | `binary_sensor.koreader_wifi` / `switch.koreader_wifi` |
| `battery_level` | Battery (%) | `sensor.koreader_battery` |
| `device_model` | Device model | device info |
| `book_title` | Book title | `sensor.koreader_book_title` |
| `book_author` | Book author | `sensor.koreader_book_author` |
| `book_series` | Series / collection | `sensor.koreader_book_series` |
| `book_format` | File format | `sensor.koreader_book_format` |
| `book_language` | Language | `sensor.koreader_book_language` |
| `chapter` | Current chapter | `sensor.koreader_chapter` |
| `progress_percent` | Progress (%) | `sensor.koreader_progress` |
| `current_page` | Current page | `sensor.koreader_current_page` |
| `total_pages` | Total pages | `sensor.koreader_total_pages` |
| `pages_left` | Pages left in book | `sensor.koreader_pages_left` |
| `pages_left_chapter` | Pages left in chapter | `sensor.koreader_pages_left_in_chapter` |
| `time_to_finish_book_min` | ETA to finish book (min) | `sensor.koreader_time_to_finish_book` |
| `time_to_finish_chapter_min` | ETA to finish chapter (min) | `sensor.koreader_time_to_finish_chapter` |
| `reading_speed_pph` | Reading speed (pages/h) | `sensor.koreader_reading_speed` |
| `reading_time_today_min` | Reading time today (min) | `sensor.koreader_reading_time_today` |
| `pages_read_today` | Pages read today | `sensor.koreader_pages_read_today` |
| `session_time_min` | Current session (min) | `sensor.koreader_session_time` |
| `total_time_min` | Lifetime time for the book (min) | `sensor.koreader_total_reading_time` |
| `annotations_count` | Highlights / notes | `sensor.koreader_annotations` |
| `frontlight` | Frontlight level (%) | `sensor.koreader_frontlight` / `number.koreader_frontlight` |
| `frontlight_on` | Frontlight on/off | `binary_sensor.koreader_frontlight_on` |
| `warmth` | Frontlight warmth | `sensor.koreader_warmth` / `number.koreader_warmth` |
| `last_seen` | Snapshot timestamp | attribute |

## Commands applied (webhook mode)

Commands returned by Home Assistant are applied on the next check-in:

| Command | Effect |
|---|---|
| `show_message` | Show a text message on screen |
| `set_frontlight` | Set frontlight brightness |
| `set_frontlight_power` | Turn frontlight on/off |
| `set_warmth` | Set frontlight warmth |
| `set_wifi` | Turn Wi-Fi on/off |
| `page_turn` | Turn to next/previous page |
| `goto_page` | Jump to a specific page |
| `refresh` | Refresh the e-ink screen |
| `sync_now` | Trigger a sync |

## Development

Tests use [busted](https://lunarmodules.github.io/busted/):

```bash
brew install luarocks && luarocks install busted
busted
```

CI runs the suite on every push/PR. Tagging `vX.Y.Z` builds a plugin zip and publishes a
GitHub release automatically.
