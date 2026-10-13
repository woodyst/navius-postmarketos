#!/bin/bash
# Instala en el dispositivo el ultimo paquete compilado. Se ejecuta en local.
#
#   ./instalar-epo2.sh                  al epo2 (epo2lan), que es el de pruebas
#   ./instalar-epo2.sh epolan           al otro telefono
#   ./instalar-epo2.sh epo2lan <fichero.apk>   un paquete concreto
#
# Coge el .apk mas reciente de pmbootstrap, no el de una ruta fija: compilar deja
# uno nuevo con la fecha en la version y es facil instalar el de antes sin
# enterarse. El 13/10/2026 paso eso: media hora buscando por que no aparecian los
# cambios en el dispositivo, y lo que habia instalado era la compilacion
# anterior.
#
# Despues de instalar hay que **volver a abrir la app**: apk reemplaza el binario
# pero no reinicia nada. Si estaba abierta, cerrarla del todo primero.
set -euo pipefail

HOST=${1:-${NAVIUS_PMOS_HOST:-epo2lan}}
PAQUETE=${2:-$(ls -t "$HOME"/.local/var/pmbootstrap/packages/*/aarch64/navius-*.apk 2>/dev/null | head -1)}

[ -n "$PAQUETE" ] && [ -f "$PAQUETE" ] || {
    echo "ERROR: no hay paquete que instalar. Compila antes con ./compilar.sh" >&2; exit 1; }

echo "paquete: $(basename "$PAQUETE")  ($(date -r "$PAQUETE" '+%d/%m %H:%M'))"

ssh -o ConnectTimeout=10 "$HOST" true 2>/dev/null || {
    echo "ERROR: $HOST no responde. ¿Esta el movil despierto y en la wifi?" >&2; exit 1; }

scp -q "$PAQUETE" "$HOST:/tmp/" || { echo "ERROR: no se pudo copiar" >&2; exit 1; }
ssh "$HOST" "sudo apk add --allow-untrusted /tmp/$(basename "$PAQUETE") >/dev/null 2>&1 \
             && rm -f /tmp/$(basename "$PAQUETE")"

# Comprobar lo que ha quedado puesto, no lo que creemos haber instalado.
echo
# `apk info -v navius` saca la descripcion, no la version: la version esta en la
# primera palabra de `apk info navius`.
ssh "$HOST" 'echo "version:   $(apk info navius | head -1 | cut -d" " -f1)"; \
             echo "binario:   $(stat -c "%y" /usr/sbin/navius | cut -c1-16)"'
echo
echo "abre la app en el dispositivo para ver los cambios"
