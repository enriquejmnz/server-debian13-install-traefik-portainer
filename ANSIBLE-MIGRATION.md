# ANSIBLE-MIGRATION.md

Guía completa del proyecto Ansible para `server-debian13-install-traefik-portainer`.

> **Estado real hoy**: la implementación Ansible **soporta Debian 12 y Debian 13** con Molecule + lint, pero **aún no se ha validado en VM real**. **Ubuntu sigue sin soporte**. Los scripts Bash están validados en VMs reales para Debian 12 y 13. La fuente de verdad sobre soporte y roadmap es **[`PLATFORM-SUPPORT.md`](PLATFORM-SUPPORT.md)**.

---

## 1. Introducción y motivación

Los scripts Bash (`main.sh` + `modules/*.sh`) funcionan para instalaciones rápidas en un solo servidor, pero presentan limitaciones que se vuelven críticas al escalar o automatizar. La variante Ansible está pensada para resolver gran parte de esas limitaciones y hoy concentra la mejor cobertura del repo en Debian 13:

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

Los scripts Bash siguen siendo válidos para instalación inicial rápida en un único servidor. Para decidir qué plataforma usar hoy, consultá también `PLATFORM-SUPPORT.md`.

---

## 2. Mapa de equivalencias

| Script / Función Bash | Role / Task Ansible | Módulo principal | Notas |
|---|---|---|---|
| `common.sh` — variables globales | `group_vars/all.yml` | — | Variables centralizadas, sin lógica |
| `common.sh` — `log()`, `warn()`, `error()` | `debug:`, `fail:` tasks | `ansible.builtin.debug`, `ansible.builtin.fail` | Ansible loguea automáticamente con `-v` |
| `common.sh` — `detect_debian_version()` | `roles/common/tasks/main.yml` | `ansible.builtin.assert` | Valida Debian 12/13 y bloquea Ubuntu al inicio del play |
| `secure_server.sh` — `apt-get update/upgrade` | `roles/security/tasks/packages.yml` | `ansible.builtin.apt` | `update_cache: yes`, `upgrade: dist` |
| `secure_server.sh` — instalar paquetes esenciales | `roles/security/tasks/packages.yml` | `ansible.builtin.apt` | Lista en `defaults/main.yml` |
| `secure_server.sh` — unattended-upgrades | `roles/security/tasks/packages.yml` | `ansible.builtin.template` | Template `50unattended-upgrades-custom.j2` |
| `secure_server.sh` — UFW reset/default policies | `roles/security/tasks/ufw.yml` | `community.general.ufw` | `state: reset` luego reglas individuales |
| `secure_server.sh` — UFW allow SSH/HTTP/HTTPS | `roles/security/tasks/ufw.yml` | `community.general.ufw` | Puerto SSH desde variable `ssh_port` |
| `secure_server.sh` — sshd_config (heredoc) | `roles/security/templates/sshd_config.j2` | `ansible.builtin.template` | Jinja2 con todas las variables |
| `secure_server.sh` — grupo sshusers | `roles/security/tasks/users.yml` | `ansible.builtin.group` | `state: present` |
| `secure_server.sh` — usuario admin + sudo | `roles/security/tasks/users.yml` | `ansible.builtin.user` | `groups: [sudo, sshusers]` |
| `secure_server.sh` — fail2ban jail.local | `roles/security/templates/jail.local.j2` | `ansible.builtin.template` | Template con `ssh_port`, backend systemd en Debian 12/13 |
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
| `install_traefik.sh` — docker-compose.yml | `roles/traefik_portainer/templates/docker-compose.yml.j2` | `ansible.builtin.template` | Sin IPs estáticas, con versión de Portainer derivada del archivo canónico compartido |
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

