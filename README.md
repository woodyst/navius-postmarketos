**Español** · [English](README.en.md)

# Navius — postmarketOS

Port de [Navius](https://github.com/woodyst/navius) — navegador GPS offline basado
en OpenStreetMap — desde Ubuntu Touch / Lomiri a **postmarketOS con Phosh**.

Misma app y misma lógica de navegación que la versión de Ubuntu Touch; cambia la
capa de plataforma: interfaz sobre QtQuickControls2 en vez de Lomiri.Components,
empaquetado APK (`abuild`/`pmbootstrap`) en vez de click, y motores de voz
recompilados de forma nativa para musl/Alpine.

Probado en un Xiaomi POCO X3 NFC (`qcom-sm7150`) con Phosh. Cualquier dispositivo
aarch64 con postmarketOS y Phosh debería servir.

## Qué trae

- Navegación guiada con voz (Valhalla), rutas offline y online.
- Mapas vectoriales (mapbox-gl-qml) online u offline vía OSM Scout Server.
- Radares fijos y de tramo con caché local persistente.
- Dead reckoning en túneles (posición por shape de ruta, IMU como señal).
- Vista de satélites GNSS (GPS, GLONASS, Galileo, BeiDou) leyendo NMEA
  directamente de ModemManager.
- Voz en 4 motores: Piper (neural), Mimic HTS, PicoTTS y espeak-ng.
- Interfaz en 12 idiomas.

## Compilar

El paquete se construye con [pmbootstrap](https://postmarketos.org/pmbootstrap).
Hacen falta dos aports que no están en pmaports oficial y viven en el árbol local
(`pmaports/temp/`): `navius` (este proyecto) y `piper` (rhasspy/piper compilado
desde fuente para musl — el paquete `piper` de Alpine es libratbag/Piper, una GUI
para ratones gaming sin ninguna relación).

```sh
# iteración rápida: compila desde un árbol de fuentes local sin commitear
pmbootstrap build --src /ruta/a/navius_postmaketos navius

# build reproducible desde el aport
pmbootstrap build navius
```

Instalar el `.apk` resultante en el dispositivo:

```sh
pmbootstrap sideload --host <dispositivo> --user <usuario> navius
# o a mano:
#   scp navius-*.apk usuario@dispositivo:/tmp/
#   sudo apk add --allow-untrusted /tmp/navius-*.apk
```

### Mapas en local

Para rutas y mapas sin conexión hace falta **OSM Scout Server**, que está en el
repositorio `community` de Alpine:

```sh
sudo apk add osmscout-server
```

No hay que arrancarlo a mano: Navius lo lanza cuando lo necesita. Sí hay que
descargar los mapas de tu región desde su propia interfaz la primera vez. Ver
[Instalación en postmarketOS](docs/instalacion.es.md).

### Fuentes de terceros no versionadas aquí

Por tamaño, el árbol de Mimic1 (`extras/mimic`, ~320 MB con `lang/`) se
sincroniza desde el repo de la versión de Ubuntu Touch antes de compilar. El
`build()` del APKBUILD lo recompila nativamente para musl/aarch64.

## Diferencias respecto a la versión de Ubuntu Touch

- **UI**: QtQuickControls2 nativo (estilo Material) en lugar de Lomiri.Components,
  con una capa de compatibilidad que reimplementa `units.gu()` e `i18n.tr()`.
- **Escala**: el grid unit se calcula al arrancar a partir de la geometría real de
  la pantalla y del `devicePixelRatio` del compositor, en vez de venir de una
  variable de entorno de la sesión. Ajustable en Preferencias → Escala de interfaz,
  o forzable con `GRID_UNIT_PX`.
- **Mapa**: paquete del sistema `mapbox-gl-qml`, no una librería vendorizada.
- **Google Maps embebido**: eliminado. Usaba QtWebEngine, que en postmarketOS solo
  existe para Qt6 y esta app es Qt5.
- **Teclado en pantalla**: API D-Bus propia de Phosh (`sm.puri.OSK0`), porque Qt5
  no trae integración nativa con ella.
- **Satélites**: NMEA vía ModemManager. El plugin `geoclue2` de Qt solo expone la
  posición agregada, sin datos por satélite.
- **Content-Hub** sustituido por el esquema `geo:` para compartir ubicación y por
  un FileDialog nativo para importar música.
- **Empaquetado**: APKBUILD/abuild en vez de clickable.

Los cambios de lógica "core" (routing, tracking, alertas) se portan a mano desde el
repo de Ubuntu Touch: no hay sincronización automática entre ambos.

## Depuración

```sh
NAVIUS_DEBUG=1 navius        # trazas de GPS/NMEA por stderr
GRID_UNIT_PX=6 navius        # forzar el tamaño del grid unit
```

## Documentación

- [Instalación en postmarketOS](docs/instalacion.es.md) — [English](docs/install.en.md)
- [Notas del port](docs/port.es.md) — [English](docs/port.en.md)
- [Empaquetado](packaging/README.md)

## Licencia

GPL-3.0-or-later, igual que la versión de Ubuntu Touch.
