# ANSIBLE-MIGRATION.md

Guía completa para migrar el proyecto `server-debian13-install-traefik-portainer` de scripts Bash a un proyecto Ansible estructurado.

---

## 1. Introducción y motivación

Los scripts Bash actuales (`main.sh` + `modules/*.sh`) funcionan, pero presentan limitaciones que se vuelven críticas al escalar o automatizar:

| Limitación (Bash) | Solución (Ansible) |
|---|---|
| Interactivo por defecto — `read -p` en cada módulo | Variables declaradas en `group_vars/`, sin prompts |
| No idempotente — re-ejecutar puede romper el sistema | Módulos idempotentes (`apt`, `user`, `ufw`, `template`) |
| Sin dry-run real | `--check --diff` nativo |
| Secrets en texto plano o variables de entorno | `ansible-vault encrypt_string` / archivos vault |
| Un solo servidor a la vez | Inventario multi-host, grupos, límites con `--limit` |
| Sin rollback estructurado | Handlers, notify, tags; posibilidad de snapshots previos |
| Sin testing | Molecule + Docker para test de roles en aislamiento |
| Sin diff de configuración | `--diff` muestra exactamente qué cambia en cada template |
| Logs solo en `/var/log/server-setup.log` | `ansible.log`, callbacks, integración con Slack/PagerDuty |
| Difícil reutilizar en otros proyectos | Roles reutilizables, Galaxy-compatible |

**Cuándo usar Ansible en lugar de los scripts:**
- Gestión de más de 1 servidor
- Necesidad de aplicar cambios incrementales sin reinstalar todo
- Entornos CI/CD o cloud-init
- Equipos donde varios desarrolladores deben aplicar la misma configuración de forma reproducible

Los scripts Bash siguen siendo válidos para instalación inicial rápida en un único servidor de desarrollo.

---

## 2. Mapa de equivalencias

| Script / Función Bash | Role / Task Ansible | Módulo principal | Notas |
|---|---|---|---|
| `common.sh` — variables globales | `group_vars/all.yml` | — | Variables centralizadas, sin lógica |
| `common.sh` — `log()`, `warn()`, `error()` | `debug:`, `fail:` tasks | `ansible.builtin.debug`, `ansible.builtin.fail` | Ansible loguea automáticamente con `-v` |
| `common.sh` — `detect_debian_version()` | `roles/common/tasks/assert_debian.yml` | `ansible.builtin.assert` | Valida OS al inicio del play |
| `secure_server.sh` — `apt-get update/upgrade` | `roles/security/tasks/packages.yml` | `ansible.builtin.apt` | `update_cache: yes`, `upgrade: dist` |
| `secure_server.sh` — instalar paquetes esenciales | `roles/security/tasks/packages.yml` | `ansible.builtin.apt` | Lista en `defaults/main.yml` |
| `secure_server.sh` — unattended-upgrades | `roles/security/tasks/unattended_upgrades.yml` | `ansible.builtin.template` | Template `50unattended-upgrades.j2` |
| `secure_server.sh` — UFW reset/default policies | `roles/security/tasks/ufw.yml` | `community.general.ufw` | `state: reset` luego reglas individuales |
| `secure_server.sh` — UFW allow SSH/HTTP/HTTPS | `roles/security/tasks/ufw.yml` | `community.general.ufw` | Puerto SSH desde variable `ssh_port` |
| `secure_server.sh` — sshd_config (heredoc) | `roles/security/templates/sshd_config.j2` | `ansible.builtin.template` | Jinja2 con todas las variables |
| `secure_server.sh` — grupo sshusers | `roles/security/tasks/users.yml` | `ansible.builtin.group` | `state: present` |
| `secure_server.sh` — usuario admin + sudo | `roles/security/tasks/users.yml` | `ansible.builtin.user` | `groups: [sudo, sshusers]` |
| `secure_server.sh` — fail2ban jail.local | `roles/security/templates/jail.local.j2` | `ansible.builtin.template` | Template con `ssh_port`, backend systemd |
| `secure_server.sh` — paths-debian.conf (Debian 13) | `roles/security/tasks/fail2ban.yml` | `ansible.builtin.lineinfile` | Solo si `ansible_distribution_major_version >= 13` |
| `secure_server.sh` — limits.conf | `roles/security/templates/limits.conf.j2` | `ansible.builtin.template` | |
| `secure_server.sh` — systemd limits.conf | `roles/security/templates/systemd_limits.conf.j2` | `ansible.builtin.template` | En `/etc/systemd/system.conf.d/` |
| `secure_server.sh` — timezone UTC | `roles/security/tasks/time.yml` | `community.general.timezone` | `name: UTC` |
| `secure_server.sh` — systemd-timesyncd | `roles/security/tasks/time.yml` | `ansible.builtin.systemd` | `enabled: yes`, `state: started` |
| `secure_server.sh` — auditd | `roles/security/tasks/audit.yml` | `ansible.builtin.systemd` | `enabled: yes`, `state: started` |
| `install_docker.sh` — eliminar paquetes previos | `roles/docker/tasks/remove_old.yml` | `ansible.builtin.apt` | `state: absent`, `purge: yes` |
| `install_docker.sh` — GPG key Docker | `roles/docker/tasks/repo.yml` | `ansible.builtin.get_url` + `ansible.builtin.apt_key` | Key en `/etc/apt/keyrings/docker.gpg` |
| `install_docker.sh` — repositorio Docker | `roles/docker/tasks/repo.yml` | `ansible.builtin.apt_repository` | Fuente oficial Docker |
| `install_docker.sh` — instalar docker-ce etc. | `roles/docker/tasks/install.yml` | `ansible.builtin.apt` | Lista en `defaults/main.yml` |
| `install_docker.sh` — systemctl enable/start | `roles/docker/tasks/install.yml` | `ansible.builtin.systemd` | `enabled: yes`, `state: started` |
| `install_docker.sh` — daemon.json | `roles/docker/templates/daemon.json.j2` | `ansible.builtin.template` | Notify handler `Restart Docker` |
| `install_docker.sh` — usuario Docker | `roles/docker/tasks/users.yml` | `ansible.builtin.user` | Solo si `docker_user` está definido |
| `install_docker.sh` — `/opt/docker-compose` | `roles/docker/tasks/dirs.yml` | `ansible.builtin.file` | `state: directory`, `mode: '0755'` |
| `install_traefik.sh` — apache2-utils | `roles/traefik_portainer/tasks/prereqs.yml` | `ansible.builtin.apt` | |
| `install_traefik.sh` — directorios de instalación | `roles/traefik_portainer/tasks/dirs.yml` | `ansible.builtin.file` | `/opt/traefik-portainer/...` |
| `install_traefik.sh` — docker-compose.yml | `roles/traefik_portainer/templates/docker-compose.yml.j2` | `ansible.builtin.template` | Sin IPs estáticas, con versiones pinadas |
| `install_traefik.sh` — traefik.yml | `roles/traefik_portainer/templates/traefik.yml.j2` | `ansible.builtin.template` | |
| `install_traefik.sh` — dynamic.yml | `roles/traefik_portainer/templates/dynamic.yml.j2` | `ansible.builtin.template` | `traefik_auth` desde vault |
| `install_traefik.sh` — acme.json (chmod 600) | `roles/traefik_portainer/tasks/acme.yml` | `ansible.builtin.file` | `state: touch`, `mode: '0600'` (solo si no existe) |
| `install_traefik.sh` — red Docker "proxy" | `roles/traefik_portainer/tasks/network.yml` | `community.docker.docker_network` | `driver: bridge`, subnet configurable |
| `install_traefik.sh` — `docker compose up -d` | `roles/traefik_portainer/tasks/deploy.yml` | `community.docker.docker_compose_v2` | |
| `install_traefik.sh` — UFW 80/443 | `roles/traefik_portainer/tasks/firewall.yml` | `community.general.ufw` | |
| `update_traefik.sh` — `docker compose pull` | `roles/update/tasks/pull.yml` | `community.docker.docker_compose_v2` | `pull: always` |
| `update_traefik.sh` — `docker compose up -d` | `roles/update/tasks/deploy.yml` | `community.docker.docker_compose_v2` | |
| `update_traefik.sh` — `docker image prune -f` | `roles/update/tasks/prune.yml` | `community.docker.docker_prune` | `images: yes` |
| `main.sh` — menú interactivo | `playbooks/site.yml` con tags | — | `--tags security,docker,traefik` |