## 3. Arquitectura Ansible implementada

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
│   │   │   ├── ufw.yml                  # Firewall UFW (reset + reglas)
│   │   │   ├── ssh.yml                  # sshd_config + backup + validación
│   │   │   ├── fail2ban.yml             # fail2ban + jail.local + backend systemd
│   │   │   ├── limits.yml               # limits.conf + systemd limits
│   │   │   ├── timezone.yml             # Timezone UTC + NTP
│   │   │   ├── auditd.yml               # auditd habilitado
│   │   │   └── admin_user.yml           # Usuario admin + grupo sshusers
│   │   ├── handlers/
│   │   │   └── main.yml                 # Restart ssh, fail2ban, ufw reload
│   │   ├── defaults/
│   │   │   └── main.yml                 # ssh_port, admin_user, etc.
│   │   ├── templates/
│   │   │   ├── sshd_config.j2           # /etc/ssh/sshd_config
│   │   │   ├── jail.local.j2            # /etc/fail2ban/jail.local
│   │   │   ├── limits.conf.j2           # /etc/security/limits.conf
│   │   │   └── systemd_limits.conf.j2   # /etc/systemd/system.conf.d/limits.conf
│   │   ├── molecule/default/            # Tests Molecule
│   │   │   ├── molecule.yml
│   │   │   ├── converge.yml
│   │   │   └── tests/test_default.py
│   │   └── meta/
│   │       └── main.yml
│   │
│   ├── docker/
│   │   ├── tasks/
│   │   │   ├── main.yml                 # Incluye todos los subtasks
│   │   │   ├── repo.yml                 # Repositorio oficial + GPG key
│   │   │   ├── install.yml              # Instalar Docker + clean install opcional + verify
│   │   │   └── daemon.yml               # daemon.json template
│   │   ├── handlers/
│   │   │   └── main.yml                 # Restart Docker
│   │   ├── defaults/
│   │   │   └── main.yml                 # docker_user, log config, docker_clean_install, etc.
│   │   ├── templates/
│   │   │   └── daemon.json.j2           # /etc/docker/daemon.json
│   │   ├── molecule/default/            # Tests Molecule
│   │   │   ├── molecule.yml
│   │   │   ├── converge.yml
│   │   │   └── tests/test_default.py
│   │   └── meta/
│   │       └── main.yml
│   │
│   ├── traefik_portainer/
│   │   ├── tasks/
│   │   │   ├── main.yml                 # Incluye todos los subtasks
│   │   │   ├── prepare.yml              # apache2-utils, directorios, basicAuth hash
│   │   │   ├── network.yml              # Red Docker "proxy"
│   │   │   └── install.yml              # Templates + deploy + firewall + verify
│   │   ├── handlers/
│   │   │   └── main.yml                 # Recrear contenedores si config cambia
│   │   ├── defaults/
│   │   │   └── main.yml                 # base_domain, imágenes, subdominios
│   │   ├── templates/
│   │   │   ├── docker-compose.yml.j2    # Stack completo Traefik + Portainer
│   │   │   ├── traefik.yml.j2           # Configuración estática Traefik
│   │   │   └── dynamic.yml.j2           # Middlewares, TLS, basicAuth
│   │   ├── molecule/default/            # Tests Molecule
│   │   │   ├── molecule.yml
│   │   │   ├── converge.yml
│   │   │   └── tests/test_default.py
│   │   └── meta/
│   │       └── main.yml                 # depends_on: [docker]
│   │
│   └── update/
│       ├── tasks/
│       │   └── main.yml                 # Pull, deploy, prune en un solo archivo
│       ├── defaults/
│       │   └── main.yml                 # install_dir
│       ├── molecule/default/            # Tests Molecule
│       │   ├── molecule.yml
│       │   ├── converge.yml
│       │   └── tests/test_default.py
│       └── meta/
│           └── main.yml                 # depends_on: [docker]
│
└── (Molecule tests integrados en cada role — ver sección 12)
```

### 3.2 Descripción de cada role

#### Role: `common`

**`tasks/main.yml`** — Lista de tareas:
1. Verificar que el sistema operativo es Debian (assert)
2. Verificar que la versión de Debian sea 12 o 13 (assert)
3. Publicar facts `common_debian_major_version` y `common_debian_release` para los roles siguientes
4. Instalar paquetes de utilidad base (curl, gnupg, lsb-release, ca-certificates)
5. Actualizar la caché de apt

**`handlers/main.yml`** — No requiere handlers.

**`defaults/main.yml`** — Variables:
```yaml
common_supported_debian_versions:
  - 12
  - 13
