#!/bin/bash
#
# deploy_sftp.sh — Sube el contenido de un directorio local a un servidor por SFTP.
# Configura las variables HOST, USER, REMOTE_DIR y LOCAL_DIR antes de ejecutar.

set -euo pipefail

HOST="${HOST:-tu-servidor.com}"
USER="${USER:-usuario}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/html}"
LOCAL_DIR="${LOCAL_DIR:-./web}"

if [ ! -d "$LOCAL_DIR" ]; then
    echo "Error: el directorio local '$LOCAL_DIR' no existe" >&2
    exit 1
fi

echo "Subiendo $LOCAL_DIR -> $USER@$HOST:$REMOTE_DIR ..."

sftp "$USER@$HOST" <<EOF
cd $REMOTE_DIR
lcd $LOCAL_DIR
put -r *
bye
EOF

echo "Subida completada"
