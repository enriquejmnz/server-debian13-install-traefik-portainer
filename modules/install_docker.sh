#!/bin/bash
# modules/install_docker.sh - Módulo para instalar Docker y Docker Compose
# Corregido para Debian 13 (Trixie) eliminando dependencias obsoletas.

configure_docker_user() {
  log "Configurando usuario para Docker..."
  read -r -p "Ingrese el nombre de usuario que administrará Docker (dejarlo vacío para omitir): " docker_user

  if [[ -z $docker_user ]]; then
    warn "No se ha especificado ningún usuario para Docker"
    return 0
  fi

  if id "$docker_user" >/dev/null 2>&1; then
    log "Añadiendo usuario $docker_user al grupo docker..."
    usermod -aG docker "$docker_user" || error "Error al añadir $docker_user al grupo docker"
  else
    log "Creando usuario $docker_user..."
    adduser "$docker_user" || error "Error al crear usuario $docker_user"
    usermod -aG docker "$docker_user" || error "Error al añadir $docker_user al grupo docker"
  fi

  log "Usuario $docker_user añadido al grupo docker"
}

# Función para instalar Docker
install_docker() {
  log "Iniciando instalación de Docker..."

  log "Eliminando instalaciones previas de Docker..."
  apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin 2>/dev/null || warn "No hay instalaciones previas de Docker"
  rm -rf /var/lib/docker /var/lib/containerd 2>/dev/null || true

  log "Actualizando el sistema e instalando dependencias..."
  apt-get update || error "Error al actualizar índices de paquetes"
  # Se eliminan 'software-properties-common' y 'apt-transport-https' por ser innecesarios/obsoletos en Debian 13.
  apt-get install -y ca-certificates curl gnupg lsb-release || error "Error al instalar dependencias"

  log "Configurando repositorio oficial de Docker..."
  install -m 0755 -d /etc/apt/keyrings || error "Error al crear directorio /etc/apt/keyrings"
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || error "Error al descargar la clave GPG de Docker"
  chmod a+r /etc/apt/keyrings/docker.gpg || error "Error al configurar permisos de la clave GPG"
  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable
EOF

  log "Actualizando índice de paquetes..."
  apt-get update || error "Error al actualizar el índice de paquetes"

  log "Instalando Docker Engine y Docker Compose..."
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error "Error al instalar Docker"

  if ! command -v docker &>/dev/null; then error "Docker no se instaló correctamente"; fi
  if ! docker compose version &>/dev/null; then error "Docker Compose no se instaló correctamente"; fi

  log "Configurando Docker para que inicie automáticamente..."
  systemctl enable docker.service || error "Error al habilitar Docker"
  systemctl enable containerd.service || error "Error al habilitar containerd"
  systemctl start docker || error "Error al iniciar Docker"

  docker_user=""
  configure_docker_user

  log "Configurando protección del daemon de Docker..."
  mkdir -p /etc/docker || error "Error al crear directorio /etc/docker"
  cat >/etc/docker/daemon.json <<EOF
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

  log "Reiniciando Docker para aplicar la configuración..."
  systemctl restart docker || error "Error al reiniciar Docker"

  log "Verificando instalación de Docker..."
  docker --version
  docker compose version

  log "Creando directorio para Docker Compose..."
  mkdir -p /opt/docker-compose || error "Error al crear directorio /opt/docker-compose"
  chmod 755 /opt/docker-compose || error "Error al configurar permisos de /opt/docker-compose"

  log "Instalación de Docker completada con éxito"
  if [ -n "$docker_user" ]; then
    log "  - Usuario configurado para administrar Docker: $docker_user"
    log "NOTA: Para que los cambios en los permisos del grupo tengan efecto, el usuario debe cerrar sesión e iniciarla nuevamente"
  fi
}