common_supported_debian_releases:
  12: bookworm
  13: trixie
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
- import_tasks: packages.yml
- import_tasks: ufw.yml
- import_tasks: ssh.yml
- import_tasks: fail2ban.yml
- import_tasks: limits.yml
- import_tasks: timezone.yml
- import_tasks: auditd.yml
- import_tasks: admin_user.yml
```

**`tasks/packages.yml`** — Tareas:
1. `apt: update_cache=yes upgrade=dist` — actualizar sistema
2. `apt: name={{ security_packages }} state=present` — instalar lista
3. `apt: name={{ security_optional_packages }} state=present` — opcionales, `ignore_errors: yes`

**`tasks/ssh.yml`** — Tareas:
1. Instalar `openssh-server` para asegurar la presencia de `sshd`
2. Desplegar template `sshd_config.j2` → `/etc/ssh/sshd_config`
3. Validar configuración (`command: sshd -t`) antes de reiniciar
4. Notify handler `Restart SSH`

**`tasks/admin_user.yml`** — Tareas:
1. Crear grupo `sshusers` (`ansible.builtin.group`)
2. Crear usuario admin si no existe (`ansible.builtin.user`)
3. Añadir admin a grupos `sudo`, `sshusers`
4. Si `admin_ssh_public_key` definida, añadir authorized_key

**`tasks/fail2ban.yml`** — Tareas:
1. Desplegar template `jail.local.j2` → `/etc/fail2ban/jail.local` con backend `systemd` para Debian 12/13
2. Si Debian >= 13: añadir `sshd_backend = systemd` a `paths-debian.conf` (`lineinfile`)
3. Notify handler `Restart fail2ban`

**`tasks/limits.yml`** — Tareas:
1. Desplegar template `limits.conf.j2` → `/etc/security/limits.conf`
2. Crear directorio `/etc/systemd/system.conf.d/`
3. Desplegar template `systemd_limits.conf.j2`

**`tasks/timezone.yml`** — Tareas:
1. `community.general.timezone: name=UTC`
2. `systemd: name=systemd-timesyncd enabled=yes state=started`

**`tasks/auditd.yml`** — Tareas:
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
  - openssh-server
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
- `jail.local.j2` — Template de fail2ban con `{{ ssh_port }}`, `{{ fail2ban_bantime }}`, `{{ fail2ban_maxretry }}`, backend systemd para Debian 12/13
- `limits.conf.j2` — Template con `{{ system_nofile_limit }}`, `{{ system_nproc_limit }}`
- `systemd_limits.conf.j2` — Template sección `[Manager]`
- `50unattended-upgrades-custom.j2` — Template para configuración de upgrades automáticos

**`meta/main.yml`**:
```yaml
dependencies:
  - role: common
