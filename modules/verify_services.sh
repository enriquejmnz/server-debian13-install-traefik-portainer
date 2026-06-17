#!/bin/bash
# modules/verify_services.sh - Verificar estado de todos los servicios instalados

verify_services() {
  while true; do
    clear
    printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    printf '%s\n' "${GREEN}║      VERIFICACIÓN DE ESTADO DEL SISTEMA     ║${NC}"
    printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    printf '%s\n' "  ${GREEN}1${NC}) Chequeo general"
    printf '%s\n' "       SSH · UFW · Docker · Traefik · Portainer · recursos"
    echo ""
    printf '%s\n' "  ${GREEN}2${NC}) Verificación post-reinicio"
    printf '%s\n' "       Espera a que el stack esté listo tras un reboot"
    echo ""
    printf '%s\n' "  ${GREEN}0${NC}) Volver al menú principal"
    echo ""
    printf '%s' "${YELLOW}  Seleccione una opción (0-2):${NC} "
    read -r verify_choice

    case $verify_choice in
    1)
      verify_general
      printf '%s' "  Presione Enter para volver al sub-menú..."
      read -r
      ;;
    2)
      if [[ ${NON_INTERACTIVE:-false} == false ]]; then
        printf '%s\n' ""
        printf '%s\n' "  ${YELLOW}Esta verificación puede tardar hasta 60 segundos.${NC}"
        printf '%s' "  Presione Enter para iniciar (Ctrl+C para cancelar)..."
        read -r
      fi
      verify_post_reboot
      printf '%s' "  Presione Enter para volver al sub-menú..."
      read -r
      ;;
    0)
      return 0
      ;;
    *)
      warn "Opción inválida."
      sleep 1
      ;;
    esac
  done
}

