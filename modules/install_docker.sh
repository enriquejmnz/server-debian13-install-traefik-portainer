#!/bin/bash
# modules/install_docker.sh - Módulo para instalar Docker y Docker Compose
# Corregido para Debian 13 (Trixie) eliminando dependencias obsoletas.

# Función para instalar Docker
install_docker() {
    log "Iniciando instalación de Docker..."

    log "Eliminando instalaciones previas de Docker..."
    apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin 2>/dev/null || warn "No hay instalaciones previas de Docker"
    rm -rf /var/lib/docker /var/lib/containerd 2>/dev/null || true

    log "Actualizando el sistema e instalando dependencias..."
    apt-get update
    check_error $? "Error al actualizar índices de paquetes"
    # Se eliminan 'software-properties-common' y 'apt-transport-https' por ser innecesarios/obsoletos en Debian 13.
    apt-get install -y ca-certificates curl gnupg lsb-release
    check_error $? "Error al instalar dependencias"

    log "Configurando repositorio oficial de Docker..."
    install -m 0755 -d /etc/apt/keyrings
    check_error $? "Error al crear directorio /etc/apt/keyrings"
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    check_error $? "Error al descargar la clave GPG de Docker"
    chmod a+r /etc/apt/keyrings/docker.gpg
    check_error $? "Error al configurar permisos de la clave GPG"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    check_error $? "Error al configurar el repositorio de Docker"

    log "Actualizando índice de paquetes..."
    apt-get update
    check_error $? "Error al actualizar el índice de paquetes"

    log "Instalando Docker Engine y Docker Compose..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_error $? "Error al instalar Docker"

    if ! command -v docker &> /dev/null; then error "Docker no se instaló correctamente"; fi
    if ! docker compose version &> /dev/null; then error "Docker Compose no se instaló correctamente"; fi

    log "Configurando Docker para que inicie automáticamente..."
    systemctl enable docker.service
    check_error $? "Error al habilitar Docker"
    systemctl enable containerd.service
    check_error $? "Error al habilitar containerd"
    systemctl start docker
    check_error $? "Error al iniciar Docker"

    create_docker_user() {
        log "Configurando usuario para Docker..."
        read -p "Ingrese el nombre de usuario que administrará Docker (dejarlo vacío para omitir): " docker_user
        if [ -n "$docker_user" ]; then
            if id "$docker_user" &>/dev/null; then
                log "Añadiendo usuario $docker_user al grupo docker..."
                usermod -aG docker "$docker_user"
                check_error $? "Error al añadir $docker_user al grupo docker"
            else
                log "Creando usuario $docker_user..."
                # Usar adduser en lugar de useradd para una creación interactiva y completa del perfil.
                adduser "$docker_user"
                check_error $? "Error al crear usuario $docker_user"
                usermod -aG docker "$docker_user"
                check_error $? "Error al añadir $docker_user al grupo docker"
            fi
            log "Usuario $docker_user añadido al grupo docker"
        else
            warn "No se ha especificado ningún usuario para Docker"
            # Asegurarse de que la variable esté vacía si no se proporciona un usuario.
            docker_user=""
        fi
    }
    create_docker_user

    log "Configurando protección del daemon de Docker..."
    mkdir -p /etc/docker
    check_error $? "Error al crear directorio /etc/docker"
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "default-ulimits": { "nofile": { "Name": "nofile", "Hard": 64000, "Soft": 64000 } },
  "icc": false,
  "no-new-privileges": true,
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "ip6tables": true,
  "iptables": true
}
EOF
    check_error $? "Error al configurar daemon.json"

    log "Reiniciando Docker para aplicar la configuración..."
    systemctl restart docker
    check_error $? "Error al reiniciar Docker"

    log "Verificando instalación de Docker..."
    docker --version
    docker compose version

    log "Creando directorio para Docker Compose..."
    mkdir -p /opt/docker-compose
    check_error $? "Error al crear directorio /opt/docker-compose"
    chmod 755 /opt/docker-compose
    check_error $? "Error al configurar permisos de /opt/docker-compose"

    log "Instalación de Docker completada con éxito"
    if [ -n "$docker_user" ]; then
        log "  - Usuario configurado para administrar Docker: $docker_user"
        log "NOTA: Para que los cambios en los permisos del grupo tengan efecto, el usuario debe cerrar sesión e iniciarla nuevamente"
    fi
}
