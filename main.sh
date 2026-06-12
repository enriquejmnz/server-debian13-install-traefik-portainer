#!/bin/bash
#
# main.sh - Script principal para configurar y asegurar un servidor Debian 12/13
# Autor: Claude, con asistencia de Grok - Actualizado para Debian 12/13
# Fecha: 2025-09-02
#
# Este script modularizado llama a funciones específicas desde el directorio /modules.

set -e
set -o pipefail

# Directorio de módulos
MODULES_DIR="modules"

# Cargar funciones comunes
if [[ -f "$MODULES_DIR/common.sh" ]]; then
  source "$MODULES_DIR/common.sh"
else
  echo "[ERROR] El archivo de funciones comunes '$MODULES_DIR/common.sh' no se encuentra."
  exit 1
fi

# Cargar todos los módulos de funciones
for module in "$MODULES_DIR"/*.sh; do
  if [[ -f $module && $module != *"/common.sh" ]]; then
    source "$module"
  fi
done

initialize_log_file() {
  local requested_log_file fallback_log_file log_dir

  fallback_log_file="/tmp/server-setup.log"
  requested_log_file="${LOG_FILE:-$fallback_log_file}"
  log_dir=$(dirname "$requested_log_file")

  if [[ ! -d $log_dir ]] && ! mkdir -p "$log_dir" 2>/dev/null; then
    printf '%s\n' "[WARN] No se pudo crear el directorio de log '$log_dir'. Se usará '$fallback_log_file'."
    requested_log_file="$fallback_log_file"
  fi

  if ! touch "$requested_log_file" 2>/dev/null; then
    if [[ $requested_log_file != "$fallback_log_file" ]]; then
      printf '%s\n' "[WARN] No se pudo escribir en '$requested_log_file'. Se usará '$fallback_log_file'."
    fi

    requested_log_file="$fallback_log_file"
    if ! touch "$requested_log_file" 2>/dev/null; then
      printf '%s\n' "[ERROR] No se pudo inicializar ningún archivo de log."
      exit 1
    fi
  fi

  chmod 640 "$requested_log_file" 2>/dev/null || chmod 600 "$requested_log_file" 2>/dev/null || true
  LOG_FILE="$requested_log_file"
}

# Iniciar log y redirigir salida
initialize_log_file
exec > >(tee -a "$LOG_FILE") 2>&1

# Verificar si se ejecuta como root
if [[ $(id -u) -ne 0 ]]; then
  error "Este script debe ejecutarse como root"
fi

# Detectar plataforma soportada al inicio
detect_debian_version

# --- CLI argument parsing ---
NON_INTERACTIVE=false
STEP=""
ENV_FILE=""

show_usage() {
  cat <<EOF
Uso: ${0##*/} [OPCIONES]

Opciones:
  --help, -h              Muestra esta ayuda
  --non-interactive       Modo no interactivo (requiere .env)
  --step PASO             Ejecuta un paso específico y sale
                          Valores: secure, docker, traefik, update, all
  --env-file ARCHIVO      Ruta al archivo .env (defecto: ./.env)
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
  --help | -h)
    show_usage
    exit 0
    ;;
  --non-interactive)
    NON_INTERACTIVE=true
    shift
    ;;
  --step)
    STEP="${2?--step requiere un argumento}"
    shift 2
    ;;
  --env-file)
    ENV_FILE="${2?--env-file requiere un argumento}"
    shift 2
    ;;
  *) error "Opción desconocida: $1. Use --help." ;;
  esac
done

# Cargar .env si existe
ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"
if [[ -f $ENV_FILE ]]; then
  log "Cargando variables desde $ENV_FILE..."
  set -a
  source "$ENV_FILE"
  set +a
fi

# Si se especificó --step, ejecutar y salir
if [[ -n $STEP ]]; then
  case "$STEP" in
  secure) secure_server ;;
  docker) install_docker ;;
  traefik) install_traefik_portainer ;;
  update) update_traefik_portainer ;;
  all)
    secure_server
    install_docker
    install_traefik_portainer
    ;;
  *) error "Paso desconocido: $STEP. Valores: secure, docker, traefik, update, all" ;;
  esac
  exit 0
fi

# Menú interactivo
show_menu() {
  clear
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║    CONFIGURACIÓN DE SERVIDOR DEBIAN 12/13   ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  ${GREEN}1${NC}) Asegurar el servidor"
  printf '%s\n' "       UFW · SSH · fail2ban · auditd · límites"
  echo ""
  printf '%s\n' "  ${GREEN}2${NC}) Instalar Docker y Docker Compose"
  printf '%s\n' "       Docker Engine · daemon.json · usuario"
  echo ""
  printf '%s\n' "  ${GREEN}3${NC}) Instalar Traefik y Portainer"
  printf '%s\n' "       Reverse proxy · TLS automático · dashboard"
  echo ""
  printf '%s\n' "  ${GREEN}4${NC}) Buscar parches de seguridad"
  printf '%s\n' "       Traefik + Portainer · cambio de versión"
  echo ""
  printf '%s\n' "  ${GREEN}5${NC}) Instalación completa en secuencia"
  printf '%s\n' "       Ejecuta opciones 1 → 2 → 3"
  echo ""
  printf '%s\n' "  ${GREEN}6${NC}) Salir"
  echo ""
  printf '%s' "${YELLOW}  Seleccione una opción (1-6):${NC} "
}

# Procesar la selección del menú
process_choice() {
  local choice=$1
  case $choice in
  1)
    secure_server
    log "Presione Enter para volver al menú..."
    read -r
    ;;
  2)
    install_docker
    log "Presione Enter para volver al menú..."
    read -r
    ;;
  3)
    install_traefik_portainer
    log "Presione Enter para volver al menú..."
    read -r
    ;;
  4)
    update_traefik_portainer
    log "Presione Enter para volver al menú..."
    read -r
    ;;
  5)
    log "Ejecutando todos los procesos secuencialmente..."
    secure_server
    install_docker
    install_traefik_portainer
    log "Todos los procesos completados. Presione Enter para volver al menú..."
    read -r
    ;;
  6)
    log "Saliendo..."
    exit 0
    ;;
  *)
    warn "Opción inválida. Por favor, seleccione una opción válida."
    log "Presione Enter para continuar..."
    read -r
    ;;
  esac
}

# Bucle principal del menú
main_loop() {
  while true; do
    show_menu
    read -r choice
    process_choice "$choice"
  done
}

# Ejecutar el script
main_loop
