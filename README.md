# server-debian13-install-traefik-portainer

[![Shell lint](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/shell-lint.yml/badge.svg)](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/shell-lint.yml)
[![Ansible lint](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/ansible-lint.yml/badge.svg)](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/ansible-lint.yml)
[![Molecule Tests](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/molecule.yml/badge.svg)](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/molecule.yml)

Instalador modular para configurar un servidor **Debian** con hardening de seguridad, Docker Engine, Traefik v3 y Portainer CE.

> **Estado real hoy**
>
> - **Bash:** ✅ **Validado** en Debian 12 y Debian 13 en VMs reales
> - **Ansible:** ⏳ Implementado con Molecule + lint, **pendiente de validación en VM real**
> - **Ubuntu Server:** **no soportado actualmente**
>
> Ver detalle en **[PLATFORM-SUPPORT.md](PLATFORM-SUPPORT.md)**.

---

## ¿Qué hace?

En menos de 30 minutos, este proyecto configura un servidor Debian con:

- **Hardening de seguridad** — UFW, fail2ban (backend systemd), SSH endurecido, limits del sistema, auditd y actualizaciones automáticas
- **Docker Engine** — Instalación desde el repositorio oficial, daemon.json reforzado (logging, ulimits, icc=false)
- **Traefik v3** — Reverse proxy con TLS automático vía Let's Encrypt, dashboard protegido con basicAuth
- **Portainer CE** — Panel web para gestión de contenedores Docker

Disponible en dos variantes:

| Variante | Cuándo usarla |
|---|---|
| **Scripts Bash** (`main.sh`) | Instalación inicial rápida, un solo servidor, sin Ansible instalado |
| **Ansible** (`ansible/`) | Múltiples servidores, cambios incrementales, CI/CD, equipos |

---

## Requisitos

### Para los scripts Bash

- **Sistema operativo**: Debian 12 (Bookworm) o Debian 13 (Trixie)
- **Usuario**: root
- **Conectividad**: acceso a internet (para descargar paquetes y GPG keys)
- **DNS**: dominio base apuntando a la IP del servidor (solo para instalar Traefik)

### Para Ansible

Todo lo anterior en servidores Debian objetivo, más:

- **Máquina de control** con Python 3 y Ansible >= 2.14
- **Acceso SSH** desde la máquina de control a los servidores objetivo
- **Colecciones Galaxy**: `community.general`, `community.docker`, `ansible.posix`

> **Importante**: la ruta Ansible soporta Debian 12/13 con guards explícitos y Molecule puede ejecutarse sobre ambas versiones, pero **aún no se ha validado en VM real**. Ubuntu no está soportado.

---

## Instalación rápida (scripts Bash)

```bash
# Clonar el repositorio en el servidor:
git clone https://github.com/tu-usuario/server-debian13-install-traefik-portainer.git
cd server-debian13-install-traefik-portainer

# Ejecutar como root (interactivo):
sudo bash main.sh

# O modo no interactivo con archivo .env:
sudo bash main.sh --non-interactive --step all
```

Si ejecutás `main.sh` sobre Ubuntu u otra distro no soportada, el instalador corta al inicio con un error claro antes de tocar paquetes o servicios.

### Modo interactivo

El menú interactivo ofrece las siguientes opciones:

```
╔══════════════════════════════════════════════╗
║    CONFIGURACIÓN DE SERVIDOR DEBIAN 12/13   ║
╚══════════════════════════════════════════════╝

  1) Asegurar el servidor
     UFW · SSH · fail2ban · auditd · límites
  2) Instalar Docker y Docker Compose
     Docker Engine · daemon.json · usuario
  3) Instalar Traefik y Portainer
     Reverse proxy · TLS automático · dashboard
  4) Instalación completa en secuencia
     Ejecuta opciones 1 → 2 → 3
  5) Buscar parches de seguridad
     Traefik + Portainer · cambio de versión
  6) Verificar estado del sistema
     SSH · UFW · Docker · Traefik · recursos
  7) Backup y Migración del stack
     Exportar o importar Traefik + Portainer
  8) Salir
```