```

---

#### Role: `docker`

**`tasks/main.yml`** — Includes:
```yaml
- import_tasks: repo.yml
- import_tasks: install.yml
- import_tasks: daemon.yml
```

**`tasks/repo.yml`** — Tareas:
1. `file: path=/etc/apt/keyrings state=directory mode=0755`
2. `get_url` para descargar GPG key de Docker
3. Decodificar GPG con `command: gpg --dearmor`
4. `apt_repository` para añadir el repositorio oficial

**`tasks/install.yml`** — Tareas:
1. Si `docker_clean_install: true`: borrar `/var/lib/docker` y `/var/lib/containerd`
2. `apt: name={{ docker_old_packages }} state=absent` — eliminar versiones antiguas
3. `apt: name={{ docker_packages }} state=present update_cache=yes`
4. `systemd: name=docker enabled=yes state=started`
5. `systemd: name=containerd enabled=yes state=started`
6. Verificar instalación con `docker --version` y `docker compose version`
7. Crear directorio `/opt/docker-compose`

**`tasks/daemon.yml`** — Tareas:
1. `file: path=/etc/docker state=directory`
2. Template `daemon.json.j2` → `/etc/docker/daemon.json`, notify `Restart Docker`

**`handlers/main.yml`**:
- `Restart Docker` → `systemd: name=docker state=restarted`

**`defaults/main.yml`**:
```yaml
docker_user: ""
docker_install_dir: /opt/docker-compose
docker_clean_install: false          # Si true, borra /var/lib/docker y /var/lib/containerd
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
- import_tasks: prepare.yml
- import_tasks: network.yml
- import_tasks: install.yml
```

**`tasks/prepare.yml`** — Tareas:
1. `apt: name=apache2-utils state=present`
2. Generar hash bcrypt para basicAuth usando `htpasswd`
3. Crear directorios de instalación (`traefik-data/configurations`, `portainer-data`)
4. Crear `acme.json` con permisos 600 (solo si no existe)

**`tasks/network.yml`** — Tareas:
1. `community.docker.docker_network: name=proxy driver=bridge ipam_config=[{subnet: "{{ proxy_subnet }}"}]`

**`tasks/install.yml`** — Tareas:
1. Template `docker-compose.yml.j2` → `{{ install_dir }}/docker-compose.yml`, notify `Recreate containers`
2. Template `traefik.yml.j2` → `{{ install_dir }}/traefik-data/traefik.yml`, notify `Recreate containers`
3. Template `dynamic.yml.j2` → `{{ install_dir }}/traefik-data/configurations/dynamic.yml`, notify `Recreate containers`
4. `community.docker.docker_compose_v2: project_src={{ install_dir }} state=present pull=missing`
5. `community.general.ufw: rule=allow port=80 proto=tcp`
6. `community.general.ufw: rule=allow port=443 proto=tcp`
7. Verificar despliegue con `docker compose ps`

**`handlers/main.yml`**:
- `Recreate containers` → `community.docker.docker_compose_v2: project_src={{ install_dir }} state=present recreate=always`

**`defaults/main.yml`**:
```yaml
install_dir: /opt/traefik-portainer
traefik_version_file: "{{ role_path | dirname | dirname }}/inventory/group_vars/all/versions.env"
traefik_version: "{{ lookup('ansible.builtin.ini', 'TRAEFIK_VERSION type=properties file=' ~ traefik_version_file) }}"
traefik_image: "traefik:{{ traefik_version }}"  # Pinado, no :latest
portainer_version_file: "{{ role_path | dirname | dirname }}/inventory/group_vars/all/versions.env"
portainer_version: "{{ lookup('ansible.builtin.ini', 'PORTAINER_VERSION type=properties file=' ~ portainer_version_file) }}"
portainer_image: "portainer/portainer-ce:{{ portainer_version }}"
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
- `docker-compose.yml.j2` — Stack completo sin IPs estáticas, usando nombres de red e imágenes pinadas. Pendiente: replicar el `healthcheck` de Traefik y `depends_on: service_healthy` de Portainer para alcanzar paridad con el script Bash (ver TODO.md).
- `traefik.yml.j2` — Configuración estática con ACME, entrypoints, providers
- `dynamic.yml.j2` — Security headers, basicAuth (usando `{{ traefik_auth }}`), TLS options

**`meta/main.yml`**:
```yaml
dependencies:
  - role: docker
```

---

#### Role: `update`

**`tasks/main.yml`** — Todas las tareas en un solo archivo:
1. `community.docker.docker_compose_v2: project_src={{ install_dir }} pull=always state=present`
2. `community.docker.docker_compose_v2: project_src={{ install_dir }} state=present recreate=auto`
3. `community.docker.docker_prune: images=yes images_filters={dangling: true}`

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
docker_clean_install: false       # Si true, borra /var/lib/docker y /var/lib/containerd
docker_log_max_size: "10m"
docker_log_max_file: "3"
docker_ulimit_nofile: 64000

# === Traefik + Portainer ===
install_dir: /opt/traefik-portainer
# traefik_image y portainer_image se derivan desde inventory/group_vars/all/versions.env
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
        traefik_image: "traefik:v3.7.4"

    staging:
      hosts:
        staging-server-01:
          ansible_host: 198.51.100.5
          ansible_user: admin
          ansible_port: 22
          base_domain: "staging.midominio.com"
      vars:
        ssh_password_auth: "yes"   # más permisivo en staging
        traefik_image: "traefik:v3.7.4"

  vars:
    ansible_python_interpreter: /usr/bin/python3
