# TODO — server-debian13-install-traefik-portainer

> Análisis técnico generado el 2026-03-28.
> Cubre bugs, seguridad, calidad de código, usabilidad y mantenibilidad de todos los módulos del proyecto.

---

## 1. Resumen del estado actual

El proyecto es un instalador modular en Bash para configurar un servidor Debian 13 (Trixie) con Docker, Traefik v3 y Portainer CE. La estructura de módulos es limpia y la separación de responsabilidades está bien planteada.

**Funciona bien:**
- Flujo modular: `main.sh` orquesta módulos independientes con `source`.
- `common.sh` centraliza logging, colores y validaciones reutilizables.
- `secure_server.sh` implementa un hardening razonablemente completo (UFW, fail2ban con backend systemd, auditd, límites del sistema, NTP, usuario admin).
- `install_docker.sh` usa el repositorio oficial de Docker, eliminó correctamente dependencias obsoletas (`apt-transport-https`, `software-properties-common`) respecto a la versión anterior.
- `install_traefik.sh` genera configuración TLS con Traefik v3, cabeceras de seguridad HTTP y ACME/Let's Encrypt.
- CI/CD inicial con ShellCheck y shfmt en `.github/workflows/shell-lint.yml`.
- `.shellcheckrc` con supresiones justificadas para el patrón `source` dinámico.

**Necesita mejora:**
- Varios bugs de comportamiento predecible (IPs hardcodeadas, `cd` sin retorno, funciones anidadas).
- Problemas de seguridad reales (contraseña en variable de entorno de proceso, `docker.sock` sin alternativa).
- Sin modo no-interactivo ni soporte para automatización/CI.
- Archivos obsoletos y sin propósito en el repositorio (`install_docker.txt`, `ai_studio_code`).
- Sin `README.md` ni `.gitignore`.
- `INSTALL_DIR` duplicado entre módulos, sin fuente única de configuración.

---

## 2. Bugs y problemas críticos (Alta prioridad)

### BUG-01 — IPs estáticas hardcodeadas en la red Docker proxy

**Archivo:** `modules/install_traefik.sh`, líneas 80 y 105

**Qué hace mal:** La red `proxy` se define con subnet `172.18.0.0/16` y los contenedores reciben IPs fijas `172.18.0.2` y `172.18.0.3`. Si el servidor ya tiene una red Docker o interfaz de red en ese rango (p. ej., otro stack de Compose levantado antes), Docker fallará al crear la red con un error de solapamiento de subredes.

**Impacto:** Instalación fallida en entornos con redes Docker preexistentes; difícil de diagnosticar.

**Solución propuesta:**
1. Eliminar las IPs estáticas — Traefik no las necesita; usa autodiscovery por etiquetas.
2. Cambiar la subnet a un rango menos común (p. ej., `172.31.0.0/24`) o hacerla configurable.
3. Si se requieren IPs fijas para algún caso de uso específico, documentarlo explícitamente.

```yaml
# Antes
networks:
  proxy:
    driver: bridge
    ipam:
      config: [{ subnet: 172.18.0.0/16 }]

# Después
networks:
  proxy:
    external: false
    driver: bridge
```

---

### BUG-02 — Portainer usa imagen `:latest` (no reproducible)

**Archivo:** `modules/install_traefik.sh`, línea 99; `modules/update_traefik.sh`, línea 30

**Qué hace mal:** `portainer/portainer-ce:latest` cambia de contenido sin preaviso. Una actualización futura puede introducir cambios de API incompatibles o comportamiento inesperado sin que el operador lo haya decidido.

**Impacto:** Instalaciones en distintos momentos obtienen versiones diferentes; el script de actualización compara IDs de imagen pero no versiones semánticas.

**Solución propuesta:** Pinear a una versión semántica estable (p. ej., `portainer/portainer-ce:2.21.5`) y actualizar la versión de forma deliberada. Exponer la versión como variable configurable al inicio del módulo.

```bash
PORTAINER_VERSION="${PORTAINER_VERSION:-2.21.5}"
```

---

### BUG-03 — `cd "$INSTALL_DIR"` sin restaurar el directorio de trabajo

