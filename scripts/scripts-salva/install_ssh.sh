#!/bin/bash
set -euo pipefail
# install_ssh.sh - Instalación inteligente y endurecimiento de SSH

echo "--- Comprobando estado de OpenSSH Server ---"

if command -v sshd >/dev/null 2>&1; then
    echo "[!] OpenSSH ya está instalado. Saltando instalación..."
else
    echo "[+] Instalando OpenSSH Server..."
    apt-get update && apt-get install -y openssh-server
fi

echo "--- Aplicando configuraciones de seguridad ---"

systemctl enable ssh
systemctl start ssh

echo "--- Configurando Firewall (UFW) ---"

if ! command -v ufw >/dev/null 2>&1; then
    apt-get install -y ufw
fi

ufw default deny incoming
ufw default allow outgoing
ufw logging on

ufw --force enable

echo "--- Resumen de estado ---"
ufw status verbose

echo "--------------------------------------------------------"
echo "Configuración completada."
echo "El puerto 22 está CERRADO por defecto."
echo "Usa /allow <IP> <servidor> desde Telegram para autorizar acceso SSH."
echo "--------------------------------------------------------"