```

---

## 6. Mejoras sobre los scripts en la versión Ansible

### 6.1 Imágenes de contenedor pinadas

**Problema original:** `portainer/portainer-ce:latest` puede cambiar de versión en cualquier `docker pull`, causando actualizaciones involuntarias y potenciales roturas.

**Solución actual:**
```yaml
# ansible/inventory/group_vars/all/versions.env   (Ansible)
# modules/versions.env                             (Bash — independiente)
PORTAINER_VERSION=2.39.3
TRAEFIK_VERSION=v3.7.4
```

Ambos sistemas tienen su propio `versions.env` independiente. Actualizar una versión requiere editar ambos archivos — cambio simple, revisable en PR, sin dependencia cruzada entre Bash y Ansible.

> **Importante**: El script `update_traefik.sh` (opción 5 del menú) y el playbook `update.yml` **no detectan nuevas versiones automáticamente**. Solo verifican si el digest de la imagen pinada cambió (ej: security patch de la misma versión). Para cambiar de versión (ej: de v3.7.4 a v3.8.0), hay que editar manualmente los archivos `versions.env`.

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
- `jail.local.j2` — Configura backend `systemd` para Debian 12/13 y deja el override extra en `paths-debian.conf` solo para Debian 13+
- `docker-compose.yml.j2` — Imágenes pinadas, sin IPs estáticas, con versiones de Traefik y Portainer leídas desde `versions.env`
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
# Alternativa: paquetes del sistema
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
  - name: ansible.posix
    version: ">=1.5.0"

roles: []
```

### Dependencias Python en la máquina de control

```bash
pip install passlib   # Para generar hashes htpasswd / bcrypt desde Ansible
pip install jmespath  # Para filtros json_query en Ansible
```

### Dependencias en el servidor objetivo (Debian 13 como ruta validada)

```bash
# Python 3 debe estar instalado (normalmente ya lo está en Debian 13)
# Ansible lo comprueba al conectar. Si no está:
apt-get install -y python3
```

> **Importante**: Debian 12 puede llegar a funcionar en algunos casos, pero este documento no debe leerse como validación formal de esa plataforma. Ubuntu sigue fuera de soporte hoy.

---

## 8. Comandos de uso

### Instalación completa (equivale al menú opción 4)

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

## 9. Estado de la migración y validación

> **Implementación completada; validación y soporte aún en consolidación**

Las piezas principales de la migración están implementadas, pero no todas tienen el mismo nivel de validación operativa ni implican soporte oficial multiplataforma:

| Fase | Descripción | Estado |
|------|-------------|--------|
| 1 | Estructura de carpetas, `ansible.cfg`, roles base, vault cifrado | ✅ Implementada |
| 2 | Implementación de los 5 roles con mejoras sobre los scripts | ✅ Implementada |
| 3 | Tests Molecule para todos los roles + workflow CI | ✅ Implementada en Debian 12/13 |
| 4 | Validación operativa adicional en VM/host real | 🔲 Pendiente de reforzar |
| 5 | Sincerar y cerrar claims de soporte por plataforma | 🔲 Pendiente |

### Mejoras implementadas sobre los scripts Bash

- Imágenes Docker pinadas (Traefik v3.7.4, Portainer 2.39.3) con versiones centralizadas en `versions.env` (independiente para Bash y Ansible)
- Sin IPs estáticas en la red Docker proxy
- Backup automático de `sshd_config` antes de reemplazar
- Validación de `sshd -t` antes de reiniciar SSH
- Validación de email y dominio con regex
- `docker_compose_v2` en lugar de `docker_compose` (legacy)
- `experimental: false` eliminado de `daemon.json` (redundante)
- Opción `docker_clean_install` para instalaciones limpias
- Verificación post-deploy de contenedores
- `docker_prune` con módulo nativo de Ansible
- apt upgrade incluido en el role security
- UFW reset explícito antes de aplicar reglas
- Red Docker creada como tarea separada e idempotente

### Qué NO afirma este documento

- NO afirma soporte oficial actual para Ubuntu.
- NO afirma que Debian 12 tenga el mismo nivel de validación que Debian 13.
- NO reemplaza a `PLATFORM-SUPPORT.md` como fuente de verdad para soporte.

