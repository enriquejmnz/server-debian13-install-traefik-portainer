#!/bin/bash
#
# main.sh - Script principal para configurar y asegurar un servidor Debian 13
# Autor: Claude, con asistencia de Grok - Actualizado para Debian 13 (Trixie)
# Fecha: 2025-09-02
#
# Este script modularizado llama a funciones específicas desde el directorio /modules.

set -e
set -o pipefail

# Directorio de módulos
MODULES_DIR="modules"

# Cargar funciones comunes
if [ -f "$MODULES_DIR/common.sh" ]; then
  source "$MODULES_DIR/common.sh"
else
  echo "[ERROR] El archivo de funciones comunes '$MODULES_DIR/common.sh' no se encuentra."
  exit 1
fi

# Cargar todos los módulos de funciones
for module in "$MODULES_DIR"/*.sh; do
  if [ -f "$module" ] && [[ $module != *"/common.sh" ]]; then
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
if [ "$(id -u)" -ne 0 ]; then
  error "Este script debe ejecutarse como root"
fi

# Detectar versión de Debian al inicio
detect_debian_version

# Menú interactivo
show_menu() {
  clear
  echo -e "${GREEN}=== Configuración de Servidor Debian 13 (Trixie) ===${NC}"
  echo "1. Asegurar el servidor"
  echo "2. Instalar Docker y Docker Compose"
  echo "3. Instalar Traefik y Portainer"
  echo "4. Verificar y actualizar Traefik y Portainer"
  echo "5. Ejecutar todos los procesos secuencialmente (1-3)"
  echo "6. Salir"
  echo -e "${YELLOW}Seleccione una opción (1-6):${NC} "
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
