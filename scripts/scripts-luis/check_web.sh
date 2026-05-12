#!/bin/bash
#
# check_web.sh — Comprueba que un host responde por HTTP.
# Uso: ./check_web.sh <host>

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Uso: $0 <host>" >&2
    exit 1
fi

host="$1"

if [[ ! "$host" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "Error: formato de host inválido" >&2
    exit 1
fi

if curl -s --head --fail "http://$host" > /dev/null; then
    echo "Web $host funcionando"
else
    echo "Error: la web $host no responde" >&2
    exit 1
fi
