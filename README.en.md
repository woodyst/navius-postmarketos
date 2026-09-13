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

Routing and maps without a connection need **OSM Scout Server**. On Alpine with
per-region maps it lives in the `community` repository:

```sh
sudo apk add osmscout-server
```

On **postmarketOS edge**, if it is not in `community`, install it as a Flatpak:

```sh
flatpak install flathub io.github.rinigus.OSMScoutServer
```

You do not need to start it yourself: Navius launches it on demand (D-Bus
activation). **The first time you must download the maps for your region from its
own interface, with the Valhalla routing engine enabled** — a fresh install ships
no maps, and if you download a region without the Valhalla part search works but
route computation does not (the `valhalla/` routing-tiles subfolder is missing). If
the local server has no routes, Navius falls back to the online routing server. See
[Installing on postmarketOS](docs/install.en.md).

### Dependencies worth knowing about

The `.apk` declares everything it needs, so `apk add` pulls it in. Two matter when
installing by hand on a very trimmed-down postmarketOS:

- **`qt5-qtbase-sqlite`** — Qt's SQLite driver. Without it the map tile cache and
  local storage fail with `SQLite driver not found`.
- **`pulseaudio-utils`** — provides `pactl`, which Navius uses to resolve the
  default speaker. On **postmarketOS edge** (recent PipeWire), opening audio against
  the "default sink" without naming it hangs (`pa_simple_new` → `Timeout`) even
  though `pactl`/`paplay` work; Navius looks up the speaker name and passes it
  explicitly. Not needed on v26.06, but the fix works on both.

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
- **Google Maps**: not embedded (QtWebEngine exists for Qt6 only on postmarketOS
  and this application is Qt5). The same viewer (`extras/gmaps/navius-gmaps.qml`)
  runs as a separate process under Qt6's `qmlscene`; it needs `qt6-qtdeclarative`
  and `qt6-qtwebengine` (package dependencies). Without them the button is hidden.
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
