#!/bin/bash
set -euo pipefail

# uninstall.sh — Script para desinstalar los servicios creados por setup.sh
# Uso: sudo bash uninstall.sh

# ==========================================
# VERIFICACIONES PREVIAS
# ==========================================

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "[ERROR] Este script debe ejecutarse como root o con sudo."
        echo "        Usa: sudo bash uninstall.sh"
        exit 1
    fi
}

# ==========================================
# DESINSTALACIÓN DEL SERVICIO
# ==========================================

remove_service() {
    echo "[+] Deteniendo el servicio guardian.service..."
    systemctl stop guardian.service || true

    echo "[+] Deshabilitando el servicio guardian.service..."
    systemctl disable guardian.service || true

    if [[ -f "/etc/systemd/system/guardian.service" ]]; then
        echo "[+] Eliminando archivo del servicio..."
        rm -f "/etc/systemd/system/guardian.service"
        systemctl daemon-reload
        echo "[OK] guardian.service eliminado de systemd."
    else
        echo "[OK] El archivo del servicio no existe."
    fi
}

# ==========================================
# ELIMINACIÓN DE CONFIGURACIÓN
# ==========================================

remove_config() {
    local CONFIG_DIR="/etc/guardian"
    if [[ -d "$CONFIG_DIR" ]]; then
        echo "[+] Eliminando el directorio de configuración $CONFIG_DIR..."
        rm -rf "$CONFIG_DIR"
        echo "[OK] Configuración eliminada."
    else
        echo "[OK] El directorio de configuración no existe."
    fi

    if [[ -d "/var/lib/guardian" ]]; then
        echo "[+] Eliminando directorio de estado /var/lib/guardian..."
        rm -rf "/var/lib/guardian"
        echo "[OK] Estado eliminado."
    fi
}

# ==========================================
# REVERSIÓN DEL FIREWALL
# ==========================================

revert_firewall() {
    echo "[+] Revirtiendo configuración del firewall (UFW)..."
    if command -v ufw >/dev/null 2>&1; then
        ufw --force reset >/dev/null 2>&1 || true
        echo "[OK] Reglas de UFW eliminadas y firewall deshabilitado."
    else
        echo "[OK] UFW no está instalado."
    fi
}

# ==========================================
# RESUMEN FINAL
# ==========================================

print_summary() {
    echo ""
    echo "========================================"
    echo " DESINSTALACIÓN COMPLETADA"
    echo "========================================"
    echo ""
    echo "El servicio guardian.service y su configuración han sido eliminados."
    echo "El firewall UFW ha sido reseteado a sus valores de fábrica (deshabilitado)."
    echo "NOTA: Las dependencias instaladas (openssh-server, ufw, curl, jq) NO han sido desinstaladas."
    echo "Si deseas eliminarlas, puedes usar: apt-get remove --purge <paquete>"
    echo "========================================"
}

# ==========================================
# MAIN
# ==========================================

main() {
    check_root
    remove_service
    remove_config
    revert_firewall
    print_summary
}

main "$@"
