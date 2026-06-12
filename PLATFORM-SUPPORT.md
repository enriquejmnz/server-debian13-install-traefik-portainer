# Estado de soporte y plan de compatibilidad

Resumen corto: **Bash está validado en Debian 12 y Debian 13 en VMs reales. Ansible tiene implementación + Molecule + lint pero todavía no se validó en VM real. Ubuntu Server no está soportado hoy**.

> **Fuentes de verdad**:
> - Este archivo → panorama de plataformas y política de soporte.
> - [`TODO.md`](TODO.md) → tracker granular de bugs, features y tareas pendientes (incluye los items detallados de Ansible, sección 9).
> - [`AGENTS.md`](AGENTS.md) → guía de desarrollo y convenciones del código.

---

## Estado actual de un vistazo

| Plataforma | Scripts Bash | Ansible | Estado real hoy |
|---|---|---|---|
| Debian 13 (Trixie) | ✅ **Validated** — probado en VM real | ✅ Implementado con Molecule + lint, **pendiente de validación en VM real** | Bash listo; Ansible implementado sin validación operativa |
| Debian 12 (Bookworm) | ✅ **Validated** — probado en VM real | ✅ Implementado con Molecule + lint, **pendiente de validación en VM real** | Bash listo; Ansible implementado sin validación operativa |
| Ubuntu Server 24.04 LTS | No soportado | Bloqueado explícitamente | **No soportado hoy** |

---

## Política explícita de soporte

Tres categorías estrictas:

- **`validated` (Validado)**: Guardrails explícitos, cobertura CI (lint + Molecule cuando aplica), validación operativa en VM real documentada, documentación consistente con el comportamiento real. *Hoy: Bash en Debian 12 y Debian 13.*
- **`experimental` (Experimental)**: Implementación existe y pasa guards de CI, pero carece de validación operativa en VM real. *Hoy: Ansible en Debian 12 y Debian 13.*
- **`unsupported` (No soportado)**: El código bloquea explícitamente la ejecución o no existe implementación. *Hoy: Ubuntu Server y cualquier otra distribución.*

---

## Qué está validado hoy

| Área | Validación confirmada | Limitación |
|---|---|---|
| Bash | ShellCheck + shfmt + smoke tests en VMs Debian 12/13 reales | Solo Debian; no cubre Ubuntu |
| Ansible | ansible-lint + Molecule sobre Debian 12/13 | Sin validación en VM real |
| CI | Workflows activos para lint y Molecule | Sin smoke tests E2E de Bash en CI |

---

## Gaps confirmados y su impacto

| Tema | Situación | Impacto |
|---|---|---|
| Bash validado en VM real | Opciones 1-5 probadas en Debian 12 y 13 | Riesgo bajo de regresiones en Bash |
| Ansible sin validación en VM real | Solo Molecule en contenedores CI | Sin garantía de funcionamiento en server real |
| Guards de distro en Bash | `modules/common.sh` valida `ID=debian` + versiones `12/13` | Corta temprano en Ubuntu |
| Repo Docker en Bash | Usa repo oficial con codename desde `/etc/os-release` | Validado en VMs reales |
| Guards de Ansible | `ansible_distribution == "Debian"` | Ubuntu bloqueado explícitamente |

---

## Decisión práctica para usar el proyecto hoy

1. **Usá los scripts Bash en Debian 12 o Debian 13** — están validados en VMs reales.
2. **Ansible está implementado pero sin validación operativa** — usalo con precaución o validalo vos mismo antes.
3. **No planifiques Ubuntu todavía.**

---

## Diferencias operativas entre Debian 12 y Debian 13

1. **Fail2ban backend**: Debian 13 usa `journald` por defecto. Bash y Ansible configuran `backend = systemd` en `jail.local` para ambas versiones, con override `sshd_backend = systemd` en `paths-debian.conf` solo para Debian 13+.
2. **Repositorio Docker**: El codename (`bookworm`/`trixie`) se deriva dinámicamente de `/etc/os-release`.
3. **Paquetes base**: Debian 13 puede requerir ajustes menores manejados por los guards.

---

## Roadmap de alto nivel

> El detalle de tareas por fase está en [`TODO.md`](TODO.md).

### Fase 1 — Sincerar soporte ✅

Documentar estado real, alinear docs, definir política de soporte.

### Fase 2 — Bash: Debian 12 y Debian 13 ✅

Endurecer guards, validar en VM real, documentar diferencias operativas.

### Fase 3 — Ansible: cerrar antes de abrir Ubuntu

Implementación lista (guards, Molecule, lint). Pendiente: **validación operativa en VM real** — ver [`TODO.md` §9](TODO.md#9-tareas-pendientes--ansible) para la lista completa de items Ansible.

### Fase 4 — Ubuntu (futuro)

No iniciar hasta cerrar Fases 2 y 3.

---

## Matriz de verificación por plataforma

| Plataforma | Bash lint | Bash VM real | Ansible lint | Molecule | Ansible VM real | Estado |
|---|---|---|---|---|---|---|
| Debian 12 | ✅ | ✅ | ✅ | ✅ | ❌ | Bash: validated / Ansible: experimental |
| Debian 13 | ✅ | ✅ | ✅ | ✅ | ❌ | Bash: validated / Ansible: experimental |
| Ubuntu 24.04 | ❌ | ❌ | ❌ | ❌ | ❌ | Unsupported |

---

## Criterio para declarar soporte oficial

Una plataforma es **soportada** solo cuando cumple TODO:

- [ ] Guardrails explícitos en Bash y/o Ansible
- [ ] Cobertura CI o pruebas reproducibles documentadas
- [ ] Al menos una validación en VM real
- [ ] Documentación consistente con el comportamiento real
- [ ] Rollback y verificación post-cambio documentados
