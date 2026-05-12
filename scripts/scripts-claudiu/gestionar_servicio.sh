#!/bin/bash

# =========================================================================
# 1. Variables de posición y Control de Uso ($0, $#, $1, $2, $3)
# =========================================================================
# Comprobamos si el usuario pide ayuda (-h) o si no pasa exactamente 3 parámetros ($#)
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ $# -ne 3 ]; then
    echo -e "\033[0;34m[USO DEL SCRIPT]\033[0m: $0 <SERVIDOR> <SERVICIO> <ACCIÓN>"
    echo "----------------------------------------------------------------"
    echo "  <SERVIDOR> : SV_CLAUDIU, SV_SALVA, SV_LUIS o una IP directamente."
    echo "  <SERVICIO> : Nombre del servicio (Ej: ssh, apache2, nginx...)"
    echo "  <ACCIÓN>   : start, stop, restart, status"
    echo -e "\n  Ejemplo 1: $0 SV_CLAUDIU apache2 stop"
    echo "  Ejemplo 2: $0 172.30.1.144 ssh restart"
    exit 0
fi

# Asignamos las variables de posición ($1, $2, $3) a nombres legibles
SERVIDOR=$1
SERVICIO=$2
ACCION=$3

ARCHIVO_LOG="registro_servicios.log"
ARCHIVO_ERRORES="errores_servicios.log"

# =========================================================================
# 2. Configuración de Nodos y de fácil uso (Mapeo de nombres a IPs)
# =========================================================================
# Según el nombre que pase el usuario, asignamos la IP correspondiente
case "$SERVIDOR" in
    "SV_CLAUDIU"|"172.30.3.235") IP_DESTINO="172.30.3.235" ;;
    "SV_SALVA"|"172.30.1.144")   IP_DESTINO="172.30.1.144" ;;
    "SV_LUIS"|"172.24.252.34")    IP_DESTINO="172.24.252.34" ;;
    *) 
        echo -e "\033[0;31m[ERROR]\033[0m Servidor no reconocido: $SERVIDOR"
        exit 1
        ;;
esac

# Validamos que la acción introducida sea segura y tenga sentido
if [[ ! "$ACCION" =~ ^(start|stop|restart|status)$ ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m Acción no válida. Solo se permite: start, stop, restart, status."
    exit 1
fi

# =========================================================================
# 3. Objetivos Sysadmin y Redirecciones
# =========================================================================
echo -e "\n\033[0;34m[INFO]\033[0m Preparando acción '$ACCION' sobre el servicio '$SERVICIO' en '$SERVIDOR' ($IP_DESTINO)..."

# Redirección de salida para el log histórico
echo "$(date '+%Y-%m-%d %H:%M:%S') - SOLICITUD: $ACCION | $SERVICIO | $IP_DESTINO" >> "$ARCHIVO_LOG"

# Obtenemos la IP de la máquina local actual para saber si ejecutar el comando aquí o por red
IP_LOCAL=$(hostname -I | awk '{print $1}')

if [ "$IP_DESTINO" == "$IP_LOCAL" ]; then
    echo "Ejecutando localmente..."
    # Ejecutamos sudo systemctl local. 
    # La salida normal va al log (>>), y los errores van al archivo de errores (2>>)
    sudo systemctl "$ACCION" "$SERVICIO" >> "$ARCHIVO_LOG" 2>> "$ARCHIVO_ERRORES"
    
    # 4. Control de errores con variable de sistema $?
    ESTADO_COMANDO=$?
else
    echo "Conectando por SSH a $IP_DESTINO..."
    # Ejecutamos por SSH. El parámetro -t fuerza la asignación de terminal por si sudo lo requiere.
    # OJO: Se asume que estás usando el mismo nombre de usuario o tienes claves configuradas.
    ssh -t "$IP_DESTINO" "sudo systemctl $ACCION $SERVICIO" >> "$ARCHIVO_LOG" 2>> "$ARCHIVO_ERRORES"
    
    # 4. Control de errores con variable de sistema $?
    ESTADO_COMANDO=$?
fi

# =========================================================================
# 5. Evaluación de resultados y pantallas que guían al usuario
# =========================================================================
echo "----------------------------------------------------------------"
if [ $ESTADO_COMANDO -eq 0 ]; then
    echo -e "\033[0;32m[ÉXITO]\033[0m La acción se completó correctamente."
    echo "RESULTADO: EXITO" >> "$ARCHIVO_LOG"
else
    echo -e "\033[0;31m[FALLO]\033[0m Ocurrió un error al ejecutar la orden (Código: $ESTADO_COMANDO)."
    echo "Revisa el archivo oculto de errores para más detalles: cat $ARCHIVO_ERRORES"
    echo "RESULTADO: FALLO" >> "$ARCHIVO_LOG"
fi
echo -e "----------------------------------------------------------------\n"
