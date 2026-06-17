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

# Extrae el FQDN de una regla Host() de Traefik en docker-compose.yml
# Uso: restore_extract_fqdn /opt/traefik-portainer/docker-compose.yml traefik-secure
restore_extract_fqdn() {
  local compose_file="$1"
  local router_name="$2"
  local rule

  rule=$(grep -E "traefik\.http\.routers\.${router_name}\.rule=Host\(" "$compose_file" 2>/dev/null | head -1)
  if [[ -z $rule ]]; then
    return 1
  fi
  # shellcheck disable=SC2016
  printf '%s' "$rule" | sed -E 's/.*Host\(`([^`]+)`\).*/\1/'
}

# Separa un FQDN en subdominio y dominio base (asume subdominio de un solo segmento)
# Uso: read -r sub domain < <(restore_split_fqdn traefik.example.com)
restore_split_fqdn() {
  local fqdn="$1"
  local subdomain domain

  subdomain=$(printf '%s' "$fqdn" | cut -d. -f1)
  domain=$(printf '%s' "$fqdn" | cut -d. -f2-)
  printf '%s %s' "$subdomain" "$domain"
}

# Pregunta (interactivo) o lee variables de entorno (no interactivo) para el cambio de dominio.
# Guarda los resultados en variables RESTORE_*.
restore_prompt_domain_change() {
  local current_traefik_fqdn="$1"
  local current_portainer_fqdn="$2"
  local current_email="$3"

  local current_traefik_subdomain current_traefik_domain
  local current_portainer_subdomain current_portainer_domain
  read -r current_traefik_subdomain current_traefik_domain < <(restore_split_fqdn "$current_traefik_fqdn")
  read -r current_portainer_subdomain current_portainer_domain < <(restore_split_fqdn "$current_portainer_fqdn")

  local change_domain="n"
  local new_base_domain="$current_traefik_domain"
  local new_traefik_subdomain="$current_traefik_subdomain"
  local new_portainer_subdomain="$current_portainer_subdomain"
  local new_email="$current_email"
  local force_new_acme="n"

  if [[ $NON_INTERACTIVE == true ]]; then
    if [[ -n ${NEW_BASE_DOMAIN:-} ]]; then
      change_domain="s"
      new_base_domain="$NEW_BASE_DOMAIN"
      new_traefik_subdomain="${NEW_TRAEFIK_SUBDOMAIN:-$current_traefik_subdomain}"
      new_portainer_subdomain="${NEW_PORTAINER_SUBDOMAIN:-$current_portainer_subdomain}"
    fi
    new_email="${NEW_LETSENCRYPT_EMAIL:-$current_email}"
    force_new_acme="${FORCE_NEW_ACME:-n}"
  else
    echo ""
    printf '%s\n' "  Dominio actual detectado:"
    printf '%s\n' "    Traefik:   ${GREEN}$current_traefik_fqdn${NC}"
    printf '%s\n' "    Portainer: ${GREEN}$current_portainer_fqdn${NC}"
    printf '%s\n' "    Email LE:  ${GREEN}$current_email${NC}"
    echo ""

    read -r -p "  ¿Desea cambiar el dominio base del stack? (s/n, predeterminado: n): " change_domain
    if [[ $change_domain =~ ^[sS]$ ]]; then
      while true; do
        read -r -p "  Nuevo dominio base (ejemplo: nuevodominio.com): " new_base_domain
        if [[ $new_base_domain =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
          break
        else
          warn "Dominio inválido. Inténtelo de nuevo."
        fi
      done

      read -r -p "  Nuevo subdominio para Traefik (predeterminado: $current_traefik_subdomain): " new_traefik_subdomain
      new_traefik_subdomain="${new_traefik_subdomain:-$current_traefik_subdomain}"

      read -r -p "  Nuevo subdominio para Portainer (predeterminado: $current_portainer_subdomain): " new_portainer_subdomain
      new_portainer_subdomain="${new_portainer_subdomain:-$current_portainer_subdomain}"
    fi

    read -r -p "  ¿Cambiar el email de Let's Encrypt? (s/n, predeterminado: n): " change_email
    if [[ ${change_email:-n} =~ ^[sS]$ ]]; then
      while true; do
        read -r -p "  Nuevo email para Let's Encrypt: " new_email
        if is_valid_email "$new_email"; then
          break
        else
          warn "Email inválido. Inténtelo de nuevo."
        fi
      done
    fi

    if [[ $change_domain =~ ^[sS]$ ]]; then
      read -r -p "  ¿Forzar nueva emisión de certificados? (recomendado, s/n, predeterminado: n): " force_new_acme
    fi
  fi

  RESTORE_NEW_TRAEFIK_FQDN="${new_traefik_subdomain}.${new_base_domain}"
  RESTORE_NEW_PORTAINER_FQDN="${new_portainer_subdomain}.${new_base_domain}"
  RESTORE_NEW_EMAIL="$new_email"
  RESTORE_FORCE_NEW_ACME="$force_new_acme"
}

# Aplica el cambio de dominio y email en los archivos de configuración del stack.
restore_apply_domain_change() {
  local compose_file="$1"
  local traefik_file="$2"
  local acme_file="$3"
  local old_traefik_fqdn="$4"
  local old_portainer_fqdn="$5"
  local old_email="$6"

  if [[ $RESTORE_NEW_TRAEFIK_FQDN != "$old_traefik_fqdn" ]]; then
    sed -i "s|${old_traefik_fqdn}|${RESTORE_NEW_TRAEFIK_FQDN}|g" "$compose_file" || error "Error al actualizar el dominio de Traefik en docker-compose.yml"
    log "Dominio de Traefik actualizado: $old_traefik_fqdn → $RESTORE_NEW_TRAEFIK_FQDN"
  fi

  if [[ $RESTORE_NEW_PORTAINER_FQDN != "$old_portainer_fqdn" ]]; then
    sed -i "s|${old_portainer_fqdn}|${RESTORE_NEW_PORTAINER_FQDN}|g" "$compose_file" || error "Error al actualizar el dominio de Portainer en docker-compose.yml"
    log "Dominio de Portainer actualizado: $old_portainer_fqdn → $RESTORE_NEW_PORTAINER_FQDN"
  fi

  if [[ $RESTORE_NEW_EMAIL != "$old_email" && -f $traefik_file ]]; then
    sed -i "s|email: ${old_email}|email: ${RESTORE_NEW_EMAIL}|g" "$traefik_file" || error "Error al actualizar el email en traefik.yml"
    log "Email de Let's Encrypt actualizado: $old_email → $RESTORE_NEW_EMAIL"
  fi

  if [[ $RESTORE_FORCE_NEW_ACME =~ ^[sS]$ || $RESTORE_FORCE_NEW_ACME == "true" ]]; then
    if [[ -f $acme_file ]]; then
      local acme_backup
      acme_backup="${acme_file}.old-domain.$(date +%Y%m%d_%H%M%S)"
      mv "$acme_file" "$acme_backup" || error "Error al respaldar acme.json"
      log "Certificados antiguos respaldados en $acme_backup"
    fi
  fi
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

  if [[ ! -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    error "El backup no contiene un docker-compose.yml válido."
  fi

  local compose_file="$INSTALL_DIR/docker-compose.yml"
  local traefik_file="$INSTALL_DIR/traefik-data/traefik.yml"
  local acme_file="$INSTALL_DIR/traefik-data/acme.json"

  local current_traefik_fqdn
  local current_portainer_fqdn
  current_traefik_fqdn=$(restore_extract_fqdn "$compose_file" "traefik-secure") || error "No se pudo detectar el dominio actual de Traefik en docker-compose.yml"
  current_portainer_fqdn=$(restore_extract_fqdn "$compose_file" "portainer-secure") || error "No se pudo detectar el dominio actual de Portainer en docker-compose.yml"

  local current_email=""
  if [[ -f $traefik_file ]]; then
    current_email=$(grep -E '^\s*email:\s*' "$traefik_file" | head -1 | sed -E 's/^\s*email:\s*//')
  fi

  # Solicitar cambio de dominio opcional
  restore_prompt_domain_change "$current_traefik_fqdn" "$current_portainer_fqdn" "$current_email"
  restore_apply_domain_change "$compose_file" "$traefik_file" "$acme_file" "$current_traefik_fqdn" "$current_portainer_fqdn" "$current_email"

  # Validar DNS del dominio resultante
  validate_dns_for_fqdns "$RESTORE_NEW_TRAEFIK_FQDN" "$RESTORE_NEW_PORTAINER_FQDN"

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
    printf '%s\n' "  ✅ Traefik:   ${GREEN}https://$RESTORE_NEW_TRAEFIK_FQDN${NC}"
    printf '%s\n' "  ✅ Portainer: ${GREEN}https://$RESTORE_NEW_PORTAINER_FQDN${NC}"
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
