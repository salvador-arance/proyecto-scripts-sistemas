#!/bin/bash
#
# menu.sh — Launcher gráfico (Zenity) para los scripts del repo.
# Lanza cualquiera de los 7 scripts operativos de scripts-salva,
# scripts-claudiu y scripts-luis pidiendo los argumentos por diálogo.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SALVA="$SCRIPT_DIR/scripts/scripts-salva"
CLAUDIU="$SCRIPT_DIR/scripts/scripts-claudiu"
LUIS="$SCRIPT_DIR/scripts/scripts-luis"

MANAGED_SCRIPTS=(
    "$SALVA/install_ssh.sh"
    "$SALVA/uninstall.sh"
    "$CLAUDIU/gestionar_servicio.sh"
    "$CLAUDIU/status.sh"
    "$LUIS/check_web.sh"
    "$LUIS/deploy_sftp.sh"
    "$LUIS/update_dns.sh"
)

# ---------------------------------------------------------------------------
# Dependencia: zenity
# ---------------------------------------------------------------------------
ensure_zenity() {
    if command -v zenity >/dev/null 2>&1; then
        return 0
    fi
    echo "Zenity no está instalado."
    read -rp "¿Instalar ahora con 'sudo apt-get install -y zenity'? [s/N] " resp
    if [[ "$resp" =~ ^[sS]$ ]]; then
        sudo apt-get install -y zenity || {
            echo "La instalación ha fallado. Instálalo manualmente y vuelve a ejecutar." >&2
            exit 1
        }
    else
        echo "Cancelado. Este menú necesita zenity para funcionar." >&2
        exit 1
    fi
    command -v zenity >/dev/null 2>&1 || {
        echo "Zenity sigue sin estar disponible tras la instalación." >&2
        exit 1
    }
}

ensure_executable() {
    for s in "${MANAGED_SCRIPTS[@]}"; do
        [ -f "$s" ] && chmod +x "$s" 2>/dev/null || true
    done
}

# ---------------------------------------------------------------------------
# Privilegios: pkexec si es interfaz gráfica, fallback a terminal con sudo
# ---------------------------------------------------------------------------
run_as_root_gui() {
    # Ejecuta el comando como root mostrando un diálogo gráfico de contraseña.
    if command -v pkexec >/dev/null 2>&1; then
        pkexec "$@"
        return $?
    fi
    run_in_terminal sudo "$@"
}

run_in_terminal() {
    # Abre una terminal nueva para ejecutar el comando (necesario cuando
    # hace falta TTY: sudo sin pkexec, o ssh con agente del usuario).
    local term
    for term in x-terminal-emulator gnome-terminal konsole xfce4-terminal xterm; do
        if command -v "$term" >/dev/null 2>&1; then
            case "$term" in
                gnome-terminal) "$term" -- bash -c "$* ; echo; read -rp 'Pulsa Enter para cerrar...'";;
                *)              "$term" -e bash -c "$* ; echo; read -rp 'Pulsa Enter para cerrar...'";;
            esac
            return 0
        fi
    done
    zenity --error --width=420 --text="No se ha encontrado ningún emulador de terminal disponible."
    return 1
}

# ---------------------------------------------------------------------------
# Patrón común: ejecutar un script y mostrar el resultado
# ---------------------------------------------------------------------------
show_result() {
    local title="$1" rc="$2" tmp="$3"
    if [ "$rc" -eq 0 ]; then
        zenity --text-info --title="$title — OK" --width=750 --height=450 --filename="$tmp"
    else
        zenity --error --width=600 --title="$title — Error (rc=$rc)" --text="$(cat "$tmp")"
    fi
}

