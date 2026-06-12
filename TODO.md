# TODO — server-debian13-install-traefik-portainer

> Estado actual: **Bash validado en Debian 12 y Debian 13 en VMs reales. Ansible implementado con Molecule + lint, pendiente de validación en VM real.**

---

## 1. Resumen del estado actual

El proyecto combina scripts Bash y una variante Ansible para configurar un servidor Debian con Docker, Traefik v3 y Portainer CE.

**Bash** está **validado** en Debian 12 y Debian 13 en VMs reales (opciones 1-5 probadas).
**Ansible** tiene implementación completa + Molecule + lint, pero **no se ha validado en VM real todavía**.

**YA resuelto:**
- `install_docker.txt` y `ai_studio_code` eliminados
- IPs estáticas eliminadas de la red Docker proxy
- Portainer pineado a versión desde `versions.env`
- `version: "3.8"` eliminado del compose
- Funciones anidadas movidas a nivel de módulo
- `detect_debian_version` con comillas, validación y expansión de parámetro
- `LOG_FILE` con fallback seguro a `/tmp`
- `set -o pipefail` en `main.sh`
- `sshd_config` validado con `sshd -t -f` antes de aplicar
- `AllowAgentForwarding no` y `AllowTcpForwarding no`
- `unset traefik_password` tras generar hash
- `INSTALL_DIR` centralizado en `common.sh`
- `set -euo pipefail` añadido en `common.sh`, `main.sh` tiene `set -e` + `pipefail`
- `destemail` de fail2ban configurable vía variable
- `experimental: false` eliminado del daemon.json
- `.gitignore` creado

**Pendiente:**
- ✅ Permisos restrictivos en `$INSTALL_DIR` y configs generados
- ✅ SCRIPT_VERSION en `common.sh`
- ✅ check_error() eliminada (código muerto)
- ✅ Validación DNS de subdominios antes de Let's Encrypt
- ✅ Flags CLI básicos (`--help`, `--non-interactive`, `--step`, `--env-file`)
- ✅ Soporte `.env` para preconfiguración no interactiva
- ✅ echo-e reemplazado por printf en todo el proyecto
- ✅ Variables sin comillas verificadas (sin SC2086)
- ✅ Indentación consistente (shfmt clean)
- ✅ Confirmación de contraseña Traefik (segundo ingreso)
- 🟡 Evaluar docker-socket-proxy como alternativa
- 🟢 CI test de integración básico
- 🟡 Ansible: validación operativa en VM real

---

## 2. Bugs y problemas críticos (Alta prioridad)

### ✅ BUG-00 — Drift documental (resuelto)

`PLATFORM-SUPPORT.md` es la fuente de verdad. Documentación alineada.

### ✅ BUG-01 — IPs estáticas (resuelto)

Red proxy sin IPs fijas ni subnet hardcodeada.

### ✅ BUG-02 — Portainer `:latest` (resuelto)

`PORTAINER_VERSION` en `versions.env`. Bash y Ansible consumen la misma versión canónica.

### ✅ BUG-03 — `cd` sin retorno (resuelto)

Usa subshells `(cd ... && ...)`.

### ✅ BUG-04 — Funciones anidadas (resuelto)

`secure_server_create_admin_user` y `configure_docker_user` a nivel de módulo.

### ✅ BUG-05 — `set -e` inconsistente (resuelto)

`main.sh` tiene `set -e` + `set -o pipefail`. `common.sh` tiene `set -euo pipefail`.

### ✅ BUG-06 — `detect_debian_version` (resuelto)

Usa `${VERSION_ID%%.*}`, valida campos, comillas dobles.

### ✅ BUG-07 — `LOG_FILE` sin validación (resuelto)

`initialize_log_file()` con fallback a `/tmp`.

### ✅ BUG-08 — `install_docker.txt` (resuelto)

Eliminado del repositorio.

### ✅ BUG-09 — `ai_studio_code` (resuelto)

Eliminado del repositorio.

### ✅ BUG-10 — `version: "3.8"` (resuelto)

Eliminado del heredoc.

---

## 3. Mejoras de calidad de código

### ✅ QC-01 — Variables sin comillas
`common.sh` y `main.sh` mejorados. `ufw allow "$ssh_port/tcp"` ya tiene comillas. Sin issues SC2086 en ShellCheck.

### ✅ QC-02 — `check_error $?` antipatrón
`check_error()` eliminada de `common.sh` (código muerto — nunca se llamaba).

