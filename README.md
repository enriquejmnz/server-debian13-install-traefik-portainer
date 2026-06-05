# server-debian13-install-traefik-portainer

[![Shell lint](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/shell-lint.yml/badge.svg)](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/shell-lint.yml)
[![Ansible lint](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/ansible-lint.yml/badge.svg)](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/ansible-lint.yml)
[![Molecule Tests](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/molecule.yml/badge.svg)](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/molecule.yml)

Instalador modular para configurar un servidor **Debian** con hardening de seguridad, Docker Engine, Traefik v3 y Portainer CE.

> **Estado real hoy**
>
> - **Ruta más validada:** Ansible sobre **Debian 13 (Trixie)**
> - **Ansible:** soporta **Debian 12 (Bookworm)** y **Debian 13 (Trixie)**; Debian 13 sigue siendo el camino con más validación operativa
> - **Scripts Bash:** soportan **Debian 12** y **Debian 13**, validan distro explícitamente y rechazan Ubuntu; todavía sin smoke test automatizado end-to-end
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

> **Importante**: la ruta Ansible soporta Debian 12/13 con guards explícitos y Molecule puede ejecutarse sobre ambas versiones. Debian 13 sigue siendo la ruta más validada operativamente. Ubuntu no está soportado.

---

## Instalación rápida (scripts Bash)

```bash
# Clonar el repositorio en el servidor:
git clone https://github.com/tu-usuario/server-debian13-install-traefik-portainer.git
cd server-debian13-install-traefik-portainer

# Ejecutar como root:
sudo bash main.sh
```

Si ejecutás `main.sh` sobre Ubuntu u otra distro no soportada, el instalador corta al inicio con un error claro antes de tocar paquetes o servicios.

El menú interactivo ofrece las siguientes opciones:

```
1. Securizar servidor        — UFW, SSH, fail2ban, limits, auditd
2. Instalar Docker           — Docker Engine + daemon.json
3. Instalar Traefik+Portainer — Stack completo con TLS
4. Actualizar contenedores   — Pull + recrear + prune
5. Instalación completa      — Opciones 1+2+3 en secuencia
6. Salir
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
| Instalar en 1 server desde consola | `sudo bash main.sh` → opción 5 |
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
├── ansible/                  # Proyecto Ansible (implementado; Debian 13 más validado)
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

Las versiones de Traefik y Portainer viven en `modules/versions.env` (Bash) y `ansible/inventory/group_vars/all/versions.env` (Ansible). Cada sistema tiene su propio archivo — ambos se actualizan manualmente al cambiar de versión. La opción 4 del menú (update) y el playbook `update.yml` **no buscan nuevas versiones**, solo verifican si el digest de la imagen pinada cambió (útil para security patches de la misma versión).

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