---

## 10. Coexistencia con scripts Bash en el mismo repositorio

### Estructura de carpetas raíz

```
server-debian13-install-traefik-portainer/
├── .github/
│   └── workflows/
│       ├── shell-lint.yml        # Ya existe — CI para scripts Bash
│       └── ansible-lint.yml      # Ya existe — CI para Ansible
├── .shellcheckrc                 # Ya existe
├── .ansible-lint                 # Ya existe — configuración ansible-lint
├── ansible/                      # Proyecto Ansible (implementado)
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

> **Recomendación operativa hoy**: si podés elegir, usá **Ansible sobre Debian 13**. Si necesitás Bash, asumí validación manual propia. Para Debian 12 o Ubuntu, primero revisá `PLATFORM-SUPPORT.md`.

---

## 11. Testing con Molecule

Cada role tiene su propio escenario Molecule bajo `molecule/default/`:

```
roles/{role}/molecule/default/
├── molecule.yml          # Configuración del driver (Docker) y plataformas
├── converge.yml          # Playbook que aplica el role
└── tests/
    └── test_default.py   # Verificaciones con testinfra
```

### Instalación

```bash
pip install molecule molecule-docker pytest-testinfra
```

### Ejecutar tests

```bash
# Para un role específico:
cd ansible/roles/security
ANSIBLE_CONFIG=../../ansible.cfg molecule test

# Para todos los roles (desde la raíz del proyecto):
for role in common security docker traefik_portainer update; do
  echo "=== Testing $role ==="
  cd ansible/roles/$role
  ANSIBLE_CONFIG=../../ansible.cfg molecule test
  cd ../../..
done
```

### Pasos del ciclo Molecule

1. `molecule create` — levanta contenedor Docker limpio (Debian 13)
2. `molecule converge` — aplica el role al contenedor
3. `molecule verify` — ejecuta asserts de testinfra
4. `molecule idempotence` — aplica el role una segunda vez, verifica que no hay cambios
5. `molecule destroy` — destruye el contenedor

### CI con Molecule

El workflow `.github/workflows/molecule.yml` ejecuta los tests de Molecule en cada push/PR para todos los roles.

### Limitaciones

- Los tests Molecule con Docker no pueden probar todo (p. ej., systemd completo, UFW real, auditd)
- La cobertura automatizada fuerte hoy está centrada en Debian 13
- Para validación completa, ejecutar los playbooks en una VM Debian 13 real con `--check --diff`
- Debian 12 requiere validación específica antes de elevar su claim de soporte
- Ubuntu requiere implementación y validación propias antes de anunciar soporte

---

## 12. Workflow de ansible-vault

El archivo `ansible/inventory/group_vars/all/vault.yml` está cifrado con ansible-vault. **Nunca** hacer commit de este archivo sin cifrar.

### Configuración inicial

```bash
# Crear archivo de contraseña (una sola vez):
echo "tu_contraseña_segura" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

### Comandos habituales

```bash
# Cifrar el vault:
ansible-vault encrypt ansible/inventory/group_vars/all/vault.yml

# Descifrar para editar:
ansible-vault decrypt ansible/inventory/group_vars/all/vault.yml

# Editar directamente (descifra, abre editor, cifra al guardar):
ansible-vault edit ansible/inventory/group_vars/all/vault.yml

# Cifrar un valor individual para pegar en vars.yml:
ansible-vault encrypt_string 'mi_password_secreta' --name 'vault_traefik_password'

# Ver contenido sin descifrar el archivo:
ansible-vault view ansible/inventory/group_vars/all/vault.yml
```

### Ejecutar playbooks con vault

```bash
# Con prompt interactivo:
ansible-playbook ansible/playbooks/site.yml --ask-vault-pass

# Con archivo de contraseña:
ansible-playbook ansible/playbooks/site.yml --vault-password-file ~/.vault_pass
```

### Variables que DEBEN ir en vault

- `vault_letsencrypt_email`
- `vault_traefik_user`
- `vault_traefik_password`
- `vault_admin_ssh_public_key`

---

## 13. Referencias y recursos útiles

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