---

## 3. Arquitectura Ansible propuesta

### 3.1 Árbol de carpetas completo

```
ansible/
├── ansible.cfg                          # Configuración global de Ansible
├── requirements.yml                     # Colecciones y roles de Galaxy
│
├── inventory/
│   ├── hosts.yml                        # Inventario de servidores (YAML)
│   └── group_vars/
│       ├── all.yml                      # Variables comunes a todos los hosts
│       └── all/
│           ├── vars.yml                 # Variables no sensibles
│           └── vault.yml                # Variables cifradas con ansible-vault
│
├── playbooks/
│   ├── site.yml                         # Playbook maestro (ejecuta todo)
│   ├── hardening.yml                    # Solo hardening del servidor
│   ├── docker.yml                       # Solo instalación de Docker
│   ├── traefik_portainer.yml            # Solo Traefik + Portainer
│   └── update.yml                       # Solo actualización de contenedores
│
├── roles/
│   ├── common/
│   │   ├── tasks/
│   │   │   └── main.yml                 # Validar OS, instalar deps base
│   │   ├── defaults/
│   │   │   └── main.yml                 # Variables por defecto del role
│   │   └── meta/
│   │       └── main.yml                 # Metadatos del role
│   │
│   ├── security/
│   │   ├── tasks/
│   │   │   ├── main.yml                 # Incluye todos los subtasks
│   │   │   ├── packages.yml             # apt update/upgrade + paquetes
│   │   │   ├── ufw.yml                  # Firewall UFW
│   │   │   ├── ssh.yml                  # sshd_config + grupo sshusers
│   │   │   ├── users.yml                # Usuario administrador
│   │   │   ├── fail2ban.yml             # fail2ban + jail.local
│   │   │   ├── limits.yml               # limits.conf + systemd limits
│   │   │   ├── time.yml                 # Timezone + NTP
│   │   │   ├── audit.yml                # auditd
│   │   │   └── unattended_upgrades.yml  # Actualizaciones automáticas
│   │   ├── handlers/
│   │   │   └── main.yml                 # Restart ssh, fail2ban, ufw reload
│   │   ├── defaults/
│   │   │   └── main.yml                 # ssh_port, admin_user, etc.
│   │   ├── templates/
│   │   │   ├── sshd_config.j2           # /etc/ssh/sshd_config
│   │   │   ├── jail.local.j2            # /etc/fail2ban/jail.local
│   │   │   ├── limits.conf.j2           # /etc/security/limits.conf
│   │   │   ├── systemd_limits.conf.j2   # /etc/systemd/system.conf.d/limits.conf
│   │   │   └── 50unattended-upgrades.j2 # /etc/apt/apt.conf.d/50unattended-upgrades-custom
│   │   └── meta/
│   │       └── main.yml
│   │
│   ├── docker/
│   │   ├── tasks/
│   │   │   ├── main.yml                 # Incluye todos los subtasks
│   │   │   ├── remove_old.yml           # Eliminar instalaciones previas
│   │   │   ├── repo.yml                 # Repositorio oficial + GPG
│   │   │   ├── install.yml              # Instalar paquetes Docker
│   │   │   ├── daemon.yml               # daemon.json
│   │   │   ├── users.yml                # Usuario para el grupo docker
│   │   │   └── dirs.yml                 # /opt/docker-compose
│   │   ├── handlers/
│   │   │   └── main.yml                 # Restart Docker
│   │   ├── defaults/
│   │   │   └── main.yml                 # docker_user, log config, etc.
│   │   ├── templates/
│   │   │   └── daemon.json.j2           # /etc/docker/daemon.json
│   │   └── meta/
│   │       └── main.yml
│   │
│   ├── traefik_portainer/
│   │   ├── tasks/
│   │   │   ├── main.yml                 # Incluye todos los subtasks
│   │   │   ├── prereqs.yml              # apache2-utils y deps
│   │   │   ├── dirs.yml                 # Crear directorios
│   │   │   ├── network.yml              # Red Docker "proxy"
│   │   │   ├── config.yml               # Templates de configuración
│   │   │   ├── acme.yml                 # acme.json con permisos 600
│   │   │   ├── deploy.yml               # docker compose up -d
│   │   │   └── firewall.yml             # UFW 80/443
│   │   ├── handlers/
│   │   │   └── main.yml                 # Recrear contenedores si config cambia
│   │   ├── defaults/
│   │   │   └── main.yml                 # base_domain, imágenes, subdominios
│   │   ├── templates/
│   │   │   ├── docker-compose.yml.j2    # Stack completo Traefik + Portainer
│   │   │   ├── traefik.yml.j2           # Configuración estática Traefik
│   │   │   └── dynamic.yml.j2           # Middlewares, TLS, basicAuth
│   │   └── meta/
│   │       └── main.yml                 # depends_on: [docker]
│   │
│   └── update/
│       ├── tasks/
│       │   ├── main.yml                 # Incluye pull, deploy, prune
│       │   ├── pull.yml                 # docker compose pull
│       │   ├── deploy.yml               # docker compose up -d
│       │   └── prune.yml                # docker image prune
│       ├── defaults/
│       │   └── main.yml                 # install_dir
│       └── meta/
│           └── main.yml                 # depends_on: [docker]
│
└── molecule/                            # Tests con Molecule (fase 4)
    └── default/
        ├── molecule.yml
        ├── converge.yml
        └── verify.yml
```

