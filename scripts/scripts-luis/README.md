# scripts-luis

Pequeña colección de utilidades de administración web: comprobación de un host por HTTP, despliegue de un directorio local por SFTP y actualización (manual / esqueleto) de un registro DNS.

Cada script es independiente: no comparten configuración ni dependen unos de otros. Se pueden ejecutar sueltos según se necesite.

---

## Índice

- [Estructura](#estructura)
- [Scripts](#scripts)
  - [check_web.sh](#check_websh)
  - [deploy_sftp.sh](#deploy_sftpsh)
  - [update_dns.sh](#update_dnssh)
- [Dependencias](#dependencias)
- [Solución de problemas](#solución-de-problemas)

---

## Estructura

```
scripts-luis/
├── README.md           # Esta documentación
├── check_web.sh        # Comprobación HTTP de un host
├── deploy_sftp.sh      # Subida de un directorio local a un servidor por SFTP
└── update_dns.sh       # Obtiene la IP pública/privada y muestra el dominio (skeleton DNS)
```

---

## Scripts

### `check_web.sh`

Comprueba que un host responde a una petición HTTP con `curl --fail`. Pensado como verificación rápida tras un despliegue o como parte de un cron de monitorización.

**Qué hace, en orden:**
1. Valida que se ha pasado el argumento `<host>`
2. Comprueba que el formato del host es válido (caracteres alfanuméricos, puntos y guiones)
3. Lanza una petición `HEAD` por HTTP y considera éxito sólo si el servidor devuelve 2xx/3xx

**Uso:**
```bash
./check_web.sh <host>

# Ejemplos
./check_web.sh midominio.com
./check_web.sh 192.168.1.10
```

**Códigos de salida:**
- `0` — la web responde
- `1` — argumento ausente, formato inválido o la web no responde

---

### `deploy_sftp.sh`

Sube de forma recursiva el contenido de un directorio local a un servidor remoto vía SFTP. Pensado para publicar una web estática contra el `DocumentRoot` del servidor.

**Variables de configuración** (se pueden sobreescribir por entorno):

| Variable     | Valor por defecto   | Descripción                                     |
|--------------|---------------------|-------------------------------------------------|
| `HOST`       | `tu-servidor.com`   | Servidor SFTP de destino                        |
| `USER`       | `usuario`           | Usuario SSH/SFTP                                |
| `REMOTE_DIR` | `/var/www/html`     | Directorio remoto donde se vuelca el contenido  |
| `LOCAL_DIR`  | `./web`             | Directorio local cuyo contenido se sube         |

**Uso:**
```bash
# Con los valores por defecto del script
./deploy_sftp.sh

# Sobreescribiendo desde la línea de comandos
HOST=ejemplo.com USER=deploy LOCAL_DIR=./public ./deploy_sftp.sh
```

> **Recomendación:** configura autenticación por clave SSH (`ssh-copy-id`) para evitar que SFTP te pida contraseña en cada ejecución.

---

### `update_dns.sh`

Detecta la IP pública del servidor (vía `ifconfig.me`) y la IP privada local, y las muestra junto con el dominio configurado. Es el **esqueleto** sobre el que integrar la llamada a la API del proveedor DNS (Cloudflare, Route53, etc.).

**Variables de configuración:**

| Variable | Valor por defecto | Descripción                              |
|----------|-------------------|------------------------------------------|
| `DOMAIN` | `midominio.com`   | Dominio cuyo registro A se actualizará   |

**Uso:**
```bash
./update_dns.sh
DOMAIN=otro-dominio.com ./update_dns.sh
```

**Pendiente:** dentro del script hay un bloque `TODO` marcando el sitio donde añadir la llamada `curl` a la API del proveedor DNS para actualizar el registro A apuntando a la IP pública detectada.

---

## Dependencias

| Paquete        | Usado por                            |
|----------------|--------------------------------------|
| `curl`         | `check_web.sh`, `update_dns.sh`      |
| `openssh-client` (`sftp`) | `deploy_sftp.sh`          |
| `iproute2` / `hostname` | `update_dns.sh` (IP privada) |

Instalación en Debian/Ubuntu:
```bash
sudo apt-get install -y curl openssh-client iproute2
```

---

## Solución de problemas

### `check_web.sh` reporta "Error" pero la web carga en el navegador

- El script comprueba **HTTP**, no HTTPS. Si tu servidor sólo escucha en 443, cambia `http://` por `https://` en el script o añade soporte para esquema.
- `curl --fail` considera fallo cualquier respuesta ≥ 400. Una página que devuelve un 401/403 se reporta como caída aunque exista.

### `deploy_sftp.sh` pide contraseña en cada ejecución

Configura autenticación por clave pública:
```bash
ssh-keygen -t ed25519        # si no tienes ya una clave
ssh-copy-id usuario@host
```

### `update_dns.sh` muestra `IP privada: no disponible`

`hostname -I` no existe en macOS ni en Windows nativo. En esos entornos el script seguirá funcionando para la IP pública, pero la IP privada quedará vacía. En Linux asegúrate de tener instalado el paquete `hostname` o `iproute2`.

### `ifconfig.me` no responde

Es un servicio público gratuito y puede caer puntualmente. Alternativas:
```bash
curl -s https://api.ipify.org
curl -s https://icanhazip.com
```
