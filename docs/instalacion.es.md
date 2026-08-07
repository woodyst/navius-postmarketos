**Español** · [English](install.en.md)

# Instalación en postmarketOS

Navius se distribuye como paquete `.apk` de Alpine para **aarch64**. Necesitas
postmarketOS con **Phosh**; el resto de interfaces (Plasma Mobile, Sxmo…) no
están probadas y el teclado en pantalla no funcionará, porque usa la API D-Bus
propia de Phosh.

## 1. Descargar

Los dos paquetes de la [última release](https://github.com/woodyst/navius-postmarketos/releases/latest):

- `navius-<versión>-r0.apk` — la aplicación.
- `piper-tts-<versión>-r0.apk` — el motor de voz neural.

## 2. Instalar

En el mismo comando, y en este orden (Navius depende de `piper-tts`):

```sh
sudo apk add --allow-untrusted piper-tts-*.apk navius-*.apk
```

Si vienes de una versión anterior que instalaba un paquete llamado `piper`,
quítalo antes — los dos exportan la misma librería y `apk` no deja tenerlos a la
vez:

```sh
sudo apk del navius piper
```

## 3. Mapas sin conexión

Para rutas y mapas sin cobertura hace falta **OSM Scout Server**, que está en el
repositorio `community` de Alpine:

```sh
sudo apk add osmscout-server
```

No hace falta arrancarlo a mano: Navius lo lanza cuando lo necesita. Sí hay que
descargar los mapas de tu región desde la propia interfaz de OSM Scout Server la
primera vez.

Sin él, Navius funciona igual pero necesita conexión para el mapa y las rutas.

## 4. Primer arranque

La aplicación aparece en el lanzador como **Navius**. En el primer arranque:

1. Acepta la política de privacidad (explica qué se envía al servidor y qué no).
2. Comprueba el tamaño de la interfaz: **Ajustes → Escala de interfaz**. El
   valor por defecto se calcula a partir de la resolución y del escalado que
   tengas puesto en Phosh; si tu pantalla es muy distinta a 1080×2400 puede que
   quieras moverlo. El cambio se aplica al reiniciar la aplicación.
3. Si vas a usar la voz, entra en **Ajustes → Voz** y descarga una voz de Piper
   en tu idioma; los otros tres motores (Mimic HTS, PicoTTS, espeak-ng) ya
   vienen incluidos y no descargan nada.

## Problemas frecuentes

**No aparece ningún satélite.** Navius lee las frases NMEA del módem por
ModemManager. Comprueba que el módem expone la interfaz de localización:

```sh
mmcli -m 0 --location-status
```

Si tu dispositivo tiene el GNSS fuera del módem, esta vía no sirve y solo
tendrás la posición agregada de geoclue, sin vista de satélites.

**La letra sale enorme o diminuta.** Es la escala de interfaz. Para probar
valores sin tocar los ajustes:

```sh
GRID_UNIT_PX=6 navius     # 1 gu = 6 px lógicos
```

**Quiero ver qué está pasando.** Las trazas de GPS, NMEA y voz se activan por
entorno:

```sh
NAVIUS_DEBUG=1 navius
```

Si lo lanzas desde el lanzador y quieres el log:

```sh
journalctl --user -f | grep navius
```

**No suena la voz.** Comprueba que el motor elegido está disponible:
`ls /usr/bin/piper-tts /usr/lib/navius/lib/`. Piper necesita además una voz
descargada; si no hay ninguna, Navius cae automáticamente a los otros motores.
