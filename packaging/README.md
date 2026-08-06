# Empaquetado

## `../APKBUILD` — aport de navius

Es el aport real, listo para enviar a Alpine aports o a pmaports: construye
desde el tarball del tag publicado en GitHub (`source=`), no desde un directorio
local. Para desarrollar sin publicar una release:

```sh
pmbootstrap build --src /ruta/al/checkout navius   # ignora source=
```

Al construir con `--src`, el `.apk` sale con versión `1.0.10_pAAAAMMDDHHMM`;
el build reproducible desde el tarball da `1.0.10-r0` a secas.

## `piper-tts/` — aport de rhasspy/piper

Motor TTS neural, compilado nativo para musl contra `onnxruntime`, `espeak-ng`,
`fmt` y `spdlog` del sistema (nada de `gcompat` ni binarios glibc).

Se llama `piper-tts` y **instala el binario en `/usr/bin/piper-tts`** porque en
Alpine el nombre `piper` ya lo ocupa libratbag/Piper, una GUI para configurar
ratones: dos paquetes no pueden instalar `/usr/bin/piper`. `nav_tts.rs` busca
primero `piper-tts` y cae a `piper` para instalaciones antiguas.

## Copia en el árbol de pmaports

`pmbootstrap` construye con el APKBUILD que hay en el árbol de pmaports, no con
el de este repo. Si tocas el empaquetado, copia los dos ficheros:

```sh
cp APKBUILD                   <pmaports>/temp/navius/APKBUILD
cp -r packaging/piper-tts     <pmaports>/temp/
```

Es la trampa más fácil de pisar: cambiar solo el de aquí y ver que el build
sigue haciendo lo de antes.

## Estado de cara a upstream

La política de postmarketOS es que los paquetes vayan a Alpine si es posible;
`temp/` en pmaports es la sala de espera de lo que está pendiente de subir.
Ambos aports construyen ya desde tarballs públicos y sin conflictos de fichero,
que era el requisito bloqueante.
