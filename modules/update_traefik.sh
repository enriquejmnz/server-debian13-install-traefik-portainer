#!/bin/bash
# modules/update_traefik.sh - Módulo para verificar y actualizar Traefik y Portainer

# Función para verificar y actualizar Traefik y Portainer
update_traefik_portainer() {
    log "Verificando actualizaciones para Traefik y Portainer..."
    INSTALL_DIR="/opt/traefik-portainer"

    if ! command -v docker &> /dev/null; then
        error "Docker no está instalado."
    fi
    if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        error "El stack de Traefik y Portainer no parece estar instalado en $INSTALL_DIR."
    fi

    cd "$INSTALL_DIR"

    # Obtener IDs de imágenes actuales
    log "Obteniendo información de las imágenes actuales..."
    current_traefik_id=$(docker images --format "{{.ID}}" traefik:v3.0 2>/dev/null)
    current_portainer_id=$(docker images --format "{{.ID}}" portainer/portainer-ce:latest 2>/dev/null)

    # Descargar las últimas versiones de las imágenes para comparar
    log "Consultando Docker Hub para las versiones más recientes..."
    docker compose pull > /dev/null 2>&1
    check_error $? "Error al contactar con Docker Hub para buscar actualizaciones."

    # Obtener IDs de las imágenes recién descargadas
    latest_traefik_id=$(docker images --format "{{.ID}}" traefik:v3.0)
    latest_portainer_id=$(docker images --format "{{.ID}}" portainer/portainer-ce:latest)

    traefik_update_available=false
    portainer_update_available=false

    if [[ -n "$current_traefik_id" && "$current_traefik_id" != "$latest_traefik_id" ]]; then
        traefik_update_available=true
    fi

    if [[ -n "$current_portainer_id" && "$current_portainer_id" != "$latest_portainer_id" ]]; then
        portainer_update_available=true
    fi

    if ! $traefik_update_available && ! $portainer_update_available; then
        log "Traefik y Portainer ya están en su última versión. No se requiere ninguna acción."
        return 0
    fi

    # Informar al usuario sobre las actualizaciones encontradas
    echo -e "${YELLOW}Actualizaciones disponibles:${NC}"
    if $traefik_update_available; then
        log "Nueva versión de Traefik encontrada."
    fi
    if $portainer_update_available; then
        log "Nueva versión de Portainer encontrada."
    fi

    read -p "¿Desea aplicar las actualizaciones ahora? (s/n): " apply_update
    if [[ ! "$apply_update" =~ ^[sS]$ ]]; then
        log "Actualización cancelada por el usuario."
        return 0
    fi

    log "Aplicando actualizaciones..."
    docker compose up -d
    check_error $? "Error al actualizar los contenedores."

    log "Limpiando imágenes antiguas y no utilizadas..."
    docker image prune -f

    log "Verificando estado de los contenedores después de la actualización..."
    docker compose ps

    log "Proceso de actualización completado con éxito."
}
