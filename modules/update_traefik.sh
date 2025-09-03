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
    log "Descargando las últimas versiones de las imágenes..."
    docker compose pull
    check_error $? "Error al descargar las nuevas imágenes"
    
    log "Recreando los contenedores con las nuevas imágenes si es necesario..."
    docker compose up -d
    check_error $? "Error al actualizar los contenedores"

    log "Verificando estado de los contenedores..."
    docker compose ps

    log "Proceso de actualización completado. Docker solo recreará los servicios cuyas imágenes hayan cambiado."
}