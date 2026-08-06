# Notas del port a postmarketOS

Navius nació como aplicación de Ubuntu Touch: Qt5/QML sobre el SDK de Lomiri,
empaquetada con clickable. Este repositorio es el mismo programa funcionando
sobre postmarketOS (Alpine, musl) con Phosh. La lógica de navegación es la misma
y se porta a mano desde el repositorio de Ubuntu Touch cuando cambia allí; lo que
cambia es todo lo que tocaba plataforma.

## Capa de compatibilidad en vez de reescritura

El QML usaba `Lomiri.Components`, que fuera de Ubuntu Touch no existe. En lugar
de reescribir 34 ficheros QML se sustituyeron los dos objetos globales que
inyectaba el SDK, implementados en Rust y expuestos como propiedades de contexto
(`src/i18n_units.rs`):

- `units.gu(n)` — la unidad de rejilla con la que está medida toda la interfaz.
- `i18n.tr(texto)` — envoltorio de gettext.

Con eso, los ~2500 usos de `units.gu()` del QML siguen valiendo sin tocar una
línea, y los controles pasaron a QtQuickControls2 con estilo Material.

## Escala de la interfaz

En Ubuntu Touch, Lomiri arrancaba la app con `GRID_UNIT_PX` en el entorno de la
sesión y `devicePixelRatio = 1`: en el teléfono de referencia, 1 gu = 12 px
físicos, o sea 90 unidades de rejilla de ancho en vertical.

En Phosh no existe esa variable, y el compositor sí aplica escalado: con el
sistema al 300 %, Qt ve `devicePixelRatio = 3` y una pantalla de 360×800 px
*lógicos*. Fijar el grid unit a una constante daba el doble de tamaño que en
Ubuntu Touch.

Ahora se calcula al arrancar a partir de la geometría real de la pantalla, con
la referencia de Ubuntu Touch corregida por un factor medido en dispositivo
(1,7×, que es lo que resultó cómodo de leer). Se puede ajustar:

- En **Ajustes → Escala de interfaz**, que multiplica el valor calculado y se
  guarda en `navius.conf`. **No se sincroniza con el servidor**: depende de la
  pantalla y del escalado de cada dispositivo.
- Con `GRID_UNIT_PX=<px>` en el entorno, que lo fuerza (admite decimales).

Los bindings de QML que llaman a `gu()` no se reevalúan solos, así que el cambio
se aplica al reiniciar la aplicación.

## Voz

Los cuatro motores siguen ahí, pero compilados de otra manera:

| Motor | En Ubuntu Touch | Aquí |
|---|---|---|
| Piper (neural) | binario glibc vendorizado | paquete propio `piper-tts`, compilado nativo para musl |
| Mimic HTS | vendorizado | recompilado desde fuente en el `build()` del APKBUILD |
| PicoTTS | vendorizado | igual, con dos correcciones de portabilidad a musl |
| espeak-ng | del sistema | del sistema |

El binario de Piper se instala como `/usr/bin/piper-tts` porque en Alpine el
nombre `piper` ya lo ocupa libratbag/Piper, una GUI para configurar ratones.

Un intento anterior ejecutaba el binario oficial glibc de Piper a través de
`gcompat`. Funcionaba con frases de prueba y se caía con datos reales: el ABI de
excepciones de C++ de glibc no es compatible con la libstdc++ nativa de Alpine
que `gcompat` acaba cargando. Por eso se compila desde fuente.

## Satélites

El plugin `geoclue2` de Qt solo expone la posición agregada, sin datos por
satélite, y el plugin `geoclue` (v1) falla siempre porque ese servicio D-Bus ya
no existe. La vista de satélites lee el **NMEA crudo del módem por
ModemManager** (`src/nmea_sat_source.h`).

La constelación de cada satélite se deduce del *talker* de la frase
(`$GPGSV`, `$GLGSV`…) y, cuando el receptor emite un único `$GNGSV` con todo
mezclado —lo habitual en los módems de Qualcomm—, del rango del PRN según la
numeración de NMEA 0183 v4.10.

## Otras diferencias

- **Teclado en pantalla**: API D-Bus propia de Phosh (`sm.puri.OSK0`), porque
  Qt5 no trae integración con ella. `qml/NavTextInput.qml` sombrea el `TextInput`
  de QtQuick en todo el proyecto para engancharlo.
- **Google Maps embebido**: eliminado. Era lo único que usaba QtWebEngine, que
  en postmarketOS solo existe para Qt6 y esta aplicación es Qt5.
- **Content-Hub**: sustituido por el esquema `geo:` para recibir ubicaciones
  compartidas y por un FileDialog nativo para importar música.
- **Mapa**: paquete del sistema `mapbox-gl-qml` en vez de una librería
  vendorizada. El `pixelRatio` del mapa está calibrado para el
  `devicePixelRatio` que reporta Phosh, que no es el que reportaba Lomiri.

## Compilar

Ver [`packaging/README.md`](../packaging/README.md). En resumen:

```sh
pmbootstrap build --src /ruta/al/checkout navius   # iteración rápida
pmbootstrap build navius                           # reproducible, desde el tag
```

El aviso importante: `pmbootstrap` usa el APKBUILD que vive en el árbol de
pmaports, no el de este repositorio. Si tocas el empaquetado, copia los dos.
