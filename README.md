# Navius — port a postmarketOS

Port de [Navius](https://github.com/) (navegador GPS) desde Ubuntu Touch/Lomiri a
postmarketOS (Phosh). Ver plan completo en el repo clickable original o pedir a Claude
que recupere `/home/edi/.claude/plans/compressed-finding-wigderson.md`.

## Dependencias externas no versionadas aquí

Dos directorios vendor NO se copian a este repo por tamaño. Antes de compilar
(APKBUILD `build()`), sincronizar ambos:

```
rsync -a --exclude=_build --exclude=voices \
  /home/edi/prog_ia/navius/navius/extras/mimic/ ./extras/mimic/

rsync -a /home/edi/prog_ia/navius/navius/vendor/piper_aarch64/ \
  ./vendor/piper_aarch64/
```

(o directamente a epolan si se compila ahí).

- `extras/mimic` (~320 MB sin `_build`/`voices` — la mayoría es `lang/`, que sí
  hace falta): fuente de Mimic1, se recompila nativamente para musl/aarch64.
- `vendor/piper_aarch64` (~50 MB): binario oficial glibc de **rhasspy/piper**
  (motor TTS neural) para aarch64, con sus `.so` propios (`libonnxruntime`,
  `libpiper_phonemize`, etc.). Se ejecuta vía `gcompat` (capa de compatibilidad
  glibc de Alpine) porque **no existe** paquete Alpine para rhasspy/piper — el
  paquete `piper` de postmarketOS es libratbag/Piper (GUI de ratones gaming),
  un proyecto homónimo sin ninguna relación. No confundir ambos.

## Diferencias respecto al repo clickable (Ubuntu Touch)

- UI: QtQuickControls2 nativo en vez de Lomiri.Components (ver plan).
- Mapa: paquete del sistema `mapbox-gl-qml` en vez de lib/ vendorizada.
- Google Maps embebido (`GoogleMapsPanel.qml`) eliminado: usaba QtWebEngine, que
  en postmarketOS solo existe para Qt6 (esta app es Qt5). Sin sustituto por ahora.
- TTS: mismas 4 capas (Piper/Mimic HTS/PicoTTS/espeak-ng), pero Mimic
  HTS/PicoTTS recompilados nativamente para musl/Alpine, Piper vía gcompat
  (ver arriba), y se quitó el dlopen especulativo de `libsonic.so.0` (sin
  fuente vendorizada, mejora opcional de calidad no crítica).
- Empaquetado: APKBUILD/abuild en vez de clickable/click.
- Content-Hub sustituido por esquema `geo:` (compartir ubicación) y FileDialog nativo
  (importar música).

Cambios en lógica "core" (routing, tracking, alertas) deben portarse a mano desde el
repo clickable si cambian allí — no hay sincronización automática.
