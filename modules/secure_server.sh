#!/bin/bash
# modules/secure_server.sh - Módulo para asegurar un servidor Debian 13

secure_server_create_admin_user() {
  local password_auth=$1

  log "Creando o configurando usuario administrador..."

  while true; do
    read -r -p "Ingrese el nombre del usuario administrador: " admin_user
    if [[ -z $admin_user ]]; then
      warn "El nombre de usuario no puede estar vacío"
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
      continue
    fi

    log "Creando usuario $admin_user..."
    adduser "$admin_user" || error "Error al crear usuario $admin_user"
    usermod -aG sudo "$admin_user" || error "Error al añadir $admin_user al grupo sudo"
    usermod -aG sshusers "$admin_user" || error "Error al añadir $admin_user al grupo sshusers"
    log "Usuario $admin_user creado y añadido a los grupos sudo y sshusers"
    break
  done

  if [[ $password_auth == "no" ]]; then
    log "Por favor, configure la autenticación por clave SSH para $admin_user, ya que la autenticación por contraseña está deshabilitada"
  else
    log "Configure la autenticación por clave SSH para $admin_user o use la contraseña proporcionada"
  fi
}

configure_fail2ban_systemd_backend() {
  local conf_file line_to_add

  if ((DEBIAN_VERSION < 13)); then
    return 0
  fi

  conf_file="/etc/fail2ban/paths-debian.conf"
  line_to_add="sshd_backend = systemd"

  touch "$conf_file" || error "Error al preparar la configuración de fail2ban en $conf_file"

  if ! grep -qF -- "$line_to_add" "$conf_file"; then
    printf '%s\n' "$line_to_add" >>"$conf_file" || error "Error al configurar backend systemd para fail2ban"
  fi
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
PermitRootLogin no
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
  log "Iniciando configuración de seguridad del servidor..."

  # Actualización del sistema
  log "Actualizando el sistema..."
  apt-get update || error "Error al actualizar los índices de paquetes"
  apt-get upgrade -y || error "Error al actualizar el sistema"

  # Instalar herramientas esenciales
  log "Instalando herramientas esenciales..."

  # Lista de paquetes esenciales
  essential_packages=(
    "ufw" "fail2ban" "unattended-upgrades" "apt-listchanges" "net-tools" "sudo"
    "htop" "curl" "wget" "gnupg" "lsb-release" "ca-certificates" "debconf"
    "systemd-timesyncd" "auditd"
  )
  # Paquetes opcionales que pueden no estar disponibles
  optional_packages=("apticron")

  # Instalar paquetes esenciales
  for package in "${essential_packages[@]}"; do
    log "Instalando $package..."
    if ! apt-get install -y "$package"; then
      warn "No se pudo instalar $package, continuando..."
    fi
  done
  # Instalar paquetes opcionales
  for package in "${optional_packages[@]}"; do
    log "Intentando instalar $package (opcional)..."
    if apt-get install -y "$package" 2>/dev/null; then
      log "$package instalado correctamente"
    else
      warn "$package no está disponible, omitiendo..."
    fi
  done

  # Configurar actualizaciones automáticas
  log "Configurando actualizaciones automáticas..."
  cat >/etc/apt/apt.conf.d/50unattended-upgrades-custom <<EOF
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF
  dpkg-reconfigure -plow unattended-upgrades || error "Error al configurar actualizaciones automáticas"

  # Configurar UFW
  log "Configurando UFW..."
  ufw --force reset
  ufw default deny incoming || error "Error al configurar política de denegación de UFW"
  ufw default allow outgoing || error "Error al configurar política de salida de UFW"

  # Configurar SSH seguro
  log "Configurando SSH seguro..."
  read -r -p "Ingrese el puerto SSH (presione Enter para usar 22, o especifique un puerto no estándar): " ssh_port
  ssh_port=${ssh_port:-22}
  if ! [[ $ssh_port =~ ^[0-9]+$ ]] || [[ $ssh_port -lt 1 ]] || [[ $ssh_port -gt 65535 ]]; then
    error "Puerto SSH inválido: $ssh_port"
  fi
  ufw allow "${ssh_port}/tcp" || error "Error al configurar puerto SSH en UFW"
  ufw allow http || error "Error al permitir HTTP en UFW"
  ufw allow https || error "Error al permitir HTTPS en UFW"
  ufw --force enable || error "Error al habilitar UFW"

  read -r -p "¿Desea deshabilitar la autenticación por contraseña para SSH? (s/n, predeterminado: s): " disable_password
  disable_password=${disable_password:-s}
  if [[ $disable_password =~ ^[sS]$ ]]; then
    password_auth="no"
    log "Autenticación por contraseña para SSH será deshabilitada"
  else
    password_auth="yes"
    log "Autenticación por contraseña para SSH permanecerá habilitada"
  fi

  deploy_sshd_config "$ssh_port" "$password_auth"

  log "Creando grupo sshusers para acceso SSH..."
  if ! getent group sshusers >/dev/null 2>&1; then
    groupadd sshusers || error "Error al crear grupo sshusers"
  else
    log "El grupo sshusers ya existe"
  fi

  log "Configurando fail2ban para Debian 13..."
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
maxretry = 3
bantime = 3600
findtime = 600
[sshd-systemd]
enabled = true
filter = sshd
backend = systemd
maxretry = 3
bantime = 3600
findtime = 600
EOF
  configure_fail2ban_systemd_backend

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

  log "Configurando timezone..."
  timedatectl set-timezone UTC || error "Error al configurar timezone"

  log "Configurando NTP..."
  systemctl enable systemd-timesyncd || error "Error al habilitar systemd-timesyncd"
  systemctl start systemd-timesyncd || error "Error al iniciar systemd-timesyncd"

  log "Configurando auditoría de seguridad..."
  systemctl enable auditd || error "Error al habilitar auditd"
  systemctl start auditd || error "Error al iniciar auditd"

  admin_user=""
  secure_server_create_admin_user "$password_auth"

  log "Reiniciando servicios..."
  systemctl restart fail2ban || error "Error al reiniciar fail2ban"
  sshd -t || error "Error en la configuración de SSH. No se reiniciará el servicio"
  systemctl restart ssh || error "Error al reiniciar ssh"

  log "Configuración de seguridad completada con éxito"
  log "Puntos importantes:"
  log "  - SSH root login deshabilitado"
  log "  - Autenticación por contraseña: $password_auth"
  log "  - Puerto SSH configurado: $ssh_port"
  log "  - Firewall configurado para permitir solo SSH, HTTP y HTTPS"
  log "  - Fail2ban implementado con backend systemd para Debian 13"
  log "  - Actualizaciones automáticas configuradas"
  log "  - Usuario administrador configurado: $admin_user"
  log "  - Solo los usuarios en el grupo 'sshusers' pueden acceder via SSH"
}
