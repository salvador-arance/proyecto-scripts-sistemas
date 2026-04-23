# scripts-salva

Scripts de administración de servidores Linux: instalación de SSH y monitoreo de intentos de acceso con alertas por Telegram.

Para instalar todo el entorno en un servidor nuevo, ejecuta `setup.sh` desde este directorio (ver sección [Instalación rápida](#instalación-rápida)). Si deseas eliminar los servicios instalados sin afectar las dependencias, usa `uninstall.sh` (ver sección [Desinstalación](#desinstalación)).

---

## Índice

- [Estructura](#estructura)
- [Instalación rápida](#instalación-rápida)
- [Desinstalación](#desinstalación)
- [Scripts](#scripts)
  - [install_ssh.sh](#install_sshsh)
  - [guardian_ssh.sh](#guardian_sshsh)
  - [guardian.service](#guardianservice)
- [Configuración de Telegram](#configuración-de-telegram)
- [Dependencias](#dependencias)
- [Solución de problemas](#solución-de-problemas)

---

## Estructura

```
scripts-salva/
├── README.md                      # Esta documentación
├── setup.sh                       # Script maestro de instalación
├── uninstall.sh                   # Desinstala los servicios creados por setup.sh
├── install_ssh.sh                 # Instala y endurece OpenSSH + UFW
├── guardian_ssh.sh                # Daemon: alertas SSH + control remoto por Telegram
└── guardian.service               # Unidad systemd para guardian_ssh.sh
```

---

## Instalación rápida

> **Recomendación:** Antes de ejecutar el script de instalación, es muy recomendable ir a la sección [Configuración de Telegram](#configuración-de-telegram) y obtener el **Token**, el **Chat ID** y tus **IDs de usuario**. El instalador te los pedirá para dejar el servicio funcionando al instante.

Desde este directorio:

```bash
sudo bash setup.sh
```

Esto instalará las dependencias, **configurará y activará el firewall (UFW)** y te preguntará de forma interactiva por las credenciales de Telegram (Token, Chat ID y Usuarios autorizados). Si las introduces en ese momento, el servicio `guardian.service` se iniciará automáticamente.

> **Advertencia:** tras la instalación el puerto 22 queda **cerrado para todos**. Si estás conectado por SSH al servidor, añade tu IP antes de ejecutar `setup.sh`:
> ```bash
> sudo ufw allow from <TU_IP> to any port 22 proto tcp
> ```
> A partir de ahí, usa `/allow` desde Telegram para autorizar nuevas IPs.

Si prefieres dejarlas en blanco durante la instalación, podrás configurarlas más tarde:

```bash
# 1. Rellena las credenciales de Telegram (si las dejaste en blanco)
sudo nano /etc/guardian/config

# 2. Arranca el guardian (si no se inició solo)
sudo systemctl start guardian.service
sudo systemctl status guardian.service
```

**Requisitos:** Debian, Ubuntu, o cualquier derivada. Se ejecuta con `sudo`.

---

## Desinstalación

Para eliminar el servicio y la configuración (sin desinstalar las dependencias de paquetes):

```bash
sudo bash uninstall.sh
```

Esto detendrá y eliminará el servicio `guardian.service` de systemd, borrará los directorios de configuración `/etc/guardian` y `/var/lib/guardian`, y **reseteará el firewall UFW a sus valores de fábrica** (deshabilitándolo).

---

## Scripts

### `install_ssh.sh`

Instala y configura OpenSSH Server con un firewall UFW restrictivo. Pensado para preparar un servidor desde cero.

**Qué hace, en orden:**
1. Comprueba si OpenSSH ya está instalado; si no, lo instala
2. Habilita e inicia el servicio `ssh` con systemd
3. Instala UFW si no está disponible
4. Configura política restrictiva: deniega todo el tráfico entrante, permite todo el saliente
5. Activa el logging de UFW (`ufw logging on`) para registrar conexiones bloqueadas
6. Activa UFW y muestra el resumen de reglas

> **El puerto 22 queda cerrado por defecto.** Solo las IPs autorizadas mediante `/allow` desde Telegram podrán conectarse por SSH. El logging de UFW es necesario para que las alertas de conexiones bloqueadas funcionen.

**Uso:**
```bash
sudo bash install_ssh.sh
```

> Este script solo necesita ejecutarse una vez. Si usas `setup.sh`, las dependencias ya quedan instaladas y no es necesario correrlo por separado.

---

### `guardian_ssh.sh`

Daemon de seguridad SSH. Hace tres cosas en paralelo:

1. **Monitor de conexiones bloqueadas** — lee `/var/log/ufw.log` en tiempo real. Cada vez que el firewall bloquea un intento de conexión al puerto 22, envía una alerta:
   ```
   🚫 [nombre-servidor] Conexión SSH bloqueada desde: 1.2.3.4
   ```
   Esto ocurre cuando una IP **no alloweada** intenta conectarse. Para evitar spam, solo se envía una alerta por IP cada **60 segundos** como máximo.

2. **Monitor de autenticación fallida** — lee `/var/log/auth.log` en tiempo real. Cuando una IP **sí alloweada** intenta conectarse pero falla la autenticación (contraseña incorrecta), envía una alerta:
   ```
   ⚠️ [nombre-servidor] Intento SSH fallido desde: 1.2.3.4
   ```

3. **Bot de comandos** — escucha mensajes en Telegram. Si un usuario autorizado envía el comando `/allow`, añade esa IP al firewall UFW y confirma por Telegram:
   ```
   ✅ [nombre-servidor] Acceso concedido a la IP 1.2.3.4
   ```

**Comando `/allow`:**
```
/allow <IP> <nombre_servidor>
/allow <IP> all
```
- `<nombre_servidor>` aplica la regla solo en el servidor con ese hostname
- `all` aplica la regla en todos los servidores que estén ejecutando el guardian

**Requisitos previos:**
- Fichero `/etc/guardian/config` configurado (creado por `setup.sh`)
- `jq`, `curl`, `ufw` instalados
- Si ejecutas el script **manualmente** (no vía systemd), necesitas permiso para ejecutar `ufw` sin contraseña. Añadir a `/etc/sudoers` con `visudo`:
  ```
  %sudo ALL=(ALL) NOPASSWD: /usr/sbin/ufw allow from * to any port 22 proto tcp
  ```
  > **Nota:** cuando el servicio `guardian.service` gestiona el daemon, corre como `root` y no necesita esta regla de sudoers.

**Uso manual:**
```bash
sudo bash guardian_ssh.sh
```

En producción se gestiona a través del servicio systemd (ver abajo). No es necesario arrancarlo manualmente.

---

### `guardian.service`

Unidad systemd que ejecuta `guardian_ssh.sh` como servicio del sistema.

**Características:**
- Se reinicia automáticamente si el script falla (`Restart=always`)
- Limita los reinicios a 5 en 60 segundos para evitar bucles de fallo
- Se ejecuta como `root` (necesario para modificar UFW)
- Sandboxing básico: `NoNewPrivileges`, `ProtectSystem=strict`
- Rutas de escritura permitidas: `/tmp`, `/etc/ufw` (persistencia de reglas UFW) y `/var/lib/guardian` (estado del bot)
- La configuración se carga directamente por `guardian_ssh.sh` desde `/etc/guardian/config`

Este archivo contiene un placeholder `%%GUARDIAN_SH_PATH%%` que `setup.sh` sustituye con la ruta real del proyecto al instalar.

**No copiar este archivo manualmente** — usa `setup.sh` para instalarlo correctamente.

**Comandos de gestión:**
```bash
sudo systemctl start guardian.service      # arrancar
sudo systemctl stop guardian.service       # parar
sudo systemctl restart guardian.service    # reiniciar
sudo systemctl status guardian.service     # ver estado
sudo journalctl -u guardian.service -f     # ver logs en tiempo real
```

---

## Configuración de Telegram

Para que el script `guardian_ssh.sh` pueda enviar alertas y recibir comandos (como `/allow`), es necesario crear y configurar un Bot de Telegram. El fichero de configuración se encuentra en `/etc/guardian/config` y requiere tres valores fundamentales: `TOKEN`, `CHAT_ID` y `USERS_AUTORIZADOS`.

A continuación, se detalla paso a paso cómo obtener cada uno de estos valores:

### 1. Obtener el `TOKEN` del Bot (vía @BotFather)

El `@BotFather` es el bot oficial de Telegram para crear y gestionar otros bots.

1. Abre Telegram y busca **@BotFather** en el buscador superior (asegúrate de que tiene la insignia azul de cuenta verificada).
2. Inicia una conversación pulsando en **Iniciar** (o enviando el comando `/start`).
3. Envía el comando `/newbot` para crear un nuevo bot.
4. Te pedirá un **nombre** para tu bot (ej. `Mi Servidor Guardian`).
5. Te pedirá un **username** (nombre de usuario) que debe terminar obligatoriamente en `bot` (ej. `mi_servidor_guardian_bot`).
6. Una vez creado, `@BotFather` te enviará un mensaje de confirmación que contiene el **Token de acceso** (una cadena larga parecida a `1234567890:ABCdefGhIJKlmNoPQRsTUVwxyZ`).
7. **Copia ese token** y pégalo en la variable `TOKEN` dentro de `/etc/guardian/config`.

### 2. Obtener el `CHAT_ID` (Grupo o Chat Privado)

El bot enviará las alertas de seguridad a este chat. Si quieres que las alertas lleguen a un grupo (útil si hay varios administradores) o a un chat privado.

**Para un grupo:**
1. Crea un nuevo grupo en Telegram y añade a los administradores que desees.
2. Añade también al bot que acabas de crear (buscándolo por su nombre de usuario, ej. `@mi_servidor_guardian_bot`).
3. Añade al bot **@RawDataBot** o **@userinfobot** al mismo grupo.
4. Al entrar, estos bots de diagnóstico suelen imprimir un mensaje JSON o información detallada del chat. Busca el apartado `"chat": {"id": -123456789, ...}`.
5. El ID de los grupos **siempre empieza por un guion (`-`)**. Ejemplo: `-1001234567890` o `-1234567890`.
6. (Opcional) Una vez obtenido el ID, puedes expulsar a `@RawDataBot` o `@userinfobot` del grupo.
7. **Copia este ID negativo** y ponlo en la variable `CHAT_ID` dentro de `/etc/guardian/config`.

**Para un chat privado (sólo para ti):**
1. Busca tu bot en Telegram y envíale un mensaje cualquiera (ej. "Hola").
2. Abre tu navegador web y entra en la siguiente URL, reemplazando `<TU_TOKEN>` por el token obtenido en el Paso 1:
   `https://api.telegram.org/bot<TU_TOKEN>/getUpdates`
3. Verás un texto en formato JSON. Busca la sección `"chat":{"id":123456789`.
4. Ese número positivo es tu `CHAT_ID`. Cópialo y pégalo en `/etc/guardian/config`.

### 3. Obtener el ID de los usuarios autorizados (`USERS_AUTORIZADOS`)

Para evitar que cualquier persona que encuentre tu bot pueda enviarle comandos como `/allow`, debes especificar qué usuarios (IDs de Telegram) están autorizados para administrarlo.

1. Abre Telegram y busca al bot **@userinfobot** (o cualquier otro bot similar como `@RawDataBot`).
2. Inicia un chat privado con él y envíale un mensaje.
3. El bot te responderá con tu **ID numérico** de Telegram (un número positivo, ej. `987654321`).
4. Si hay varios administradores, cada uno debe hacer esto y pasarte su ID.
5. **Copia este ID (o varios separados por un espacio)** y colócalos en la variable `USERS_AUTORIZADOS` dentro de `/etc/guardian/config`.

Ejemplo de cómo debe quedar el fichero `/etc/guardian/config`:

```bash
# Token del bot (obtenlo de @BotFather en Telegram)
TOKEN="1234567890:ABCdefGhIJKlmNoPQRsTUVwxyZ"

# ID del chat o grupo donde se enviarán las alertas
# Para grupos, el ID es negativo (ej: -1234567890)
CHAT_ID="-100987654321"

# IDs numéricos de Telegram de los usuarios autorizados para enviar /allow
# Separados por espacios. Consigue tu ID hablando con @userinfobot en Telegram
USERS_AUTORIZADOS="987654321 1122334455"
```

---

## Dependencias

| Paquete          | Usado por                         |
|------------------|-----------------------------------|
| `openssh-server` | `install_ssh.sh`                  |
| `ufw`            | `install_ssh.sh`, `guardian_ssh.sh` |
| `curl`           | `guardian_ssh.sh`                 |
| `jq`             | `guardian_ssh.sh`                 |
| `iputils-ping`   | diagnóstico de red                |

`setup.sh` instala todas estas dependencias automáticamente.

---

## Solución de problemas

### El servicio queda en estado `failed` o se reinicia en bucle

```bash
sudo systemctl status guardian.service
sudo journalctl -u guardian.service -n 50
```

Causas más habituales:
- **Token no configurado o inválido** — el fichero `/etc/guardian/config` contiene aún el valor por defecto `REEMPLAZA_CON_TU_TOKEN`. Edítalo y reinicia el servicio.
- **Error de red** — si el servidor no tiene acceso a internet, el servicio esperará hasta recuperar conectividad sin detenerse.

### El comando `/allow` no responde o no aplica la regla

1. Comprueba que UFW está activo: `sudo ufw status`
2. Comprueba que el `SENDER_ID` del usuario que envía el comando coincide exactamente con algún valor en `USERS_AUTORIZADOS` de `/etc/guardian/config`.
3. Verifica que el tercer argumento del comando es el hostname exacto del servidor (`hostname`) o `all`.

### No llegan alertas de conexiones bloqueadas (`🚫`)

- Comprueba que el logging de UFW está activo:
  ```bash
  sudo ufw status verbose | grep Logging
  ```
  Debe aparecer `Logging: on`. Si no, actívalo:
  ```bash
  sudo ufw logging on
  ```
- Verifica que `/var/log/ufw.log` existe. En algunos sistemas los logs de UFW van a `/var/log/syslog` en lugar de a un fichero separado. Si es así, instala `rsyslog`:
  ```bash
  sudo apt-get install -y rsyslog
  sudo systemctl enable --now rsyslog
  ```

### No llegan alertas de autenticación fallida (`⚠️`)

- El script lee `/var/log/auth.log`. En **Ubuntu 24.04+** y sistemas con `systemd-journald` como único backend de logs, este archivo puede no existir.
  - Solución: instala `rsyslog`:
    ```bash
    sudo apt-get install -y rsyslog
    sudo systemctl enable --now rsyslog
    ```
- Comprueba que el token y el `CHAT_ID` son correctos y que el bot está en el grupo/chat destinatario.

### Verificar que el bot de Telegram responde

```bash
curl -s "https://api.telegram.org/bot<TU_TOKEN>/getMe"
```

Debe devolver un JSON con `"ok":true` y los datos de tu bot.