### 3.2 Descripción de cada role

#### Role: `common`

**`tasks/main.yml`** — Lista de tareas:
1. Verificar que el sistema operativo es Debian (assert)
2. Verificar que la versión de Debian es >= 12 (assert)
3. Instalar paquetes de utilidad base (curl, gnupg, lsb-release, ca-certificates)
4. Actualizar la caché de apt

**`handlers/main.yml`** — No requiere handlers.

**`defaults/main.yml`** — Variables:
```yaml
common_base_packages:
  - curl
  - gnupg
  - lsb-release
  - ca-certificates
  - python3-apt        # requerido por módulo apt de Ansible
```

**`meta/main.yml`**:
```yaml
galaxy_info:
  role_name: common
  author: local
  min_ansible_version: "2.14"
dependencies: []
```

---

#### Role: `security`

**`tasks/main.yml`** — Lista de includes:
```yaml
- include_tasks: packages.yml
- include_tasks: unattended_upgrades.yml
- include_tasks: ufw.yml
- include_tasks: ssh.yml
- include_tasks: users.yml
- include_tasks: fail2ban.yml
- include_tasks: limits.yml
- include_tasks: time.yml
- include_tasks: audit.yml
```

**`tasks/packages.yml`** — Tareas:
1. `apt: update_cache=yes upgrade=dist` — actualizar sistema
2. `apt: name={{ security_packages }} state=present` — instalar lista
3. `apt: name={{ security_optional_packages }} state=present` — opcionales, `ignore_errors: yes`

**`tasks/ssh.yml`** — Tareas:
1. Crear backup de sshd_config (`ansible.builtin.copy` con remote_src)
2. Desplegar template `sshd_config.j2` → `/etc/ssh/sshd_config`
3. Validar configuración (`command: sshd -t`) antes de reiniciar
4. Notify handler `Restart SSH`

**`tasks/users.yml`** — Tareas:
1. Crear grupo `sshusers` (`ansible.builtin.group`)
2. Crear usuario admin si no existe (`ansible.builtin.user`)
3. Añadir admin a grupos `sudo`, `sshusers`
4. Si `admin_ssh_public_key` definida, añadir authorized_key

