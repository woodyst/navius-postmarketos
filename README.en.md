[Español](README.md) · **English**

# Navius — postmarketOS

Port of [Navius](https://github.com/woodyst/navius) — an offline GPS navigator
based on OpenStreetMap — from Ubuntu Touch / Lomiri to **postmarketOS with
Phosh**.

Same application and same navigation logic as the Ubuntu Touch version; what
changes is the platform layer: the interface runs on QtQuickControls2 instead of
Lomiri.Components, packaging is APK (`abuild`/`pmbootstrap`) instead of click,
and the speech engines are rebuilt natively for musl/Alpine.

Tested on a Xiaomi POCO X3 NFC (`qcom-sm7150`) with Phosh. Any aarch64 device
running postmarketOS with Phosh should work.

## What you get

- Turn-by-turn navigation with voice guidance, online and offline routing
  (Valhalla).
- Vector maps (mapbox-gl-qml), online or offline through OSM Scout Server.
- Fixed and average-speed camera warnings with a persistent local cache.
- Dead reckoning in tunnels (position follows the route shape, IMU as a
  supporting signal).
- GNSS satellite view (GPS, GLONASS, Galileo, BeiDou) reading NMEA straight from
  ModemManager.
- Four speech engines: Piper (neural), Mimic HTS, PicoTTS and espeak-ng.
- Interface in 12 languages.

## Building

The package is built with [pmbootstrap](https://postmarketos.org/pmbootstrap).
It needs two aports that are not in the official pmaports and live in the local
tree (`pmaports/temp/`): `navius` (this project) and `piper-tts` (rhasspy/piper
built from source for musl — the `piper` package in Alpine is libratbag/Piper, a
GUI for gaming mice, entirely unrelated).

```sh
# fast iteration: builds from a local source tree, nothing to commit
pmbootstrap build --src /path/to/navius_postmaketos navius

# reproducible build from the aport
pmbootstrap build navius
```

Install the resulting `.apk` on the device:

```sh
pmbootstrap sideload --host <device> --user <user> navius
# or by hand:
#   scp navius-*.apk user@device:/tmp/
#   sudo apk add --allow-untrusted /tmp/navius-*.apk
```

### Local maps

Routing and maps without a connection need **OSM Scout Server**, which is in
Alpine's `community` repository:

```sh
sudo apk add osmscout-server
```

You do not need to start it yourself: Navius launches it on demand. You do need
to download the maps for your region from its own interface the first time. See
[Installing on postmarketOS](docs/install.en.md).

### Third-party sources not versioned here

Because of its size, the Mimic1 tree (`extras/mimic`, ~320 MB with `lang/`) is
synced from the Ubuntu Touch repository before building. The APKBUILD's
`build()` rebuilds it natively for musl/aarch64.

## Differences from the Ubuntu Touch version

- **UI**: native QtQuickControls2 (Material style) instead of Lomiri.Components,
  with a compatibility layer reimplementing `units.gu()` and `i18n.tr()`.
- **Scaling**: the grid unit is computed at startup from the real screen
  geometry and the compositor's `devicePixelRatio`, rather than coming from a
  session environment variable. Adjustable under Settings → Interface scale, or
  forced with `GRID_UNIT_PX`.
- **Map**: the system `mapbox-gl-qml` package, not a vendored library.
- **Embedded Google Maps**: removed. It used QtWebEngine, which on postmarketOS
  exists for Qt6 only and this application is Qt5.
- **On-screen keyboard**: Phosh's own D-Bus API (`sm.puri.OSK0`), since Qt5 has
  no integration with it.
- **Satellites**: NMEA through ModemManager. Qt's `geoclue2` plugin only exposes
  the aggregated position, with no per-satellite data.
- **Content-Hub** replaced by the `geo:` scheme for sharing locations and by a
  native FileDialog for importing music.
- **Packaging**: APKBUILD/abuild instead of clickable.

Core logic changes (routing, tracking, alerts) are ported by hand from the
Ubuntu Touch repository: there is no automatic sync between the two.

## Debugging

```sh
NAVIUS_DEBUG=1 navius        # GPS/NMEA traces on stderr
GRID_UNIT_PX=6 navius        # force the grid unit size
```

## Documentation

- [Installing on postmarketOS](docs/install.en.md) — [Español](docs/instalacion.es.md)
- [Port notes](docs/port.en.md) — [Español](docs/port.es.md)
- [Packaging](packaging/README.md)

## Licence

GPL-3.0-or-later, same as the Ubuntu Touch version.
