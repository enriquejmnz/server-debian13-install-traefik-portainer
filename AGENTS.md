# AGENTS.md

Guía completa para desarrolladores humanos y agentes de IA que trabajen en este repositorio.
Un agente puede empezar a contribuir leyendo solo este archivo.

---

## 1. Descripción del proyecto

**`server-debian13-install-traefik-portainer`** es un instalador modular para configurar un servidor Debian. **Bash está validado en Debian 12 y Debian 13 en VMs reales. Ansible está implementado con Molecule + lint, pendiente de validación en VM real.**

- **Hardening de seguridad**: UFW, fail2ban (backend systemd), SSH endurecido, límites del sistema, auditd, actualizaciones automáticas
- **Docker Engine**: instalación desde repositorio oficial, daemon.json reforzado, usuario de gestión opcional
- **Traefik v3 + Portainer CE**: reverse proxy con TLS automático (Let's Encrypt) y panel de gestión de contenedores; versiones desde `versions.env` compartido entre Bash y Ansible

**Stack tecnológico:**
- Bash 5 (scripts de instalación)
- Docker Engine + Docker Compose plugin
- Traefik v3 (reverse proxy)
- Portainer CE (gestión de contenedores)
- Ansible (implementado, **pendiente de validación en VM real**)
- GitHub Actions (CI con ShellCheck + shfmt + ansible-lint + Molecule)

**Objetivo**: permitir configurar un servidor Debian seguro con proxy inverso TLS en menos de 30 minutos.

> **Estado de soporte hoy**
>
> - **Bash / Debian 12 y 13**: ✅ **Validado** en VMs reales
> - **Ansible / Debian 12 y 13**: ⏳ Implementado con Molecule + lint, pendiente de validación en VM real
> - **Ubuntu Server**: **no soportado actualmente**
>
> La fuente de verdad para soporte y roadmap es **[`PLATFORM-SUPPORT.md`](PLATFORM-SUPPORT.md)**.

---

## 2. Estructura del repositorio

```
server-debian13-install-traefik-portainer/
│
├── .github/
│   └── workflows/
│       ├── shell-lint.yml        # CI: ShellCheck + shfmt en cada push/PR
│       ├── ansible-lint.yml      # CI: ansible-lint en cada push/PR
│       └── molecule.yml          # CI: Molecule tests para todos los roles
│
├── .shellcheckrc                 # Excepciones globales de ShellCheck
│                                 #   SC1090/1091: source dinámico
│                                 #   SC2034: vars usadas en otros archivos
│                                 #   SC2154: vars definidas en otros archivos
│
├── modules/                      # Módulos Bash — uno por función principal
│   ├── common.sh                 # Variables globales, funciones log/warn/error, validadores
│   ├── secure_server.sh          # Hardening: UFW, SSH, fail2ban, límites, auditd, usuario admin
│   ├── install_docker.sh         # Docker Engine desde repositorio oficial + daemon.json
│   ├── install_traefik.sh        # Traefik + Portainer via Docker Compose
│   └── update_traefik.sh         # Actualizar imágenes y limpiar las antiguas
│
├── main.sh                       # Punto de entrada: carga módulos, menú interactivo
│
├── ansible/                      # Proyecto Ansible (implementado; soporta Debian 12/13 y valida más fuerte hoy en Debian 13)
│   ├── ansible.cfg
│   ├── requirements.yml
│   ├── inventory/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       └── all/
│   │           ├── vars.yml      # Variables no sensibles
│   │           └── vault.yml     # Secrets (cifrado con ansible-vault)
│   ├── playbooks/
│   │   ├── site.yml              # Playbook maestro
│   │   ├── hardening.yml
│   │   ├── docker.yml
│   │   ├── traefik_portainer.yml
│   │   └── update.yml
│   └── roles/
│       ├── common/
│       ├── security/
│       ├── docker/
│       ├── traefik_portainer/
│       └── update/
│
├── ANSIBLE-MIGRATION.md          # Arquitectura Ansible completa y plan de migración
├── AGENTS.md                     # Este archivo
├── CONTRIBUTING.md               # Guía de contribución y linting local
└── README.md                     # Descripción del proyecto, instalación y badges CI
```

---

## 3. Guía de los Scripts Bash

### 3.1 Flujo de ejecución

```
main.sh
  │
  ├─► Carga modules/common.sh          (variables globales + funciones)
  ├─► Carga modules/secure_server.sh   (define función secure_server)
  ├─► Carga modules/install_docker.sh  (define función install_docker)
  ├─► Carga modules/install_traefik.sh (define función install_traefik_portainer)
  ├─► Carga modules/update_traefik.sh  (define función update_traefik_portainer)
  │
  ├─► Inicializa LOG_FILE (/var/log/server-setup.log)
  ├─► Verifica root (id -u == 0)
  ├─► detect_debian_version()
  │
  └─► main_loop()
        └─► show_menu() → read choice → process_choice()
              ├── 1 → secure_server()
              ├── 2 → install_docker()
              ├── 3 → install_traefik_portainer()
              ├── 4 → update_traefik_portainer()
              ├── 5 → secure_server + install_docker + install_traefik_portainer
              └── 6 → exit
```

Todos los módulos son **funciones Bash puras** definidas en sus respectivos archivos. El sourcing en `main.sh` las carga en memoria. No existe estado compartido entre módulos salvo las variables de `common.sh`.

### 3.2 Convenciones del código Bash

**Funciones de logging** (definidas en `common.sh`):
```bash
log  "Mensaje informativo"   # Verde  [INFO]  — guardado en $LOG_FILE
warn "Advertencia"           # Amarillo [WARN] — guardado en $LOG_FILE
error "Error fatal"          # Rojo   [ERROR] — guardado en $LOG_FILE + exit 1
```

**Manejo de errores:**
```bash
comando_que_puede_fallar || error "Descripción del error si falla"
```

**Variables de configuración** (en `common.sh`):
```bash
LOG_FILE="/var/log/server-setup.log"   # Único log centralizado
RED, GREEN, YELLOW, NC                 # Colores para terminal
```

**Variables en los módulos** (locales a la función, NO exportadas):
```bash
ssh_port, base_domain, traefik_user    # Obtenidas por read -p (interactivo)
# Nota: INSTALL_DIR está centralizado en common.sh
```

**Colores**: se usan `$GREEN`, `$YELLOW`, `$RED`, `$NC` de `common.sh`. Nunca definir colores en otros módulos.

**Estilo de código** (validado por shfmt `-s -i 2`):
- Indentación: 2 espacios
- Sin tabs
- Comillas dobles para variables: `"$variable"` (no `$variable`)
- `[[ ]]` para condiciones (no `[ ]`)
- Arrays: `("elemento1" "elemento2")`

### 3.3 Cómo añadir un nuevo módulo

1. Crear `modules/nuevo_modulo.sh` con esta estructura:
```bash
#!/bin/bash
# modules/nuevo_modulo.sh - Descripción del módulo

nuevo_modulo_function() {
    log "Iniciando nuevo módulo..."

    # ... lógica del módulo ...

    log "Nuevo módulo completado con éxito"
}
```

2. El módulo se cargará automáticamente en `main.sh` por el glob `modules/*.sh`.

3. Añadir la opción al menú en `main.sh`:
   - En `show_menu()`: añadir línea `echo "N. Nuevo módulo"`
   - En `process_choice()`: añadir `N) nuevo_modulo_function ;;`

4. Actualizar los checks de CI:
   - El workflow `shell-lint.yml` ya cubre `modules/*.sh` automáticamente
   - Ejecutar `shellcheck modules/nuevo_modulo.sh` localmente antes de hacer push

### 3.4 Variables configurables

Los scripts obtienen su configuración mediante `read -p` (interactivo) o desde un archivo `.env` (no interactivo). Ver [`example.env`](example.env) para el formato exacto.

Variables importantes:

| Variable | Dónde se define | Valor por defecto | Descripción | Env var para .env |
|---|---|---|---|---|
| `LOG_FILE` | `common.sh` | `/var/log/server-setup.log` | Archivo de log centralizado | — |
| `SCRIPT_VERSION` | `common.sh` | `1.0.0` | Versión del script | — |
| `INSTALL_DIR` | `common.sh` (centralizado) | `/opt/traefik-portainer` | Directorio de instalación | — |
| `ssh_port` | `secure_server.sh` | `22` | Puerto SSH | `SSH_PORT` |
| `disable_password` | `secure_server.sh` | `s` (sí) | Deshabilitar auth por contraseña | `DISABLE_PASSWORD_AUTH` |
| `admin_user` | `secure_server.sh` | — (requerido) | Usuario administrador | `ADMIN_USER` |
| `admin_ssh_key` | `secure_server.sh` | vacío | Clave pública SSH del admin | `ADMIN_SSH_KEY` |
| `docker_user` | `install_docker.sh` | vacío (omitir) | Usuario para grupo docker | `DOCKER_USER` |
| `base_domain` | `install_traefik.sh` | — (requerido) | Dominio base | `BASE_DOMAIN` |
| `traefik_subdomain` | `install_traefik.sh` | `traefik` | Subdominio Traefik | `TRAEFIK_SUBDOMAIN` |
| `portainer_subdomain` | `install_traefik.sh` | `portainer` | Subdominio Portainer | `PORTAINER_SUBDOMAIN` |
| `email_admin` | `install_traefik.sh` | — (requerido) | Email Let's Encrypt | `EMAIL_ADMIN` |
| `traefik_user` | `install_traefik.sh` | — (requerido) | Usuario basicAuth Traefik | `TRAEFIK_USER` |
| `traefik_password` | `install_traefik.sh` | — (requerido) | Contraseña basicAuth Traefik | `TRAEFIK_PASSWORD` |
| `timezone` | `secure_server.sh` | `UTC` | Zona horaria del servidor | `TIMEZONE` |

### 3.6 Modo no interactivo y CLI

El script soporta flags de línea de comandos para ejecución sin intervención manual:

```bash
# Ayuda
sudo bash main.sh --help

# Ejecución completa con variables de entorno
sudo bash main.sh --non-interactive --step all

# Solo un paso específico
sudo bash main.sh --non-interactive --step secure

# Con archivo .env personalizado
sudo bash main.sh --non-interactive --step all --env-file /ruta/.env
```

Pasos disponibles: `secure`, `docker`, `traefik`, `update`, `all`.

En modo `--non-interactive`, si falta una variable requerida el script falla con un mensaje claro. Ver [`example.env`](example.env) para la lista completa de variables.

### 3.7 Validación DNS

Antes de instalar Traefik, el script verifica que los subdominios configurados resuelvan a la IP pública del servidor. En modo interactivo permite continuar si DNS aún está propagando; en `--non-interactive` falla si la validación no pasa.

### 3.5 Requisitos de ejecución

- **OS**: Debian 12 (Bookworm) y Debian 13 (Trixie) están soportados en la ruta Bash (validados en VMs reales); Ubuntu no está soportado
- **Usuario**: root (`id -u == 0`) — verificado al inicio de `main.sh`
- **Conectividad**: acceso a internet (descarga de paquetes y GPG keys de Docker)
- **DNS**: dominio base configurado y apuntando al servidor antes de instalar Traefik
- **Ejecución**:
```bash
sudo bash main.sh
# o siendo root:
bash main.sh
```

---

## 4. Guía del Proyecto Ansible

> La variante Ansible ya está implementada, soporta **Debian 12 y Debian 13** con Molecule + lint, pero **pendiente de validación en VM real**. Ubuntu **no** está soportado. Ver `ANSIBLE-MIGRATION.md` para arquitectura y `PLATFORM-SUPPORT.md` para estado real de soporte.

### 4.1 Estructura de roles

Cada role sigue la estructura estándar de Ansible:

```
roles/nombre_role/
├── tasks/
│   ├── main.yml        # Incluye los subtasks con import_tasks (estático)
│   └── *.yml           # Subtasks específicos (packages, ssh, ufw...)
├── handlers/
│   └── main.yml        # Handlers para reinicio de servicios
├── defaults/
│   └── main.yml        # Variables con valores por defecto (baja precedencia)
├── templates/
│   └── *.j2            # Templates Jinja2 para archivos de configuración
└── meta/
    └── main.yml        # Dependencias de otros roles
```

### 4.2 Convenciones de Ansible

**Nombres de tareas**: siempre en inglés, verbo + sustantivo, describen QUÉ hace la tarea:
```yaml
- name: Install security packages        # ✓ correcto
- name: apt install packages             # ✗ incorrecto (no descriptivo)
- name: Ensure SSH config is deployed    # ✓ correcto
```

**Variables**: prefijo del role para evitar colisiones en el namespace global:
```yaml
# role: security
ssh_port: 22
fail2ban_bantime: 3600

# role: docker
docker_user: ""
docker_log_max_size: "10m"

# role: traefik_portainer
# traefik_image y portainer_image se derivan desde versions.env via lookup plugin
```

**Variables sensibles**: siempre con prefijo `vault_` en el archivo vault:
```yaml
vault_traefik_password: "..."    # en vault.yml (cifrado)
traefik_password: "{{ vault_traefik_password }}"  # en vars.yml (referencia)
```

**Handlers**: nombres en formato imperativo, referenciados desde tasks con `notify`:
```yaml
# handlers/main.yml
- name: Restart SSH
  ansible.builtin.systemd:
    name: ssh
    state: restarted

# tasks/ssh.yml
- name: Deploy sshd_config
  ansible.builtin.template:
    src: sshd_config.j2
    dest: /etc/ssh/sshd_config
  notify: Restart SSH
```

**Templates Jinja2**: usar variables del contexto Ansible, no hardcodear valores:
```jinja2
{# sshd_config.j2 #}
Port {{ ssh_port }}
PermitRootLogin no
MaxAuthTries {{ ssh_max_auth_tries | default(3) }}
PasswordAuthentication {{ ssh_password_auth }}
```

### 4.3 Cómo añadir un nuevo role

```bash
# 1. Crear estructura:
mkdir -p ansible/roles/nuevo_role/{tasks,handlers,defaults,templates,meta}

# 2. Crear archivos base:
cat > ansible/roles/nuevo_role/tasks/main.yml << 'EOF'
---
- name: Include specific tasks
  ansible.builtin.import_tasks: subtask.yml
EOF

cat > ansible/roles/nuevo_role/defaults/main.yml << 'EOF'
---
# Variables por defecto del role nuevo_role
nuevo_role_param: "valor_por_defecto"
EOF

cat > ansible/roles/nuevo_role/meta/main.yml << 'EOF'
---
galaxy_info:
  role_name: nuevo_role
  author: local
  min_ansible_version: "2.14"
dependencies:
  - role: common
EOF
```

3. Añadir el role al playbook correspondiente en `ansible/playbooks/`.
4. Declarar todas las variables con defaults en `defaults/main.yml`.
5. Ejecutar `ansible-lint ansible/roles/nuevo_role/` antes de hacer push.

### 4.4 Cómo usar ansible-vault para secrets

```bash
# Cifrar el archivo vault completo (primera vez):
ansible-vault encrypt ansible/inventory/group_vars/all/vault.yml

# Editar valores del vault:
ansible-vault edit ansible/inventory/group_vars/all/vault.yml

# Ver contenido del vault (solo para verificar):
ansible-vault view ansible/inventory/group_vars/all/vault.yml

# Cifrar un valor individual para pegar en vars.yml:
ansible-vault encrypt_string 'mi_password_secreta' --name 'vault_traefik_password'

# Ejecutar playbook con vault (prompt de contraseña):
ansible-playbook ansible/playbooks/site.yml --ask-vault-pass

# Ejecutar con archivo de contraseña (para CI/CD):
echo "mi_vault_password" > ~/.vault_pass && chmod 600 ~/.vault_pass
ansible-playbook ansible/playbooks/site.yml --vault-password-file ~/.vault_pass
```

**NUNCA** hacer commit de `vault.yml` sin cifrar. Añadir al pre-commit hook si es necesario.

---

## 5. Reglas de coexistencia scripts ↔ Ansible

### 5.1 Ubicación de archivos

- Scripts Bash: en `modules/` — **no mover**
- Ansible: todo bajo `ansible/` — paths relativos siempre desde esa carpeta
- Documentación: en la raíz del repositorio

### 5.2 Sincronía de variables

Los valores por defecto deben mantenerse en sincronía entre los dos sistemas. La fuente de verdad es **la documentación** (sección 6 de este archivo). Cuando se cambia un valor por defecto:

1. Actualizar el script Bash (`modules/common.sh` o el módulo correspondiente)
2. Actualizar `ansible/inventory/group_vars/all/vars.yml`
3. Actualizar la tabla de variables en la sección 6 de este archivo
4. Documentar el cambio en el commit

### 5.3 Cuándo usar scripts vs Ansible

| Criterio | Scripts Bash | Ansible |
|---|---|---|
| Número de servidores | 1 servidor | 2+ servidores |
| Acceso SSH disponible desde máquina control | No requerido | Requerido |
| Ansible instalado en máquina de control | No requerido | Requerido |
| Instalación inicial desde cero | ✓ Ideal | ✓ También funciona |
| Cambios incrementales (solo SSH, solo UFW) | Difícil | ✓ Ideal (--tags) |
| Dry-run antes de aplicar | No disponible | ✓ --check --diff |
| Auditoría de cambios | Solo log | ✓ Diff de templates |
| Secrets cifrados | No | ✓ ansible-vault |
| Equipo de más de 1 persona | Funciona | ✓ Recomendado |

### 5.4 Regla de oro

> Si puedes usar Ansible, úsalo. Si no puedes (sin máquina de control, instalación en bare metal sin red), usa los scripts Bash.

---

## 6. Variables de entorno y secrets

Tabla completa de todas las variables configurables del proyecto:

| Variable | Requerida | Valor por defecto | Descripción | Scripts | Ansible |
|---|---|---|---|---|---|
| `SSH_PORT` / `ssh_port` | No | `22` | Puerto SSH del servidor | `secure_server.sh` (read) | `inventory/group_vars/all/vars.yml` |
| `ADMIN_USER` / `admin_user` | Sí | — | Usuario administrador (sudo + sshusers) | `secure_server.sh` (read) | `vars.yml` |
| `admin_ssh_public_key` | No (recomendado) | — | Clave pública SSH del admin | No soportado | `vault.yml` |
| `SSH_PASSWORD_AUTH` / `ssh_password_auth` | No | `"no"` | Habilitar auth por contraseña SSH | `secure_server.sh` (read) | `vars.yml` |
| `DOCKER_USER` / `docker_user` | No | vacío | Usuario añadido al grupo docker | `install_docker.sh` (read) | `vars.yml` |
| `BASE_DOMAIN` / `base_domain` | Sí (Traefik) | — | Dominio base (ej: example.com) | `install_traefik.sh` (read) | `vars.yml` |
| `TRAEFIK_SUBDOMAIN` / `traefik_subdomain` | No | `traefik` | Subdominio para el dashboard de Traefik | `install_traefik.sh` (read) | `vars.yml` |
| `PORTAINER_SUBDOMAIN` / `portainer_subdomain` | No | `portainer` | Subdominio para Portainer | `install_traefik.sh` (read) | `vars.yml` |
| `LETSENCRYPT_EMAIL` / `letsencrypt_email` | Sí (Traefik) | — | Email para notificaciones Let's Encrypt | `install_traefik.sh` (read) | `vault.yml` |
| `TRAEFIK_USER` / `traefik_user` | Sí (Traefik) | — | Usuario para basicAuth del dashboard Traefik | `install_traefik.sh` (read) | `vault.yml` |
| `TRAEFIK_PASSWORD` / `traefik_password` | Sí (Traefik) | — | Contraseña basicAuth Traefik (texto plano, se hashea con htpasswd) | `install_traefik.sh` (read) | `vault.yml` |
| `INSTALL_DIR` / `install_dir` | No | `/opt/traefik-portainer` | Directorio de instalación del stack | `common.sh` (centralizado) | `vars.yml` |
| `LOG_FILE` | No | `/var/log/server-setup.log` | Archivo de log de los scripts | `common.sh` | N/A (Ansible usa su propio log) |
| `TRAEFIK_IMAGE` / `traefik_image` | No | Derivada de `TRAEFIK_VERSION` | Imagen Docker de Traefik | Derivada en `modules/common.sh` | Derivada en defaults de `traefik_portainer` y `update` |
| `PORTAINER_VERSION` | No | `2.39.3` | Versión canónica de Portainer | `modules/versions.env` | `ansible/inventory/group_vars/all/versions.env` |
| `TRAEFIK_VERSION` | No | `v3.7.4` | Versión canónica de Traefik | `modules/versions.env` | `ansible/inventory/group_vars/all/versions.env` |
| `PORTAINER_IMAGE` / `portainer_image` | No | Derivada de `PORTAINER_VERSION` | Imagen Docker de Portainer | Derivada en `modules/common.sh` | Derivada en defaults de `traefik_portainer` y `update` |
| `DOCKER_CLEAN_INSTALL` / `docker_clean_install` | No | `false` | Remove /var/lib/docker and /var/lib/containerd on Docker install | Not in Bash | `install.yml` |
| `fail2ban_bantime` | No | `3600` (segundos) | Tiempo de ban en fail2ban | Hardcoded en `secure_server.sh` | `vars.yml` |
| `fail2ban_maxretry` | No | `3` | Intentos máximos antes de ban (jail SSH) | Hardcoded en `secure_server.sh` | `vars.yml` |
| `proxy_subnet` | No | `172.18.0.0/16` | Subnet de la red Docker "proxy" | Hardcoded en `install_traefik.sh` | `vars.yml` |
| `DOCKER_CLEAN_INSTALL` / `docker_clean_install` | No | `false` | Remove /var/lib/docker and /var/lib/containerd on Docker install | Not in Bash | `install.yml` |

**Nota sobre versiones**: Las versiones de Traefik y Portainer se definen en `modules/versions.env` (Bash) y `ansible/inventory/group_vars/all/versions.env` (Ansible). Cada sistema tiene su propio archivo — ambos se actualizan manualmente al cambiar de versión. La opción 4 del menú (update) **no busca nuevas versiones** en Docker Hub, solo verifica si el digest de la imagen pinada cambió (ej: security patch de la misma versión).

---

## 7. CI/CD

### 7.1 Workflow actual: `shell-lint.yml`

Archivo: `.github/workflows/shell-lint.yml`

**Triggers**: push y pull_request en cualquier rama.

**Jobs**:
1. **ShellCheck** — analiza `modules/*.sh` y `main.sh` buscando errores, advertencias y malas prácticas
2. **shfmt** — verifica que el formateo sea consistente con `-s -i 2` (simplified, 2 espacios)

**Excepciones** configuradas en `.shellcheckrc`:
- `SC1090`, `SC1091` — source dinámico (carga de módulos por glob)
- `SC2034` — variables definidas en un archivo y usadas en otro
- `SC2154` — variables referenciadas sin asignación visible (definidas en otro módulo)

### 7.2 Workflow: `ansible-lint.yml`

Archivo: `.github/workflows/ansible-lint.yml`

**Triggers**: push y pull_request en cualquier rama.

**Jobs**:
1. **ansible-lint** — analiza los playbooks y roles Ansible usando la acción oficial `ansible/ansible-lint`

Configuración de reglas en `.ansible-lint` en la raíz del repositorio.

### 7.3 Workflow: `molecule.yml`

Archivo: `.github/workflows/molecule.yml`

**Triggers**: push y pull_request en cualquier rama.

**Jobs**:
1. **molecule** — ejecuta tests Molecule para los 5 roles Ansible (common, security, docker, traefik_portainer, update)

Cada role tiene su propio escenario Molecule bajo `ansible/roles/{role}/molecule/default/`.

**Ejecutar localmente:**
```bash
cd ansible/roles/{role} && ANSIBLE_CONFIG=../../ansible.cfg molecule test
```

### 7.4 Pasar los checks localmente

```bash
# === Scripts Bash ===

# ShellCheck (instalar: sudo apt install shellcheck o brew install shellcheck):
shellcheck modules/*.sh main.sh

# shfmt (instalar desde https://github.com/mvdan/sh/releases):
shfmt -d -s -i 2 modules/*.sh main.sh   # solo muestra diff
shfmt -w -s -i 2 modules/*.sh main.sh   # aplica cambios

# === Ansible ===

# ansible-lint (instalar: pip install ansible-lint):
ansible-lint ansible/playbooks/site.yml
ansible-lint ansible/roles/security/

# Syntax check de playbooks:
ansible-playbook ansible/playbooks/site.yml --syntax-check
```

---

## 8. Guía rápida de comandos

| Acción | Comando (scripts Bash) | Comando (Ansible) |
|---|---|---|
| Instalación completa no interactiva | `sudo bash main.sh --non-interactive --step all` | `ansible-playbook ansible/playbooks/site.yml --ask-vault-pass` |
| Solo hardening | `sudo bash main.sh` → opción 1 | `ansible-playbook ansible/playbooks/hardening.yml --ask-vault-pass` |
| Solo Docker | `sudo bash main.sh` → opción 2 | `ansible-playbook ansible/playbooks/docker.yml` |
| Solo Traefik + Portainer | `sudo bash main.sh` → opción 3 | `ansible-playbook ansible/playbooks/traefik_portainer.yml --ask-vault-pass` |
| Actualizar contenedores | `sudo bash main.sh` → opción 4 | `ansible-playbook ansible/playbooks/update.yml` |
| Solo hardening (CLI) | `sudo bash main.sh --non-interactive --step secure --env-file .env` | — |
| Ver ayuda | `sudo bash main.sh --help` | — |
| Dry-run (ver cambios) | No disponible | `ansible-playbook ... --check --diff` |
| Solo SSH config | No disponible directamente | `ansible-playbook ... --tags ssh --check --diff` |
| Solo UFW | No disponible directamente | `ansible-playbook ... --tags ufw` |
| Solo fail2ban | No disponible directamente | `ansible-playbook ... --tags fail2ban` |
| Aplicar a un servidor | `ssh root@server "bash main.sh"` | `ansible-playbook ... --limit myserver` |
| Aplicar a grupo staging | No soportado | `ansible-playbook ... --limit staging` |
| Verificar conectividad | `ssh root@server "echo ok"` | `ansible all -m ping` |
| Ver log de instalación | `cat /var/log/server-setup.log` | `ansible-playbook ... -v` (verbose) |
| Linting scripts | `shellcheck modules/*.sh main.sh` | `ansible-lint ansible/playbooks/site.yml` |
| Formateo scripts | `shfmt -w -s -i 2 modules/*.sh main.sh` | N/A (YAML tiene su propio estilo) |

---

## 9. Cómo hacer cambios seguros

### 9.1 Checklist pre-cambio

Antes de modificar cualquier script o playbook que se ejecute en producción:

- [ ] ¿Tienes acceso de rollback al servidor? (acceso físico o consola KVM/VNC)
- [ ] ¿Tienes una sesión SSH activa separada (distinta a la que ejecutará el cambio)?
- [ ] ¿Has hecho backup de los archivos de configuración afectados?
- [ ] ¿Has probado el cambio en staging o VM local primero?
- [ ] ¿Has ejecutado `--check --diff` (Ansible) o revisado manualmente el script (Bash)?
- [ ] ¿El cambio es reversible sin reinstalar?

### 9.2 Comandos de backup

```bash
# Backup de configuraciones críticas:
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)
cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak.$(date +%Y%m%d_%H%M%S)
cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%Y%m%d_%H%M%S)

# Backup del stack Traefik/Portainer:
cp -r /opt/traefik-portainer /opt/traefik-portainer-backup-$(date +%Y%m%d_%H%M%S)

# Guardar estado de contenedores:
docker ps -a > /tmp/containers-before.txt
docker images > /tmp/images-before.txt
```

### 9.3 Comandos de rollback

```bash
# Rollback SSH (si quedas sin acceso, usar consola):
cp /etc/ssh/sshd_config.bak.YYYYMMDD_HHMMSS /etc/ssh/sshd_config
sshd -t && systemctl restart ssh

# Rollback fail2ban:
cp /etc/fail2ban/jail.local.bak.YYYYMMDD_HHMMSS /etc/fail2ban/jail.local
systemctl restart fail2ban

# Rollback Docker daemon:
cp /etc/docker/daemon.json.bak.YYYYMMDD_HHMMSS /etc/docker/daemon.json
systemctl restart docker

# Rollback Traefik/Portainer (versión anterior):
cd /opt/traefik-portainer
docker compose down
cd ..
mv traefik-portainer traefik-portainer-failed
mv traefik-portainer-backup-YYYYMMDD_HHMMSS traefik-portainer
cd traefik-portainer
docker compose up -d

# Rollback UFW:
ufw --force reset   # CUIDADO: elimina todas las reglas
ufw allow 22/tcp
ufw --force enable
```

### 9.4 Verificación post-cambio

```bash
# Verificar SSH:
ssh -p $SSH_PORT admin@servidor "echo 'SSH OK'"
sshd -t  # validar configuración sin reiniciar

# Verificar firewall:
ufw status verbose

# Verificar fail2ban:
systemctl status fail2ban
fail2ban-client status sshd

# Verificar Docker:
docker --version
docker compose version
docker ps
systemctl status docker

# Verificar Traefik + Portainer:
docker compose -f /opt/traefik-portainer/docker-compose.yml ps
curl -I https://traefik.midominio.com
curl -I https://portainer.midominio.com

# Verificar certificados TLS:
openssl s_client -connect traefik.midominio.com:443 -brief 2>/dev/null | head -5
```

---

## 10. Convenciones de git

### 10.1 Ramas

| Rama | Propósito |
|---|---|
| `main` | Rama principal, siempre estable. NO pushear directamente. |
| `feat/*` | Nuevas funcionalidades (ej: `feat/ansible-security-role`) |
| `fix/*` | Correcciones de bugs (ej: `fix/fail2ban-debian13-backend`) |
| `chore/*` | Tareas de mantenimiento (ej: `chore/update-dependencies`) |
| `docs/*` | Solo documentación (ej: `docs/add-agents-md`) |
| `refactor/*` | Refactoring sin cambio de comportamiento |
| `test/*` | Añadir o mejorar tests |

### 10.2 Conventional Commits

Formato: `tipo(scope): descripción corta en imperativo`

| Tipo | Cuándo usarlo |
|---|---|
| `feat` | Añade una nueva funcionalidad |
| `fix` | Corrige un bug |
| `chore` | Mantenimiento, actualización de deps, CI config |
| `docs` | Solo cambios en documentación |
| `style` | Formateo, puntuación (sin cambios lógicos) |
| `refactor` | Refactoring que no añade features ni corrige bugs |
| `test` | Añadir o modificar tests |
| `ci` | Cambios en workflows de CI/CD |

**Ejemplos correctos:**
```
feat(traefik): pin container image versions instead of using latest
fix(fail2ban): add systemd backend config for Debian 13
chore(ci): add ansible-lint workflow
docs(agents): add complete repository guide for AI agents
refactor(docker): extract daemon.json to template file
ci(shell-lint): upgrade shellcheck-action to v1
```

**Ejemplos incorrectos:**
```
Fixed stuff                     ✗ (no tipo, no descripción)
feat: updated things            ✗ (pasado, no imperativo)
WIP                             ✗ (no informativo)
fix(traefik): fix traefik       ✗ (redundante)
```

### 10.3 Pull Requests

Descripción mínima de un PR:

```markdown
## ¿Qué hace este PR?
Descripción en 1-3 líneas.

## ¿Por qué?
Motivación o issue relacionado (#123).

## ¿Cómo probarlo?
Pasos concretos para verificar que funciona.

## Checklist
- [ ] shellcheck pasa sin errores nuevos
- [ ] shfmt no reporta diferencias
- [ ] Probado en VM Debian 13 (si aplica)
- [ ] Documentación actualizada (AGENTS.md, CONTRIBUTING.md)
- [ ] No contiene secrets en texto plano
```

### 10.4 Regla de oro

> **NUNCA** hacer push directo a `main`. Siempre crear una rama, hacer PR, esperar que CI pase.

---

## 11. Errores comunes y soluciones

### Error 1: Script falla con "Este script debe ejecutarse como root"
**Causa**: Se ejecuta sin privilegios root.  
**Solución**: `sudo bash main.sh` o cambiar a root con `sudo -i` primero.

### Error 2: El script falla con errores no manejados
**Causa**: Un comando falla sin usar `comando || error "msg"`.  
**Solución**: Verificar que el módulo usa el patrón actual de manejo de errores (`|| error`), no `check_error()` que fue eliminada de `common.sh`.

### Error 3: ShellCheck falla con SC1090 o SC2154 en CI
**Causa**: Variables o sources definidos en otros archivos que ShellCheck no puede seguir.  
**Solución**: Estas excepciones ya están en `.shellcheckrc`. Si es una variable nueva en `common.sh`, añadir `SC2034` a las excepciones si es necesario (con comentario explicando por qué).

### Error 4: shfmt reporta diferencias después de editar
**Causa**: El editor no respeta la indentación de 2 espacios o añade tabs.  
**Solución**: `shfmt -w -s -i 2 modules/archivo_editado.sh` para auto-formatear.

### Error 5: SSH queda bloqueado después de ejecutar `secure_server`
**Causa**: El puerto SSH configurado difiere del que el firewall permite, o `AllowGroups sshusers` bloquea al usuario actual.  
**Solución**: 
  - Acceder por consola VNC/KVM del servidor
  - `ufw allow $PUERTO_CORRECTO/tcp`
  - Verificar que el usuario está en el grupo sshusers: `usermod -aG sshusers $USUARIO`
  - `sshd -t && systemctl restart ssh`

### Error 6: fail2ban no inicia en Debian 13
**Causa**: fail2ban necesita `backend = systemd` para Debian 13, que usa journald en lugar de archivos de log tradicionales.  
**Solución**: El script ya configura esto. Si falla manualmente, verificar que `/etc/fail2ban/paths-debian.conf` contiene `sshd_backend = systemd`.

### Error 7: Docker no se instala — error de GPG key o repositorio
**Causa**: La key GPG o el repositorio no están disponibles para la versión de Debian.  
**Solución**: 
```bash
# Verificar codename de Debian:
lsb_release -cs
# Si devuelve "trixie", el repositorio Docker debe soportarlo.
# Si hay error de GPG: borrar y recrear:
rm /etc/apt/keyrings/docker.gpg
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

### Error 8: `htpasswd: command not found` al instalar Traefik
**Causa**: `apache2-utils` no está instalado.  
**Solución**: El script lo instala, pero si se ejecuta `install_traefik.sh` directamente sin `main.sh`, ejecutar `apt-get install -y apache2-utils` primero.

### Error 9: Traefik no obtiene certificado TLS (error ACME)
**Causa**: El dominio no apunta a la IP del servidor, o los puertos 80/443 están bloqueados por el ISP/firewall del servidor.  
**Solución**:
```bash
# Verificar que el dominio resuelve correctamente:
dig +short traefik.midominio.com

# Verificar que los puertos están abiertos:
ufw status
# Verificar que los contenedores escuchan:
docker ps
# Ver logs de Traefik:
docker logs traefik
```

### Error 10: `docker compose up -d` falla — subnet ya en uso
**Causa**: La subnet `172.18.0.0/16` configurada en el `docker-compose.yml` ya está asignada a otra red Docker del sistema.  
**Solución**:
```bash
# Ver redes existentes:
docker network ls
docker network inspect proxy

# Si la red existe pero está corrupta, eliminarla:
docker network rm proxy
# Luego volver a ejecutar docker compose up -d
```

### Error 11: Ansible falla — "MODULE FAILURE: No module named 'apt'"
**Causa**: El módulo `python3-apt` no está instalado en el servidor objetivo.  
**Solución**: Añadir a las tareas de `common`:
```yaml
- name: Install python3-apt
  ansible.builtin.raw: apt-get install -y python3-apt
  changed_when: false
```

### Error 12: Ansible vault — "Decryption failed"
**Causa**: La contraseña del vault es incorrecta o se está usando `--ask-vault-pass` con una contraseña equivocada.  
**Solución**: Verificar la contraseña. Si se perdió, el vault no tiene recuperación — recrear los secrets y volver a cifrar.

---

## 12. Roadmap

Lista priorizada de mejoras futuras:

### Alta prioridad

1. **[ ] Consolidar Ansible como camino principal validado** — La implementación existe y Debian 13 tiene la mejor cobertura actual, pero todavía faltan validaciones operativas, sincerar claims de soporte y cerrar drift documental. Ver `ANSIBLE-MIGRATION.md` y `PLATFORM-SUPPORT.md`.

2. **[x] Modo no-interactivo para scripts Bash** — Soportar flags de línea de comandos y variables de entorno para eliminar los `read -p`. Permite usar los scripts en cloud-init y CI sin intervención manual.
   ```bash
   # Ejemplo:
   SSH_PORT=2222 ADMIN_USER=deploy bash main.sh --non-interactive --step=all
   ```

3. **[x] Centralizar versiones de imágenes Docker** — Versiones de Traefik y Portainer en archivos `versions.env` independientes para Bash y Ansible.

4. **[ ] Eliminar IPs estáticas de docker-compose.yml** — Las IPs `172.18.0.2` y `172.18.0.3` no son necesarias. Traefik usa autodiscovery por nombre de contenedor. Simplifica la configuración y evita conflictos.

### Media prioridad

5. **[x] README.md** — Creado con badges de CI, instrucciones de instalación, requisitos, y descripción del proyecto.

6. **[x] CI con Molecule para roles Ansible** — Workflow `molecule.yml` creado y activo. Tests Molecule implementados para los 5 roles.

7. **[ ] Script de rollback automatizado** — `modules/rollback.sh` que restaure backups de SSH, fail2ban y Docker de forma automática. Útil si algo sale mal durante la instalación.

8. **[ ] Validar Debian 12 antes de abrir soporte multi-distribución** — Primero cerrar compatibilidad real entre Debian 12 y Debian 13; recién después evaluar Ubuntu 24.04 LTS. Hoy Ubuntu **no** está soportado.

9. **[ ] Notificaciones de fail2ban por email** — Configurar `mta` y `destemail` en `jail.local` para recibir emails cuando se produzcan bans.

### Baja prioridad

10. **[ ] Traefik con Cloudflare DNS Challenge** — Añadir soporte para el challenge DNS de Cloudflare como alternativa al HTTP challenge, para servidores detrás de NAT o sin puertos 80/443 abiertos.

11. **[ ] Hardening de kernel (sysctl)** — Añadir configuración de `sysctl.conf` para parámetros de red y memoria: `net.ipv4.tcp_syncookies`, `kernel.randomize_va_space`, etc.

12. **[ ] Dashboard de monitorización** — Añadir Grafana + Prometheus + Node Exporter al stack Docker Compose de Traefik/Portainer como servicios opcionales.

13. **[ ] Tests de integración con GitHub Actions** — Usar una VM Debian 13 real (no contenedor) en GitHub Actions para ejecutar los scripts completos y verificar el resultado final.

14. **[ ] Publicar roles en Ansible Galaxy** — Una vez los roles estén maduros, publicarlos en Galaxy para reutilización en otros proyectos.
 los roles estén maduros, publicarlos en Galaxy para reutilización en otros proyectos.
les estén maduros, publicarlos en Galaxy para reutilización en otros proyectos.
