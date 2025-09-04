#!/bin/bash
# modules/secure_server.sh - Módulo para asegurar un servidor Debian 13

# Función para asegurar el servidor
secure_server() {
    log "Iniciando configuración de seguridad del servidor..."

    # Actualización del sistema
    log "Actualizando el sistema..."
    apt-get update
    check_error $? "Error al actualizar los índices de paquetes"
    apt-get upgrade -y
    check_error $? "Error al actualizar el sistema"

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
    echo 'Unattended-Upgrade::Automatic-Reboot "false";' > /etc/apt/apt.conf.d/50unattended-upgrades-custom
    echo 'Unattended-Upgrade::Automatic-Reboot-Time "02:00";' >> /etc/apt/apt.conf.d/50unattended-upgrades-custom
    dpkg-reconfigure -plow unattended-upgrades
    check_error $? "Error al configurar actualizaciones automáticas"

    # Configurar UFW
    log "Configurando UFW..."
    ufw --force reset
    ufw default deny incoming
    check_error $? "Error al configurar política de denegación de UFW"
    ufw default allow outgoing
    check_error $? "Error al configurar política de salida de UFW"

    # Configurar SSH seguro
    log "Configurando SSH seguro..."
    read -p "Ingrese el puerto SSH (presione Enter para usar 22, o especifique un puerto no estándar): " ssh_port
    ssh_port=${ssh_port:-22}
    if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1 ] || [ "$ssh_port" -gt 65535 ]; then
        error "Puerto SSH inválido: $ssh_port"
    fi
    ufw allow $ssh_port/tcp
    check_error $? "Error al configurar puerto SSH en UFW"
    ufw allow http
    check_error $? "Error al permitir HTTP en UFW"
    ufw allow https
    check_error $? "Error al permitir HTTPS en UFW"
    echo "y" | ufw enable
    check_error $? "Error al habilitar UFW"

    read -p "¿Desea deshabilitar la autenticación por contraseña para SSH? (s/n, predeterminado: s): " disable_password
    disable_password=${disable_password:-s}
    if [[ "$disable_password" =~ ^[sS]$ ]]; then
        password_auth="no"
        log "Autenticación por contraseña para SSH será deshabilitada"
    else
        password_auth="yes"
        log "Autenticación por contraseña para SSH permanecerá habilitada"
    fi

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)
    check_error $? "Error al respaldar configuración de SSH"
    cat > /etc/ssh/sshd_config <<EOF
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
AllowAgentForwarding yes
AllowTcpForwarding yes
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
    check_error $? "Error al configurar archivo sshd_config"

    log "Creando grupo sshusers para acceso SSH..."
    if ! getent group sshusers > /dev/null 2>&1; then
        groupadd sshusers
        check_error $? "Error al crear grupo sshusers"
    else
        log "El grupo sshusers ya existe"
    fi

    log "Configurando fail2ban para Debian 13..."
    cat > /etc/fail2ban/jail.local <<EOF
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
    check_error $? "Error al configurar fail2ban"
    if [ "$DEBIAN_VERSION" -ge 13 ]; then
        echo "sshd_backend = systemd" >> /etc/fail2ban/paths-debian.conf
        check_error $? "Error al configurar backend systemd para fail2ban"
    fi

    log "Configurando límites del sistema..."
    cat > /etc/security/limits.conf <<EOF
*               soft    nofile          65535
*               hard    nofile          65535
*               soft    nproc           65535
*               hard    nproc           65535
root            soft    nofile          65535
root            hard    nofile          65535
root            soft    nproc           65535
root            hard    nproc           65535
EOF
    check_error $? "Error al configurar límites del sistema"
    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/limits.conf <<EOF
[Manager]
DefaultLimitNOFILE=65535
DefaultLimitNPROC=65535
EOF
    check_error $? "Error al configurar límites de systemd"

    log "Configurando timezone..."
    timedatectl set-timezone UTC
    check_error $? "Error al configurar timezone"

    log "Configurando NTP..."
    systemctl enable systemd-timesyncd
    check_error $? "Error al habilitar systemd-timesyncd"
    systemctl start systemd-timesyncd
    check_error $? "Error al iniciar systemd-timesyncd"

    log "Configurando auditoría de seguridad..."
    systemctl enable auditd
    check_error $? "Error al habilitar auditd"
    systemctl start auditd
    check_error $? "Error al iniciar auditd"

    create_admin_user() {
        log "Creando o configurando usuario administrador..."
        while true; do
            read -p "Ingrese el nombre del usuario administrador: " admin_user
            if [ -z "$admin_user" ]; then
                error "El nombre de usuario no puede estar vacío"
            fi
            if id "$admin_user" &>/dev/null; then
                log "El usuario $admin_user ya existe"
                read -p "¿Desea usar el usuario existente $admin_user como administrador? (s/n, predeterminado: s): " use_existing
                use_existing=${use_existing:-s}
                if [[ "$use_existing" =~ ^[sS]$ ]]; then
                    log "Configurando $admin_user como administrador..."
                    usermod -aG sudo "$admin_user"
                    check_error $? "Error al añadir $admin_user al grupo sudo"
                    usermod -aG sshusers "$admin_user"
                    check_error $? "Error al añadir $admin_user al grupo sshusers"
                    log "Usuario $admin_user configurado como administrador y añadido a los grupos sudo y sshusers"
                    break
                else
                    log "Por favor, ingrese un nombre de usuario diferente"
                fi
            else
                log "Creando usuario $admin_user..."
                adduser "$admin_user"
                check_error $? "Error al crear usuario $admin_user"
                usermod -aG sudo "$admin_user"
                check_error $? "Error al añadir $admin_user al grupo sudo"
                usermod -aG sshusers "$admin_user"
                check_error $? "Error al añadir $admin_user al grupo sshusers"
                log "Usuario $admin_user creado y añadido a los grupos sudo y sshusers"
                break
            fi
        done
        if [[ "$password_auth" == "no" ]]; then
            log "Por favor, configure la autenticación por clave SSH para $admin_user, ya que la autenticación por contraseña está deshabilitada"
        else
            log "Configure la autenticación por clave SSH para $admin_user o use la contraseña proporcionada"
        fi
    }
    create_admin_user

    log "Reiniciando servicios..."
    systemctl restart fail2ban
    check_error $? "Error al reiniciar fail2ban"
    sshd -t
    check_error $? "Error en la configuración de SSH. No se reiniciará el servicio"
    systemctl restart ssh
    check_error $? "Error al reiniciar ssh"

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
