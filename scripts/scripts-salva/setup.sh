#!/bin/bash
set -euo pipefail

# setup.sh — Script maestro de instalación de ProyectoScripts
# Idempotente: puede ejecutarse múltiples veces sin efectos destructivos
# Uso: sudo bash setup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDIAN_SH="${SCRIPT_DIR}/guardian_ssh.sh"
GUARDIAN_SERVICE_SRC="${SCRIPT_DIR}/guardian.service"
GUARDIAN_SERVICE_DST="/etc/systemd/system/guardian.service"
CONFIG_DIR="/etc/guardian"
CONFIG_FILE="${CONFIG_DIR}/config"

# ==========================================
# VERIFICACIONES PREVIAS
# ==========================================

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "[ERROR] Este script debe ejecutarse como root o con sudo."
        echo "        Usa: sudo bash setup.sh"
        exit 1
    fi
}

check_distro() {
    if [[ ! -f /etc/os-release ]]; then
        echo "[ERROR] No se puede determinar la distribución."
        exit 1
    fi
    source /etc/os-release
    case "${ID:-}" in
        debian|ubuntu|raspbian)
            ;;
        *)
            if [[ "${ID_LIKE:-}" =~ debian|ubuntu ]]; then
                echo "[WARN] Distribución $ID con base Debian/Ubuntu. Continuando..."
            else
                echo "[ERROR] Distribución no soportada: ${ID:-desconocida}"
                echo "        Este script requiere Debian, Ubuntu o derivada."
                exit 1
            fi
            ;;
    esac
    echo "[OK] Distribución: ${PRETTY_NAME:-$ID}"
}

# ==========================================
# INSTALACIÓN DE DEPENDENCIAS
# ==========================================

install_deps() {
    local deps=(openssh-server ufw curl jq iputils-ping)
    local to_install=()

    echo "[+] Actualizando lista de paquetes..."
    apt-get update -qq

    for dep in "${deps[@]}"; do
        if dpkg -l "$dep" 2>/dev/null | grep -q "^ii"; then
            echo "[OK] $dep ya instalado."
        else
            to_install+=("$dep")
        fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        echo "[+] Instalando: ${to_install[*]}"
        apt-get install -y "${to_install[@]}"
    fi
}

# ==========================================
# FICHERO DE CONFIGURACIÓN
# ==========================================

create_config() {
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    mkdir -p /var/lib/guardian
    chmod 700 /var/lib/guardian

    if [[ -f "$CONFIG_FILE" ]]; then
        echo "[OK] $CONFIG_FILE ya existe. No se sobreescribe."
        return
    fi

    echo ""
    echo "========================================"
    echo " CONFIGURACIÓN DE TELEGRAM GUARDIAN"
    echo "========================================"
    echo "El servicio necesita credenciales para funcionar."
    echo "Si no las tienes a mano, pulsa ENTER para dejarlas en blanco y editarlas luego."
    echo ""
    
    read -p "Introduce el TOKEN del bot: " input_token
    read -p "Introduce el CHAT_ID: " input_chat
    read -p "Introduce los IDs de USERS_AUTORIZADOS (separados por espacio): " input_users

    # Valores por defecto si se dejan en blanco
    input_token=${input_token:-"REEMPLAZA_CON_TU_TOKEN"}
    input_chat=${input_chat:-"REEMPLAZA_CON_TU_CHAT_ID"}
    input_users=${input_users:-"ID_USUARIO_1 ID_USUARIO_2"}

    cat > "$CONFIG_FILE" << EOF
# /etc/guardian/config — Configuración de Guardian SSH

# Token del bot de Telegram (obtenlo de @BotFather)
TOKEN="${input_token}"

# ID del chat o grupo donde enviar alertas (puede ser negativo para grupos)
CHAT_ID="${input_chat}"

# IDs de Telegram de usuarios autorizados para enviar comandos /allow
# Separados por espacios
USERS_AUTORIZADOS="${input_users}"
EOF

    chmod 600 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
    echo "[+] Creado $CONFIG_FILE con las credenciales proporcionadas."
}

# ==========================================
# PERMISOS DE EJECUCIÓN
# ==========================================

set_permissions() {
    find "$SCRIPT_DIR" -name "*.sh" -exec chmod +x {} \;
    echo "[+] Permisos de ejecución aplicados a todos los .sh"
}

# ==========================================
# INSTALACIÓN DEL SERVICIO SYSTEMD
# ==========================================

install_service() {
    if [[ ! -f "$GUARDIAN_SH" ]]; then
        echo "[ERROR] No se encuentra: $GUARDIAN_SH"
        exit 1
    fi

    # Sustituir el placeholder %%GUARDIAN_SH_PATH%% con la ruta real
    sed "s|%%GUARDIAN_SH_PATH%%|${GUARDIAN_SH}|g" \
        "$GUARDIAN_SERVICE_SRC" > "$GUARDIAN_SERVICE_DST"

    chmod 644 "$GUARDIAN_SERVICE_DST"
    echo "[+] guardian.service instalado en $GUARDIAN_SERVICE_DST"

    systemctl daemon-reload
    systemctl enable guardian.service
    echo "[+] guardian.service habilitado en systemd."

    if grep -q "REEMPLAZA_CON_TU_TOKEN" "$CONFIG_FILE"; then
        echo "[!] Servicio NO iniciado — token no configurado. Edita $CONFIG_FILE primero."
    else
        systemctl start guardian.service || true
        echo "[+] guardian.service iniciado automáticamente."
    fi
}

# ==========================================
# RESUMEN FINAL
# ==========================================

print_summary() {
    echo ""
    echo "========================================"
    echo " INSTALACIÓN COMPLETADA"
    echo "========================================"
    echo ""
    echo "DEPENDENCIAS INSTALADAS:"
    echo "  openssh-server, ufw, curl, jq, iputils-ping"
    echo ""
    if grep -q "REEMPLAZA_CON_TU_TOKEN" "$CONFIG_FILE"; then
        echo "SERVICIO:"
        echo "  guardian.service instalado y habilitado (no iniciado)"
        echo ""
        echo "ACCIÓN REQUERIDA:"
        echo "  1. Configura las credenciales pendientes:"
        echo "     sudo nano ${CONFIG_FILE}"
        echo ""
        echo "  2. Inicia el servicio:"
        echo "     sudo systemctl start guardian.service"
    else
        echo "SERVICIO:"
        echo "  guardian.service instalado, habilitado e INICIADO."
        echo ""
        echo "ACCIÓN REQUERIDA:"
        echo "  - Ninguna. El servicio ya está funcionando."
        echo "  - Para ver su estado en tiempo real:"
        echo "     sudo journalctl -u guardian.service -f"
    fi
    echo "========================================"
}

# ==========================================
# MAIN
# ==========================================

main() {
    check_root
    check_distro
    install_deps
    create_config
    set_permissions
    
    echo ""
    echo "[+] Configurando SSH y Firewall (UFW)..."
    bash "${SCRIPT_DIR}/install_ssh.sh"
    echo ""

    install_service
    print_summary
}

main "$@"
