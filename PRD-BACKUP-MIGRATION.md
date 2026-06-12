# PRD: Backup y Migración de Traefik + Portainer

## 1. Contexto y Objetivo
**Problema**: Actualmente, migrar el stack de Traefik + Portainer a un nuevo VPS o realizar un backup ante un desastre requiere intervención manual (copiar archivos, recrear redes, reconfigurar permisos), lo que es propenso a errores y downtime.  
**Objetivo**: Crear un módulo modular y sencillo que permita exportar el estado completo del stack (configuraciones, certificados TLS y base de datos de Portainer) en un solo archivo, y restaurarlo en el mismo o en un nuevo servidor con un solo comando.

---

## 2. Alcance (Scope)

### ✅ Incluido (Fase 1)
- Backup de todo el directorio `$INSTALL_DIR` (`/opt/traefik-portainer`), que contiene:
  - `docker-compose.yml`
  - `traefik-data/traefik.yml`
  - `traefik-data/configurations/dynamic.yml`
  - `traefik-data/acme.json` (certificados Let's Encrypt)
  - `portainer-data/portainer.db` (usuarios, endpoints, stacks)
- Generación de un archivo `.tar.gz` con timestamp.
- Función de restauración que valida el archivo, extrae en `$INSTALL_DIR`, ajusta permisos y levanta los contenedores.
- Integración en el menú interactivo y vía CLI (`--step backup`, `--step restore`).

### ❌ Fuera de alcance (por ahora)
- Backup de configuraciones del host (UFW, SSH, fail2ban). *Se maneja por separado o en una Fase 2*.
- Migración automática de DNS (el usuario debe actualizar los registros A/CNAME en su proveedor de dominio).

---

## 3. Arquitectura y Flujo

El flujo se divide en 3 fases claras, manteniendo la simplicidad del script:

1. **Backup (Origen)**:
   - Verifica que el stack esté instalado.
   - Detiene los contenedores brevemente (recomendado para consistencia de `portainer.db` y `acme.json`).
   - Crea un archivo `traefik-portainer-backup-YYYYMMDD_HHMMSS.tar.gz` en el directorio actual o `/tmp`.
   - Reinicia los contenedores.
   - Muestra la ruta del archivo, su tamaño y un comando `scp` de ejemplo para transferirlo.

2. **Transferencia (Manual)**:
   - El usuario descarga el `.tar.gz` y lo sube al nuevo servidor (vía `scp`, `rsync` o SFTP). *No se implementa transferencia automática en la Fase 1 para evitar complejidad de credenciales SSH entre servidores*.

3. **Restore (Destino)**:
   - Verifica que Docker esté instalado.
   - Solicita la ruta del archivo `.tar.gz`.
   - Valida que sea un archivo válido y contenga la estructura esperada.
   - Detiene contenedores existentes (si los hay) y hace backup del estado actual por seguridad.
   - Extrae el contenido en `$INSTALL_DIR`.
   - Ajusta permisos (`chmod 750` en dir, `600` en `acme.json` y `dynamic.yml`).
   - Levanta el stack con `docker compose up -d`.

---

## 4. Diseño del Módulo (`modules/backup_restore.sh`)

Se creará un nuevo archivo siguiendo las convenciones existentes:

```bash
#!/bin/bash
# modules/backup_restore.sh - Backup y restauración del stack Traefik + Portainer

backup_stack() {
  require_supported_debian
  # 1. Verificar existencia del stack
  # 2. Mostrar banner y pausa
  # 3. docker compose stop (graceful)
  # 4. tar -czf /tmp/backup-$(date +%Y%m%d_%H%M%S).tar.gz -C /opt traefik-portainer
  # 5. docker compose start
  # 6. Mostrar ruta, tamaño y comando scp de ejemplo
}

restore_stack() {
  require_supported_debian
  # 1. Verificar que Docker esté instalado
  # 2. Pedir ruta del archivo .tar.gz (o usar variable de entorno en modo no interactivo)
  # 3. Validar archivo (tar -tzf)
  # 4. Backup preventivo del estado actual en /opt (si existe)
  # 5. Extraer en $INSTALL_DIR
  # 6. Aplicar permisos restrictivos (chmod 750, 640, 600)
  # 7. docker compose up -d
  # 8. Verificar estado y mostrar resumen
}
```

---

## 5. Integración con el Sistema Existente

### Menú Interactivo
Se agrega una nueva opción (desplazando "Salir" a la 8):
```text
  6) Verificar estado del sistema
  7) Backup y Migración del stack
       Exportar o importar Traefik + Portainer
  8) Salir
```
Al seleccionar 7, se muestra un submenú simple:
```text
  1) Crear backup del stack actual
  2) Restaurar stack desde archivo
  3) Volver al menú principal
```

### Modo CLI (`--non-interactive`)
```bash
# Crear backup
sudo bash main.sh --non-interactive --step backup

# Restaurar backup (requiere variable de entorno o flag)
sudo bash main.sh --non-interactive --step restore --backup-file /ruta/al/backup.tar.gz
```

---

## 6. Casos Borde y Seguridad

1. **Consistencia de datos**: Se detienen los contenedores (`docker compose stop`) antes de empaquetar para evitar que `portainer.db` o `acme.json` queden en estado de escritura (locked).
2. **Permisos**: El script de restore **debe** re-aplicar los permisos restrictivos (`chmod 750` en el directorio, `600` en `acme.json` y `dynamic.yml`), ya que `tar` puede no preservarlos correctamente dependiendo de cómo se haya creado el archivo.
3. **Cambio de dominio**: Si el usuario migra a un nuevo dominio, el script de restore debe preguntar: *"¿Desea actualizar el dominio base en las configuraciones?"*. Si dice que sí, ejecuta un `sed -i` sobre `traefik.yml` y `docker-compose.yml` antes de levantar los contenedores.
4. **Espacio en disco**: Verificar que haya al menos 2x el tamaño del `$INSTALL_DIR` libre en el disco antes de crear el backup.

---

## 7. Plan de Implementación (Pasos)

1. **Crear `modules/backup_restore.sh`** con las funciones `backup_stack()` y `restore_stack()`.
2. **Integrar en `main.sh`**: cargar el módulo, agregar al menú y al parser de `--step`.
3. **Actualizar documentación**: `README.md`, `AGENTS.md` y `NOTES.md`.
4. **Pruebas manuales**:
   - Backup en VM Debian 13 → Transferir → Restore en VM Debian 12/13.
   - Verificar que Portainer conserva usuarios y que Traefik sirve el certificado existente.
5. **Marcar como resuelto** en `TODO.md` y `NOTES.md`.

---

## 8. Criterios de Aceptación
- [ ] El backup se crea en menos de 5 segundos y el archivo es válido.
- [ ] El restore falla con un mensaje claro si el archivo está corrupto o no es un backup del stack.
- [ ] Tras el restore, `docker compose ps` muestra ambos contenedores como `running`.
- [ ] Los permisos de `acme.json` y `dynamic.yml` son `600` tras la restauración.
- [ ] El flujo funciona tanto en modo interactivo como en `--non-interactive`.
