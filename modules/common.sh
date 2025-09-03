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
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DEBIAN_VERSION=$(echo $VERSION_ID | cut -d. -f1)
        DEBIAN_CODENAME=$VERSION_CODENAME
        log "Detectada Debian $DEBIAN_VERSION ($DEBIAN_CODENAME)"
    else
        error "No se pudo detectar la versión de Debian"
    fi
}

# Función para manejo de errores
check_error() {
    local exit_code=$1
    local message=$2
    if [ $exit_code -ne 0 ]; then
        error "$message"
    fi
}

# Función para mostrar mensajes y guardar en el log
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "$message" >> "$LOG_FILE"
}

warn() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "$message" >> "$LOG_FILE"
}

error() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$message" >> "$LOG_FILE"
    exit 1
}
