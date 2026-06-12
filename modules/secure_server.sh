#!/bin/bash
# modules/secure_server.sh - Módulo para asegurar un servidor Debian soportado

secure_server_create_admin_user() {
  log "Creando o configurando usuario administrador..."

  while true; do
    prompt_or_default "ADMIN_USER" "Ingrese el nombre del usuario administrador"
    admin_user="${ADMIN_USER}"

    if [[ -z $admin_user ]]; then
      warn "El nombre de usuario no puede estar vacío"
      unset ADMIN_USER
      continue
    fi

    if id "$admin_user" >/dev/null 2>&1; then
      log "El usuario $admin_user ya existe"
      read -r -p "¿Desea usar el usuario existente $admin_user como administrador? (s/n, predeterminado: s): " use_existing
      use_existing=${use_existing:-s}
      if [[ $use_existing =~ ^[sS]$ ]]; then
        log "Configurando $admin_user como administrador..."
        usermod -aG sudo "$admin_user" || error "Error al añadir $admin_user al grupo sudo"
        usermod -aG sshusers "$admin_user" || error "Error al añadir $admin_user al grupo sshusers"
        log "Usuario $admin_user configurado como administrador y añadido a los grupos sudo y sshusers"
        break
      fi
      log "Por favor, ingrese un nombre de usuario diferente"
      unset ADMIN_USER
      continue
    fi

    log "Creando usuario $admin_user..."
    adduser "$admin_user" || error "Error al crear usuario $admin_user"
    usermod -aG sudo "$admin_user" || error "Error al añadir $admin_user al grupo sudo"
    usermod -aG sshusers "$admin_user" || error "Error al añadir $admin_user al grupo sshusers"
    log "Usuario $admin_user creado y añadido a los grupos sudo y sshusers"
    break
  done

  echo ""
  printf '%s\n' "${YELLOW}==========================================${NC}"
  printf '%s\n' "${YELLOW}  CONFIGURACIÓN DE ACCESO SSH${NC}"
  printf '%s\n' "${YELLOW}==========================================${NC}"
  echo ""
  printf '%s\n' "  Método 1 — Pegar clave pública ahora:"
  printf '%s\n' "    Si ya tenés tu clave pública, pegala a continuación."
  printf '%s\n' "    (Generala con: ${GREEN}ssh-keygen -t ed25519${NC})"
  echo ""

  prompt_or_default "ADMIN_SSH_KEY" "  Pegá tu clave pública SSH (dejar vacío para omitir)"
  admin_ssh_key="${ADMIN_SSH_KEY:-}"

  if [[ -n $admin_ssh_key ]]; then
    local auth_keys_dir="/home/$admin_user/.ssh"
    local auth_keys_file="$auth_keys_dir/authorized_keys"

    mkdir -p "$auth_keys_dir" || error "Error al crear $auth_keys_dir"
    printf '%s\n' "$admin_ssh_key" >>"$auth_keys_file" || error "Error al escribir la clave SSH"
    chmod 700 "$auth_keys_dir" || error "Error al ajustar permisos de $auth_keys_dir"
    chmod 600 "$auth_keys_file" || error "Error al ajustar permisos de $auth_keys_file"
    chown -R "$admin_user:$admin_user" "$auth_keys_dir" || error "Error al asignar propiedad de $auth_keys_dir"
    log "Clave SSH configurada para $admin_user"
  else
    echo ""
    printf '%s\n' "  Método 2 — Usar ssh-copy-id desde tu máquina local:"
    printf '%s\n' "  ${GREEN}ssh-copy-id -p $ssh_port $admin_user@$(hostname -I | awk '{print $1}')${NC}"
    printf '%s\n' "  O con una clave específica:"
    printf '%s\n' "  ${GREEN}ssh-copy-id -i ~/.ssh/tu_clave.pub -p $ssh_port $admin_user@$(hostname -I | awk '{print $1}')${NC}"
    echo ""
    read -r -p "  Presioná Enter cuando hayas copiado la clave (o escribí 'skip' para omitir): " ssh_key_confirm

    if [[ $ssh_key_confirm == "skip" ]]; then
      warn "No se configuró clave SSH para $admin_user. Asegurate de hacerlo manualmente después."
    fi
  fi
}