**Archivos:** `modules/install_traefik.sh`, línea 185; `modules/update_traefik.sh`, línea 16

**Qué hace mal:** Ambas funciones hacen `cd "$INSTALL_DIR"` y nunca regresan al directorio original. Cuando se ejecuta la opción 5 del menú (todos los procesos secuencialmente), las funciones siguientes operan desde `/opt/traefik-portainer` en lugar del directorio original del script, lo que puede causar que rutas relativas fallen silenciosamente.

**Impacto:** Comportamiento impredecible al encadenar módulos; difícil de depurar.

**Solución propuesta:** Usar `pushd`/`popd` o subshells:

```bash
# Opción 1: pushd/popd
pushd "$INSTALL_DIR" > /dev/null
docker compose up -d
popd > /dev/null

# Opción 2: subshell (más seguro)
(cd "$INSTALL_DIR" && docker compose up -d)
```

---

### BUG-04 — Funciones definidas dentro de funciones (antipatrón Bash)

**Archivos:** `modules/secure_server.sh`, líneas 217–256 (`create_admin_user` dentro de `secure_server`); `modules/install_docker.sh`, líneas 49–71 (`create_docker_user` dentro de `install_docker`)

**Qué hace mal:** En Bash, definir una función dentro de otra no crea un scope léxico. La función interna queda registrada en el entorno global del shell la primera vez que se ejecuta la función externa. Si la función externa se invoca dos veces, la función interna se redefine (no hay error, pero es confuso). Además, impide reutilizar la función interna de forma independiente y dificulta las pruebas.

**Impacto:** Comportamiento sorprendente si los módulos se recargan; viola las convenciones de shellcheck y estilo Bash.

**Solución propuesta:** Mover `create_admin_user` y `create_docker_user` al nivel superior del módulo correspondiente, fuera de la función que las llama.

---

### BUG-05 — `set -e` en `main.sh` pero módulos no tienen `set -e` consistente

**Archivo:** `main.sh`, línea 9; todos los módulos

**Qué hace mal:** `main.sh` establece `set -e`, pero los módulos son cargados con `source`, por lo que heredan el `set -e`. Sin embargo, ningún módulo declara explícitamente `set -e` ni `set -o pipefail`. Esto es confuso para quien lee un módulo de forma aislada: no es obvio que los módulos dependen del contexto de `set -e` del llamador.

Más grave: las pipes sin `pipefail` ocultan errores. Por ejemplo, en `common.sh` línea 47:
```bash
DEBIAN_VERSION=$(echo $VERSION_ID | cut -d. -f1)
```
Si `cut` falla, el error se pierde.

**Impacto:** Errores silenciosos en pipelines; comportamiento diferente si un módulo se ejecuta directamente en lugar de cargarse desde `main.sh`.

**Solución propuesta:**
- Añadir al inicio de cada módulo `.sh`: `set -euo pipefail` (o documentar explícitamente que dependen del contexto del llamador).
- En `main.sh`, añadir `set -o pipefail` junto al `set -e` existente.

---

### BUG-06 — `detect_debian_version` sin comillas y sin validación

**Archivo:** `modules/common.sh`, líneas 47–48

**Qué hace mal:**
```bash
DEBIAN_VERSION=$(echo $VERSION_ID | cut -d. -f1)
DEBIAN_CODENAME=$VERSION_CODENAME
```
1. `$VERSION_ID` sin comillas: si el valor contiene espacios o caracteres especiales, se produce word-splitting.
2. Si `/etc/os-release` no contiene `VERSION_ID` o `VERSION_CODENAME` (posible en imágenes mínimas de Debian), las variables quedan vacías y los módulos que las usan (p. ej., `secure_server.sh` línea 165: `if [ "$DEBIAN_VERSION" -ge 13 ]`) producen un error aritmético.
3. El `echo $VERSION_ID | cut` es innecesario: se puede usar expansión de parámetro directamente: `DEBIAN_VERSION="${VERSION_ID%%.*}"`.

**Impacto:** Error en la comparación aritmética de versión → `secure_server` aborta.