verify_general() {
  clear
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║       CHEQUEO GENERAL DE ESTADO             ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""

  local ok="${GREEN}✓${NC}"
  local warn="⚠ "
  local fail="${RED}✗${NC}"
  local issues=0

  # ── SSH ──
  printf '%s' "  SSH ................... "
  if systemctl is-active --quiet ssh 2>/dev/null; then
    ssh_port=$(awk '/^Port / {print $2}' /etc/ssh/sshd_config 2>/dev/null)
    ssh_port=${ssh_port:-22}
    printf '%s puerto %s\n' "$ok" "${GREEN}${ssh_port}${NC}"
  else
    printf '%s\n' "$fail no está corriendo"
    ((issues++))
  fi

  # ── UFW ──
  printf '%s' "  UFW ................... "
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw_rules=$(ufw status 2>/dev/null | grep -c "ALLOW")
    printf '%s activo (%d reglas ALLOW)\n' "$ok" "$ufw_rules"
  elif command -v ufw &>/dev/null; then
    printf '%s\n' "${warn}${YELLOW}instalado pero inactivo${NC}"
    ((issues++))
  else
    printf '%s\n' "${warn}${YELLOW}no instalado${NC}"
    ((issues++))
  fi

  # ── fail2ban ──
  printf '%s' "  Fail2ban .............. "
  if systemctl is-active --quiet fail2ban 2>/dev/null; then
    banned=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
    banned=${banned:-0}
    printf '%s activo' "$ok"
    if [[ $banned -gt 0 ]]; then
      printf ' (%d IPs baneadas)' "$banned"
    fi
    printf '\n'
  elif dpkg -l fail2ban &>/dev/null; then
    printf '%s\n' "${fail} instalado pero detenido${NC}"
    ((issues++))
  else
    printf '%s\n' "${warn}${YELLOW}no instalado${NC}"
    ((issues++))
  fi

  # ── Docker ──
  printf '%s' "  Docker ................ "
  if systemctl is-active --quiet docker 2>/dev/null; then
    docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | sed 's/,//')
    compose_version=$(docker compose version 2>/dev/null | awk '{print $NF}' | sed 's/v//')
    printf '%s' "$ok Engine ${docker_version}"
    if [[ -n $compose_version ]]; then
      printf ', Compose %s' "$compose_version"
    fi
    printf '\n'
  elif command -v docker &>/dev/null; then
    printf '%s\n' "${fail} instalado pero detenido${NC}"
    ((issues++))
  else
    printf '%s\n' "${warn}${YELLOW}no instalado${NC}"
    ((issues++))
  fi

  # ── Contenedores ──
  if command -v docker &>/dev/null && systemctl is-active --quiet docker 2>/dev/null; then
    printf '%s' "  Traefik ............... "
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^traefik$'; then
      traefik_status=$(docker inspect --format '{{.State.Status}}' traefik 2>/dev/null)
      if [[ $traefik_status == "running" ]]; then
        printf '%s\n' "$ok corriendo"
      else
        printf '%s estado: %s\n' "$fail" "$traefik_status"
        ((issues++))
      fi
    else
      printf '%s\n' "${warn}${YELLOW}no desplegado${NC}"
    fi

    printf '%s' "  Portainer ............. "
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^portainer$'; then
      portainer_status=$(docker inspect --format '{{.State.Status}}' portainer 2>/dev/null)
      if [[ $portainer_status == "running" ]]; then
        printf '%s\n' "$ok corriendo"
      else
        printf '%s estado: %s\n' "$fail" "$portainer_status"
        ((issues++))
      fi
    else
      printf '%s\n' "${warn}${YELLOW}no desplegado${NC}"
    fi
  fi

  # ── Red ──
  printf '%s' "  Red Docker proxy ...... "
  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q '^proxy$'; then
    printf '%s\n' "$ok existe"
  else
    printf '%s\n' "${warn}${YELLOW}no creada${NC}"
  fi

  # ── Certificados TLS ──
  if [[ -f "$INSTALL_DIR/traefik-data/acme.json" ]]; then
    printf '%s' "  TLS (acme.json) ....... "
    acme_size=$(stat -c%s "$INSTALL_DIR/traefik-data/acme.json" 2>/dev/null || echo 0)
    if [[ $acme_size -gt 100 ]]; then
      printf '%s presente (%d bytes)\n' "$ok" "$acme_size"
    else
      printf '%s\n' "${warn}${YELLOW}vacío — certificados no generados aún${NC}"
    fi
  fi

  # ── Sistema ──
  printf '%s' "  Auditd ................ "
  if systemctl is-active --quiet auditd 2>/dev/null; then
    printf '%s\n' "$ok activo"
  else
    printf '%s\n' "${warn}${YELLOW}no activo${NC}"
    ((issues++))
  fi

  printf '%s' "  NTP ................... "
  if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
    printf '%s\n' "$ok sincronizado"
  elif systemctl is-active --quiet chronyd 2>/dev/null; then
    printf '%s\n' "$ok chronyd"
  else
    printf '%s\n' "${warn}${YELLOW}no activo${NC}"
    ((issues++))
  fi

  printf '%s' "  Timezone .............. "
  timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "desconocido")
  printf '%s\n' "$ok ${timezone}"

  printf '%s' "  Límites (nofile) ...... "
  nofile_limit=$(ulimit -n 2>/dev/null)
  if [[ $nofile_limit -ge 65535 ]]; then
    printf '%s\n' "$ok ${nofile_limit}"
  else
    printf '%s actual: %d (esperado ≥65535)\n' "${warn}${YELLOW}" "$nofile_limit"
    ((issues++))
  fi

  # ── Recursos ──
  printf '%s' "  Disco ................. "
  disk_avail=$(df -h / | awk 'NR==2 {print $4}')
  disk_use=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
  if [[ $disk_use -lt 85 ]]; then
    printf '%s libre: %s (uso: %d%%)\n' "$ok" "$disk_avail" "$disk_use"
  else
    printf '%s libre: %s (uso: %d%%)\n' "${warn}${YELLOW}" "$disk_avail" "$disk_use"
    ((issues++))
  fi

  printf '%s' "  Memoria ............... "
  mem_free=$(free -h | awk '/^Mem:/ {print $4}')
  mem_available=$(free -h | awk '/^Mem:/ {print $NF}')
  printf '%s libre: %s (disponible: %s)\n' "$ok" "$mem_free" "$mem_available"

  printf '%s' "  Uptime ................ "
  uptime_str=$(uptime -p 2>/dev/null | sed 's/up //')
  printf '%s\n' "$ok ${uptime_str}"

  echo ""

  # ── Resumen ──
  if [[ $issues -eq 0 ]]; then
    printf '%s\n' "${GREEN}  ✅ Todos los servicios OK — sin problemas detectados.${NC}"
  else
    printf '%s\n' "${YELLOW}  ⚠️  Se encontraron ${issues} avisos. Revisar los puntos marcados.${NC}"
  fi

  echo ""
}

