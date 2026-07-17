# Navius — port a postmarketOS

Port de [Navius](https://github.com/) (navegador GPS) desde Ubuntu Touch/Lomiri a
postmarketOS (Phosh). Ver plan completo en el repo clickable original o pedir a Claude
que recupere `/home/edi/.claude/plans/compressed-finding-wigderson.md`.

## Dependencia externa no versionada aquí

`extras/mimic` (motor Mimic1, ~1.1 GB con voces y builds intermedios) NO se copia a
este repo por tamaño. Antes de compilar (Fase 5), sincronizar desde el repo clickable:

```
rsync -a --exclude=_build --exclude=voices \
  /home/edi/prog_ia/navius/navius/extras/mimic/ ./extras/mimic/
```

(o directamente a epolan si se compila ahí).

## Diferencias respecto al repo clickable (Ubuntu Touch)

- UI: QtQuickControls2 nativo en vez de Lomiri.Components (ver plan).
- Mapa: paquete del sistema `mapbox-gl-qml` en vez de lib/ vendorizada.
- TTS: mismas 4 capas (Piper/Mimic HTS/PicoTTS/espeak-ng) pero recompiladas
  nativamente para musl/Alpine.
- Empaquetado: APKBUILD/abuild en vez de clickable/click.
- Content-Hub sustituido por esquema `geo:` (compartir ubicación) y FileDialog nativo
  (importar música).

Cambios en lógica "core" (routing, tracking, alertas) deben portarse a mano desde el
repo clickable si cambian allí — no hay sincronización automática.
