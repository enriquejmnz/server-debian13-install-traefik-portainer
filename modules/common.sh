#!/bin/bash
# modules/common.sh - Funciones y variables comunes para el instalador

# Asegurar que el PATH incluya /usr/sbin y /sbin
export PATH="$PATH:/usr/sbin:/sbin"

# Colores para la salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Configuración de logs
LOG_FILE="/var/log/server-setup.log"
INSTALL_DIR="${INSTALL_DIR:-/opt/traefik-portainer}"
TRAEFIK_IMAGE="${TRAEFIK_IMAGE:-traefik:v3.0}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:2.21.5}"

# Función para validar correo electrónico
validate_email() {
  local email=$1
  if [[ ! $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Correo electrónico inválido: $email"
  fi
}

# Función para validar el formato de un correo (devuelve 0 si es válido, 1 si no)
# Usada para bucles de re-intento sin salir del script.
is_valid_email() {
  local email=$1
  if [[ $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    return 0 # Éxito (válido)
  else
    return 1 # Fallo (inválido)
  fi
}

# Función para validar dominio
validate_domain() {
  local domain=$1
  if [[ ! $domain =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Dominio inválido: $domain"
  fi
}

# Función para detectar la versión de Debian
detect_debian_version() {
  if [[ ! -f /etc/os-release ]]; then
    error "No se pudo detectar la versión de Debian"
  fi

  # shellcheck source=/etc/os-release
  . /etc/os-release

  if [[ -z ${VERSION_ID:-} || -z ${VERSION_CODENAME:-} ]]; then
    error "No se pudo detectar la versión de Debian: VERSION_ID o VERSION_CODENAME no definidos"
  fi

  DEBIAN_VERSION="${VERSION_ID%%.*}"
  DEBIAN_CODENAME="${VERSION_CODENAME}"

  if [[ ! $DEBIAN_VERSION =~ ^[0-9]+$ ]]; then
    error "No se pudo detectar una versión de Debian válida: '$DEBIAN_VERSION'"
  fi

  log "Detectada Debian $DEBIAN_VERSION ($DEBIAN_CODENAME)"
}

# Función para manejo de errores
check_error() {
  local exit_code=$1
  local message=$2
  if [[ $exit_code -ne 0 ]]; then
    error "$message"
  fi
}

write_log_entry() {
  local message=$1
  local target_log_file

  target_log_file="${LOG_FILE:-/tmp/server-setup.log}"
  if ! printf '%s\n' "$message" >>"$target_log_file" 2>/dev/null; then
    target_log_file="/tmp/server-setup.log"
    LOG_FILE="$target_log_file"
    touch "$target_log_file" 2>/dev/null || return 0
    chmod 600 "$target_log_file" 2>/dev/null || true
    printf '%s\n' "$message" >>"$target_log_file" 2>/dev/null || true
  fi
}

# Función para mostrar mensajes y guardar en el log
log() {
  local message
  message="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
  echo -e "${GREEN}[INFO]${NC} $1"
  write_log_entry "$message"
}

warn() {
  local message
  message="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
  echo -e "${YELLOW}[WARN]${NC} $1"
  write_log_entry "$message"
}

error() {
  local message
  message="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
  echo -e "${RED}[ERROR]${NC} $1"
  write_log_entry "$message"
  exit 1
}
