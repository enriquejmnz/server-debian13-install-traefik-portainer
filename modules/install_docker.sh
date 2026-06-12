#!/bin/bash
# modules/install_docker.sh - Módulo para instalar Docker y Docker Compose
# Compatible con Debian 12 (Bookworm) y Debian 13 (Trixie).

configure_docker_user() {
  log "Configurando usuario para Docker..."
  prompt_or_default "DOCKER_USER" "Ingrese el nombre de usuario que administrará Docker (dejarlo vacío para omitir)"
  docker_user="${DOCKER_USER:-}"

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
  local docker_repo_url docker_keyring docker_architecture

  require_supported_debian

  clear
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║      INSTALACIÓN DE DOCKER ENGINE           ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  Este proceso realizará:"
  printf '%s\n' "    1. Eliminar instalaciones previas de Docker"
  printf '%s\n' "    2. Agregar repositorio oficial de Docker"
  printf '%s\n' "    3. Instalar Docker Engine + Compose plugin"
  printf '%s\n' "    4. Configurar daemon.json con hardening"
  printf '%s\n' "    5. Configurar usuario administrador (opcional)"
  echo ""

  if [[ $NON_INTERACTIVE == false ]]; then
    read -r -p "  Presione Enter para continuar (Ctrl+C para cancelar)..."
  fi

  log "Iniciando instalación de Docker..."

  log "Eliminando instalaciones previas de Docker..."
  apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin 2>/dev/null || warn "No hay instalaciones previas de Docker"
  rm -rf /var/lib/docker /var/lib/containerd 2>/dev/null || true

  log "Actualizando el sistema e instalando dependencias..."
  apt-get update || error "Error al actualizar índices de paquetes"
  apt-get install -y ca-certificates curl gnupg || error "Error al instalar dependencias"

  docker_repo_url="https://download.docker.com/linux/debian"
  docker_keyring="/etc/apt/keyrings/docker.gpg"
  docker_architecture=$(dpkg --print-architecture)

  log "Configurando repositorio oficial de Docker para Debian $DEBIAN_VERSION ($DEBIAN_CODENAME)..."
  install -m 0755 -d /etc/apt/keyrings || error "Error al crear directorio /etc/apt/keyrings"
  curl -fsSL "$docker_repo_url/gpg" | gpg --dearmor --yes -o "$docker_keyring" || error "Error al descargar la clave GPG de Docker"
  chmod a+r "$docker_keyring" || error "Error al configurar permisos de la clave GPG"
  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$docker_architecture signed-by=$docker_keyring] $docker_repo_url $DEBIAN_CODENAME stable
EOF

  log "Actualizando índice de paquetes..."
  apt-get update || error "Error al actualizar el índice de paquetes"

  log "Instalando Docker Engine y Docker Compose..."
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error "Error al instalar Docker"

  if ! command -v docker &>/dev/null; then
    error "Docker no se instaló correctamente"
  fi

  if ! docker compose version &>/dev/null; then
    error "Docker Compose no se instaló correctamente"
  fi

  log "Configurando Docker para que inicie automáticamente..."
  systemctl enable docker.service || error "Error al habilitar Docker"
  systemctl enable containerd.service || error "Error al habilitar containerd"
  systemctl start docker || error "Error al iniciar Docker"
  log "✓ Docker Engine instalado y en ejecución"

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
  "ip6tables": true,
  "iptables": true
}
EOF

  log "Reiniciando Docker para aplicar la configuración..."
  systemctl restart docker || error "Error al reiniciar Docker"
  log "✓ daemon.json aplicado"

  log "Verificando instalación de Docker..."
  docker --version
  docker compose version

  log "Creando directorio para Docker Compose..."
  mkdir -p /opt/docker-compose || error "Error al crear directorio /opt/docker-compose"
  chmod 755 /opt/docker-compose || error "Error al configurar permisos de /opt/docker-compose"

  echo ""
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║      DOCKER INSTALADO CON ÉXITO             ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  🐳 Docker Engine:       instalado y en ejecución"
  printf '%s\n' "  🐳 Docker Compose:      plugin v2 disponible"
  printf '%s\n' "  🛡️  daemon.json:         hardening aplicado"
  if [[ -n $docker_user ]]; then
    printf '%s\n' "  👤 Usuario Docker:       ${GREEN}${docker_user}${NC}"
    printf '%s\n' "  ⚠️  NOTA: Para usar docker sin sudo, cerrar e iniciar sesión."
  fi
  echo ""
  log "Instalación de Docker completada con éxito"
}
