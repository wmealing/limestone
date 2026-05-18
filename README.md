<!--
 Copyright 2026 <wmealing@gmail.com>

 SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
-->
# my_status_node

An Erlang application for the **Raspberry Pi Pico W** running on [AtomVM](https://atomvm.net/). It connects to Wi-Fi, reads sensor data, and POSTs it as JSON to a remote HTTP(S) server on a 20-second loop.

## What it does

1. Connects to Wi-Fi (retrying indefinitely on failure).
2. Reads sensor data via `dummy_sensor` (currently returns a hardcoded JSON payload).
3. POSTs the payload to `/api/collect/` on a configurable host over plain TCP or SSL.
4. Sleeps 20 seconds and repeats.

## Source modules

| Module | Purpose |
|---|---|
| `my_status_node` | Entry point — boot banner, Wi-Fi loop, main sensor loop |
| `networking` | HTTP POST over plain TCP or SSL; handles connect/send/recv/close |
| `dummy_sensor` | Stub sensor — returns `{"sensor_id":"1","value":"12"}` as JSON |
| `button` | GPIO helper — reads a push-button on pin 15 (pull-up, active-low) |
| `config` | Central config map (server hostname, host IP, port) |

## Build & flash

All commands run from the repo root:

```bash
# Compile + flash the Erlang app (Pico W must be connected via USB)
make build-image

# Copy AtomVM firmware + stdlib onto a Pico W in BOOTSEL mode
make deploy-image

# Attach a serial console to see output
make observe
```

Or from inside `my_status_node/`:

```bash
rebar3 compile                  # compile only
rebar3 atomvm packbeam          # produce the .avm bundle
rebar3 atomvm pico_flash        # build + flash over USB serial
```

## First-time setup (firmware)

1. Hold **BOOTSEL**, plug in the Pico W — it mounts as `RPI-RP2`.
2. Run `make deploy-image` to write the AtomVM VM firmware and stdlib (VM first, then stdlib after a 5 s delay).
3. The device reboots into AtomVM.
4. Run `make build-image` to compile and flash the app.
5. Run `make observe` to open the serial console (`/dev/cu.usbmodem11101`).

## Configuration

Wi-Fi credentials are set in `my_status_node.erl`:

```erlang
-define(WIFI_CONFIG, [
    {ssid, <<"your-ssid">>},
    {psk,  <<"your-password">>},
    {dhcp_hostname, <<"firstpico">>}
]).
```

The target server is set in `networking.erl` (and mirrored in `config.erl`):

```erlang
-define(HOST_TCP, "cobalt-mellowed-blossom-1379.fly.dev").
-define(PORT_TCP, 80).
-define(HOST_SSL, "cobalt-mellowed-blossom-1379.fly.dev").
-define(PORT_SSL, 443).
```

SSL is disabled by default (`UseSsl = false` in `start/0`). Set it to `true` to use HTTPS.

## Running on ESP32

AtomVM supports ESP32 boards (ESP32, ESP32-S3, ESP32-C3, etc.) with a few changes.

### Additional prerequisite

Install `esptool.py` — the ESP32 flash tool. ESP32 does **not** use `picotool`.

```bash
pip install esptool
# or
brew install esptool
```

### Download ESP32 firmware

Get the matching AtomVM ESP32 firmware from the [AtomVM releases page](https://github.com/atomvm/AtomVM/releases). You need the `.bin` file for your chip variant, e.g. `AtomVM-esp32-v0.7.0-alpha.1.bin`. Unlike Pico W, the stdlib is bundled in the main firmware image — there is no separate stdlib `.uf2`.

### Flash the firmware (first-time only)

Put the board into flash mode: hold the **BOOT** button, press and release **EN/Reset**, then release **BOOT**. Then:

```bash
esptool.py --chip esp32 --port /dev/cu.SLAB_USBtoUART --baud 921600 \
    write_flash -z 0x1000 AtomVM-esp32-v0.7.0-alpha.1.bin
```

Adjust `--chip` for your variant (`esp32s3`, `esp32c3`, etc.) and `--port` for your serial device. On macOS the port is typically `/dev/cu.SLAB_USBtoUART` (CP2102) or `/dev/cu.usbserial-*` (CH340/FTDI) — run `ls /dev/cu.*` to find it.

### Update rebar.config

Add the `esp32_flash` key to the plugin config so `rebar3 atomvm esp32_flash` knows which port to target:

```erlang
{atomvm_rebar3_plugin, [
    {packbeam, [{start, my_status_node}, prune]},
    {include_stdlib, true},
    {esp32_flash, [{port, "/dev/cu.SLAB_USBtoUART"}, {baud, 115200}]}
]}.
```

### Flash the app

```bash
rebar3 atomvm esp32_flash
```

### Serial console

```bash
screen /dev/cu.SLAB_USBtoUART 115200
```

### What stays the same

The Erlang source code (`my_status_node`, `networking`, `dummy_sensor`, `button`, `config`) does not need changes — the AtomVM API for Wi-Fi, TCP, SSL, and GPIO is the same across Pico W and ESP32. The only platform-specific detail is the GPIO pin numbering in `button.erl` if you wire a button differently.

## Dependencies

- [AtomVM](https://atomvm.net/) v0.7.0-alpha.1 (Pico W firmware `.uf2` included in repo root; ESP32 firmware downloaded separately)
- [`atomvm_lib`](https://github.com/atomvm/atomvm_lib) — pinned via `rebar.lock`
- [`atomvm_rebar3_plugin`](https://github.com/atomvm/atomvm_rebar3_plugin) — build tooling
- `rebar3`
- Pico W: `picotool` (`brew install picotool`)
- ESP32: `esptool.py` (`pip install esptool` or `brew install esptool`)

## License

Apache-2.0 OR LGPL-2.1-or-later
