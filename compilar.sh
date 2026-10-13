#!/bin/bash
# Compila el paquete de postmarketOS desde ESTE arbol. Se ejecuta en local.
#
# pmbootstrap construye dentro de un chroot nativo: la SBC ya es aarch64, asi que
# no hay emulacion de por medio y el ciclo entero son dos o tres minutos.
#
# Dos avisos que cuestan una tarde si no se saben:
#
#  - Con `--src` se ignora el `source=` del APKBUILD y se compila lo que hay en el
#    directorio, commiteado o no. La version sale como 1.0.14_pAAAAMMDDHHMM, con
#    la fecha de la compilacion, para que se distinga de la del tag.
#  - **pmbootstrap usa el APKBUILD del arbol de pmaports, no el de este
#    repositorio.** Si se toca el empaquetado hay que copiar los dos ficheros
#    (ver packaging/README.md).
set -euo pipefail

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
REGISTRO=${REGISTRO:-/tmp/navius-pmos-build.log}

command -v pmbootstrap >/dev/null || {
    echo "ERROR: no esta pmbootstrap (pipx install pmbootstrap)" >&2; exit 1; }

echo "compilando $SRC_DIR  (registro en $REGISTRO)"
pmbootstrap build --src "$SRC_DIR" navius 2>&1 | tee "$REGISTRO" | tail -3

# El paquete no lo dice pmbootstrap por la salida, asi que se busca el mas
# reciente: es el que acaba de salir y el que recogera instalar-epo2.sh.
PAQUETE=$(ls -t "$HOME"/.local/var/pmbootstrap/packages/*/aarch64/navius-*.apk 2>/dev/null | head -1)
[ -n "$PAQUETE" ] || { echo "ERROR: no encuentro el .apk generado" >&2; exit 1; }

echo
echo "paquete: $PAQUETE"
echo "         $(stat -c%s "$PAQUETE") bytes, $(date -r "$PAQUETE" '+%d/%m %H:%M')"
echo
echo "para instalarlo:  ./instalar-epo2.sh"