**Solución propuesta:**
```bash
detect_debian_version() {
    if [ ! -f /etc/os-release ]; then
        error "No se pudo detectar la versión de Debian: /etc/os-release no existe"
    fi
    . /etc/os-release
    if [ -z "${VERSION_ID:-}" ] || [ -z "${VERSION_CODENAME:-}" ]; then
        error "No se pudo detectar la versión de Debian: VERSION_ID o VERSION_CODENAME no definidos en /etc/os-release"
    fi
    DEBIAN_VERSION="${VERSION_ID%%.*}"
    DEBIAN_CODENAME="$VERSION_CODENAME"
    log "Detectada Debian $DEBIAN_VERSION ($DEBIAN_CODENAME)"
}
```

---

### BUG-07 — `LOG_FILE` escrito antes de verificar que el directorio existe

**Archivo:** `main.sh`, líneas 30–32; `modules/common.sh`, líneas 68, 74, 80

**Qué hace mal:** `touch "$LOG_FILE"` se ejecuta antes de verificar que `/var/log` existe y es escribible. En un entorno mínimo o chroot, `/var/log` puede no existir. Además, las funciones `log`, `warn` y `error` en `common.sh` escriben directamente a `$LOG_FILE` con `>>` sin verificar que el archivo sea accesible, lo que hace que cada llamada a `log` falle silenciosamente si el archivo no es escribible.

**Impacto:** Mensajes de log perdidos sin ninguna advertencia al operador.

**Solución propuesta:**
```bash
# En main.sh, antes de touch:
if [ ! -d "$(dirname "$LOG_FILE")" ]; then
    mkdir -p "$(dirname "$LOG_FILE")" || { echo "[WARN] No se puede crear el directorio de log"; LOG_FILE="/tmp/server-setup.log"; }
fi
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/server-setup.log"
```

---

### BUG-08 — `install_docker.txt` — versión obsoleta en el repositorio

**Archivo:** `modules/install_docker.txt`

**Qué hace mal:** Es una copia casi idéntica de `install_docker.sh` que incluye las dependencias obsoletas `apt-transport-https` y `software-properties-common` que fueron deliberadamente eliminadas del `.sh` activo. Su presencia puede:
- Confundir a colaboradores sobre cuál es la versión correcta.
- Ser ejecutado accidentalmente (el loop de carga en `main.sh` solo carga `*.sh`, pero podría editarse el glob).
- No es procesado por el CI (ShellCheck solo procesa `*.sh`).

**Solución propuesta:** Eliminar el archivo. Si se quiere conservar historial, el registro de git es suficiente.

---

### BUG-09 — `ai_studio_code` sin extensión y sin propósito claro en el repositorio

**Archivo:** `ai_studio_code`

**Qué hace mal:** Es un diagrama de estructura del proyecto en texto plano, sin extensión `.md` o `.txt`, sin shebang, sin referencia en ningún otro archivo. Su nombre no es autoexplicativo y podría confundir a colaboradores.

**Solución propuesta:** Eliminar el archivo o integrar su contenido en `README.md` como sección de estructura del proyecto.

---

### BUG-10 — `version: "3.8"` en docker-compose.yml (obsoleto en Compose v2)

**Archivo:** `modules/install_traefik.sh`, línea 71 (heredoc generado)

**Qué hace mal:** La clave `version` en `docker-compose.yml` fue declarada obsoleta en Docker Compose v2. Las versiones modernas la ignoran con un warning. Su presencia da una falsa sensación de compatibilidad versionada y genera ruido en los logs de Compose.

**Solución propuesta:** Eliminar la línea `version: "3.8"` del heredoc generado.

---

## 3. Mejoras de calidad de código (Bash best practices)

### QC-01 — Variables sin comillas en múltiples ubicaciones

ShellCheck reportaría (SC2086) las siguientes variables sin comillas:

| Archivo | Línea | Variable problemática |
|---|---|---|
| `common.sh` | 47 | `echo $VERSION_ID` |
| `secure_server.sh` | 66 | `ufw allow $ssh_port/tcp` |
| `secure_server.sh` | 59 | `check_error $? "..."` — `$?` sin comillas (SC2181) |
| `install_docker.sh` | 10 | `2>/dev/null \|\| warn "..."` tras comando con variables sin citar |