**`tasks/fail2ban.yml`** — Tareas:
1. Desplegar template `jail.local.j2` → `/etc/fail2ban/jail.local`
2. Si Debian >= 13: añadir `sshd_backend = systemd` a `paths-debian.conf` (`lineinfile`)
3. Notify handler `Restart fail2ban`

**`tasks/limits.yml`** — Tareas:
1. Desplegar template `limits.conf.j2` → `/etc/security/limits.conf`
2. Crear directorio `/etc/systemd/system.conf.d/`
3. Desplegar template `systemd_limits.conf.j2`

**`tasks/time.yml`** — Tareas:
1. `community.general.timezone: name=UTC`
2. `systemd: name=systemd-timesyncd enabled=yes state=started`

**`tasks/audit.yml`** — Tareas:
1. `systemd: name=auditd enabled=yes state=started`

**`handlers/main.yml`**:
- `Restart SSH` → `systemd: name=ssh state=restarted`
- `Restart fail2ban` → `systemd: name=fail2ban state=restarted`
- `Reload UFW` → `community.general.ufw: state=reloaded`

**`defaults/main.yml`** — Variables principales:
```yaml
ssh_port: 22
ssh_password_auth: "no"
admin_user: "admin"
admin_ssh_public_key: ""      # vault
security_packages:
  - ufw
  - fail2ban
  - unattended-upgrades
  - apt-listchanges
  - net-tools
  - sudo
  - htop
  - curl
  - wget
  - gnupg
  - lsb-release
  - ca-certificates
  - debconf
  - systemd-timesyncd
  - auditd
security_optional_packages:
  - apticron
fail2ban_bantime: 3600
fail2ban_maxretry: 3
fail2ban_findtime: 600
system_nofile_limit: 65535
system_nproc_limit: 65535
```

**`templates/`**:
- `sshd_config.j2` — Template completo de `/etc/ssh/sshd_config` con todas las directivas del script original, usando variables `{{ ssh_port }}`, `{{ ssh_password_auth }}`
- `jail.local.j2` — Template de fail2ban con `{{ ssh_port }}`, `{{ fail2ban_bantime }}`, `{{ fail2ban_maxretry }}`, backend systemd condicional
- `limits.conf.j2` — Template con `{{ system_nofile_limit }}`, `{{ system_nproc_limit }}`
- `systemd_limits.conf.j2` — Template sección `[Manager]`
- `50unattended-upgrades.j2` — Template para configuración de upgrades automáticos

**`meta/main.yml`**:
```yaml
dependencies:
  - role: common
```

---

#### Role: `docker`

**`tasks/main.yml`** — Includes:
```yaml
- include_tasks: remove_old.yml
- include_tasks: repo.yml
- include_tasks: install.yml
- include_tasks: daemon.yml
- include_tasks: users.yml
- include_tasks: dirs.yml
```

**`tasks/remove_old.yml`** — Tareas:
1. `apt: name={{ docker_old_packages }} state=absent purge=yes` — eliminar versiones antiguas
2. `file: path={{ item }} state=absent` — borrar `/var/lib/docker`, `/var/lib/containerd`

**`tasks/repo.yml`** — Tareas:
1. `file: path=/etc/apt/keyrings state=directory mode=0755`
2. `get_url` para descargar GPG key de Docker
3. Decodificar GPG con `command: gpg --dearmor` (o `ansible.builtin.apt_key` para versiones antiguas)
4. `apt_repository` para añadir el repositorio oficial

**`tasks/install.yml`** — Tareas:
1. `apt: name={{ docker_packages }} state=present update_cache=yes`
2. `systemd: name=docker enabled=yes state=started`
3. `systemd: name=containerd enabled=yes state=started`

**`tasks/daemon.yml`** — Tareas:
1. `file: path=/etc/docker state=directory`
2. Template `daemon.json.j2` → `/etc/docker/daemon.json`, notify `Restart Docker`

**`tasks/users.yml`** — Tareas:
1. Cuando `docker_user` está definido y no vacío: `user: name={{ docker_user }} groups=docker append=yes`

**`tasks/dirs.yml`** — Tareas:
1. `file: path=/opt/docker-compose state=directory mode=0755`

**`handlers/main.yml`**:
- `Restart Docker` → `systemd: name=docker state=restarted`

**`defaults/main.yml`**:
```yaml
docker_user: ""
docker_install_dir: /opt/docker-compose
docker_log_max_size: "10m"
docker_log_max_file: "3"
docker_ulimit_nofile: 64000
docker_packages:
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - docker-buildx-plugin
  - docker-compose-plugin
docker_old_packages:
  - docker
  - docker-engine
  - docker.io
  - containerd
  - runc
```

**`templates/`**:
- `daemon.json.j2` — Template de `/etc/docker/daemon.json` con log-driver, ulimits, icc=false, no-new-privileges, live-restore, ip6tables, iptables

**`meta/main.yml`**:
```yaml
dependencies:
  - role: common
```

---

#### Role: `traefik_portainer`

**`tasks/main.yml`** — Includes:
```yaml
- include_tasks: prereqs.yml
- include_tasks: dirs.yml
- include_tasks: network.yml
- include_tasks: config.yml
- include_tasks: acme.yml
- include_tasks: deploy.yml
- include_tasks: firewall.yml
```

**`tasks/prereqs.yml`** — Tareas:
1. `apt: name=apache2-utils state=present`
2. Generar hash bcrypt para basicAuth usando `htpasswd` o módulo `passlib` de Python

