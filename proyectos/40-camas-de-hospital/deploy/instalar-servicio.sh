#!/usr/bin/env bash
# Construye el release e instala el proyecto 40 como servicio systemd.
# Uso (desde cualquier carpeta):  bash deploy/instalar-servicio.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
USUARIO="$(whoami)"
SERVICIO=p40-camas

echo "== Proyecto: $DIR (usuario $USUARIO)"

# Un rebar3 shell abierto ocupa el puerto 8080 y el servicio no podria arrancar.
if pgrep -u "$USUARIO" -f 'rebar3 shell' >/dev/null; then
  echo "Cierra primero el 'rebar3 shell' que esta corriendo (escribe q(). en esa terminal)."
  exit 1
fi

echo "== Construyendo el release"
cd "$DIR"
rebar3 release

echo "== Instalando /etc/systemd/system/$SERVICIO.service"
sed -e "s|__USUARIO__|$USUARIO|g" -e "s|__HOME__|$HOME|g" -e "s|__DIR__|$DIR|g" \
  "$DIR/deploy/$SERVICIO.service" | sudo tee "/etc/systemd/system/$SERVICIO.service" >/dev/null

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICIO"
sudo systemctl restart "$SERVICIO"

echo "== Esperando a que responda"
for _ in $(seq 1 20); do
  if curl -fs -o /dev/null http://localhost:8080/api/resumen; then
    echo "Listo: el servicio $SERVICIO esta corriendo y arranca solo al prender la VM."
    systemctl --no-pager --lines=0 status "$SERVICIO" || true
    exit 0
  fi
  sleep 1
done

echo "El servicio no respondio. Revisa los logs con: journalctl -u $SERVICIO -n 50"
exit 1