configure_fail2ban_systemd_backend() {
  local conf_file line_to_add line

  if ((DEBIAN_VERSION < 13)); then
    return 0
  fi

  conf_file="/etc/fail2ban/paths-debian.conf"
  line_to_add="sshd_backend = systemd"

  touch "$conf_file" || error "Error al preparar la configuración de fail2ban en $conf_file"

  while IFS= read -r line; do
    if [[ $line == "$line_to_add" ]]; then
      return 0
    fi
  done <"$conf_file"

  printf '%s\n' "$line_to_add" >>"$conf_file" || error "Error al configurar backend systemd para fail2ban"
}

configure_fail2ban_jail() {
  local ssh_port=$1

  log "Configurando fail2ban para Debian $DEBIAN_VERSION ($DEBIAN_CODENAME)..."
  cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
mta = sendmail
#action = %(action_mwl)s
backend = systemd

[sshd]
enabled = true
port = $ssh_port
filter = sshd
backend = systemd
maxretry = 3
bantime = 3600
findtime = 600
EOF

  configure_fail2ban_systemd_backend
}

deploy_sshd_config() {
  local ssh_port=$1
  local password_auth=$2
  local tmp_sshd_config

  tmp_sshd_config=$(mktemp) || error "Error al crear archivo temporal para sshd_config"

  cat >"$tmp_sshd_config" <<EOF
Port $ssh_port
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
LoginGraceTime 120
PermitRootLogin prohibit-password
StrictModes yes
MaxAuthTries 3
MaxSessions 10
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication $password_auth
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
AllowAgentForwarding no
AllowTcpForwarding no
GatewayPorts no
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
PermitUserEnvironment no
Compression delayed
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
PidFile /run/sshd.pid
MaxStartups 10:30:100
UsePAM yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
AllowGroups sshusers
EOF

  sshd -t -f "$tmp_sshd_config" || {
    rm -f "$tmp_sshd_config"
    error "Error en la nueva configuración de SSH. No se aplicarán cambios."
  }

  cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)" || {
    rm -f "$tmp_sshd_config"
    error "Error al respaldar configuración de SSH"
  }

  install -m 644 "$tmp_sshd_config" /etc/ssh/sshd_config || {
    rm -f "$tmp_sshd_config"
    error "Error al configurar archivo sshd_config"
  }

  rm -f "$tmp_sshd_config"
}