**`tasks/dirs.yml`** — Tareas:
1. `file: path={{ install_dir }}/traefik-data/configurations state=directory`
2. `file: path={{ install_dir }}/portainer-data state=directory`

**`tasks/network.yml`** — Tareas:
1. `community.docker.docker_network: name=proxy driver=bridge ipam_config=[{subnet: "{{ proxy_subnet }}"}]`

**`tasks/config.yml`** — Tareas:
1. Template `docker-compose.yml.j2` → `{{ install_dir }}/docker-compose.yml`, notify `Recreate containers`
2. Template `traefik.yml.j2` → `{{ install_dir }}/traefik-data/traefik.yml`, notify `Recreate containers`
3. Template `dynamic.yml.j2` → `{{ install_dir }}/traefik-data/configurations/dynamic.yml`, notify `Recreate containers`

**`tasks/acme.yml`** — Tareas:
1. `file: path={{ install_dir }}/traefik-data/acme.json state=touch mode=0600` (solo si no existe: `creates`)

**`tasks/deploy.yml`** — Tareas:
1. `community.docker.docker_compose_v2: project_src={{ install_dir }} state=present pull=missing`

**`tasks/firewall.yml`** — Tareas:
1. `community.general.ufw: rule=allow port=80 proto=tcp`
2. `community.general.ufw: rule=allow port=443 proto=tcp`

**`handlers/main.yml`**:
- `Recreate containers` → `community.docker.docker_compose_v2: project_src={{ install_dir }} state=present recreate=always`

**`defaults/main.yml`**:
```yaml
install_dir: /opt/traefik-portainer
traefik_image: "traefik:v3.3"          # Pinado, no :latest
portainer_image: "portainer/portainer-ce:2.21.5"  # Pinado, no :latest
base_domain: ""                         # REQUERIDO
traefik_subdomain: traefik
portainer_subdomain: portainer
letsencrypt_email: ""                   # REQUERIDO — en vault
traefik_user: ""                        # REQUERIDO — en vault
traefik_password: ""                    # REQUERIDO — en vault
traefik_auth: ""                        # Generado automáticamente
proxy_network: proxy
proxy_subnet: "172.18.0.0/16"
```

**`templates/`**:
- `docker-compose.yml.j2` — Stack completo sin IPs estáticas, usando nombres de red, imágenes pinadas
- `traefik.yml.j2` — Configuración estática con ACME, entrypoints, providers
- `dynamic.yml.j2` — Security headers, basicAuth (usando `{{ traefik_auth }}`), TLS options

**`meta/main.yml`**:
```yaml
dependencies:
  - role: docker
```

---

#### Role: `update`

**`tasks/main.yml`** — Includes:
```yaml
- include_tasks: pull.yml
- include_tasks: deploy.yml
- include_tasks: prune.yml
```

**`tasks/pull.yml`** — Tareas:
1. `community.docker.docker_compose_v2: project_src={{ install_dir }} pull=always state=present`

**`tasks/deploy.yml`** — Tareas:
1. `community.docker.docker_compose_v2: project_src={{ install_dir }} state=present recreate=auto`

**`tasks/prune.yml`** — Tareas:
1. `community.docker.docker_prune: images=yes images_filters={dangling: true}`

**`defaults/main.yml`**:
```yaml
install_dir: /opt/traefik-portainer
```

**`meta/main.yml`**:
```yaml
dependencies:
  - role: docker
```

---

## 4. Variables y secrets

### `inventory/group_vars/all/vars.yml` — Variables no sensibles

```yaml
# === Sistema ===
timezone: UTC
system_nofile_limit: 65535
system_nproc_limit: 65535

# === SSH ===
ssh_port: 22
ssh_password_auth: "no"
ssh_login_grace_time: 120
ssh_max_auth_tries: 3
ssh_max_sessions: 10
ssh_client_alive_interval: 300
ssh_client_alive_count_max: 2

# === Usuario administrador ===
admin_user: "admin"
# admin_ssh_public_key: definir en vault o por host

# === fail2ban ===
fail2ban_bantime: 3600
fail2ban_findtime: 600
fail2ban_maxretry: 3
fail2ban_default_maxretry: 5

# === Docker ===
docker_user: ""
docker_log_max_size: "10m"
docker_log_max_file: "3"
docker_ulimit_nofile: 64000

# === Traefik + Portainer ===
install_dir: /opt/traefik-portainer
traefik_image: "traefik:v3.3"
portainer_image: "portainer/portainer-ce:2.21.5"
traefik_subdomain: traefik
portainer_subdomain: portainer
proxy_network: proxy
proxy_subnet: "172.18.0.0/16"

# === Dominios (NO sensible, pero específico por entorno) ===
base_domain: "example.com"
```

### `inventory/group_vars/all/vault.yml` — Variables sensibles (cifradas con ansible-vault)

```yaml
# Cifrar este archivo con: ansible-vault encrypt inventory/group_vars/all/vault.yml

# === Let's Encrypt ===
vault_letsencrypt_email: "admin@example.com"

# === Traefik basicAuth ===
vault_traefik_user: "admin"
vault_traefik_password: "supersecretpassword"

# === SSH ===
vault_admin_ssh_public_key: "ssh-ed25519 AAAA... user@host"

# === Contraseña del usuario admin (hash shadow) ===
# Generar con: python3 -c "import crypt; print(crypt.crypt('PASSWORD', crypt.mksalt(crypt.METHOD_SHA512)))"
vault_admin_password_hash: "$6$rounds=..."
```

