#!/bin/bash
# modules/update_traefik.sh - Módulo para verificar y actualizar Traefik y Portainer

# Función para verificar y actualizar Traefik y Portainer
update_traefik_portainer() {
  require_supported_debian

  clear
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║   PARCHE DE SEGURIDAD — TRAEFIK+PORTAINER   ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  Este proceso realizará:"
  printf '%s\n' "    1. Mostrar versiones actuales"
  printf '%s\n' "    2. Opción de cambiar versión de Traefik/Portainer"
  printf '%s\n' "    3. Buscar parches de seguridad (pull)"
  printf '%s\n' "    4. Backup preventivo de la DB de Portainer"
  printf '%s\n' "    5. Aplicar actualización si hay cambios"
  echo ""

  if [[ $NON_INTERACTIVE == false ]]; then
    read -r -p "  Presione Enter para continuar (Ctrl+C para cancelar)..."
  fi

  log "Verificando actualizaciones para Traefik y Portainer..."

  if ! command -v docker &>/dev/null; then
    error "Docker no está instalado."
  fi
  if [[ ! -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    error "El stack de Traefik y Portainer no parece estar instalado en $INSTALL_DIR."
  fi

  # Mostrar versiones actuales y ofrecer cambio manual
  log "Versiones instaladas:"
  log "  Traefik:  ${TRAEFIK_IMAGE}"
  log "  Portainer: ${PORTAINER_IMAGE}"
  log "Para cambiar de versión, editar manualmente: $SHARED_VERSIONS_FILE"
  echo ""

  if [[ $NON_INTERACTIVE == false ]]; then
    read -r -p "¿Desea cambiar la versión de Traefik? (s/n, Enter para omitir): " change_traefik_ver
    if [[ $change_traefik_ver =~ ^[sS]$ ]]; then
      printf '%s\n' "  Formato: v3.8.0 (con 'v' inicial) — actual: ${TRAEFIK_VERSION}"
      read -r -p "  Nueva versión de Traefik: " new_traefik_version
      if [[ -n $new_traefik_version ]]; then
        sed -i "s/^TRAEFIK_VERSION=.*/TRAEFIK_VERSION=$new_traefik_version/" "$SHARED_VERSIONS_FILE"
        log "TRAEFIK_VERSION actualizada en $SHARED_VERSIONS_FILE"
      fi
    fi

    read -r -p "¿Desea cambiar la versión de Portainer? (s/n, Enter para omitir): " change_portainer_ver
    if [[ $change_portainer_ver =~ ^[sS]$ ]]; then
      printf '%s\n' "  Formato: 2.40.0 (sin 'v') — actual: ${PORTAINER_VERSION}"
      read -r -p "  Nueva versión de Portainer: " new_portainer_version
      if [[ -n $new_portainer_version ]]; then
        sed -i "s/^PORTAINER_VERSION=.*/PORTAINER_VERSION=$new_portainer_version/" "$SHARED_VERSIONS_FILE"
        log "PORTAINER_VERSION actualizada en $SHARED_VERSIONS_FILE"
      fi
    fi

    # Re-sourcear versions.env para que TRAEFIK_IMAGE/PORTAINER_IMAGE tomen los nuevos valores
    # shellcheck source=/dev/null
    if [[ -f $SHARED_VERSIONS_FILE ]]; then
      . "$SHARED_VERSIONS_FILE"
      TRAEFIK_IMAGE="traefik:${TRAEFIK_VERSION}"
      PORTAINER_IMAGE="portainer/portainer-ce:${PORTAINER_VERSION}"
    fi

    # Actualizar las imágenes en docker-compose.yml para aplicar el cambio de versión
    if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
      sed -i "s|image: traefik:.*|image: ${TRAEFIK_IMAGE}|" "$INSTALL_DIR/docker-compose.yml"
      sed -i "s|image: portainer/portainer-ce:.*|image: ${PORTAINER_IMAGE}|" "$INSTALL_DIR/docker-compose.yml"
      log "docker-compose.yml actualizado con las versiones: ${TRAEFIK_IMAGE} y ${PORTAINER_IMAGE}"
    fi
    echo ""
  fi

  if [[ $NON_INTERACTIVE == false ]]; then
    read -r -p "¿Desea buscar parches de seguridad para las versiones instaladas? (s/n, predeterminado: s): " check_patches
    check_patches=${check_patches:-s}
    if [[ ! $check_patches =~ ^[sS]$ ]]; then
      log "Búsqueda de parches cancelada."
      return 0
    fi
  fi

  # Obtener IDs de imágenes actuales
  log "Obteniendo información de las imágenes actuales..."
  current_traefik_id=$(docker image inspect --format '{{.Id}}' "$TRAEFIK_IMAGE" 2>/dev/null || true)
  current_portainer_id=$(docker image inspect --format '{{.Id}}' "$PORTAINER_IMAGE" 2>/dev/null || true)

  # Pull de las imágenes pinadas para detectar si hubo cambios en el digest
  # (ej: security patch sobre la misma versión). NO busca versiones nuevas.
  log "Buscando parches de seguridad para las versiones instaladas..."
  (cd "$INSTALL_DIR" && docker compose pull >/dev/null 2>&1) || error "Error al descargar las imágenes."

  # Obtener IDs de las imágenes recién descargadas
  latest_traefik_id=$(docker image inspect --format '{{.Id}}' "$TRAEFIK_IMAGE" 2>/dev/null || true)
  latest_portainer_id=$(docker image inspect --format '{{.Id}}' "$PORTAINER_IMAGE" 2>/dev/null || true)

  traefik_update_available=false
  portainer_update_available=false

  if [[ $current_traefik_id != "$latest_traefik_id" ]]; then
    traefik_update_available=true
  fi

  if [[ $current_portainer_id != "$latest_portainer_id" ]]; then
    portainer_update_available=true
  fi

  if [[ $traefik_update_available == false && $portainer_update_available == false ]]; then
    log "Traefik y Portainer ya están en su última versión. No se requiere ninguna acción."
    return 0
  fi

  # Informar al usuario sobre las actualizaciones encontradas
  printf '%s%s%s\n' "$YELLOW" "Actualizaciones disponibles:" "$NC"
  if [[ $traefik_update_available == true ]]; then
    log "Parche de seguridad disponible para Traefik (${TRAEFIK_IMAGE})."
  fi
  if [[ $portainer_update_available == true ]]; then
    log "Parche de seguridad disponible para Portainer (${PORTAINER_IMAGE})."
  fi

  read -r -p "¿Desea aplicar las actualizaciones ahora? (s/n): " apply_update
  if [[ ! $apply_update =~ ^[sS]$ ]]; then
    log "Actualización cancelada por el usuario."
    return 0
  fi

  # Backup preventivo de la base de datos de Portainer antes de actualizar
  db_path="$INSTALL_DIR/portainer-data/portainer.db"
  pre_update_backup=""
  if [[ -f $db_path ]]; then
    pre_update_backup="$db_path.pre-update.$(date +%Y%m%d_%H%M%S)"
    cp "$db_path" "$pre_update_backup" || warn "No se pudo crear backup preventivo de portainer.db"
    log "Backup preventivo de Portainer: $pre_update_backup"
  fi

  # Detener Portainer gracefulmente para que cierre BoltDB limpiamente
  if docker ps -q -f name=portainer &>/dev/null; then
    log "Deteniendo Portainer gracefulmente (SIGTERM)..."
    (cd "$INSTALL_DIR" && docker compose stop portainer) || true
    sleep 2
  fi

  log "Aplicando actualizaciones..."
  (cd "$INSTALL_DIR" && docker compose up -d) || error "Error al actualizar los contenedores."

  # Esperar a que los contenedores se estabilicen
  sleep 3

  # Detectar crash loop de Portainer por DB corrupta
  portainer_status=$(docker inspect --format '{{.State.Status}}' portainer 2>/dev/null || true)
  portainer_exit_code=$(docker inspect --format '{{.State.ExitCode}}' portainer 2>/dev/null || true)

  if [[ $portainer_status == "exited" && $portainer_exit_code -ne 0 ]]; then
    portainer_logs=$(docker logs portainer 2>&1 | tail -5 || true)
    if echo "$portainer_logs" | grep -qi "failed opening store\|timeout"; then
      warn "Portainer está en crash loop por un problema en la base de datos (BoltDB locked)."
      log "Intentando restaurar backup preventivo..."

      (cd "$INSTALL_DIR" && docker compose stop portainer) || true
      sleep 1

      recovered=false

      if [[ -n $pre_update_backup && -f $pre_update_backup ]]; then
        cp "$pre_update_backup" "$db_path" || warn "Error al restaurar backup"
        log "Backup preventivo restaurado. Intentando iniciar Portainer..."
        (cd "$INSTALL_DIR" && docker compose up -d) || true
        sleep 3

        new_status=$(docker inspect --format '{{.State.Status}}' portainer 2>/dev/null || true)
        if [[ $new_status == "running" ]]; then
          log "Portainer recuperado exitosamente con backup preventivo."
          recovered=true
        else
          warn "El backup preventivo no resolvió el problema."
        fi
      else
        warn "No hay backup preventivo disponible para restaurar."
      fi

      if [[ $recovered == false ]]; then
        warn "Se perderán usuarios, endpoints y configuraciones guardadas en Portainer."
        warn "Los contenedores y servicios NO se ven afectados."

        if [[ $NON_INTERACTIVE == false ]]; then
          echo ""
          warn "¿Desea eliminar la base de datos y crear una nueva?"
          read -r -p "  (s/n, predeterminado: n): " recover_db
          if [[ ! $recover_db =~ ^[sS]$ ]]; then
            log "Recuperación cancelada. La DB corrupta se conserva."
            log "Backup preventivo disponible en: $pre_update_backup"
            return 0
          fi
        fi

        log "Deteniendo Portainer y eliminando base de datos corrupta..."
        (cd "$INSTALL_DIR" && docker compose stop portainer) || true
        sleep 1

        crashed_backup="$db_path.crashed.$(date +%Y%m%d_%H%M%S)"
        if [[ -f $db_path ]]; then
          cp "$db_path" "$crashed_backup" || true
          rm "$db_path" || error "Error al eliminar portainer.db corrupta"
          log "Base de datos corrupta respaldada en: $crashed_backup"
        fi

        log "Iniciando Portainer con nueva base de datos..."
        (cd "$INSTALL_DIR" && docker compose up -d) || error "Error al iniciar Portainer"
        sleep 3

        new_status=$(docker inspect --format '{{.State.Status}}' portainer 2>/dev/null || true)
        if [[ $new_status == "running" ]]; then
          log "Portainer funcionando con nueva base de datos."
          log "IMPORTANTE: usuarios, endpoints y configuraciones anteriores se perdieron."
          log "Backup preventivo disponible en: $pre_update_backup"
        else
          warn "Portainer no se recuperó automáticamente. Verificar: docker logs portainer"
        fi
      fi
    fi
  fi

  log "Limpiando imágenes antiguas y no utilizadas..."
  docker image prune -f

  log "Verificando estado de los contenedores después de la actualización..."
  (cd "$INSTALL_DIR" && docker compose ps) || error "Error al verificar el estado de los contenedores tras la actualización"

  log "Proceso de actualización completado con éxito."
}