# Función para asegurar el servidor
secure_server() {
  require_supported_debian

  clear
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║   CONFIGURACIÓN DE SEGURIDAD DEL SERVIDOR   ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  Este proceso realizará:"
  printf '%s\n' "    1. Actualización del sistema (apt update + upgrade)"
  printf '%s\n' "    2. Instalación de paquetes de seguridad"
  printf '%s\n' "    3. Configuración de SSH (puerto y autenticación)"
  printf '%s\n' "    4. Creación de usuario administrador"
  printf '%s\n' "    5. Hardening: UFW, fail2ban, límites, timezone, auditd"
  echo ""

  if [[ $NON_INTERACTIVE == false ]]; then
    read -r -p "  Presione Enter para continuar (Ctrl+C para cancelar)..."
  fi

  log "Iniciando hardening de seguridad..."

  # =====================================================================
  # FASE 1 — Preparación del sistema y paquetes
  # =====================================================================
  printf '%s\n' "${YELLOW}── FASE 1/5: Preparación del sistema${NC}"
  echo ""

  log "Actualizando el sistema (apt update + upgrade)..."
  apt-get update || error "Error al actualizar los índices de paquetes"
  apt-get upgrade -y || error "Error al actualizar el sistema"

  log "Instalando paquetes de seguridad..."
  essential_packages=(
    "ufw" "fail2ban" "unattended-upgrades" "apt-listchanges" "net-tools" "sudo"
    "htop" "curl" "wget" "gnupg" "lsb-release" "ca-certificates" "debconf"
    "systemd-timesyncd" "auditd" "openssh-server"
  )
  optional_packages=("apticron")

  for package in "${essential_packages[@]}"; do
    if ! apt-get install -y "$package" 2>/dev/null; then
      warn "No se pudo instalar $package, continuando..."
    fi
  done
  for package in "${optional_packages[@]}"; do
    if apt-get install -y "$package" 2>/dev/null; then
      log "$package instalado (opcional)"
    fi
  done

  command -v sshd >/dev/null 2>&1 || error "openssh-server no está disponible después de la instalación de paquetes"
  log "✓ Sistema actualizado y paquetes instalados"
  echo ""

  # =====================================================================
  # FASE 2 — SSH: puerto y política de contraseñas
  # =====================================================================
  printf '%s\n' "${YELLOW}── FASE 2/5: Configuración de SSH${NC}"
  echo ""

  prompt_or_default "SSH_PORT" "Ingrese el puerto SSH (Enter para usar 22, o especifique un puerto no estándar)" "22"
  ssh_port="${SSH_PORT:-22}"
  if ! [[ $ssh_port =~ ^[0-9]+$ ]] || [[ $ssh_port -lt 1 ]] || [[ $ssh_port -gt 65535 ]]; then
    error "Puerto SSH inválido: $ssh_port"
  fi

  prompt_or_default "DISABLE_PASSWORD_AUTH" "¿Deshabilitar autenticación por contraseña para SSH? (s/n, predeterminado: s)" "s"
  disable_password="${DISABLE_PASSWORD_AUTH:-s}"
  if [[ $disable_password =~ ^[sS]$ ]]; then
    password_auth="no"
  else
    password_auth="yes"
  fi
  echo ""

  # =====================================================================
  # FASE 3 — Usuario administrador (ANTES de tocar UFW/SSH)
  # =====================================================================
  printf '%s\n' "${YELLOW}── FASE 3/5: Usuario administrador${NC}"
  echo ""

  log "Creando grupo sshusers para acceso SSH..."
  if ! getent group sshusers >/dev/null 2>&1; then
    groupadd sshusers || error "Error al crear grupo sshusers"
  else
    log "El grupo sshusers ya existe"
  fi

  admin_user=""
  secure_server_create_admin_user
  echo ""

  # =====================================================================
  # CHECKPOINT — Confirmación antes de aplicar hardening
  # =====================================================================
  if [[ $NON_INTERACTIVE == false ]]; then
    local pass_status
    if [[ $password_auth == "no" ]]; then
      pass_status="${RED}DESHABILITADA${NC}"
    else
      pass_status="${GREEN}HABILITADA${NC}"
    fi

    echo ""
    printf '%s\n' "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
    printf '%s\n' "${YELLOW}║        RESUMEN PREVIO AL HARDENING          ║${NC}"
    printf '%s\n' "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    printf '%s\n' "  Puerto SSH:              ${GREEN}${ssh_port}${NC}"
    printf '%s\n' "  Auth por contraseña:     ${pass_status}"
    printf '%s\n' "  Usuario administrador:   ${GREEN}${admin_user}${NC}"
    printf '%s\n' "  Grupos del admin:        sudo + sshusers"
    echo ""
    printf '%s\n' "  Cambios a aplicar:"
    printf '%s\n' "  • Firewall UFW:           solo SSH(${ssh_port}), HTTP, HTTPS"
    printf '%s\n' "  • PermitRootLogin:        prohibit-password"
    printf '%s\n' "  • Acceso SSH:             solo miembros del grupo sshusers"
    printf '%s\n' "  • Fail2ban:               activo (backend systemd)"
    printf '%s\n' "  • Actualizaciones:        automáticas (seguridad)"
    printf '%s\n' "  • Límites del sistema:    nofile=65535, nproc=65535"
    printf '%s\n' "  • Timezone + NTP:         sincronización horaria"
    printf '%s\n' "  • Auditd:                 auditoría de seguridad"
    echo ""

    read -r -p "  ¿Aplicar estos cambios? (s/n, predeterminado: s): " confirm_hardening
    confirm_hardening=${confirm_hardening:-s}
    if [[ ! $confirm_hardening =~ ^[sS]$ ]]; then
      log "Hardening cancelado por el usuario."
      log "El usuario $admin_user permanece configurado. Para re-ejecutar: opción 1 del menú."
      return 0
    fi
  fi

  echo ""
  printf '%s\n' "${YELLOW}── FASE 4/5: Aplicando hardening${NC}"
  echo ""

  # --- UFW ---
  log "Configurando firewall UFW..."
  ufw --force reset
  ufw default deny incoming || error "Error al configurar política de denegación de UFW"
  ufw default allow outgoing || error "Error al configurar política de salida de UFW"
  ufw allow "${ssh_port}/tcp" || error "Error al configurar puerto SSH en UFW"
  ufw allow http || error "Error al permitir HTTP en UFW"
  ufw allow https || error "Error al permitir HTTPS en UFW"
  ufw --force enable || error "Error al habilitar UFW"
  log "✓ UFW configurado"

  # --- Actualizaciones automáticas ---
  log "Configurando actualizaciones automáticas..."
  cat >/etc/apt/apt.conf.d/50unattended-upgrades-custom <<EOF
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF
  dpkg-reconfigure -plow unattended-upgrades || error "Error al configurar actualizaciones automáticas"

  # --- SSH hardening ---
  log "Aplicando configuración hardened de SSH..."
  deploy_sshd_config "$ssh_port" "$password_auth"
  log "✓ SSH configurado"

  # --- fail2ban ---
  configure_fail2ban_jail "$ssh_port"
  log "✓ Fail2ban configurado"

  # --- Límites del sistema ---
  log "Configurando límites del sistema..."
  cat >/etc/security/limits.conf <<EOF
*               soft    nofile          65535
*               hard    nofile          65535
*               soft    nproc           65535
*               hard    nproc           65535
root            soft    nofile          65535
root            hard    nofile          65535
root            soft    nproc           65535
root            hard    nproc           65535
EOF
  mkdir -p /etc/systemd/system.conf.d || error "Error al crear directorio de límites de systemd"
  cat >/etc/systemd/system.conf.d/limits.conf <<EOF
[Manager]
DefaultLimitNOFILE=65535
DefaultLimitNPROC=65535
EOF
  log "✓ Límites del sistema configurados"

  # --- Timezone y NTP ---
  log "Configurando timezone y NTP..."
  if [[ -n ${TIMEZONE:-} ]]; then
    if timedatectl set-timezone "$TIMEZONE" 2>/dev/null; then
      timezone="$TIMEZONE"
      log "Zona horaria: $timezone"
    else
      warn "Zona horaria \"$TIMEZONE\" no válida. Usando UTC."
      timedatectl set-timezone UTC || true
      timezone="UTC"
    fi
  else
    while true; do
      echo ""
      printf '%s\n' "  Zonas horarias disponibles (ejemplos):"
      printf '%s\n' "    ${GREEN}timedatectl list-timezones${NC} — muestra todas las zonas"
      printf '%s\n' "    America/Argentina/Buenos_Aires  America/Mexico_City  America/Santiago"
      printf '%s\n' "    Europe/Madrid  Europe/London  Asia/Tokyo  UTC"
      echo ""
      read -r -p "  Ingrese la zona horaria (Enter para UTC): " timezone
      timezone=${timezone:-UTC}
      if timedatectl set-timezone "$timezone" 2>/dev/null; then
        log "Zona horaria configurada: $timezone"
        break
      else
        warn "Zona horaria \"$timezone\" no válida. Ejecutá 'timedatectl list-timezones' para ver las zonas disponibles."
      fi
    done
  fi

  systemctl enable systemd-timesyncd || error "Error al habilitar systemd-timesyncd"
  systemctl start systemd-timesyncd || error "Error al iniciar systemd-timesyncd"
  log "✓ Timezone y NTP configurados"

  # --- Auditoría ---
  log "Configurando auditoría de seguridad..."
  systemctl enable auditd || error "Error al habilitar auditd"
  systemctl start auditd || error "Error al iniciar auditd"
  log "✓ Auditd habilitado"

  # =====================================================================
  # FASE 5 — Reinicio de servicios
  # =====================================================================
  echo ""
  printf '%s\n' "${YELLOW}── FASE 5/5: Reiniciando servicios${NC}"
  echo ""

  systemctl enable fail2ban || error "Error al habilitar fail2ban"
  systemctl restart fail2ban || error "Error al reiniciar fail2ban"
  log "✓ Fail2ban iniciado"

  sshd -t || error "Error en la configuración de SSH. No se reiniciará el servicio"
  systemctl restart ssh || error "Error al reiniciar ssh"
  log "✓ SSH reiniciado"

  # =====================================================================
  # Resumen final
  # =====================================================================
  echo ""
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║      HARDENING COMPLETADO CON ÉXITO         ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  🔒 SSH:                    puerto ${GREEN}${ssh_port}${NC}, contraseña ${password_auth}"
  printf '%s\n' "  👤 Usuario admin:          ${GREEN}${admin_user}${NC} (sudo + sshusers)"
  printf '%s\n' "  🛡️  Firewall:               solo SSH(${ssh_port}), HTTP, HTTPS"
  printf '%s\n' "  🚫 Fail2ban:               activo (backend systemd)"
  printf '%s\n' "  📦 Actualizaciones:        automáticas (seguridad)"
  printf '%s\n' "  ⏰ Timezone:               ${timezone:-UTC}"
  printf '%s\n' "  📋 Auditd:                 habilitado"
  echo ""
  log "Hardening de seguridad completado con éxito"
}