La opción 6 abre un sub-menú con dos chequeos:

- **Chequeo general**: snapshot instantáneo de todos los servicios.
- **Verificación post-reinicio**: smoke test que espera hasta 60s a que el stack esté `running/healthy` tras un `reboot` del VPS.

Cada opción arranca con un banner descriptivo, una pausa con "Presione Enter (Ctrl+C para cancelar)", y finaliza con un resumen visual de lo aplicado. La opción 1 (hardening) tiene además un checkpoint previo donde podés revisar el resumen de cambios antes de aplicar nada irreversible.

### Modo no interactivo (CLI)

```bash
sudo bash main.sh --help                                     # Ver opciones
sudo bash main.sh --non-interactive --step secure            # Solo hardening
sudo bash main.sh --non-interactive --step docker            # Solo Docker
sudo bash main.sh --non-interactive --step traefik           # Solo Traefik+Portainer
sudo bash main.sh --non-interactive --step verify            # Diagnóstico del sistema
sudo bash main.sh --non-interactive --step post-reboot       # Smoke test del stack tras un reboot
sudo bash main.sh --non-interactive --step backup            # Crear backup del stack
sudo bash main.sh --non-interactive --step restore           # Restaurar stack (requiere BACKUP_FILE)
sudo bash main.sh --non-interactive --step all               # Todo
sudo bash main.sh --non-interactive --step all --env-file .env  # Con .env personalizado
```

Copiar [`example.env`](example.env) a `.env` y ajustar las variables requeridas.

**Validación DNS**: antes de instalar Traefik, el script verifica que los subdominios resuelvan a la IP del servidor. En modo interactivo permite continuar si DNS aún se está propagando; en `--non-interactive` bloquea si falla.

### Healthcheck y arranque ordenado

El `docker-compose.yml` generado configura **Traefik con healthcheck** (`traefik healthcheck`, cada 10s) y **Portainer con `depends_on: service_healthy`**. Esto garantiza que, tras un `reboot` del VPS, Portainer solo arranque cuando Traefik esté realmente respondiendo — sin ventanas de proxy caído ni errores 502/504. La opción `--step post-reboot` (o sub-opción 2 dentro de la opción 6) automatiza la verificación de este flujo.
```

---

## Instalación con Ansible

```bash
# 1. Instalar dependencias en la máquina de control:
pip install ansible passlib jmespath

# 2. Instalar colecciones de Galaxy:
ansible-galaxy collection install -r ansible/requirements.yml

# 3. Configurar inventario:
# El repositorio ya incluye ansible/inventory/hosts.yml con valores de ejemplo.
# Editalo directamente con la IP y datos de conexión reales del servidor.

# 4. Configurar variables:
# Editar ansible/inventory/group_vars/all/vars.yml (variables no sensibles)
# Editar ansible/inventory/group_vars/all/vault.yml (secrets)
# Ver sección "Gestión de secrets (Vault)" abajo

# 5. Dry-run (ver qué cambiaría sin aplicar nada):
ansible-playbook ansible/playbooks/site.yml --vault-password-file ansible/.vault_pass --check --diff

# 6. Aplicar:
ansible-playbook ansible/playbooks/site.yml --vault-password-file ansible/.vault_pass
```

### Playbooks individuales

```bash
# Solo hardening:
ansible-playbook ansible/playbooks/hardening.yml --vault-password-file ansible/.vault_pass

# Solo Docker:
ansible-playbook ansible/playbooks/docker.yml

# Solo Traefik + Portainer:
ansible-playbook ansible/playbooks/traefik_portainer.yml --vault-password-file ansible/.vault_pass

# Solo actualizar contenedores:
ansible-playbook ansible/playbooks/update.yml --vault-password-file ansible/.vault_pass
```

### Ejecución quirúrgica con tags

Cada role tiene tags que permiten ejecutar solo una parte específica:

```bash
# Solo configurar SSH:
ansible-playbook ansible/playbooks/hardening.yml --tags ssh --check --diff

