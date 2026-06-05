#!/bin/bash
# modules/update_traefik.sh - Módulo para verificar y actualizar Traefik y Portainer

# Función para verificar y actualizar Traefik y Portainer
update_traefik_portainer() {
  require_supported_debian
  log "Verificando actualizaciones para Traefik y Portainer..."

  if ! command -v docker &>/dev/null; then
    error "Docker no está instalado."
  fi
  if [[ ! -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    error "El stack de Traefik y Portainer no parece estar instalado en $INSTALL_DIR."
  fi

  # Obtener IDs de imágenes actuales
  log "Obteniendo información de las imágenes actuales..."
  current_traefik_id=$(docker image inspect --format '{{.Id}}' "$TRAEFIK_IMAGE" 2>/dev/null || true)
  current_portainer_id=$(docker image inspect --format '{{.Id}}' "$PORTAINER_IMAGE" 2>/dev/null || true)

  # Descargar las últimas imágenes para verificar si el digest de la versión pinada cambió
  log "Verificando si hay nuevos digests para las versiones pinadas..."
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
  echo -e "${YELLOW}Actualizaciones disponibles:${NC}"
  if [[ $traefik_update_available == true ]]; then
    log "Nueva versión de Traefik encontrada."
  fi
  if [[ $portainer_update_available == true ]]; then
    log "Nueva versión de Portainer encontrada."
  fi

  read -r -p "¿Desea aplicar las actualizaciones ahora? (s/n): " apply_update
  if [[ ! $apply_update =~ ^[sS]$ ]]; then
    log "Actualización cancelada por el usuario."
    return 0
  fi

  log "Aplicando actualizaciones..."
  (cd "$INSTALL_DIR" && docker compose up -d) || error "Error al actualizar los contenedores."

  log "Limpiando imágenes antiguas y no utilizadas..."
  docker image prune -f

  log "Verificando estado de los contenedores después de la actualización..."
  (cd "$INSTALL_DIR" && docker compose ps) || error "Error al verificar el estado de los contenedores tras la actualización"

  log "Proceso de actualización completado con éxito."
}
