# proyecto-scripts-sistemas

Colección de scripts Bash para administración de servidores Linux, agrupados por autor. Incluye utilidades de seguridad SSH, gestión remota de servicios `systemd`, escaneo de puertos, despliegue por SFTP, monitorización HTTP y un launcher gráfico (Zenity) que centraliza el acceso a todos los scripts operativos.

---

## Índice

- [Estructura del repo](#estructura-del-repo)
- [Launcher gráfico (`menu.sh`)](#launcher-gráfico-menush)
- [Familias de scripts](#familias-de-scripts)
  - [scripts-salva](#scripts-salva)
  - [scripts-claudiu](#scripts-claudiu)
  - [scripts-luis](#scripts-luis)
- [Nodos del laboratorio](#nodos-del-laboratorio)
- [Convenciones](#convenciones)
- [Requisitos generales](#requisitos-generales)

---

## Estructura del repo

```
proyecto-scripts-sistemas/
├── README.md                  # Este documento
├── menu.sh                    # Launcher Zenity para todas las utilidades
└── scripts/
    ├── scripts-salva/         # SSH hardening + Guardian (alertas Telegram)
    │   ├── README.md
    │   ├── setup.sh           # Instalador maestro
    │   ├── uninstall.sh
    │   ├── install_ssh.sh
    │   ├── guardian_ssh.sh    # Daemon
    │   └── guardian.service   # Unidad systemd
    ├── scripts-claudiu/       # Gestión remota y escaneo del laboratorio
    │   ├── README.md
    │   ├── gestionar_servicio.sh
    │   └── status.sh
    └── scripts-luis/          # Utilidades web (HTTP, SFTP, DNS)
        ├── README.md
        ├── check_web.sh
        ├── deploy_sftp.sh
        └── update_dns.sh
```

---

## Launcher gráfico (`menu.sh`)

`menu.sh` es la forma recomendada de usar el repo. Abre un menú Zenity con las 7 utilidades operativas y recoge los argumentos con diálogos específicos (listas, entradas de texto, selector de carpetas, formularios). Para acciones que requieren `root` usa **`pkexec`** (diálogo gráfico de contraseña) o abre una terminal nueva con `sudo` cuando hace falta TTY.

```bash
chmod +x menu.sh
./menu.sh
```

Si Zenity no está instalado, el propio script ofrece instalarlo con `sudo apt-get install -y zenity`.

**Quedan fuera del menú** (por diseño):
- `scripts-salva/guardian_ssh.sh` — daemon de larga duración, se gestiona con `systemctl`.
- `scripts-salva/setup.sh` — instalador interactivo que ya pide datos por terminal.

---

## Familias de scripts

Cada carpeta tiene su propio `README.md` con la documentación completa (argumentos, ejemplos, troubleshooting). Aquí va sólo el resumen.

### `scripts-salva`

Endurecimiento SSH y daemon de seguridad con alertas y control remoto por Telegram. Ver [scripts/scripts-salva/README.md](scripts/scripts-salva/README.md).

| Script              | Propósito                                                    |
|---------------------|--------------------------------------------------------------|
| `setup.sh`          | Instalador maestro (deps + UFW + servicio Guardian)          |
| `uninstall.sh`      | Elimina el servicio y la configuración de Guardian           |
| `install_ssh.sh`    | Instala OpenSSH y configura UFW restrictivo                  |
| `guardian_ssh.sh`   | Daemon: alertas SSH + comando `/allow` por Telegram          |
| `guardian.service`  | Unidad systemd que gestiona el daemon                        |

> Tras `setup.sh` el puerto 22 queda **cerrado para todos**. Sólo IPs autorizadas vía `/allow` desde Telegram pueden conectarse.

### `scripts-claudiu`

Operación del laboratorio: gestión de servicios `systemd` (local o por SSH) y escaneo de puertos. Ver [scripts/scripts-claudiu/README.md](scripts/scripts-claudiu/README.md).

| Script                   | Propósito                                                       |
|--------------------------|-----------------------------------------------------------------|
| `gestionar_servicio.sh`  | `start`/`stop`/`restart`/`status` sobre cualquier nodo del lab  |
| `status.sh`              | Escanea SSH/HTTP/HTTPS de los tres nodos con `netcat`           |

### `scripts-luis`

Utilidades web sueltas: monitorización HTTP, despliegue por SFTP y esqueleto de actualización DNS. Ver [scripts/scripts-luis/README.md](scripts/scripts-luis/README.md).

| Script             | Propósito                                                        |
|--------------------|------------------------------------------------------------------|
| `check_web.sh`     | Comprueba que un host responde por HTTP                          |
| `deploy_sftp.sh`   | Sube recursivamente un directorio local a un servidor SFTP       |
| `update_dns.sh`    | Detecta IP pública/privada (esqueleto para integrar API DNS)     |

---

## Nodos del laboratorio

Los scripts de `scripts-claudiu` (y los diálogos de `menu.sh`) trabajan con un mapa fijo de nodos:

| Alias        | IP              |
|--------------|-----------------|
| `SV_CLAUDIU` | `172.30.3.235`  |
| `SV_SALVA`   | `172.30.1.144`  |
| `SV_LUIS`    | `172.24.252.34` |

Para añadir o cambiar nodos hay que editar el `case` de `gestionar_servicio.sh`, los arrays de `status.sh` y la lista del menú en `menu.sh`.

---

## Convenciones

- **Idioma:** mensajes, comentarios y documentación en español.
- **Shebang:** `#!/bin/bash` en todos los scripts.
- **Modo estricto:** los scripts nuevos usan `set -euo pipefail`; los más antiguos del repo aún no lo aplican homogéneamente.
- **Logs locales:** los scripts que generan logs lo hacen en el **directorio actual de ejecución**, no junto al script. Si los lanzas desde `cron`, fija `WorkingDirectory`.
- **Variables sobreescribibles:** los scripts de `scripts-luis` admiten configuración por variables de entorno (`HOST=… ./deploy_sftp.sh`).
- **Privilegios:** los scripts que requieren `root` lo dicen explícitamente en el README de su carpeta; `menu.sh` los lanza con `pkexec` o terminal con `sudo` según el caso.

---

## Requisitos generales

Probado en Debian/Ubuntu y derivadas. Paquetes que pueden hacer falta según qué scripts uses:

```bash
sudo apt-get install -y \
    bash curl openssh-client openssh-server ufw jq \
    netcat-openbsd iproute2 zenity policykit-1
```

- `zenity` y `policykit-1` (`pkexec`) — para [menu.sh](menu.sh).
- `openssh-server`, `ufw`, `curl`, `jq` — para [scripts-salva](scripts/scripts-salva/).
- `openssh-client`, `netcat-openbsd` — para [scripts-claudiu](scripts/scripts-claudiu/).
- `curl`, `openssh-client` — para [scripts-luis](scripts/scripts-luis/).
