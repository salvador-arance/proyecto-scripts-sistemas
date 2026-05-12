#!/bin/bash
#
# update_dns.sh — Detecta la IP pública (y privada) del equipo y muestra
# el dominio asociado. Pensado como esqueleto para integrar con una API
# DNS (Cloudflare, Route53, etc.).

set -euo pipefail

DOMAIN="${DOMAIN:-midominio.com}"

IP_PUBLICA=$(curl -s ifconfig.me || true)
if [ -z "$IP_PUBLICA" ]; then
    echo "Error: no se ha podido obtener la IP pública" >&2
    exit 1
fi

IP_PRIVADA=$(hostname -I 2>/dev/null | awk '{print $1}')

echo "Dominio    : $DOMAIN"
echo "IP pública : $IP_PUBLICA"
echo "IP privada : ${IP_PRIVADA:-no disponible}"

# TODO: llamada a la API del proveedor DNS para actualizar el registro A
#       de $DOMAIN apuntando a $IP_PUBLICA.

echo "DNS actualizado (pendiente integración con API)"
