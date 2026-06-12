#!/bin/bash
# modules/common.sh - Funciones y variables comunes para el instalador

# Asegurar que el PATH incluya /usr/sbin y /sbin
export PATH="$PATH:/usr/sbin:/sbin"

# Colores para la salida (solo si se ejecuta en un terminal interactivo)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

# Versión del instalador (semver)
SCRIPT_VERSION="1.0.0"

# Configuración compartida del proyecto — independiente de Ansible
COMMON_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$COMMON_DIR")
SHARED_VERSIONS_FILE="$COMMON_DIR/versions.env"

load_portainer_version() {
  if [[ ! -f $SHARED_VERSIONS_FILE ]]; then
    printf '%s\n' "[ERROR] No se encontró el archivo de versiones ($SHARED_VERSIONS_FILE)." >&2
    exit 1
  fi

  # shellcheck source=/dev/null
  . "$SHARED_VERSIONS_FILE"

  if [[ -z ${PORTAINER_VERSION:-} ]]; then
    printf '%s\n' "[ERROR] PORTAINER_VERSION no está definido en $SHARED_VERSIONS_FILE" >&2
    exit 1
  fi

  if [[ -z ${TRAEFIK_VERSION:-} ]]; then
    printf '%s\n' "[ERROR] TRAEFIK_VERSION no está definido en $SHARED_VERSIONS_FILE" >&2
    exit 1
  fi
}

load_portainer_version

# Configuración de logs
LOG_FILE="${LOG_FILE:-/var/log/server-setup.log}"
INSTALL_DIR="${INSTALL_DIR:-/opt/traefik-portainer}"
TRAEFIK_IMAGE="${TRAEFIK_IMAGE:-traefik:${TRAEFIK_VERSION}}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:${PORTAINER_VERSION}}"
SUPPORTED_DEBIAN_VERSIONS=("12" "13")
SUPPORTED_DEBIAN_LABEL="Debian 12 (Bookworm) y Debian 13 (Trixie)"

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

is_supported_debian_version() {
  local version=$1
  local supported_version

  for supported_version in "${SUPPORTED_DEBIAN_VERSIONS[@]}"; do
    if [[ $version == "$supported_version" ]]; then
      return 0
    fi
  done

  return 1
}

unsupported_bash_platform() {
  local current_platform=$1

  error "Plataforma no soportada para la ruta Bash: ${current_platform}. Este instalador solo soporta ${SUPPORTED_DEBIAN_LABEL}. Ubuntu Server no está soportado actualmente."
}

# Función para detectar la versión de Debian soportada por la ruta Bash
detect_debian_version() {
  if [[ ! -f /etc/os-release ]]; then
    error "No se pudo detectar el sistema operativo: falta /etc/os-release"
  fi

  # shellcheck source=/etc/os-release
  . /etc/os-release

  DISTRO_ID="${ID:-}"
  DISTRO_NAME="${PRETTY_NAME:-${NAME:-desconocido}}"

  if [[ -z ${DISTRO_ID:-} || -z ${VERSION_ID:-} ]]; then
    error "No se pudo detectar una plataforma compatible: ID o VERSION_ID no definidos en /etc/os-release"
  fi

  if [[ $DISTRO_ID != "debian" ]]; then
    unsupported_bash_platform "$DISTRO_NAME"
  fi

  DEBIAN_VERSION="${VERSION_ID%%.*}"
  DEBIAN_CODENAME="${VERSION_CODENAME:-}"

  if [[ ! $DEBIAN_VERSION =~ ^[0-9]+$ ]]; then
    error "No se pudo detectar una versión de Debian válida: '$DEBIAN_VERSION'"
  fi

  if [[ -z $DEBIAN_CODENAME ]]; then
    case $DEBIAN_VERSION in
    12)
      DEBIAN_CODENAME="bookworm"
      ;;
    13)
      DEBIAN_CODENAME="trixie"
      ;;
    esac
  fi

  if ! is_supported_debian_version "$DEBIAN_VERSION"; then
    unsupported_bash_platform "$DISTRO_NAME"
  fi

  if [[ -z $DEBIAN_CODENAME ]]; then
    error "No se pudo resolver el codename de Debian para la versión '$DEBIAN_VERSION'"
  fi

  log "Detectado Debian $DEBIAN_VERSION ($DEBIAN_CODENAME). La ruta Bash soporta ${SUPPORTED_DEBIAN_LABEL}."
}

require_supported_debian() {
  if [[ -z ${DEBIAN_VERSION:-} || -z ${DEBIAN_CODENAME:-} || -z ${DISTRO_ID:-} ]]; then
    detect_debian_version
    return 0
  fi

  if [[ $DISTRO_ID != "debian" ]] || ! is_supported_debian_version "$DEBIAN_VERSION"; then
    unsupported_bash_platform "${DISTRO_NAME:-$DISTRO_ID}"
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