# Solo UFW:
ansible-playbook ansible/playbooks/hardening.yml --tags ufw

# Solo fail2ban:
ansible-playbook ansible/playbooks/hardening.yml --tags fail2ban

# Solo daemon.json de Docker:
ansible-playbook ansible/playbooks/docker.yml --tags docker-daemon
```

### Gestión de secrets (Vault)

El archivo `vault.yml` contiene passwords y secrets. Está cifrado con `ansible-vault` y **nunca** se commitea en texto plano.

```bash
# Primera vez: crear el archivo de password (gitignored):
openssl rand -base64 32 > ansible/.vault_pass && chmod 600 ansible/.vault_pass

# Cifrar el vault (si aún no está cifrado):
ansible-vault encrypt ansible/inventory/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass

# Editar secrets:
ansible-vault edit ansible/inventory/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass

# Ver secrets (solo lectura):
ansible-vault view ansible/inventory/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
```

> **Nota**: `.vault_pass` está en `.gitignore`. Cada desarrollador debe crear el suyo con la password compartida del equipo.

---

## Guía de uso: ¿cuándo usar cada cosa?

| Necesidad | Usá |
|-----------|-----|
| Instalar en 1 server desde consola | `sudo bash main.sh` → opción 4 |
| Instalar en N servers | `ansible-playbook site.yml` |
| Ver qué cambiaría sin aplicar | `ansible-playbook ... --check --diff` |
| Solo tocar SSH/UFW/fail2ban | `--tags ssh` / `--tags ufw` / `--tags fail2ban` |
| Verificar que los roles funcionan | `molecule test` (ver abajo) |
| Editar passwords/secrets | `ansible-vault edit vault.yml` |

### Scripts Bash vs Ansible

| Criterio | Scripts Bash | Ansible |
|----------|-------------|---------|
| Número de servidores | 1 servidor | 2+ servidores |
| Ansible instalado | No requerido | Requerido |
| Instalación desde cero | Ideal | También funciona |
| Cambios incrementales | Difícil | Ideal (`--tags`) |
| Dry-run antes de aplicar | No disponible | `--check --diff` |
| Idempotente (re-ejecutable) | No | Sí |
| Secrets cifrados | No | `ansible-vault` |
| Equipo de más de 1 persona | Funciona | Recomendado |

> **Regla**: si podés usar Ansible, usalo. Si no (instalación en bare metal sin red, sin máquina de control), usá los scripts Bash.

---

## Estructura del proyecto

```
server-debian13-install-traefik-portainer/
│
├── .github/workflows/
│   ├── shell-lint.yml        # CI: ShellCheck + shfmt
│   ├── ansible-lint.yml      # CI: ansible-lint
│   └── molecule.yml          # CI: Molecule tests para todos los roles
│
├── modules/                  # Módulos Bash (uno por función)
│   ├── common.sh             # Variables globales y funciones de log
│   ├── secure_server.sh      # Hardening del servidor
│   ├── install_docker.sh     # Instalación de Docker Engine
│   ├── install_traefik.sh    # Traefik + Portainer vía Docker Compose
│   └── update_traefik.sh     # Actualización de contenedores
│
├── main.sh                   # Punto de entrada con menú interactivo
│
├── ansible/                  # Proyecto Ansible (implementado; pendiente de validación en VM real)
│   ├── ansible.cfg
│   ├── requirements.yml      # Colecciones: community.general, community.docker, ansible.posix
│   ├── inventory/
│   │   ├── hosts.yml         # Inventario de servidores
│   │   └── group_vars/all/
│   │       ├── vars.yml      # Variables no sensibles
│   │       ├── vault.yml     # Secrets cifrados con ansible-vault
│   │       └── vault.yml.example  # Referencia de variables del vault
│   ├── playbooks/            # site.yml, hardening.yml, docker.yml, traefik_portainer.yml, update.yml
│   └── roles/                # common, security, docker, traefik_portainer, update (cada uno con molecule/)
│
├── AGENTS.md                 # Guía completa para desarrolladores y agentes IA
├── ANSIBLE-MIGRATION.md      # Arquitectura Ansible, estado actual y roadmap
└── CONTRIBUTING.md           # Guía de contribución y linting local
```

---

## Variables de configuración principales

| Variable | Valor por defecto | Descripción |
|---|---|---|
| `ssh_port` | `22` | Puerto SSH |
| `admin_user` | — (requerido) | Usuario administrador |
| `base_domain` | — (requerido) | Dominio base (ej: `example.com`) |
| `traefik_subdomain` | `traefik` | Subdominio del dashboard Traefik |
| `portainer_subdomain` | `portainer` | Subdominio de Portainer |
| `letsencrypt_email` | — (requerido) | Email para Let's Encrypt |
| `traefik_image` | Derivada de `modules/versions.env` | Imagen Docker de Traefik construida desde la versión canónica |
| `portainer_image` | Derivada de `modules/versions.env` | Imagen Docker de Portainer construida desde la versión canónica |
| `install_dir` | `/opt/traefik-portainer` | Directorio de instalación del stack |

Las versiones de Traefik y Portainer viven en `modules/versions.env` (Bash) y `ansible/inventory/group_vars/all/versions.env` (Ansible). Cada sistema tiene su propio archivo — ambos se actualizan manualmente al cambiar de versión. La opción 5 del menú (parches) y el playbook `update.yml` **no buscan nuevas versiones**, solo verifican si el digest de la imagen pinada cambió (útil para security patches de la misma versión).

Consulta [AGENTS.md](AGENTS.md#6-variables-de-entorno-y-secrets) para la tabla completa de variables.

---

## Testing con Molecule

Cada role Ansible tiene tests automatizados con [Molecule](https://molecule.readthedocs.io/) que levantan contenedores **Debian 12** y **Debian 13**, aplican el role y verifican el resultado con [testinfra](https://testinfra.readthedocs.io/).

```bash
# Instalar Molecule (una sola vez):
pip install molecule molecule-plugins[docker] pytest pytest-testinfra

