# server-debian13-install-traefik-portainer

[![Shell lint](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/shell-lint.yml/badge.svg)](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/shell-lint.yml)
[![Ansible lint](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/ansible-lint.yml/badge.svg)](https://github.com/tu-usuario/server-debian13-install-traefik-portainer/actions/workflows/ansible-lint.yml)

Instalador modular para configurar un servidor **Debian 13 (Trixie)** listo para producción con hardening de seguridad, Docker Engine, Traefik v3 y Portainer CE.

---

## ¿Qué hace?

En menos de 30 minutos, este proyecto configura un servidor Debian 13 con:

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

- **Sistema operativo**: Debian 13 (Trixie)
- **Usuario**: root
- **Conectividad**: acceso a internet (para descargar paquetes y GPG keys)
- **DNS**: dominio base apuntando a la IP del servidor (solo para instalar Traefik)

### Para Ansible

Todo lo anterior en los servidores objetivo, más:

- **Máquina de control** con Python 3 y Ansible >= 2.14
- **Acceso SSH** desde la máquina de control a los servidores objetivo
- **Colecciones Galaxy**: `community.general`, `community.docker`, `ansible.posix`

---

## Instalación rápida (scripts Bash)

```bash
# Clonar el repositorio en el servidor:
git clone https://github.com/tu-usuario/server-debian13-install-traefik-portainer.git
cd server-debian13-install-traefik-portainer

# Ejecutar como root:
sudo bash main.sh
```

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
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
# Editar hosts.yml con la IP y datos de conexión del servidor

# 4. Configurar variables:
# Editar ansible/inventory/group_vars/all/vars.yml (variables no sensibles)
# Crear y cifrar el vault con las contraseñas:
ansible-vault encrypt ansible/inventory/group_vars/all/vault.yml

# 5. Dry-run (ver qué cambiaría sin aplicar nada):
ansible-playbook ansible/playbooks/site.yml --ask-vault-pass --check --diff

# 6. Aplicar:
ansible-playbook ansible/playbooks/site.yml --ask-vault-pass
```

### Playbooks individuales

```bash
# Solo hardening:
ansible-playbook ansible/playbooks/hardening.yml --ask-vault-pass

# Solo Docker:
ansible-playbook ansible/playbooks/docker.yml

# Solo Traefik + Portainer:
ansible-playbook ansible/playbooks/traefik_portainer.yml --ask-vault-pass

# Solo actualizar contenedores:
ansible-playbook ansible/playbooks/update.yml

# Con tags (ej: solo SSH):
ansible-playbook ansible/playbooks/site.yml --tags ssh --check --diff
```

---

## Estructura del proyecto

```
server-debian13-install-traefik-portainer/
│
├── .github/workflows/
│   ├── shell-lint.yml        # CI: ShellCheck + shfmt
│   └── ansible-lint.yml      # CI: ansible-lint
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
├── ansible/                  # Proyecto Ansible (migración en curso)
│   ├── ansible.cfg
│   ├── requirements.yml      # Colecciones: community.general, community.docker, ansible.posix
│   ├── inventory/
│   │   ├── hosts.yml         # Inventario de servidores
│   │   └── group_vars/all/
│   │       ├── vars.yml      # Variables no sensibles
│   │       └── vault.yml     # Secrets cifrados con ansible-vault
│   ├── playbooks/            # site.yml, hardening.yml, docker.yml, traefik_portainer.yml, update.yml
│   └── roles/                # common, security, docker, traefik_portainer, update
│
├── AGENTS.md                 # Guía completa para desarrolladores y agentes IA
├── ANSIBLE-MIGRATION.md      # Arquitectura Ansible y plan de migración
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
| `traefik_image` | `traefik:v3.3` | Imagen Docker de Traefik |
| `portainer_image` | `portainer/portainer-ce:2.21.5` | Imagen Docker de Portainer |
| `install_dir` | `/opt/traefik-portainer` | Directorio de instalación del stack |

Consulta [AGENTS.md](AGENTS.md#6-variables-de-entorno-y-secrets) para la tabla completa de variables.

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
- **[ANSIBLE-MIGRATION.md](ANSIBLE-MIGRATION.md)** — Arquitectura completa del proyecto Ansible, equivalencias con los scripts Bash, y plan de migración por fases
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Guía de contribución: cómo hacer PRs, ejecutar linting local y convenciones de commits

---

## Licencia

MIT