### ✅ QC-03 — `set -o pipefail` y `set -u`
✅ `set -o pipefail` en `main.sh`. ✅ `set -euo pipefail` en `common.sh`.

### ✅ QC-04 — `read` sin `-r`
Resuelto de hecho — todos los `read -p` ya incluían `-r`.

### ✅ QC-05 — `echo -e` no portable
Reemplazado por `printf` en todo el proyecto. Colores definidos con `$'...'` en `common.sh`.

### ✅ QC-06 — Indentación inconsistente
Resuelto de hecho — `shfmt` no reporta diferencias en `secure_server.sh`.

---

## 4. Mejoras de seguridad

### ✅ SEC-01 — Contraseña visible en proceso (resuelto)
`unset traefik_password` inmediatamente tras generar el hash.

### ✅ SEC-02 — Permisos en dynamic.yml (resuelto)
Se aplican permisos restrictivos en `$INSTALL_DIR` (750), `docker-compose.yml` (640), `traefik.yml` (640), `dynamic.yml` (600). Y `unset traefik_auth` tras generar el archivo.

### SEC-03 — docker.sock (documentado)
Riesgo conocido. Evaluar socket proxy como mejora futura.

### ✅ SEC-04 — sshd_config validado (resuelto)
Usa `mktemp` + `sshd -t -f` + `install -m 644`. Backup antes de sobreescribir.

### ✅ SEC-05 — AgentForwarding (resuelto)
`AllowAgentForwarding no`, `AllowTcpForwarding no`.

### ✅ SEC-06 — destemail (mejorado)
Configurable vía variable, aunque sigue con `root@localhost` por defecto en jail.local.

### ✅ SEC-07 — experimental: false (resuelto)
Eliminado del daemon.json.

### SEC-08 — Secrets en log (no aplica)
Ya implementado: no se pasan variables sensibles a log. Pendiente añadir comentario explícito donde se usa `traefik_auth`.

---

## 5. Mejoras de usabilidad / modo no-interactivo

### ✅ USA-01 — Flags CLI
`--help`, `--non-interactive`, `--step secure|docker|traefik|update|all`, `--env-file PATH`. Parseo en `main.sh`.

### ✅ USA-02 — Variables de entorno / .env
`.env` file sourced en `main.sh`. `prompt_or_default()` helper en `common.sh` skip ea los prompts si la var ya está definida. `example.env` como referencia.

### ✅ USA-03 — Validación DNS
`dns_validate_subdomain()` en `common.sh`. Se ejecuta tras recolectar vars en `install_traefik.sh`, antes de generar configs. Advierte por subdominio y permite continuar en modo interactivo, pero bloquea en `--non-interactive`.

### USA-04 — Docs sincronizados
✅ Resuelto vía `PLATFORM-SUPPORT.md` como fuente de verdad.

### USA-05 — Sin modo dry-run
Pendiente. No hay `--dry-run`.

---

## 6. Mejoras de mantenibilidad

### ✅ MAN-01 — INSTALL_DIR centralizado (resuelto)
En `common.sh`.

### ✅ MAN-02 — Portainer pineado (resuelto)
vía `versions.env`.

### ✅ MAN-03 — .gitignore (resuelto)
Creado con exclusiones para `.env`, `acme.json`, `*.bak`, vault, etc.

### ✅ MAN-04 — SCRIPT_VERSION
`SCRIPT_VERSION="1.0.0"` añadido en `common.sh`.

### ✅ MAN-05 — ai_studio_code (resuelto)
Eliminado.

### ✅ MAN-06 — install_docker.txt (resuelto)
Eliminado.

### MAN-07 — Traefik pinning
✅ Traefik pineado a `v3.7.4` en `versions.env`.

---

## 7. CI/CD

### ✅ CI-01 — ShellCheck + shfmt
Configurado y activo.

### CI-02 — Test de integración
Pendiente. No hay smoke tests en CI.

### ✅ CI-03 — ansible-lint
Configurado y activo.

### ✅ CI-04 — hadolint (no aplica)
No hay Dockerfiles propios.

---

## 8. Checklist priorizado de tareas

> Prioridades: 🔴 Alta / 🟡 Media / 🟢 Baja
> Esfuerzo: S < 1h / M 1–4h / L 4h+

