#!/bin/bash
set -euo pipefail

# ==========================================
# CONFIGURACIÓN — cargada desde fichero externo
# ==========================================
CONFIG_FILE="/etc/guardian/config"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ERROR] Fichero de configuración no encontrado: $CONFIG_FILE"
    echo "        Ejecuta setup.sh primero."
    exit 1
fi

source "$CONFIG_FILE"

: "${TOKEN:?'TOKEN no definido en $CONFIG_FILE'}"
: "${CHAT_ID:?'CHAT_ID no definido en $CONFIG_FILE'}"
: "${USERS_AUTORIZADOS:?'USERS_AUTORIZADOS no definido en $CONFIG_FILE'}"

MI_NOMBRE=$(hostname)
LOG_FILE="/var/log/auth.log"
ULTIMO_ID_FILE="/var/lib/guardian/last_update_id"
mkdir -p "$(dirname "$ULTIMO_ID_FILE")"

# ==========================================
# FUNCIONES AUXILIARES
# ==========================================

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" -d text="$1" > /dev/null
}

# Monitor de intentos de acceso fallidos (autenticación)
monitor_ssh() {
    echo "[+] Monitor de auth.log iniciado en $MI_NOMBRE"
    tail -Fn0 "$LOG_FILE" | while read -r LINEA; do
        if echo "$LINEA" | grep -q "Failed password\|Connection closed by authenticating user"; then
            IP_ATAQUE=$(echo "$LINEA" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
            if [[ -n "$IP_ATAQUE" ]]; then
                send_telegram "⚠️ [$MI_NOMBRE] Intento SSH fallido desde: $IP_ATAQUE"
            fi
        fi
    done
}

# Monitor de conexiones bloqueadas por UFW al puerto 22
monitor_ufw() {
    local UFW_LOG="/var/log/ufw.log"
    if [[ ! -f "$UFW_LOG" ]]; then
        echo "[!] $UFW_LOG no encontrado, monitor UFW desactivado."
        return
    fi
    echo "[+] Monitor de ufw.log iniciado en $MI_NOMBRE"
    declare -A LAST_ALERT
    local COOLDOWN=60
    tail -Fn0 "$UFW_LOG" | while read -r LINEA; do
        if echo "$LINEA" | grep -q "\[UFW BLOCK\]" && echo "$LINEA" | grep -q "DPT=22"; then
            IP_ATAQUE=$(echo "$LINEA" | grep -oP 'SRC=\K[0-9.]+')
            if [[ -n "$IP_ATAQUE" ]]; then
                local NOW
                NOW=$(date +%s)
                local LAST=${LAST_ALERT[$IP_ATAQUE]:-0}
                if (( NOW - LAST >= COOLDOWN )); then
                    send_telegram "🚫 [$MI_NOMBRE] Conexión SSH bloqueada desde: $IP_ATAQUE"
                    LAST_ALERT[$IP_ATAQUE]=$NOW
                fi
            fi
        fi
    done
}

# ==========================================
# EJECUCIÓN
# ==========================================

monitor_ssh &
MONITOR_PID=$!
monitor_ufw &
MONITOR_UFW_PID=$!
trap 'kill "$MONITOR_PID" "$MONITOR_UFW_PID" 2>/dev/null || true' EXIT INT TERM

echo "[+] Bot de comandos activo en $MI_NOMBRE. Escuchando..."

while true; do
    LAST_ID=$(cat "$ULTIMO_ID_FILE" 2>/dev/null || echo 0)

    UPDATES=$(curl -s "https://api.telegram.org/bot$TOKEN/getUpdates?offset=$((LAST_ID + 1))&timeout=20" || true)

    RESULTADO=$(echo "$UPDATES" | jq -c '
        .result[]
        | select(.message.text // "" | test("^/allow[@a-zA-Z0-9_]* "))
        | {update_id: .update_id, sender_id: .message.from.id, text: .message.text}
    ' 2>/dev/null | tail -1 || true)

    if [[ -n "$RESULTADO" ]]; then
        UPDATE_ID=$(echo "$RESULTADO" | jq -r '.update_id')
        SENDER_ID=$(echo "$RESULTADO" | jq -r '.sender_id')
        TEXTO=$(echo "$RESULTADO"    | jq -r '.text')

        if [ "$UPDATE_ID" -gt "$LAST_ID" ]; then
            echo "$UPDATE_ID" > "$ULTIMO_ID_FILE"

            if [[ " $USERS_AUTORIZADOS " =~ " $SENDER_ID " ]]; then

                IP_REQ=$(echo "$TEXTO" | awk '{print $2}')
                TARGET=$(echo "$TEXTO" | awk '{print $3}')

                # Validar formato IPv4 para prevenir inyección de comandos
                if [[ ! "$IP_REQ" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                    send_telegram "⛔ [$MI_NOMBRE] IP inválida rechazada: $IP_REQ"
                    continue
                fi
                IFS='.' read -r o1 o2 o3 o4 <<< "$IP_REQ"
                if (( o1 > 255 || o2 > 255 || o3 > 255 || o4 > 255 )); then
                    send_telegram "⛔ [$MI_NOMBRE] IP fuera de rango rechazada: $IP_REQ"
                    continue
                fi

                if [ "$TARGET" == "$MI_NOMBRE" ] || [ "$TARGET" == "all" ]; then
                    sudo ufw allow from "$IP_REQ" to any port 22 proto tcp > /dev/null
                    send_telegram "✅ [$MI_NOMBRE] Acceso concedido a la IP $IP_REQ"
                fi
            fi
        fi
    fi
done