**Referencias en `vars.yml`** (para usar las variables vault sin exponer nombres):
```yaml
letsencrypt_email: "{{ vault_letsencrypt_email }}"
traefik_user: "{{ vault_traefik_user }}"
traefik_password: "{{ vault_traefik_password }}"
admin_ssh_public_key: "{{ vault_admin_ssh_public_key }}"
```

**Variables que DEBEN ir en vault** (nunca en texto plano):
- `vault_letsencrypt_email`
- `vault_traefik_user`
- `vault_traefik_password`
- `vault_admin_ssh_public_key`
- `vault_admin_password_hash`

---

## 5. Ejemplo de inventario

### Un solo servidor

```yaml
# inventory/hosts.yml
all:
  hosts:
    myserver:
      ansible_host: 203.0.113.10
      ansible_user: admin
      ansible_port: 22
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519
      # Variables específicas de este host (sobreescriben group_vars):
      base_domain: "midominio.com"
      ssh_port: 2222
```

### Múltiples servidores con grupos

```yaml
# inventory/hosts.yml
all:
  children:
    production:
      hosts:
        prod-server-01:
          ansible_host: 203.0.113.10
          ansible_user: admin
          ansible_port: 2222
          base_domain: "prod.midominio.com"
        prod-server-02:
          ansible_host: 203.0.113.11
          ansible_user: admin
          ansible_port: 2222
          base_domain: "prod2.midominio.com"
      vars:
        traefik_image: "traefik:v3.3"
        portainer_image: "portainer/portainer-ce:2.21.5"

    staging:
      hosts:
        staging-server-01:
          ansible_host: 198.51.100.5
          ansible_user: ubuntu
          ansible_port: 22
          base_domain: "staging.midominio.com"
      vars:
        ssh_password_auth: "yes"   # más permisivo en staging
        traefik_image: "traefik:v3.3"

  vars:
    ansible_python_interpreter: /usr/bin/python3
```

---

## 6. Mejoras sobre los scripts en la versión Ansible

### 6.1 Imágenes de contenedor pinadas

**Problema actual:** `portainer/portainer-ce:latest` puede cambiar de versión en cualquier `docker pull`, causando actualizaciones involuntarias y potenciales roturas.

**Solución Ansible:**
```yaml
# defaults/main.yml del role traefik_portainer
traefik_image: "traefik:v3.3"
portainer_image: "portainer/portainer-ce:2.21.5"
```

Actualizar a una nueva versión es un cambio de una sola línea en `vars.yml`, revisable en PR y con historial en git.

### 6.2 Sin IPs estáticas en la red Docker

**Problema actual:** `ipv4_address: 172.18.0.2` y `.3` son frágiles si la subnet ya está en uso y no aportan ningún beneficio (Traefik usa autodiscovery por nombre de servicio).

**Solución en `docker-compose.yml.j2`:**
```yaml
services:
  traefik:
    networks:
      - proxy          # Sin IP estática
  portainer:
    networks:
      - proxy          # Sin IP estática

networks:
  proxy:
    name: "{{ proxy_network }}"
    driver: bridge
```

### 6.3 Dry-run nativo con `--check --diff`

```bash
# Ver exactamente qué cambiaría sin tocar nada:
ansible-playbook playbooks/site.yml --check --diff -i inventory/hosts.yml

# El diff muestra línea a línea qué cambia en sshd_config, daemon.json, etc.
```

### 6.4 Idempotencia total

Cada módulo Ansible garantiza idempotencia:
- `apt` solo instala si el paquete no está presente
- `template` solo escribe si el contenido difiere (y notifica handlers para reiniciar servicios)
- `user`/`group` solo crean si no existen
- `docker_network` no recrea si ya existe con los mismos parámetros
- `file: state=touch` + `creates` para `acme.json`

### 6.5 ansible-vault para secrets

```bash
# Cifrar el archivo vault completo:
ansible-vault encrypt inventory/group_vars/all/vault.yml

# Cifrar un valor individual (para pegar en vars.yml):
ansible-vault encrypt_string 'mysecretpassword' --name 'vault_traefik_password'

# Editar el vault cifrado:
ansible-vault edit inventory/group_vars/all/vault.yml

# Ejecutar playbook con vault:
ansible-playbook playbooks/site.yml --ask-vault-pass
# O con archivo de contraseña:
ansible-playbook playbooks/site.yml --vault-password-file ~/.vault_pass
```

### 6.6 Templates Jinja2 completos

Todos los archivos de configuración usan templates Jinja2:

- `sshd_config.j2` — Elimina el heredoc frágil del script, valida antes de aplicar
- `jail.local.j2` — Configura backend systemd condicionalmente con `{% if ansible_distribution_major_version | int >= 13 %}`
- `docker-compose.yml.j2` — Imágenes pinadas, sin IPs estáticas, variables en un solo lugar
- `traefik.yml.j2` / `dynamic.yml.j2` — Regenerados automáticamente si cambia email o auth
- `daemon.json.j2` — Configuración Docker en template versionado

---

## 7. Instalación de Ansible

### En la máquina de control (donde se ejecuta Ansible, NO en el servidor objetivo)