| # | Tarea | Prio | Esfuerzo | Estado |
|---|---|---|---|---|
| 1 | Eliminar `install_docker.txt` | 🔴 | S | ✅ |
| 2 | Eliminar `ai_studio_code` | 🔴 | S | ✅ |
| 3 | `cd` con subshells en install/update | 🔴 | S | ✅ |
| 4 | Pinear Portainer a versión semántica | 🔴 | S | ✅ |
| 5 | Eliminar IPs estáticas de red Docker | 🔴 | S | ✅ |
| 6 | Eliminar `version: "3.8"` del compose | 🔴 | S | ✅ |
| 7 | Mover `create_admin_user` a nivel módulo | 🔴 | S | ✅ |
| 8 | Mover `create_docker_user` a nivel módulo | 🔴 | S | ✅ |
| 9 | `detect_debian_version` con comillas y validación | 🔴 | S | ✅ |
| 10 | `initialize_log_file` con fallback a /tmp | 🔴 | S | ✅ |
| 11 | `set -o pipefail` en `main.sh` | 🔴 | S | ✅ |
| 12 | `sshd_config` temp + validación sshd -t | 🔴 | M | ✅ |
| 13 | `AllowAgentForwarding no`, `AllowTcpForwarding no` | 🔴 | S | ✅ |
| 14 | `unset traefik_password` | 🔴 | S | ✅ |
| **15** | **Permisos restrictivos en $INSTALL_DIR y configs** | **🔴** | **S** | **✅** |
| 16 | `-r` en todos los `read -p` | 🟡 | S | ✅ (ya estaba) |
| 17 | Centralizar `INSTALL_DIR` en `common.sh` | 🟡 | S | ✅ |
| 18 | Reemplazar `check_error $?` por `comando \|\| error` | 🟡 | M | ✅ (eliminada función muerta) |
| 19 | `SCRIPT_VERSION` en `common.sh` | 🟡 | S | ✅ |
| 20 | Sincronizar docs cuando cambie soporte | 🟡 | S | ✅ |
| 21 | Crear `.gitignore` | 🟡 | S | ✅ |
| 22 | `destemail` de fail2ban configurable | 🟡 | S | ✅ |
| 23 | Eliminar `experimental: false` de daemon.json | 🟡 | S | ✅ |
| 24 | Validación DNS subdominios | 🟡 | M | ✅ |
| 25 | Flags CLI básicos (`--help`, `--non-interactive`, `--step`, `--env-file`) | 🟡 | M | ✅ |
| 26 | Soporte `.env` para preconfiguración | 🟡 | L | ✅ |
| 27 | Evaluar docker-socket-proxy | 🟡 | L | ❌ Pendiente |
| 28 | Pinear Traefik a minor explícita | 🟢 | S | ✅ |
| 29 | CI test de integración básico | 🟢 | M | ❌ Pendiente |
| 30 | Indentación inconsistente en `secure_server.sh` | 🟢 | S | ❌ Pendiente |

---

## 9. Tareas pendientes — Ansible

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 1 | Validación operativa en VM real (Debian 13) | 🟡 | ❌ Pendiente |
| 2 | Template de reglas auditd personalizadas | 🟢 | ❌ Pendiente |
| 3 | Tests de idempotencia en Molecule (converge dos veces) | 🟢 | ❌ Pendiente |
| 4 | Smoke tests en VM real para versiones de imágenes | 🟢 | ❌ Pendiente |
| 5 | Validación operativa Debian 12 en Ansible | 🟡 | ❌ Pendiente |
| 6 | Ubuntu fuera de soporte explícitamente | 🟡 | ✅ |

---

## 10. Última sesión (2026-06-05)

### Completado
- `modules/versions.env` creado para Bash (independiente de Ansible)
- `TRAEFIK_VERSION=v3.7.4` agregado a ambos archivos de versiones
- `modules/common.sh` ya no sourcea rutas Ansible
- Ansible replicó el patrón dinámico de `traefik_version` via lookup plugin
- Molecule: nuevo test `load_traefik_version()`
- `PermitRootLogin` → `prohibit-password`, timezone interactivo con `timedatectl`
- Mensajes de update corregidos

### Bash validado en VM real
- Opción 1 (secure_server) → ✅ OK en Debian 12

### Pendiente
1. ~~Opción 3 (Traefik+Portainer) en Debian 12~~ → ✅ Hecho
2. ~~Opción 4 (update) con versiones pinadas~~ → ✅ Hecho
3. ~~Opción 5 (todo junto) en Debian 13~~ → ✅ Hecho
4. ~~Validar opciones 2-5 en Debian 12~~ → ✅ Hecho
5. Ansible: validación operativa en VM real → ❌ Pendiente
