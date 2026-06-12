#!/bin/bash
# modules/install_traefik.sh - Módulo para instalar Traefik y Portainer

# Función para limpiar en caso de error en Traefik/Portainer
cleanup_traefik_portainer() {
  log "Limpiando archivos generados por Traefik/Portainer..."
  rm -rf "$INSTALL_DIR"
}

# Función para instalar Traefik y Portainer
install_traefik_portainer() {
  require_supported_debian
  log "Iniciando instalación de Traefik y Portainer..."
  if ! command -v docker &>/dev/null; then
    error "Docker no está instalado. Ejecute primero la instalación de Docker."
  fi

  if [[ -d $INSTALL_DIR ]] || [[ -n "$(docker ps -a -q -f name=traefik)" ]] || [[ -n "$(docker ps -a -q -f name=portainer)" ]]; then
    warn "El stack de Traefik y Portainer ya está instalado. Reinstalar eliminará datos."
    read -r -p " ¿Desea reinstalar el stack? (y/n): " reinstall_choice
    if [[ ! $reinstall_choice =~ ^[yY]$ ]]; then
      log "Instalación cancelada."
      return 0
    fi

    log "Procediendo con la reinstalación..."
    backup_dir=""
    if [[ -d $INSTALL_DIR ]]; then
      backup_dir="/opt/traefik-portainer-backup-$(date +%Y%m%d_%H%M%S)"
      log "Creando copia de seguridad en $backup_dir..."
      mv "$INSTALL_DIR" "$backup_dir" || error "Error al crear copia de seguridad"
    fi

    if [[ -n $backup_dir && -f "$backup_dir/docker-compose.yml" ]]; then
      docker compose -f "$backup_dir/docker-compose.yml" down --remove-orphans 2>/dev/null || true
    fi
    docker rm -f traefik portainer 2>/dev/null || true
  fi

  apt-get install -y apache2-utils || error "Error al instalar apache2-utils"

  mkdir -p "$INSTALL_DIR/traefik-data/configurations" "$INSTALL_DIR/portainer-data" || error "Error al crear directorios de instalación"
  chmod 750 "$INSTALL_DIR" || error "Error al ajustar permisos de $INSTALL_DIR"

  trap cleanup_traefik_portainer ERR

  prompt_or_default "BASE_DOMAIN" "Ingrese el dominio base (ejemplo: example.com)"
  base_domain="${BASE_DOMAIN}"
  validate_domain "$base_domain"
  prompt_or_default "TRAEFIK_SUBDOMAIN" "Ingrese el subdominio para Traefik" "traefik"
  traefik_subdomain="${TRAEFIK_SUBDOMAIN:-traefik}"
  prompt_or_default "PORTAINER_SUBDOMAIN" "Ingrese el subdominio para Portainer" "portainer"
  portainer_subdomain="${PORTAINER_SUBDOMAIN:-portainer}"

  # Bucle de validación para el correo electrónico
  if [[ -z ${EMAIL_ADMIN:-} ]]; then
    while true; do
      read -r -p "Ingrese el correo para Let's Encrypt: " email_admin
      if is_valid_email "$email_admin"; then
        break
      else
        warn "Formato de correo electrónico inválido. Por favor, inténtelo de nuevo."
      fi
    done
  else
    email_admin="$EMAIL_ADMIN"
  fi

  prompt_or_default "TRAEFIK_USER" "Ingrese el nombre de usuario para Traefik"
  traefik_user="${TRAEFIK_USER}"
  if [[ -z ${TRAEFIK_PASSWORD:-} ]]; then
    read -r -s -p "Ingrese la contraseña para Traefik: " traefik_password
    echo
  else
    traefik_password="$TRAEFIK_PASSWORD"
  fi
  if [[ -z $traefik_user || -z $traefik_password ]]; then error "El usuario y contraseña de Traefik no pueden estar vacíos"; fi
  traefik_auth=$(htpasswd -nb "$traefik_user" "$traefik_password") || error "Error al generar autenticación para Traefik"
  unset traefik_password

  # --- Validación DNS antes de continuar ---
  log "Verificando resolución DNS de los subdominios..."
  server_ip=$(get_public_ip)
  if [[ -z $server_ip ]]; then
    warn "No se pudo determinar la IP pública del servidor. Omitiendo validación DNS."
  else
    dns_ok=true
    for sub in "$traefik_subdomain" "$portainer_subdomain"; do
      fqdn="${sub}.${base_domain}"
      if ! dns_validate_subdomain "$fqdn" "$server_ip"; then
        dns_ok=false
      fi
    done

    if [[ $dns_ok == false ]]; then
      if [[ $NON_INTERACTIVE == true ]]; then
        error "Validación DNS fallida. Configure los registros DNS antes de continuar."
      fi
      warn "Algunos subdominios no resuelven correctamente a la IP del servidor."
      read -r -p "¿Desea continuar de todas formas? (s/n, predeterminado: n): " continue_dns
      if [[ ! $continue_dns =~ ^[sS]$ ]]; then
        error "Instalación cancelada. Configure el DNS y vuelva a ejecutar."
      fi
    fi
  fi

  log "Configurando docker-compose.yml..."
  cat >"$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  traefik:
    image: ${TRAEFIK_IMAGE}
    container_name: traefik
    restart: unless-stopped
    security_opt: [no-new-privileges:true]
    networks:
      - proxy
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
    image: ${PORTAINER_IMAGE}
    container_name: portainer
    restart: unless-stopped
    depends_on: [traefik]
    security_opt: [no-new-privileges:true]
    networks:
      - proxy
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
    name: proxy
    driver: bridge
EOF
  chmod 640 "$INSTALL_DIR/docker-compose.yml" || error "Error al ajustar permisos de docker-compose.yml"

  log "Configurando traefik.yml..."
  # ... (El resto del archivo traefik.yml y dynamic.yml no necesita cambios)
  # ... (El resto de la función tampoco necesita cambios)
  cat >"$INSTALL_DIR/traefik-data/traefik.yml" <<EOF
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
  chmod 640 "$INSTALL_DIR/traefik-data/traefik.yml" || error "Error al ajustar permisos de traefik.yml"

  log "Configurando dynamic.yml..."
  cat >"$INSTALL_DIR/traefik-data/configurations/dynamic.yml" <<EOF
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
  chmod 600 "$INSTALL_DIR/traefik-data/configurations/dynamic.yml" || error "Error al ajustar permisos de dynamic.yml"
  unset traefik_auth

  touch "$INSTALL_DIR/traefik-data/acme.json" || error "Error al crear acme.json"
  chmod 600 "$INSTALL_DIR/traefik-data/acme.json" || error "Error al ajustar permisos de acme.json"

  log "Iniciando contenedores..."
  (cd "$INSTALL_DIR" && docker compose up -d) || error "Error al iniciar contenedores"

  log "Verificando estado de los contenedores..."
  (cd "$INSTALL_DIR" && docker compose ps) || error "Error al verificar el estado de los contenedores"

  if command -v ufw &>/dev/null; then
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