```bash
# Método recomendado: pipx (aislado, sin contaminar el sistema)
sudo apt-get install -y pipx
pipx install ansible
pipx inject ansible passlib jmespath

# Verificar:
ansible --version
```

```bash
# Alternativa: pip en virtualenv
python3 -m venv ~/.ansible-venv
source ~/.ansible-venv/bin/activate
pip install ansible passlib jmespath

# Activar en cada sesión:
source ~/.ansible-venv/bin/activate
```

```bash
# Alternativa: desde repositorio oficial Ansible (Debian/Ubuntu)
sudo add-apt-repository --yes --update ppa:ansible/ansible  # solo Ubuntu
sudo apt-get install -y ansible

# En Debian 13:
sudo apt-get install -y ansible
```

### Instalar colecciones de Galaxy necesarias

```bash
# Instalar todas las colecciones declaradas en requirements.yml:
ansible-galaxy collection install -r ansible/requirements.yml
```

**`ansible/requirements.yml`:**
```yaml
---
collections:
  - name: community.general
    version: ">=9.0.0"
  - name: community.docker
    version: ">=3.0.0"

roles: []
```

### Dependencias Python en la máquina de control

```bash
pip install passlib   # Para generar hashes htpasswd / bcrypt desde Ansible
pip install jmespath  # Para filtros json_query en Ansible
```

### Dependencias en el servidor objetivo (Debian 13)

```bash
# Python 3 debe estar instalado (normalmente ya lo está en Debian 13)
# Ansible lo comprueba al conectar. Si no está:
apt-get install -y python3
```

---

## 8. Comandos de uso

### Instalación completa (equivale al menú opción 5)

```bash
# Con dry-run primero:
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --ask-vault-pass \
  --check --diff

# Aplicar:
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --ask-vault-pass
```

### Playbooks individuales

```bash
# Solo hardening del servidor:
ansible-playbook ansible/playbooks/hardening.yml \
  -i ansible/inventory/hosts.yml \
  --ask-vault-pass

# Solo Docker:
ansible-playbook ansible/playbooks/docker.yml \
  -i ansible/inventory/hosts.yml

# Solo Traefik + Portainer:
ansible-playbook ansible/playbooks/traefik_portainer.yml \
  -i ansible/inventory/hosts.yml \
  --ask-vault-pass

# Solo actualización de contenedores:
ansible-playbook ansible/playbooks/update.yml \
  -i ansible/inventory/hosts.yml
```

### Con tags para tareas específicas

```bash
# Ver qué tags están disponibles:
ansible-playbook ansible/playbooks/site.yml --list-tags

# Solo ejecutar tareas de UFW:
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --tags ufw

# Solo ejecutar tareas de SSH:
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --tags ssh \
  --check --diff

# Saltar tareas de actualización de paquetes (más rápido):
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --skip-tags packages
```

### Limitar a servidores específicos

```bash
# Solo un servidor del inventario:
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --limit prod-server-01 \
  --ask-vault-pass

# Solo el grupo staging:
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --limit staging \
  --ask-vault-pass
```

### Dry-run y diff

```bash
# Ver exactamente qué cambiaría:
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --ask-vault-pass \
  --check --diff \
  --limit myserver

# Verbosidad extra para debug:
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --ask-vault-pass \
  -vv
```

### Comandos de utilidad

```bash
# Verificar conectividad con todos los hosts:
ansible all -i ansible/inventory/hosts.yml -m ping

# Ejecutar un comando ad-hoc:
ansible all -i ansible/inventory/hosts.yml -m command -a "ufw status"

# Ver facts del sistema:
ansible myserver -i ansible/inventory/hosts.yml -m setup | less

# Comprobar sintaxis del playbook:
ansible-playbook ansible/playbooks/site.yml --syntax-check

# Listar hosts que se verían afectados:
ansible-playbook ansible/playbooks/site.yml \
  -i ansible/inventory/hosts.yml \
  --list-hosts
```

---

## 9. Plan de migración por fases

### Fase 1: Estructura de carpetas y roles vacíos (1-2 horas)

```bash
# Crear estructura base:
mkdir -p ansible/{inventory/group_vars/all,playbooks,molecule/default}
mkdir -p ansible/roles/{common,security,docker,traefik_portainer,update}/{tasks,handlers,defaults,templates,meta}

# Crear ansible.cfg:
cat > ansible/ansible.cfg << 'EOF'
[defaults]
inventory          = inventory/hosts.yml
roles_path         = roles
collections_paths  = ~/.ansible/collections
host_key_checking  = False
stdout_callback    = yaml
interpreter_python = auto_silent

[privilege_escalation]
become      = True
become_method = sudo
EOF

# Instalar colecciones:
ansible-galaxy collection install -r ansible/requirements.yml
```

Entregable: estructura de carpetas creada, `ansible-playbook --syntax-check` sin errores.

### Fase 2: Implementar roles (orden recomendado, 1-2 días)

1. **`common`** — El más simple, sirve como base. Probar con `ping`.
2. **`security`** — El más crítico. Testear sshd_config en VM antes de producción.
3. **`docker`** — Dependiente de `common`. Verificar con `docker --version`.
4. **`traefik_portainer`** — Dependiente de `docker`. Testear primero con dominio de prueba.
5. **`update`** — El más simple operacionalmente.

Para cada role:
1. Implementar `defaults/main.yml` con todas las variables
2. Implementar templates Jinja2 comparando con el heredoc del script original
3. Implementar tasks de más simple a más compleja
4. Probar con `--check --diff` antes de aplicar

