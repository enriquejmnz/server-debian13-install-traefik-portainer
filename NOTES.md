# Notes

Se describen las notas rápidas sobre el proyecto que se vienen a la mente en el transcurso del desarrollo. No son pendientes ya definidos ni adecuacones ya establecidas, sino ideas de mejoras, correcciones y rumbo que se le quiere dar al proyecto. 

Consta de un inbox el cual se escriben todos los pensaientos que se creen relevantes para la mejora del proyecto. Esta compuesto por ideas, recordatorios, posibles mejoras, cosas por investigar, curiosidades.

## Descripcion

Este es un espacio para capturar ideas, correcciones, mejoras, y el rumbo futuro deseado para el desarrollo del proyecto. No contiene tareas o adecuaciones ya establecidas.

FUNCIÓN PRINCIPAL El Inbox:

Actúa como un registro de pensamientos relevantes para la evolución continua del proyecto.

CLASIFICACIÓN DEL CONTENIDO:

Las notas deben ser clasificadas en las siguientes categorías:

Ideas y Mejoras: Posibles optimizaciones y nuevos enfoques.

Correcciones: Ajustes necesarios al plan o desarrollo actual.

Investigación/Curiosidades: Información de fondo relacionada con el proyecto.

Rumbo Futuro: Visiones y nuevas direcciones para el proyecto.

OBJETIVO PARA EL AGENTE:

Analizar estas notas para generar propuestas de mejora, identificar riesgos potenciales (a partir de las correcciones), y sugerir posibles rutas futuras (a partir del rumbo).

## Inbox

- [x] **Análisis de flujo de configuración (Parte 1 Script)**
  - El orden actual (puerto SSH → usuario admin → hardening) es el correcto para seguridad
  - Se agregó checkpoint visual antes del hardening para que el usuario revise cambios
  - Todas las opciones del menú ahora tienen banner introductorio con resumen y pausa
- [ ] **Seguridad: Usuario Sudo y Acceso SSH**
  - Verificar si es técnicamente correcto delegar privilegios `sudo` al administrador y evitar el uso de `root`.
  - Confirmar si este mismo usuario puede ser el utilizado para la autenticación SSH mediante clave pública.
- [ ] **Verificación de servicios**
  - Agregar una opción de test para verificar que los servicios instalados funcionen correctamente y ofrecer un resumen del estado del sistema.
- [ ] **Seguridad: Grupo Docker**
  - Evaluar si, por seguridad, el usuario administrador no debe ser parte del grupo `docker`.
- [x] **Gestión de versiones (Traefik y Portainer)**
  - ✅ Las actualizaciones son manuales: editar `modules/versions.env` para cambiar de versión
  - ✅ `common.sh` lee `versions.env` y deriva `TRAEFIK_IMAGE`/`PORTAINER_IMAGE`
  - ✅ La opción update solo compara digests de la versión pinada (parches de seguridad), no busca versiones nuevas
- [ ] **Backup y Migración**
  - Agregar una sección de *backup* para Traefik y Portainer.
  - Facilitar la migración entre VPS de manera automática y reducir la carga operativa para el administrador.

- [x] **Confirmar contraseña de usuario traefik**

        Implementado en modules/install_traefik.sh: bucle while true con segundo ingreso y comparación.