verify_post_reboot() {
  clear
  printf '%s\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${GREEN}║    VERIFICACIÓN POST-REINICIO DEL SERVIDOR  ║${NC}"
  printf '%s\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  printf '%s\n' "  Esperando a que Docker y los contenedores estén listos..."
  echo ""

  local ok="${GREEN}✓${NC}"
  local fail="${RED}✗${NC}"
  local max_wait=60
  local elapsed=0
  local docker_ok=false
  local traefik_ok=false
  local portainer_ok=false

  # ── Esperar a que el daemon Docker esté activo ──
  while [[ $elapsed -lt $max_wait ]]; do
    if systemctl is-active --quiet docker 2>/dev/null; then
      docker_ok=true
      break
    fi
    sleep 2
    ((elapsed += 2))
  done

  printf '%s' "  Docker daemon ......... "
  if [[ $docker_ok == true ]]; then
    printf '%s activo tras %ds\n' "$ok" "$elapsed"
  else
    printf '%s no responde tras %ds\n' "$fail" "$max_wait"
    printf '%s\n' "${YELLOW}  El stack no puede arrancar sin Docker. Abortando.${NC}"
    return 1
  fi

  # ── Esperar a que ambos contenedores estén running/healthy ──
  elapsed=0
  while [[ $elapsed -lt $max_wait ]]; do
    traefik_ok=false
    portainer_ok=false

    local t_state t_health p_state p_health
    t_state=$(docker inspect --format '{{.State.Status}}' traefik 2>/dev/null || echo "missing")
    t_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' traefik 2>/dev/null || echo "none")
    p_state=$(docker inspect --format '{{.State.Status}}' portainer 2>/dev/null || echo "missing")
    p_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' portainer 2>/dev/null || echo "none")

    if [[ $t_state == "running" && ($t_health == "healthy" || $t_health == "none") ]]; then
      traefik_ok=true
    fi
    if [[ $p_state == "running" && ($p_health == "healthy" || $p_health == "none") ]]; then
      portainer_ok=true
    fi

    if [[ $traefik_ok == true && $portainer_ok == true ]]; then
      break
    fi
    sleep 3
    ((elapsed += 3))
  done

  printf '%s' "  Traefik ............... "
  if [[ $traefik_ok == true ]]; then
    printf '%s %s\n' "$ok" "${GREEN}running${NC}"
  else
    local t_state t_health
    t_state=$(docker inspect --format '{{.State.Status}}' traefik 2>/dev/null || echo "missing")
    t_health=$(docker inspect --format '{{.State.Health.Status}}' traefik 2>/dev/null || echo "n/a")
    printf '%s estado=%s health=%s\n' "$fail" "$t_state" "$t_health"
  fi

  printf '%s' "  Portainer ............. "
  if [[ $portainer_ok == true ]]; then
    printf '%s %s\n' "$ok" "${GREEN}running${NC}"
  else
    local p_state p_health
    p_state=$(docker inspect --format '{{.State.Status}}' portainer 2>/dev/null || echo "missing")
    p_health=$(docker inspect --format '{{.State.Health.Status}}' portainer 2>/dev/null || echo "n/a")
    printf '%s estado=%s health=%s\n' "$fail" "$p_state" "$p_health"
  fi

  printf '%s' "  UFW 80/443 ............ "
  if ufw status 2>/dev/null | grep -E "80/tcp.*ALLOW|443/tcp.*ALLOW" >/dev/null; then
    printf '%s\n' "$ok reglas presentes"
  else
    printf '%s\n' "$fail reglas ausentes — TLS fallará"
  fi

  echo ""
  if [[ $traefik_ok == true && $portainer_ok == true ]]; then
    printf '%s\n' "${GREEN}  ✅ Stack Traefik + Portainer listo tras el reinicio.${NC}"
    return 0
  else
    printf '%s\n' "${RED}  ✗ Uno o más servicios no están listos. Revise 'docker compose logs'.${NC}"
    return 1
  fi
}