**Regla general:** Siempre citar `"$variable"` a menos que se requiera word-splitting deliberado.

### QC-02 — `check_error $?` es un antipatrón (SC2181)

**Archivo:** Todos los módulos, usos múltiples

`check_error $?` captura el código de salida del comando anterior, pero con `set -e` activo, si ese comando falla, el script ya habrá terminado antes de que `check_error` pueda ejecutarse. La comprobación es redundante y engañosa.

**Solución:** Con `set -e` activo, simplemente ejecutar el comando. Para mensajes de error personalizados, usar:
```bash
command || error "Mensaje de error"
```

### QC-03 — Ausencia de `set -o pipefail` y `set -u`

**Archivo:** `main.sh`, todos los módulos

- `set -o pipefail`: sin él, `cmd1 | cmd2` reporta éxito aunque `cmd1` falle.
- `set -u`: sin él, variables no definidas se expanden a cadena vacía silenciosamente, ocultando errores de typo en nombres de variable.

**Solución:** Añadir `set -euo pipefail` al inicio de `main.sh` y documentar en los módulos que asumen este contexto, o añadirlo en cada módulo.

### QC-04 — `read` sin `-r` en `main_loop`

**Archivo:** `main.sh`, línea 103

```bash
read -r choice  # Correcto — ya presente
```
Pero en módulos como `secure_server.sh` línea 61, `install_traefik.sh` líneas 45–63, los `read -p` sin `-r` permiten que el usuario introduzca backslashes de escape que alteran el valor leído.

**Solución:** Añadir `-r` a todos los `read -p`.

### QC-05 — Uso de `echo -e` no portable

**Archivos:** `main.sh` (líneas 45, 52), `update_traefik.sh` (línea 49)

`echo -e` no es POSIX y su comportamiento varía entre implementaciones de `echo`. Las funciones `log`, `warn` y `error` ya usan `echo -e` correctamente en `common.sh`. Para consistencia y portabilidad, usar `printf` o la función `log` existente.

### QC-06 — Indentación inconsistente en `secure_server.sh`

**Archivo:** `modules/secure_server.sh`, líneas 165–177

El bloque `if [ "$DEBIAN_VERSION" -ge 13 ]` tiene indentación de 0 espacios en el nivel del `if` y 8 espacios en el cuerpo, incongruente con el resto del archivo que usa 4 espacios. `shfmt` reportaría esto como error de formato.

---

## 4. Mejoras de seguridad

### SEC-01 — Contraseña de Traefik visible en variables del proceso

**Archivo:** `modules/install_traefik.sh`, líneas 63–65

```bash
read -sp "Ingrese la contraseña para Traefik: " traefik_password; echo
traefik_auth=$(htpasswd -nb "$traefik_user" "$traefik_password")
```

La contraseña se almacena en la variable `$traefik_password` en el entorno del proceso. Aunque `read -s` evita que aparezca en pantalla, la variable es visible en `/proc/<PID>/environ` mientras el proceso está activo y puede filtrarse a subshells.

**Impacto:** En un servidor multiusuario, otro proceso con acceso a `/proc` podría leer la contraseña.

**Solución propuesta:** Pasar la contraseña directamente a `htpasswd` usando un archivo temporal con permisos restrictivos o mediante stdin:
```bash
traefik_auth=$(echo "$traefik_password" | htpasswd -ni "$traefik_user")
unset traefik_password
```
Limpiar la variable inmediatamente con `unset` tras su uso.

### SEC-02 — Hash bcrypt de Traefik escrito en texto plano en `dynamic.yml`

**Archivo:** `modules/install_traefik.sh`, líneas 169–171 (heredoc de `dynamic.yml`)

```yaml
user-auth:
  basicAuth:
    users: ["${traefik_auth}"]
```

El hash `htpasswd` (aunque es un hash y no la contraseña en claro) queda almacenado en `dynamic.yml` con permisos del directorio `$INSTALL_DIR` (755 por defecto de `mkdir`). Si los permisos no se restringen, cualquier usuario del sistema puede leer el hash.