run_capture() {
    # run_capture "<título>" <comando> [args...]
    local title="$1"; shift
    local tmp; tmp=$(mktemp)
    "$@" >"$tmp" 2>&1
    local rc=$?
    show_result "$title" "$rc" "$tmp"
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Acciones por script
# ---------------------------------------------------------------------------
run_check_web() {
    local host
    host=$(zenity --entry --title="check_web" \
        --text="Host a comprobar (dominio o IP):" --entry-text="example.com") || return 0
    [ -z "$host" ] && { zenity --error --text="Host vacío."; return 0; }
    run_capture "check_web $host" "$LUIS/check_web.sh" "$host"
}

run_deploy_sftp() {
    local form host user remote local_dir
    form=$(zenity --forms --title="deploy_sftp" \
        --text="Datos del servidor SFTP" \
        --add-entry="HOST" \
        --add-entry="USER" \
        --add-entry="REMOTE_DIR (ej. /var/www/html)" \
        --separator="|") || return 0

    host=$(echo "$form" | cut -d'|' -f1)
    user=$(echo "$form" | cut -d'|' -f2)
    remote=$(echo "$form" | cut -d'|' -f3)

    if [ -z "$host" ] || [ -z "$user" ] || [ -z "$remote" ]; then
        zenity --error --text="Faltan datos del servidor."
        return 0
    fi

    local_dir=$(zenity --file-selection --directory \
        --title="Carpeta local a subir") || return 0

    run_capture "deploy_sftp" env \
        HOST="$host" USER="$user" REMOTE_DIR="$remote" LOCAL_DIR="$local_dir" \
        "$LUIS/deploy_sftp.sh"
}

run_update_dns() {
    local domain
    domain=$(zenity --entry --title="update_dns" \
        --text="Dominio (vacío = midominio.com):") || return 0
    if [ -n "$domain" ]; then
        run_capture "update_dns" env DOMAIN="$domain" "$LUIS/update_dns.sh"
    else
        run_capture "update_dns" "$LUIS/update_dns.sh"
    fi
}

# Devuelve 0 si la IP destino coincide con alguna IP local de este equipo
is_local_target() {
    local target="$1" ip
    for ip in $(hostname -I 2>/dev/null); do
        [ "$ip" = "$target" ] && return 0
    done
    return 1
}

run_gestionar_servicio() {
    local server ip service action
    server=$(zenity --list --radiolist --title="gestionar_servicio · Servidor" \
        --text="Elige el servidor destino:" \
        --column="" --column="Alias" --column="IP" \
        TRUE  "SV_CLAUDIU" "172.30.3.235" \
        FALSE "SV_SALVA"   "172.30.1.144" \
        FALSE "SV_LUIS"    "172.24.252.34" \
        FALSE "Otra IP…"   "(introducir)") || return 0

    if [ "$server" = "Otra IP…" ]; then
        server=$(zenity --entry --title="gestionar_servicio" \
            --text="Introduce la IP destino:") || return 0
        [ -z "$server" ] && { zenity --error --text="IP vacía."; return 0; }
        ip="$server"
    else
        case "$server" in
            SV_CLAUDIU) ip="172.30.3.235";;
            SV_SALVA)   ip="172.30.1.144";;
            SV_LUIS)    ip="172.24.252.34";;
        esac
    fi

    service=$(zenity --entry --title="gestionar_servicio · Servicio" \
        --text="Nombre del servicio systemd (ssh, apache2, nginx…):") || return 0
    [ -z "$service" ] && { zenity --error --text="Servicio vacío."; return 0; }

    action=$(zenity --list --radiolist --title="gestionar_servicio · Acción" \
        --text="Acción a aplicar:" \
        --column="" --column="Acción" \
        FALSE "start" \
        FALSE "stop" \
        FALSE "restart" \
        TRUE  "status") || return 0
    [ -z "$action" ] && return 0

    if is_local_target "$ip"; then
        # Destino local: pkexec abre diálogo gráfico de contraseña
        local tmp; tmp=$(mktemp)
        run_as_root_gui "$CLAUDIU/gestionar_servicio.sh" "$server" "$service" "$action" \
            >"$tmp" 2>&1
        show_result "gestionar_servicio $server $service $action" "$?" "$tmp"
        rm -f "$tmp"
    else
        # Destino remoto: necesita TTY y agente SSH, abrir terminal
        run_in_terminal "$CLAUDIU/gestionar_servicio.sh" "$server" "$service" "$action"
    fi
}

run_status() {
    local logfile
    logfile=$(zenity --file-selection --save --confirm-overwrite \
        --title="status · Fichero de log (Cancelar = usar el por defecto)" \
        --filename="reporte_nodos.log") || logfile=""

    if [ -n "$logfile" ]; then
        run_capture "status" "$CLAUDIU/status.sh" "$logfile"
    else
        run_capture "status" "$CLAUDIU/status.sh"
    fi
}

run_install_ssh() {
    zenity --question --width=520 \
        --title="install_ssh · Confirmación" \
        --text="Esto instalará OpenSSH y activará UFW con política <b>deny</b>.\n\nEl puerto 22 quedará <b>cerrado para todos</b>.\nSi estás conectado por SSH puedes perder la sesión.\n\n¿Continuar?" \
        || return 0

    local tmp; tmp=$(mktemp)
    run_as_root_gui bash "$SALVA/install_ssh.sh" >"$tmp" 2>&1
    show_result "install_ssh" "$?" "$tmp"
    rm -f "$tmp"
}

run_uninstall() {
    zenity --question --width=520 \
        --title="uninstall · ¡Acción destructiva!" \
        --text="Esto detendrá y eliminará el servicio <b>guardian.service</b>,\nborrará <b>/etc/guardian</b> y <b>/var/lib/guardian</b>,\ny <b>reseteará UFW a fábrica (deshabilitándolo)</b>.\n\n¿Estás seguro?" \
        || return 0

    local tmp; tmp=$(mktemp)
    run_as_root_gui bash "$SALVA/uninstall.sh" >"$tmp" 2>&1
    show_result "uninstall" "$?" "$tmp"
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Menú principal
# ---------------------------------------------------------------------------
main_menu() {
    while true; do
        local choice
        choice=$(zenity --list --radiolist --width=720 --height=420 \
            --print-column=3 \
            --title="proyecto-scripts-sistemas" \
            --text="Elige una utilidad:" \
            --column="" --column="Familia" --column="Script" --column="Descripción" \
            TRUE  "luis"    "check_web"          "Comprueba que un host responde por HTTP" \
            FALSE "luis"    "deploy_sftp"        "Sube un directorio local por SFTP" \
            FALSE "luis"    "update_dns"         "Muestra IP pública/privada del equipo" \
            FALSE "claudiu" "gestionar_servicio" "Arranca/para/reinicia servicios systemd (local o SSH)" \
            FALSE "claudiu" "status"             "Escanea SSH/HTTP/HTTPS de los nodos del lab" \
            FALSE "salva"   "install_ssh"        "Instala y endurece OpenSSH + UFW" \
            FALSE "salva"   "uninstall"          "Elimina el servicio Guardian y resetea UFW") \
            || return 0

        case "$choice" in
            check_web)          run_check_web ;;
            deploy_sftp)        run_deploy_sftp ;;
            update_dns)         run_update_dns ;;
            gestionar_servicio) run_gestionar_servicio ;;
            status)             run_status ;;
            install_ssh)        run_install_ssh ;;
            uninstall)          run_uninstall ;;
            "")                 return 0 ;;
        esac
    done
}

ensure_zenity
ensure_executable
main_menu
