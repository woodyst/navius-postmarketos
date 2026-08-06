# Navius — an offline GPS navigator, now on postmarketOS/Phosh

I have been building **[Navius](https://github.com/woodyst/navius)**, a
turn-by-turn GPS navigator, for Ubuntu Touch for a while. It is now ported to
**postmarketOS with Phosh**, and the first release is out:

**https://github.com/woodyst/navius-postmarketos/releases/latest**

Tested on a Xiaomi POCO X3 NFC (`qcom-sm7150`). It should work on any aarch64
device running postmarketOS with Phosh.

---

## What it does

- Turn-by-turn navigation with spoken instructions, in 12 languages.
- Fully offline routing and maps through OSM Scout Server, which it starts on
  demand.
- Vector maps (mapbox-gl-qml) with day, night and satellite styles.
- Fixed and average-speed camera warnings, cached locally so it does not hammer
  Overpass while you drive.
- Dead reckoning in tunnels: position keeps following the route shape when GPS
  drops, with the IMU as a supporting signal rather than as the source.
- GNSS satellite view: GPS, GLONASS, Galileo and BeiDou.
- Four offline speech engines: Piper (neural), Mimic HTS, PicoTTS, espeak-ng.

GPL-3.0. No ads, no subscription, no telemetry in this version.

## Install

Two packages, in this order:

```sh
sudo apk add --allow-untrusted piper-tts-*.apk navius-*.apk
sudo apk add osmscout-server      # optional, for offline maps and routing
```

## Notes that may be useful to other porters

A few things I ran into that are not specific to this app:

**Grid units and compositor scaling.** The whole UI is measured in Lomiri "grid
units". On Ubuntu Touch, Lomiri sets `GRID_UNIT_PX` in the session environment
and apps run at `devicePixelRatio = 1`. Under Phosh there is no such variable and
the compositor *does* scale: at 300 % the app sees `devicePixelRatio = 3` and a
360×800 logical screen. Carrying over a fixed pixel constant made the whole
interface exactly twice its intended size. It is now derived at startup from the
screen geometry, with a user-facing multiplier for fine tuning.

**Per-satellite GNSS data.** Qt's `geoclue2` plugin only exposes the aggregated
position — no per-satellite information — and the legacy `geoclue` (v1) plugin
always fails because that D-Bus service is long gone. What worked was reading raw
NMEA from the modem through ModemManager (`MMModemLocationSource::GPS_NMEA`).
Watch out for the reply signature: `GetLocation` returns `a{uv}`, with **uint32**
keys, and a `QVariantMap` will not match it.

**Multi-constellation NMEA.** Qualcomm modems tend to emit a single `$GNGSV`
with every constellation mixed in, rather than `$GPGSV`/`$GLGSV`/`$GAGSV`. If you
derive the constellation from the sentence talker alone, everything shows up as
"unknown" and nothing is ever marked as in use. The PRN ranges in NMEA 0183
v4.10 are what actually tell them apart.

**glibc binaries through gcompat.** I first ran the official glibc build of
rhasspy/piper under `gcompat`. It worked on test phrases and crashed on real
input: glibc's C++ exception ABI does not match Alpine's native libstdc++, which
`gcompat` ends up loading. Compiling from source against Alpine's onnxruntime,
espeak-ng, fmt and spdlog fixed it for good.

**Package name collisions.** If you package rhasspy/piper, note that Alpine
already has a `piper` package — libratbag/Piper, a GUI for gaming mice. Mine is
`piper-tts`, installing `/usr/bin/piper-tts`, so both can coexist.

**On-screen keyboard.** Qt5 has no integration with Phosh's OSK. It is driven
through Phosh's own D-Bus interface (`sm.puri.OSK0`, `SetVisible`). The layout
hints (numeric, URL…) would need real Wayland text-input support, so for now
everything gets the default layout.

## Where it stands

Working: map, routing, voice, GPS and satellite view, offline maps, on-screen
keyboard, community alerts. Pending: screen/power inhibition during navigation
(the Lomiri API has no port yet) and keyboard layout hints.

The aports for both packages are in the repository, building from release
tarballs. I would like to get them into Alpine eventually; feedback on the
packaging is welcome, especially about the engines that are still vendored
inside the app package.

Happy to hear how it behaves on other devices.
