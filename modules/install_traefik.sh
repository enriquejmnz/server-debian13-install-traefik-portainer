#!/bin/bash
# modules/install_traefik.sh - Módulo para instalar Traefik y Portainer

# Función para limpiar en caso de error en Traefik/Portainer
cleanup_traefik_portainer() {
    log "Limpiando archivos generados por Traefik/Portainer..."
    rm -rf "/opt/traefik-portainer"
}

# Función para instalar Traefik y Portainer
install_traefik_portainer() {
    log "Iniciando instalación de Traefik y Portainer..."
    if ! command -v docker &> /dev/null; then
        error "Docker no está instalado. Ejecute primero la instalación de Docker."
    fi

    INSTALL_DIR="/opt/traefik-portainer"
    if [ -d "$INSTALL_DIR" ] || [ "$(docker ps -a -q -f name=traefik)" ] || [ "$(docker ps -a -q -f name=portainer)" ]; then
        warn "El stack de Traefik y Portainer ya está instalado. Reinstalar eliminará datos."
        read -p " ¿Desea reinstalar el stack? (y/n): " reinstall_choice
        if [[ ! "$reinstall_choice" =~ ^[yY]$ ]]; then
            log "Instalación cancelada."
            return 0
        fi

        log "Procediendo con la reinstalación..."
        if [ -d "$INSTALL_DIR" ]; then
            backup_dir="/opt/traefik-portainer-backup-$(date +%Y%m%d_%H%M%S)"
            log "Creando copia de seguridad en $backup_dir..."
            mv "$INSTALL_DIR" "$backup_dir"
            check_error $? "Error al crear copia de seguridad"
        fi
        docker compose -f "$backup_dir/docker-compose.yml" down --remove-orphans 2>/dev/null || true
        docker rm -f traefik portainer 2>/dev/null || true
    fi

    apt-get install -y apache2-utils
    check_error $? "Error al instalar apache2-utils"

    mkdir -p "$INSTALL_DIR/traefik-data/configurations" "$INSTALL_DIR/portainer-data"
    check_error $? "Error al crear directorios de instalación"
    
    trap cleanup_traefik_portainer ERR

    read -p "Ingrese el dominio base (ejemplo: example.com): " base_domain
    validate_domain "$base_domain"
    read -p "Ingrese el subdominio para Traefik (def: traefik): " traefik_subdomain
    traefik_subdomain=${traefik_subdomain:-traefik}
    read -p "Ingrese el subdominio para Portainer (def: portainer): " portainer_subdomain
    portainer_subdomain=${portainer_subdomain:-portainer}

    # Bucle de validación para el correo electrónico
    while true; do
        read -p "Ingrese el correo para Let's Encrypt: " email_admin
        if is_valid_email "$email_admin"; then
            break
        else
            warn "Formato de correo electrónico inválido. Por favor, inténtelo de nuevo."
        fi
    done

    read -p "Ingrese el nombre de usuario para Traefik: " traefik_user
    read -sp "Ingrese la contraseña para Traefik: " traefik_password; echo
    if [ -z "$traefik_user" ] || [ -z "$traefik_password" ]; then error "El usuario y contraseña de Traefik no pueden estar vacíos"; fi
    traefik_auth=$(htpasswd -nb "$traefik_user" "$traefik_password")
    check_error $? "Error al generar autenticación para Traefik"

    log "Configurando docker-compose.yml..."
    cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
# Usando etiquetas de versión estables y recientes para previsibilidad
version: "3.8"
services:
  traefik:
    # Usando la última versión mayor estable de Traefik v3
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    security_opt: [no-new-privileges:true]
    networks:
      proxy: { ipv4_address: 172.18.0.2 }
    ports: ["80:80", "443:443"]
    environment: { CF_API_EMAIL: "${email_admin}" }
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik-data/traefik.yml:/traefik.yml:ro
      - ./traefik-data/acme.json:/acme.json
      - ./traefik-data/configurations:/configurations
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.traefik-secure.entrypoints=websecure"
      - "traefik.http.routers.traefik-secure.rule=Host(\`${traefik_subdomain}.${base_domain}\`)"
      - "traefik.http.routers.traefik-secure.middlewares=user-auth@file"
      - "traefik.http.routers.traefik-secure.service=api@internal"

  portainer:
    # Usando 'latest' para obtener siempre la última versión estable de Portainer CE
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    depends_on: [traefik]
    security_opt: [no-new-privileges:true]
    networks:
      proxy: { ipv4_address: 172.18.0.3 }
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./portainer-data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.portainer-secure.entrypoints=websecure"
      - "traefik.http.routers.portainer-secure.rule=Host(\`${portainer_subdomain}.${base_domain}\`)"
      - "traefik.http.routers.portainer-secure.service=portainer"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  proxy:
    driver: bridge
    ipam:
      config: [{ subnet: 172.18.0.0/16 }]
EOF

    log "Configurando traefik.yml..."
    # ... (El resto del archivo traefik.yml y dynamic.yml no necesita cambios)
    # ... (El resto de la función tampoco necesita cambios)
    cat > "$INSTALL_DIR/traefik-data/traefik.yml" <<EOF
api: { dashboard: true }
entryPoints:
  web:
    address: ":80"
    http: { redirections: { entryPoint: { to: websecure } } }
  websecure:
    address: ":443"
    http:
      middlewares: [secureHeaders@file]
      tls: { certResolver: letsencrypt }
providers:
  docker: { endpoint: "unix:///var/run/docker.sock", exposedByDefault: false }
  file: { directory: /configurations }
certificatesResolvers:
  letsencrypt:
    acme:
      email: ${email_admin}
      storage: acme.json
      keyType: EC384
      httpChallenge: { entryPoint: web }
log: { level: INFO }
accessLog: {}
EOF

    log "Configurando dynamic.yml..."
    cat > "$INSTALL_DIR/traefik-data/configurations/dynamic.yml" <<EOF
http:
  middlewares:
    secureHeaders:
      headers:
        sslRedirect: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"
        permissionsPolicy: "camera=(), microphone=(), payment=()"
        customFrameOptionsValue: "SAMEORIGIN"
    user-auth:
      basicAuth:
        users: ["${traefik_auth}"]
tls:
  options:
    default:
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
      minVersion: VersionTLS12
EOF

    touch "$INSTALL_DIR/traefik-data/acme.json"
    chmod 600 "$INSTALL_DIR/traefik-data/acme.json"

    cd "$INSTALL_DIR"
    log "Iniciando contenedores..."
    docker compose up -d
    check_error $? "Error al iniciar contenedores"

    log "Verificando estado de los contenedores..."
    docker compose ps

    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp && ufw allow 443/tcp
        log "Puertos 80 y 443 abiertos en el firewall."
    fi

    log "Instalación de Traefik y Portainer completada con éxito"
    log "  - Traefik: https://${traefik_subdomain}.${base_domain}"
    log "  - Portainer: https://${portainer_subdomain}.${base_domain}"
    log "  - Usuario Traefik: $traefik_user"
    log "NOTA: Los certificados SSL pueden tardar unos minutos en generarse."
    trap - ERR
}