**Solución propuesta:** Configurar permisos restrictivos en los archivos de configuración:
```bash
chmod 750 "$INSTALL_DIR"
chmod 640 "$INSTALL_DIR/traefik-data/configurations/dynamic.yml"
chown root:docker "$INSTALL_DIR/traefik-data/configurations/dynamic.yml"
```

### SEC-03 — `docker.sock` montado como volumen sin alternativas

**Archivo:** `modules/install_traefik.sh`, líneas 85 y 108

```yaml
- /var/run/docker.sock:/var/run/docker.sock:ro
```

Montar el socket de Docker (incluso en modo `:ro`) da a Traefik y Portainer acceso efectivo de root al host, ya que cualquier proceso que pueda hablar con `docker.sock` puede crear contenedores con montajes de volumen del host, escalar privilegios, etc. Este es un riesgo conocido y aceptado en muchos stacks de homelab, pero no debe hacerse sin documentación explícita.

**Solución propuesta:**
- Para **Traefik**: evaluar el uso del [Docker provider via TCP con TLS](https://doc.traefik.io/traefik/providers/docker/#docker-api-access) en lugar del socket Unix, o usar [Traefik con socket proxy](https://github.com/Tecnativa/docker-socket-proxy) (contenedor intermediario que filtra las llamadas permitidas).
- Para **Portainer**: es inherente a su funcionamiento; documentar el riesgo explícitamente.
- Como mínimo: asegurar que el grupo `docker` no tenga usuarios no autorizados.

### SEC-04 — `sshd_config` sobreescrito completamente sin validar sintaxis antes

**Archivo:** `modules/secure_server.sh`, líneas 85–126

Se hace un backup antes de sobreescribir (`sshd_config.bak.<timestamp>`), pero `sshd -t` se ejecuta **después** del reemplazo (línea 262). Si `sshd -t` falla, el script aborta por `check_error`, pero ya se habrá sobrescrito el archivo de configuración original con uno potencialmente inválido.

El backup existe, pero el operador debe restaurarlo manualmente en caso de error — no hay recuperación automática.

**Solución propuesta:** Escribir la nueva configuración en un archivo temporal, validarla con `sshd -t -f /tmp/sshd_config.new`, y solo entonces reemplazar el archivo activo:
```bash
cat > /tmp/sshd_config.new <<EOF
...
EOF
sshd -t -f /tmp/sshd_config.new || error "Configuración SSH inválida"
mv /tmp/sshd_config.new /etc/ssh/sshd_config
```

### SEC-05 — `AllowAgentForwarding yes` y `AllowTcpForwarding yes` innecesarios

**Archivo:** `modules/secure_server.sh`, líneas 108–109

En un servidor de producción que actúa como plataforma de infraestructura (no como jumphost), habilitar `AllowAgentForwarding` y `AllowTcpForwarding` amplía la superficie de ataque: un usuario con acceso SSH comprometido podría usar el servidor como relay.

**Solución propuesta:** Establecer ambas a `no` por defecto. Si se necesita tunneling específico, documentarlo como excepción.

### SEC-06 — `destemail = root@localhost` hardcodeado en fail2ban

**Archivo:** `modules/secure_server.sh`, línea 143

El destinatario de alertas de fail2ban es `root@localhost`, que en la mayoría de los servidores en producción nunca se lee. Las alertas de ban se pierden silenciosamente.

**Solución propuesta:** Pedir el email de alertas de forma interactiva (reutilizando `is_valid_email`) o leer de una variable de configuración centralizada. Si `sendmail` no está configurado, advertirlo explícitamente.

### SEC-07 — `"experimental": false` redundante en `daemon.json`

**Archivo:** `modules/install_docker.sh`, línea 86

`experimental: false` es el valor por defecto del daemon de Docker. Incluirlo explícitamente no añade seguridad ni claridad; solo genera confusión sobre si se habilitó algo experimental en algún momento.

**Solución propuesta:** Eliminar la línea.

### SEC-08 — Secretos no deben aparecer en el log

**Archivo:** `modules/install_traefik.sh`, línea 201

```bash
log "  - Usuario Traefik: $traefik_user"
```

El nombre de usuario de Traefik se registra en el log. El hash `traefik_auth` no se loguea directamente, pero si se añade logging de debug en el futuro, podría filtrarse.

**Solución propuesta:** Verificar que ninguna variable sensible (`traefik_password`, `traefik_auth`) se pase a `log()`, `warn()` o `error()`. Añadir comentario explícito donde se use `traefik_auth` advirtiendo que no debe loguearse.

---

## 5. Mejoras de usabilidad / modo no-interactivo

### USA-01 — Sin flags CLI ni modo no-interactivo

El script no acepta argumentos de línea de comandos. No hay forma de ejecutar una operación específica sin pasar por el menú interactivo, lo que impide su uso en pipelines de CI/CD o provisioning automatizado (Ansible, Terraform, cloud-init).

**Solución propuesta:** Añadir soporte de flags en `main.sh`:
```bash
# Uso: sudo ./main.sh [--secure] [--docker] [--traefik] [--all] [--non-interactive]
```

### USA-02 — Sin soporte de variables de entorno para configuración

No existe un mecanismo para preconfigurar valores (puerto SSH, dominio, email, versiones de imágenes) mediante variables de entorno o un archivo de configuración (`.env`). En un servidor de producción real, estos valores deben poder pasarse sin interacción.

**Solución propuesta:** Leer variables desde un archivo `.env` opcional al inicio de `main.sh`, con valores interactivos como fallback:
```bash
[ -f .env ] && source .env
ssh_port="${SSH_PORT:-$(read -p '...' p; echo $p)}"
```

### USA-03 — Sin validación de resolución DNS antes de configurar dominios

**Archivo:** `modules/install_traefik.sh`, línea 46

Se acepta un dominio base y subdominios sin verificar que resuelvan a la IP del servidor. Si el DNS no está configurado, Let's Encrypt fallará en el challenge HTTP y los certificados no se emitirán, pero el usuario no recibirá ninguna advertencia preventiva.

**Solución propuesta:** Añadir una comprobación de DNS antes de proceder:
```bash
server_ip=$(curl -sf https://api.ipify.org || curl -sf https://ifconfig.me)
resolved_ip=$(dig +short "${traefik_subdomain}.${base_domain}" | tail -1)
if [ "$server_ip" != "$resolved_ip" ]; then
    warn "El subdominio ${traefik_subdomain}.${base_domain} no resuelve a la IP de este servidor ($server_ip). Let's Encrypt puede fallar."
fi
```

### USA-04 — Sin README.md

No existe documentación de uso. Un nuevo colaborador o usuario no sabe cómo ejecutar el script, qué prerrequisitos necesita, qué hace cada módulo, ni cuáles son las limitaciones conocidas.

### USA-05 — Sin modo `--dry-run`

No hay forma de previsualizar qué cambios haría el script sin ejecutarlos. Especialmente útil para `secure_server.sh`, que modifica configuraciones críticas del sistema.

---

## 6. Mejoras de mantenibilidad

### MAN-01 — `INSTALL_DIR` duplicado en dos módulos

**Archivos:** `modules/install_traefik.sh`, línea 17; `modules/update_traefik.sh`, línea 7

```bash
INSTALL_DIR="/opt/traefik-portainer"  # Repetido en ambos
```

Si se cambia la ruta de instalación, hay que actualizarla en dos lugares. Un error al hacerlo causaría que `update_traefik` busque los archivos en la ubicación incorrecta.

**Solución propuesta:** Definir `INSTALL_DIR` como constante en `common.sh` y exportarla.

### MAN-02 — Imagen de Portainer sin pinear (relacionado con BUG-02)

Ver BUG-02. Desde la perspectiva de mantenibilidad, una imagen sin pinear hace que el historial de git no sea suficiente para reproducir el estado exacto de una instalación pasada.

### MAN-03 — Ausencia de `.gitignore`

No existe `.gitignore`. Archivos generados durante el desarrollo (archivos `.env` con credenciales, `acme.json`, backups locales) podrían ser committeados accidentalmente.

**Solución propuesta:** Crear `.gitignore` con al menos:
```
.env
*.bak
acme.json
/opt/
```

### MAN-04 — Sin versión del script ni changelog

No hay ningún mecanismo de versionado (variable `SCRIPT_VERSION`, archivo `CHANGELOG.md`, tag de git). Imposible saber qué versión del script instaló un servidor dado.

**Solución propuesta:** Añadir `SCRIPT_VERSION="1.0.0"` en `common.sh` y mostrarla en el menú y en los logs.

### MAN-05 — `ai_studio_code` debe eliminarse o integrarse en documentación

Ver BUG-09. Su contenido es útil como sección en `README.md`.

### MAN-06 — `install_docker.txt` debe eliminarse

Ver BUG-08. El historial de git conserva la versión anterior.

### MAN-07 — Traefik v3.0 podría actualizarse a `v3` (tag flotante de major version)

**Archivo:** `modules/install_traefik.sh`, línea 75

`traefik:v3.0` recibirá parches de seguridad del minor `3.0.x` pero no de `3.1+`. Si el objetivo es mantenerse en la línea v3 con actualizaciones de seguridad, considerar `traefik:v3` (que sigue el último minor estable de la serie v3) o pinear a `traefik:v3.4` (última versión estable actual) como variable configurable.

---

## 7. CI/CD

### CI-01 — GitHub Actions: ShellCheck y shfmt ya configurados ✅

**Archivo:** `.github/workflows/shell-lint.yml`

El workflow cubre `modules/*.sh` y `main.sh` con ShellCheck y shfmt. Funciona sobre `push` y `pull_request`.

**Mejora pendiente:** `install_docker.txt` no es procesado por el workflow (correcto, pero es otro argumento para eliminarlo). Si se añaden scripts en subdirectorios futuros, el glob `modules/*.sh` no los capturaría.

### CI-02 — Falta: test de integración en contenedor/VM

No hay ningún test funcional que verifique que los módulos se ejecutan sin errores en un entorno limpio de Debian 13. ShellCheck detecta errores estáticos pero no de runtime.

**Solución propuesta:** Añadir un workflow de GitHub Actions con Docker-in-Docker (DinD) o una imagen base de Debian 13 que ejecute los módulos en modo `--dry-run` (una vez implementado), o al menos que cargue todos los módulos sin ejecutarlos para detectar errores de parsing.

### CI-03 — Falta: ansible-lint (para futuro módulo Ansible)

Si el proyecto evoluciona para incluir playbooks de Ansible, añadir `ansible-lint` al workflow de CI.

### CI-04 — Considerar añadir `hadolint` si se generan Dockerfiles

Actualmente no hay Dockerfiles, pero si se añaden en el futuro, `hadolint` debería integrarse en el CI.

---

## 8. Checklist priorizado de tareas

> Prioridades: 🔴 Alta (afecta funcionalidad/seguridad) / 🟡 Media (calidad/mantenibilidad) / 🟢 Baja (mejoras opcionales)
> Esfuerzo: S < 1h / M 1–4h / L 4h+

| # | Tarea | Archivo(s) | Prio | Esfuerzo | Depende de |
|---|---|---|---|---|---|
| 1 | Eliminar `install_docker.txt` del repositorio | `modules/install_docker.txt` | 🔴 | S | — |
| 2 | Eliminar o integrar `ai_studio_code` en `README.md` | `ai_studio_code` | 🔴 | S | #20 |
| 3 | Corregir `cd "$INSTALL_DIR"` con `pushd`/`popd` en `install_traefik.sh` y `update_traefik.sh` | `modules/install_traefik.sh:185`, `modules/update_traefik.sh:16` | 🔴 | S | — |
| 4 | Pinear imagen de Portainer a versión semántica y exponerla como variable | `modules/install_traefik.sh:99`, `modules/update_traefik.sh:30` | 🔴 | S | — |
| 5 | Eliminar IPs estáticas hardcodeadas de la red Docker proxy | `modules/install_traefik.sh:80,105,122` | 🔴 | S | — |
| 6 | Eliminar `version: "3.8"` del heredoc de `docker-compose.yml` | `modules/install_traefik.sh:71` | 🔴 | S | — |
| 7 | Mover `create_admin_user` fuera de `secure_server()` al nivel de módulo | `modules/secure_server.sh:217-257` | 🔴 | S | — |
| 8 | Mover `create_docker_user` fuera de `install_docker()` al nivel de módulo | `modules/install_docker.sh:49-71` | 🔴 | S | — |
| 9 | Corregir `detect_debian_version`: añadir comillas, validar campos, usar expansión de parámetro | `modules/common.sh:47-48` | 🔴 | S | — |
| 10 | Validar que `/var/log` existe antes de `touch "$LOG_FILE"`, con fallback a `/tmp` | `main.sh:30-31` | 🔴 | S | — |
| 11 | Añadir `set -o pipefail` a `main.sh` | `main.sh:9` | 🔴 | S | — |
| 12 | Escribir nueva `sshd_config` en archivo temporal, validar con `sshd -t -f` antes de reemplazar | `modules/secure_server.sh:87-126` | 🔴 | M | — |
| 13 | Establecer `AllowAgentForwarding no` y `AllowTcpForwarding no` en `sshd_config` generado | `modules/secure_server.sh:108-109` | 🔴 | S | — |
| 14 | Añadir `unset traefik_password` tras generar `traefik_auth` | `modules/install_traefik.sh:65` | 🔴 | S | — |
| 15 | Añadir permisos restrictivos a `$INSTALL_DIR` y archivos de configuración generados | `modules/install_traefik.sh` | 🔴 | S | — |
| 16 | Añadir `-r` a todos los `read -p` sin flag `-r` | Todos los módulos | 🟡 | S | — |
| 17 | Centralizar `INSTALL_DIR` como constante en `common.sh` | `modules/common.sh`, `modules/install_traefik.sh:17`, `modules/update_traefik.sh:7` | 🟡 | S | — |
| 18 | Reemplazar patrón `check_error $?` por `comando || error "msg"` en todos los módulos | Todos los módulos | 🟡 | M | — |
| 19 | Añadir `SCRIPT_VERSION` en `common.sh` y mostrarla en el menú y los logs | `modules/common.sh`, `main.sh` | 🟡 | S | — |
| 20 | Crear `README.md` con instrucciones de uso, prerrequisitos y estructura del proyecto | `README.md` (nuevo) | 🟡 | M | — |
| 21 | Crear `.gitignore` (`.env`, `acme.json`, `*.bak`, backups locales) | `.gitignore` (nuevo) | 🟡 | S | — |
| 22 | Solicitar `destemail` de fail2ban de forma interactiva o desde variable de entorno | `modules/secure_server.sh:143` | 🟡 | S | — |
| 23 | Eliminar `"experimental": false` de `daemon.json` (redundante) | `modules/install_docker.sh:86` | 🟡 | S | — |
| 24 | Añadir validación de resolución DNS de subdominios antes de configurar Let's Encrypt | `modules/install_traefik.sh:45-50` | 🟡 | M | — |
| 25 | Añadir soporte de flags CLI básicos (`--help`, número de opción) a `main.sh` | `main.sh` | 🟡 | M | — |
| 26 | Añadir soporte de archivo `.env` opcional para preconfiguración no interactiva | `main.sh`, todos los módulos | 🟡 | L | #25 |
| 27 | Evaluar socket proxy (Tecnativa/docker-socket-proxy) como alternativa a montar `docker.sock` en Traefik | `modules/install_traefik.sh:85` | 🟡 | L | — |
| 28 | Pinear imagen de Traefik a versión minor explícita y exponerla como variable | `modules/install_traefik.sh:75` | 🟢 | S | — |
| 29 | Añadir workflow de CI con test de integración básico (carga de módulos sin ejecución en imagen Debian 13) | `.github/workflows/` | 🟢 | M | — |
| 30 | Corregir indentación inconsistente en bloque `if DEBIAN_VERSION` en `secure_server.sh` | `modules/secure_server.sh:165-177` | 🟢 | S | — |

---

*Última actualización: 2026-03-28*
