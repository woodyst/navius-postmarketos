# Installing on postmarketOS

Navius ships as an Alpine `.apk` package for **aarch64**. You need postmarketOS
with **Phosh**; other interfaces (Plasma Mobile, Sxmo…) are untested and the
on-screen keyboard will not work there, because it uses Phosh's own D-Bus API.

## 1. Download

Both packages from the [latest release](https://github.com/woodyst/navius-postmarketos/releases/latest):

- `navius-<version>-r0.apk` — the application.
- `piper-tts-<version>-r0.apk` — the neural speech engine.

## 2. Install

In a single command, in this order (Navius depends on `piper-tts`):

```sh
sudo apk add --allow-untrusted piper-tts-*.apk navius-*.apk
```

If you are coming from an earlier build that installed a package called `piper`,
remove it first — both export the same library and `apk` will not have them
installed at the same time:

```sh
sudo apk del navius piper
```

## 3. Offline maps

Routing and maps without coverage need **OSM Scout Server**, which is in
Alpine's `community` repository:

```sh
sudo apk add osmscout-server
```

You do not need to start it yourself: Navius launches it on demand. You do need
to download the maps for your region from OSM Scout Server's own interface the
first time.

Without it Navius still works, but needs a connection for maps and routing.

## 4. First run

The app shows up in the launcher as **Navius**. On first run:

1. Accept the privacy policy (it spells out what is sent to the server and what
   is not).
2. Check the interface size under **Settings → Interface scale**. The default is
   derived from your screen resolution and the scaling factor set in Phosh; on a
   screen far from 1080×2400 you may want to adjust it. The change takes effect
   when the app restarts.
3. For voice guidance, go to **Settings → Voice** and download a Piper voice for
   your language. The other three engines (Mimic HTS, PicoTTS, espeak-ng) are
   bundled and download nothing.

## Troubleshooting

**No satellites at all.** Navius reads NMEA sentences from the modem through
ModemManager. Check that your modem exposes the location interface:

```sh
mmcli -m 0 --location-status
```

If your device has the GNSS chip outside the modem, this path does not apply and
you will only get geoclue's aggregated position, with no satellite view.

**Text is huge or tiny.** That is the interface scale. To try values without
touching the settings:

```sh
GRID_UNIT_PX=6 navius     # 1 gu = 6 logical px
```

**See what is going on.** GPS, NMEA and speech traces are enabled from the
environment:

```sh
NAVIUS_DEBUG=1 navius
```

If you start it from the launcher instead:

```sh
journalctl --user -f | grep navius
```

**No voice.** Check that the selected engine is present:
`ls /usr/bin/piper-tts /usr/lib/navius/lib/`. Piper also needs a downloaded
voice; with none available Navius falls back to the other engines automatically.
