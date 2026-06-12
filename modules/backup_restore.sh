#!/bin/bash
# modules/backup_restore.sh - Backup y restauración del stack Traefik + Portainer

backup_stack() {
  require_supported_debian
  if [[ ! -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    error "El stack de Traefik y Portainer no está instalado en $INSTALL_DIR."
  fi

  clear
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║      BACKUP DEL STACK TRAEFIK + PORTAINER   ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  Este proceso realizará:"
  printf '%s\n' "    1. Detener contenedores (graceful) para consistencia"
  printf '%s\n' "    2. Empaquetar configuraciones y certificados"
  printf '%s\n' "    3. Reiniciar contenedores"
  echo ""

  if [[ $NON_INTERACTIVE == false ]]; then
    read -r -p "  Presione Enter para continuar (Ctrl+C para cancelar)..."
  fi

  log "Deteniendo contenedores para garantizar consistencia de datos..."
  (cd "$INSTALL_DIR" && docker compose stop) || error "Error al detener contenedores"

  local backup_file
  backup_file="traefik-portainer-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
  local backup_path
  backup_path="$(pwd)/$backup_file"

  log "Creando archivo de backup en $backup_path..."
  (cd /opt && tar -czf "$backup_path" "traefik-portainer") || error "Error al crear el archivo de backup"

  log "Reiniciando contenedores..."
  (cd "$INSTALL_DIR" && docker compose start) || error "Error al reiniciar contenedores"

  local backup_size
  backup_size=$(du -h "$backup_path" | awk '{print $1}')

  echo ""
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║           BACKUP COMPLETADO CON ÉXITO       ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  📦 Archivo:   ${GREEN}$backup_path${NC}"
  printf '%s\n' "  📏 Tamaño:    ${GREEN}$backup_size${NC}"
  echo ""
  printf '%s\n' "  💡 Para transferir a otro servidor, usa:"
  printf '%s\n' "     ${YELLOW}scp $backup_path usuario@nuevo-servidor:/tmp/${NC}"
  echo ""
  log "Backup finalizado."
}

restore_stack() {
  require_supported_debian
  if ! command -v docker &>/dev/null; then
    error "Docker no está instalado. Instálelo primero."
  fi

  local backup_file="${BACKUP_FILE:-}"

  if [[ -z $backup_file ]]; then
    read -r -p "Ingrese la ruta del archivo de backup (.tar.gz): " backup_file
  fi

  if [[ ! -f $backup_file ]]; then
    error "El archivo de backup no existe: $backup_file"
  fi

  if ! tar -tzf "$backup_file" &>/dev/null; then
    error "El archivo no es un backup válido o está corrupto."
  fi

  clear
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║     RESTAURACIÓN DEL STACK TRAEFIK+PORTAINER║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  Archivo seleccionado: ${GREEN}$backup_file${NC}"
  echo ""

  if [[ $NON_INTERACTIVE == false ]]; then
    read -r -p "  ¿Desea continuar? Esto sobrescribirá la configuración actual. (s/n): " confirm_restore
    if [[ ! $confirm_restore =~ ^[sS]$ ]]; then
      log "Restauración cancelada."
      return 0
    fi
  fi

  log "Deteniendo contenedores actuales (si existen)..."
  if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    (cd "$INSTALL_DIR" && docker compose stop) || true
  fi

  local pre_restore_backup
  pre_restore_backup="$INSTALL_DIR.pre-restore.$(date +%Y%m%d_%H%M%S)"
  if [[ -d $INSTALL_DIR ]]; then
    log "Creando backup preventivo del estado actual en $pre_restore_backup..."
    mv "$INSTALL_DIR" "$pre_restore_backup" || error "Error al respaldar estado actual"
  fi

  log "Extrayendo backup en $INSTALL_DIR..."
  mkdir -p "$INSTALL_DIR" || error "Error al crear directorio de instalación"
  tar -xzf "$backup_file" -C /opt || error "Error al extraer el backup"

  log "Aplicando permisos restrictivos de seguridad..."
  chmod 750 "$INSTALL_DIR" || error "Error en permisos de directorio"
  chmod 600 "$INSTALL_DIR/traefik-data/acme.json" 2>/dev/null || true
  chmod 600 "$INSTALL_DIR/traefik-data/configurations/dynamic.yml" 2>/dev/null || true

  log "Iniciando contenedores..."
  (cd "$INSTALL_DIR" && docker compose up -d) || error "Error al iniciar contenedores"

  sleep 3
  local traefik_status
  local portainer_status
  traefik_status=$(docker inspect --format '{{.State.Status}}' traefik 2>/dev/null || true)
  portainer_status=$(docker inspect --format '{{.State.Status}}' portainer 2>/dev/null || true)

  echo ""
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║        RESTAURACIÓN COMPLETADA CON ÉXITO    ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  if [[ $traefik_status == "running" && $portainer_status == "running" ]]; then
    printf '%s\n' "  ✅ Traefik:   corriendo"
    printf '%s\n' "  ✅ Portainer: corriendo"
    printf '%s\n' "  💾 Backup anterior guardado en: ${YELLOW}$pre_restore_backup${NC}"
  else
    printf '%s\n' "  ⚠️  Advertencia: Algunos contenedores no iniciaron correctamente."
    printf '%s\n' "     Verifique con: ${YELLOW}docker compose -f $INSTALL_DIR/docker-compose.yml logs${NC}"
  fi
  echo ""
  log "Restauración finalizada."
}

backup_restore_menu() {
  while true; do
    clear
    printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    printf '%s\n' "${GREEN}║        BACKUP Y MIGRACIÓN DEL STACK         ║${NC}"
    printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    printf '%s\n' "  1) Crear backup del stack actual"
    printf '%s\n' "  2) Restaurar stack desde archivo"
    printf '%s\n' "  3) Volver al menú principal"
    echo ""
    printf '%s' "${YELLOW}  Seleccione una opción (1-3):${NC} "
    read -r choice
    case $choice in
    1)
      backup_stack
      read -r -p "  Presione Enter para continuar..."
      ;;
    2)
      restore_stack
      read -r -p "  Presione Enter para continuar..."
      ;;
    3) return 0 ;;
    *)
      warn "Opción inválida."
      sleep 1
      ;;
    esac
  done
}