### Fase 3: Testing con `--check` y Molecule (2-3 días)

```bash
# Instalar Molecule:
pip install molecule molecule-docker

# Inicializar tests para el role security:
cd ansible/roles/security
molecule init scenario --driver-name docker

# Ejecutar tests:
molecule test
```

Pasos del test Molecule:
1. `molecule create` — levantar contenedor Docker limpio (Debian 13)
2. `molecule converge` — aplicar el role
3. `molecule verify` — ejecutar asserts de verificación
4. `molecule idempotence` — aplicar dos veces, verificar que no cambia nada
5. `molecule destroy` — destruir el contenedor

### Fase 4: CI/CD con ansible-lint + Molecule (1-2 días)

```bash
# Instalar ansible-lint:
pip install ansible-lint

# Ejecutar lint local:
ansible-lint ansible/playbooks/site.yml
ansible-lint ansible/roles/security/

# Workflow GitHub Actions a crear: .github/workflows/ansible-lint.yml
```

**`.github/workflows/ansible-lint.yml`** (a crear):
```yaml
name: Ansible lint

on: [push, pull_request]

jobs:
  ansible-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run ansible-lint
        uses: ansible/ansible-lint@v24
        with:
          args: ansible/playbooks/site.yml
```

---

## 10. Coexistencia con scripts Bash en el mismo repositorio

### Estructura de carpetas raíz

```
server-debian13-install-traefik-portainer/
├── .github/
│   └── workflows/
│       ├── shell-lint.yml        # Ya existe — CI para scripts Bash
│       └── ansible-lint.yml      # A crear — CI para Ansible
├── .shellcheckrc                 # Ya existe
├── .ansible-lint                 # A crear — configuración ansible-lint
├── ansible/                      # Proyecto Ansible (NUEVO)
│   ├── ansible.cfg
│   ├── requirements.yml
│   ├── inventory/
│   ├── playbooks/
│   └── roles/
├── modules/                      # Scripts Bash (existente)
│   ├── common.sh
│   ├── secure_server.sh
│   ├── install_docker.sh
│   ├── install_traefik.sh
│   └── update_traefik.sh
├── main.sh                       # Script principal (existente)
├── ANSIBLE-MIGRATION.md          # Este archivo
├── AGENTS.md                     # Guía para desarrolladores y agentes IA
└── CONTRIBUTING.md               # Ya existe
```

### Convenciones de coexistencia

1. **Scripts Bash** viven en `/modules/` y son invocados por `main.sh` — no se mueven
2. **Ansible** vive enteramente en `/ansible/` — paths relativos siempre desde esa carpeta
3. **Variables compartidas**: los valores por defecto en `ansible/inventory/group_vars/all/vars.yml` deben mantenerse en sincronía manual con los defaults en `modules/common.sh` y los scripts
4. **Templates Ansible** son la fuente de verdad para los archivos de configuración — si se cambia el template, documentar el cambio equivalente en el script

### Cuándo usar scripts Bash vs Ansible

| Situación | Usar scripts Bash | Usar Ansible |
|---|---|---|
| Instalación inicial rápida, un solo server | ✓ | |
| Sin acceso a máquina de control con Ansible | ✓ | |
| Entorno de desarrollo personal | ✓ | |
| Múltiples servidores | | ✓ |
| CI/CD o cloud-init automatizado | | ✓ |
| Cambios incrementales (solo SSH, solo fail2ban) | | ✓ |
| Auditoría y diff de configuración | | ✓ |
| Equipos de más de 1 persona | | ✓ |
| Staging + producción con variables distintas | | ✓ |

---

## 11. Referencias y recursos útiles

### Documentación oficial

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [community.docker collection](https://docs.ansible.com/ansible/latest/collections/community/docker/)
- [community.general collection](https://docs.ansible.com/ansible/latest/collections/community/general/)
- [ansible-vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
- [Molecule documentation](https://ansible.readthedocs.io/projects/molecule/)

### Módulos clave usados en este proyecto

- [`ansible.builtin.apt`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html)
- [`ansible.builtin.template`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [`ansible.builtin.user`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/user_module.html)
- [`community.general.ufw`](https://docs.ansible.com/ansible/latest/collections/community/general/ufw_module.html)
- [`community.general.timezone`](https://docs.ansible.com/ansible/latest/collections/community/general/timezone_module.html)
- [`community.docker.docker_compose_v2`](https://docs.ansible.com/ansible/latest/collections/community/docker/docker_compose_v2_module.html)
- [`community.docker.docker_network`](https://docs.ansible.com/ansible/latest/collections/community/docker/docker_network_module.html)

### Herramientas de desarrollo

- [ansible-lint](https://ansible.readthedocs.io/projects/lint/) — linter para playbooks y roles
- [Molecule](https://ansible.readthedocs.io/projects/molecule/) — framework de testing para roles
- [ansible-navigator](https://ansible.readthedocs.io/projects/navigator/) — interfaz TUI para Ansible

### Ejemplos de roles similares en Galaxy

- [geerlingguy.docker](https://galaxy.ansible.com/ui/standalone/roles/geerlingguy/docker/) — referencia para instalación de Docker
- [dev-sec.ssh-hardening](https://galaxy.ansible.com/ui/standalone/roles/dev-sec/ssh_hardening/) — referencia para hardening SSH
