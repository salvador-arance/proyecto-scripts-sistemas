# scripts-claudiu

Scripts de administración remota para el laboratorio de servidores: gestión de servicios `systemd` (local o por SSH) y escaneo de puertos sobre los nodos del entorno.

Ambos scripts trabajan con un **mapa fijo de nodos** (SV_CLAUDIU, SV_SALVA, SV_LUIS) definido dentro del propio script. Si cambian las IPs del laboratorio hay que actualizarlas en el código.

---

## Índice

- [Estructura](#estructura)
- [Nodos del laboratorio](#nodos-del-laboratorio)
- [Scripts](#scripts)
  - [gestionar_servicio.sh](#gestionar_serviciosh)
  - [status.sh](#statussh)
- [Ficheros de log generados](#ficheros-de-log-generados)
- [Dependencias](#dependencias)
- [Solución de problemas](#solución-de-problemas)

---

## Estructura

```
scripts-claudiu/
├── README.md                # Esta documentación
├── gestionar_servicio.sh    # Arranca/para/reinicia servicios systemd local o por SSH
└── status.sh                # Escanea SSH/HTTP/HTTPS de todos los nodos del lab
```

---

## Nodos del laboratorio

| Alias        | IP              |
|--------------|-----------------|
| `SV_CLAUDIU` | `172.30.3.235`  |
| `SV_SALVA`   | `172.30.1.144`  |
| `SV_LUIS`    | `172.24.252.34` |

Los alias están **codificados en el script**. Para añadir o cambiar un nodo, edita el `case` de `gestionar_servicio.sh` y los arrays `NODOS`/`SV` de `status.sh`.

---

## Scripts

### `gestionar_servicio.sh`

Lanza acciones `systemctl` (`start`, `stop`, `restart`, `status`) sobre un servicio en cualquiera de los nodos del laboratorio. Detecta si el destino es la propia máquina (lo ejecuta localmente) o un nodo remoto (lo ejecuta por SSH).

**Qué hace, en orden:**
1. Valida los argumentos: ayuda con `-h` / `--help`, o exactamente 3 parámetros
2. Resuelve el alias del servidor a IP mediante un `case` (acepta también la IP directamente)
3. Valida que la acción está dentro de la lista permitida
4. Compara la IP destino con la IP local (`hostname -I`) para decidir local vs SSH
5. Ejecuta `sudo systemctl <acción> <servicio>` y captura el código de salida (`$?`)
6. Registra la solicitud en `registro_servicios.log` y los errores en `errores_servicios.log`

**Uso:**
```bash
./gestionar_servicio.sh <SERVIDOR> <SERVICIO> <ACCIÓN>

# Ejemplos
./gestionar_servicio.sh SV_CLAUDIU apache2 stop
./gestionar_servicio.sh 172.30.1.144 ssh restart
./gestionar_servicio.sh SV_LUIS nginx status
```

**Argumentos:**
- `<SERVIDOR>`: alias (`SV_CLAUDIU`, `SV_SALVA`, `SV_LUIS`) o IP directa
- `<SERVICIO>`: nombre de unidad systemd (`ssh`, `apache2`, `nginx`, …)
- `<ACCIÓN>`: `start`, `stop`, `restart` o `status`

> **Requisitos para ejecución remota:**
> - Acceso SSH al nodo destino con el mismo usuario que ejecuta el script (o claves configuradas)
> - El usuario remoto debe poder ejecutar `sudo systemctl` (el flag `-t` fuerza TTY por si `sudo` lo necesita)

---

### `status.sh`

Recorre todos los nodos del laboratorio y comprueba con `netcat` si los puertos **22 (SSH)**, **80 (HTTP)** y **443 (HTTPS)** están abiertos. Imprime una tabla con colores en pantalla y guarda una copia sin colores en un fichero de log.

**Qué hace, en orden:**
1. Comprueba que `nc` (netcat) está instalado; si no, aborta con un error claro
2. Permite pasar el nombre del fichero de log como argumento (por defecto `reporte_nodos.log`)
3. Itera sobre los tres nodos y los tres servicios
4. Por cada combinación, lanza `nc -z -w 1 <ip> <puerto>` y marca `[ENCENDIDO]` / `[CAÍDO]` según `$?`
5. Vuelca a pantalla (con colores) y a fichero (sin colores)

**Uso:**
```bash
./status.sh                          # log por defecto: reporte_nodos.log
./status.sh mi_reporte_$(date +%F).log
```

**Salida de ejemplo:**
```
SERVIDOR        IP NODO          SERVICIO (PUERTO)    ESTADO
-----------------------------------------------------------------------
SV_CLAUDIU      172.30.3.235     SSH (22)             [ENCENDIDO]
SV_CLAUDIU      172.30.3.235     Apache-HTTP (80)     [CAÍDO]
SV_CLAUDIU      172.30.3.235     Apache-HTTPS (443)   [CAÍDO]
-----------------------------------------------------------------------
...
```

---

## Ficheros de log generados

Los scripts escriben en el **directorio actual desde el que se ejecutan**, no junto al script. Si los lanzas desde `cron`, fíjate en el `WorkingDirectory`.

| Fichero                  | Generado por             | Contenido                                          |
|--------------------------|--------------------------|----------------------------------------------------|
| `registro_servicios.log` | `gestionar_servicio.sh`  | Solicitudes y resultado (`EXITO` / `FALLO`)        |
| `errores_servicios.log`  | `gestionar_servicio.sh`  | `stderr` capturado de `systemctl` / `ssh`          |
| `reporte_nodos.log`      | `status.sh`              | Tabla del escaneo sin códigos de color             |
| `errores_ocultos.log`    | `status.sh`              | `stderr` capturado de `nc` (red inalcanzable, etc.)|

---

## Dependencias

| Paquete             | Usado por                |
|---------------------|--------------------------|
| `openssh-client`    | `gestionar_servicio.sh`  |
| `sudo`              | `gestionar_servicio.sh`  |
| `netcat-openbsd`    | `status.sh`              |
| `iproute2` / `hostname` | `gestionar_servicio.sh` (IP local) |

Instalación en Debian/Ubuntu:
```bash
sudo apt-get install -y openssh-client netcat-openbsd iproute2
```

---

## Solución de problemas

### `gestionar_servicio.sh` no me deja conectar al nodo remoto

- Verifica que puedes hacer `ssh <ip>` a mano desde la máquina origen sin tocar nada más.
- Si SSH te pide contraseña en cada ejecución, configura claves públicas (`ssh-copy-id <usuario>@<ip>`).
- Si `sudo` pide contraseña, o bien usas `-t` (ya incluido) y la introduces a mano, o configuras `NOPASSWD` para `systemctl` en `/etc/sudoers.d/` del nodo destino.

### Detecta mal si la IP es local o remota

El script compara contra la **primera IP** que devuelve `hostname -I`. Si la máquina tiene varias interfaces (VPN, Docker, etc.) puede que ese primer valor no sea el del laboratorio. Soluciones:
- Forzar la ruta remota pasando una IP que no coincida con `hostname -I | awk '{print $1}'`
- Editar el script para fijar `IP_LOCAL` por hostname (`hostname`) en lugar de por IP

### `status.sh` aborta con "El comando 'nc' no está instalado"

En Debian/Ubuntu modernos el paquete se llama `netcat-openbsd`:
```bash
sudo apt-get install -y netcat-openbsd
```
El mensaje del script sugiere `netcat`, que es un paquete virtual y puede no existir en todas las distros.

### Todos los servicios aparecen como `[CAÍDO]` desde mi PC

- Comprueba que tienes ruta de red a los nodos: `ping 172.30.3.235`
- Si estás en una red distinta a la del laboratorio (otra VLAN, fuera de la VPN), el `nc` con timeout de 1 segundo (`-w 1`) cortará antes de que llegue la respuesta. Aumenta el timeout o conéctate a la red correcta.
