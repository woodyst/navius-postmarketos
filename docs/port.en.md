# postmarketOS port notes

Navius started as an Ubuntu Touch application: Qt5/QML on the Lomiri SDK,
packaged with clickable. This repository is the same program running on
postmarketOS (Alpine, musl) with Phosh. The navigation logic is the same and is
ported by hand from the Ubuntu Touch repository whenever it changes there; what
differs is everything that touched the platform.

## A compatibility layer instead of a rewrite

The QML used `Lomiri.Components`, which does not exist outside Ubuntu Touch.
Rather than rewriting 34 QML files, the two global objects the SDK injected were
reimplemented in Rust and exposed as context properties
(`src/i18n_units.rs`):

- `units.gu(n)` — the grid unit the whole interface is measured in.
- `i18n.tr(text)` — a gettext wrapper.

With those, the ~2500 `units.gu()` call sites keep working untouched, and the
controls moved to QtQuickControls2 with the Material style.

## Interface scale

On Ubuntu Touch, Lomiri started the app with `GRID_UNIT_PX` in the session
environment and `devicePixelRatio = 1`: on the reference phone, 1 gu = 12
physical px, i.e. 90 grid units across in portrait.

Phosh has no such variable, and the compositor does apply scaling: with the
system at 300 %, Qt sees `devicePixelRatio = 3` and a 360×800 *logical* pixel
screen. Pinning the grid unit to a constant made everything twice the size it
had on Ubuntu Touch.

It is now computed at startup from the real screen geometry, using the Ubuntu
Touch reference corrected by a factor measured on device (1.7×, which is what
turned out comfortable to read). It can be adjusted:

- Under **Settings → Interface scale**, which multiplies the computed value and
  is stored in `navius.conf`. It is **not synced to the server**: it depends on
  each device's screen and scaling factor.
- With `GRID_UNIT_PX=<px>` in the environment, which forces it (decimals
  allowed).

QML bindings that call `gu()` are not re-evaluated on the fly, so the change
applies when the application restarts.

## Speech

The same four engines, built differently:

| Engine | On Ubuntu Touch | Here |
|---|---|---|
| Piper (neural) | vendored glibc binary | own `piper-tts` package, built native for musl |
| Mimic HTS | vendored | rebuilt from source in the APKBUILD's `build()` |
| PicoTTS | vendored | same, with two musl portability fixes |
| espeak-ng | system | system |

Piper's binary installs as `/usr/bin/piper-tts` because in Alpine the name
`piper` is already taken by libratbag/Piper, a GUI for configuring mice.

An earlier attempt ran Piper's official glibc binary through `gcompat`. It
worked on test phrases and crashed on real data: glibc's C++ exception ABI is
not compatible with Alpine's native libstdc++, which `gcompat` ends up loading.
Hence building from source.

## Satellites

Qt's `geoclue2` plugin only exposes the aggregated position, with no per
satellite data, and the legacy `geoclue` (v1) plugin always fails because that
D-Bus service no longer exists. The satellite view reads **raw NMEA from the
modem through ModemManager** (`src/nmea_sat_source.h`).

Each satellite's constellation comes from the sentence talker (`$GPGSV`,
`$GLGSV`…) and, when the receiver emits a single `$GNGSV` with everything mixed
together — the common case on Qualcomm modems — from the PRN range as numbered
by NMEA 0183 v4.10.

## Other differences

- **On-screen keyboard**: Phosh's own D-Bus API (`sm.puri.OSK0`), since Qt5 has
  no integration with it. `qml/NavTextInput.qml` shadows QtQuick's `TextInput`
  across the project to hook it up.
- **Embedded Google Maps**: removed. It was the only user of QtWebEngine, which
  on postmarketOS exists for Qt6 only and this application is Qt5.
- **Content-Hub**: replaced by the `geo:` scheme for incoming shared locations
  and a native FileDialog for importing music.
- **Map**: the system `mapbox-gl-qml` package instead of a vendored library. The
  map's `pixelRatio` is calibrated for the `devicePixelRatio` Phosh reports,
  which is not the one Lomiri reported.

## Building

See [`packaging/README.md`](../packaging/README.md). In short:

```sh
pmbootstrap build --src /path/to/checkout navius   # fast iteration
pmbootstrap build navius                           # reproducible, from the tag
```

The one gotcha: `pmbootstrap` uses the APKBUILD living in the pmaports tree, not
the one in this repository. If you touch packaging, copy both.