# Testear un role específico:
cd ansible/roles/security
ANSIBLE_CONFIG=../../ansible.cfg molecule test

# Testear todos los roles:
for role in common security docker traefik_portainer update; do
  cd ansible/roles/$role && ANSIBLE_CONFIG=../../ansible.cfg molecule test && cd ../../..
done
```

> **Nota**: algunos features (UFW, auditd, fail2ban runtime) no funcionan dentro de Docker. Los tests verifican la configuración de archivos, no el estado de servicios que requieren kernel del host. Esta cobertura ayuda a Debian 12/13, pero NO equivale todavía a validación completa en VM/host real. Ubuntu sigue fuera de soporte.

---

## Linting local

```bash
# Scripts Bash:
shellcheck modules/*.sh main.sh
shfmt -d -s -i 2 modules/*.sh main.sh

# Ansible:
ansible-lint ansible/playbooks/site.yml
ansible-playbook ansible/playbooks/site.yml --syntax-check
```

---

## Documentación

- **[AGENTS.md](AGENTS.md)** — Guía completa para desarrolladores y agentes IA: flujo de ejecución, convenciones, variables, CI/CD, errores comunes y roadmap
- **[ANSIBLE-MIGRATION.md](ANSIBLE-MIGRATION.md)** — Arquitectura completa del proyecto Ansible, equivalencias con los scripts Bash, y estado real de implementación/validación
- **[PLATFORM-SUPPORT.md](PLATFORM-SUPPORT.md)** — Estado real de soporte hoy, gaps de compatibilidad y roadmap para Debian 12, Debian 13 y Ubuntu Server
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Guía de contribución: cómo hacer PRs, ejecutar linting local y convenciones de commits

---

## Licencia

MIT
