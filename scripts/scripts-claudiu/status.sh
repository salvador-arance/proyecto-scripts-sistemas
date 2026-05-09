#!/bin/bash

# =========================================================================
# 1. Variables de posición y Control de Uso ($0, $#, $1)
# =========================================================================
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "Uso: $0 [archivo_reporte.log]"
    echo "Si no se indica archivo, se guardará por defecto en 'reporte_nodos.log'"
    exit 0
fi

# Si el usuario pasa un argumento ($1), se usa como log. Si no, usa el defecto.
ARCHIVO_LOG=${1:-"reporte_nodos.log"}
ARCHIVO_ERRORES="errores_ocultos.log"

# =========================================================================
# 2. Control de errores inicial (con variable $?)
# =========================================================================
# Verificamos que 'netcat' está instalado, vital para este script
command -v nc >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "\033[0;31m[ERROR CRÍTICO]\033[0m El comando 'nc' no está instalado."
    echo "Por favor, instálelo usando: sudo apt install netcat"
    exit 1
fi

# =========================================================================
# Configuración del entorno
# =========================================================================
NODOS=("172.30.3.235" "172.30.1.144" "172.24.252.34")
SV=("SV_CLAUDIU" "SV_SALVA" "SV_LUIS")
SERVICIOS=("SSH:22" "Apache-HTTP:80" "Apache-HTTPS:443")

VERDE='\033[0;32m'
ROJO='\033[0;31m'
AZUL='\033[0;34m'
NC='\033[0m'

# =========================================================================
# Ejecución y Redirecciones
# =========================================================================
echo -e "\nIniciando escaneo. Guardando copia en: $ARCHIVO_LOG"

# Redirección de salida normal: Guardamos el encabezado en el log sin colores
echo "-----------------------------------------------------------------------" >> "$ARCHIVO_LOG"
echo "$(date '+%Y-%m-%d %H:%M:%S') - INICIO DE MONITORIZACIÓN" >> "$ARCHIVO_LOG"

printf "${AZUL}%-15s %-16s %-20s %-15s${NC}\n" "SERVIDOR" "IP NODO" "SERVICIO (PUERTO)" "ESTADO"
echo "-----------------------------------------------------------------------"

for i in "${!NODOS[@]}"; do
    IP="${NODOS[$i]}"
    NOMBRE_SV="${SV[$i]}"
    
    for ITEM in "${SERVICIOS[@]}"; do
        SERV_NOMBRE=$(echo "$ITEM" | cut -d: -f1)
        PUERTO=$(echo "$ITEM" | cut -d: -f2)

        # Redirección de error (2>>): Si falla por red inalcanzable, va al archivo de errores
        nc -z -w 1 "$IP" "$PUERTO" 2>> "$ARCHIVO_ERRORES"

        # Control de errores en ejecución con $?
        if [ $? -eq 0 ]; then
            printf "%-15s %-16s %-20s ${VERDE}[ENCENDIDO]${NC}\n" "$NOMBRE_SV" "$IP" "$SERV_NOMBRE ($PUERTO)"
            # Redirección de salida normal (>>)
            printf "%-15s %-16s %-20s [ENCENDIDO]\n" "$NOMBRE_SV" "$IP" "$SERV_NOMBRE ($PUERTO)" >> "$ARCHIVO_LOG"
        else
            printf "%-15s %-16s %-20s ${ROJO}[CAÍDO]${NC}\n" "$NOMBRE_SV" "$IP" "$SERV_NOMBRE ($PUERTO)"
            # Redirección de salida normal (>>)
            printf "%-15s %-16s %-20s [CAÍDO]\n" "$NOMBRE_SV" "$IP" "$SERV_NOMBRE ($PUERTO)" >> "$ARCHIVO_LOG"
        fi
    done
    echo "-----------------------------------------------------------------------"
done

echo -e "\nMonitorización finalizada. Errores de red guardados en: $ARCHIVO_ERRORES"
