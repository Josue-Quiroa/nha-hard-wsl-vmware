# REVIEW-NOTES — nha-hard-wsl-vmware

Revisión pre-push (2026-11-15, America/Guatemala). No se hizo `git init` ni push (lo maneja el agente padre).

## Checklist de confirmación

| Chequeo | Resultado |
|---------|-----------|
| README vs archivos (rutas, roles, hosts, IPs, dominios, scripts, playbooks) | OK tras alinear tabla de fases |
| `inventory.ini` vs `group_vars` / `host_vars` / README | OK (`192.168.56.10/11/12/13/20`, `nyxcore.lab` / `veloran.corp`) |
| `deploy.sh` PHASES vs `ansible/playbooks/*.yml` | OK (00–10 + `site.yml`) |
| `site.yml` imports vs playbooks existentes | OK |
| Variables usadas en roles vs defaults/`group_vars` | OK (defaults presentes en roles) |
| Enlaces relativos en docs | OK (`docs/*.md` desde README) |
| `Configure-WinRM.ps1` corto y sin tocar Defender | OK |
| `setup-wsl.sh` / `deploy.sh` shebang + ejecutables + shellcheck | OK |
| YAML parse de todos los `.yml` | OK (0 errores) |
| `.gitignore` (logs, vault, Sysmon binaries; no ignora YAML del lab) | OK |
| ATTACK-PATHS / sample-flags vs passwords y flags en `group_vars` | OK |
| Share `DeptConfigs/IT-Ops/db-conn.txt` presente | OK |

**Listo para push: SÍ** (con limitaciones conocidas no bloqueantes abajo).

## Corregido en esta revisión

1. **`ansible/group_vars/all.yml`** — Comentario de `reused_password` decía que se reutiliza en veloran; en realidad se documenta en Description + share (`onboarding.txt` / `backup-agent.config`). La reutilización entre bosques es `helio_reused_password`.
2. **`ansible/group_vars/all.yml`** — FLAG-07 apuntaba a `group_vars/veloran_dcs.yml`; el atributo `info` está en `group_vars/veloran.yml`.
3. **`ansible/roles/ad_acls_flags/tasks/main.yml`** — Crear `C:\Lab\logs\transcripts` antes de habilitar PowerShell Transcription en el jump (si no, la transcripción puede fallar en silencio).
4. **`ansible/roles/win_sysmon/tasks/main.yml`** — Usar `sysmon_svc.exists | default(false)` para no romper si `win_service_info` no trae `exists`.
5. **`ansible/roles/ad_adcs/tasks/main.yml`** — Instalar `Web-Server` + `Web-Asp-Net45` junto a Web Enrollment (evita fallos de `/certsrv` sin IIS).
6. **`ansible/roles/ad_users_groups/tasks/main.yml`** — Reubicar grupos a `ad_groups_path` si se crearon antes en otro contenedor (p.ej. `PKI-Operators` creado en la fase 06 en `CN=Users`).
7. **`README.md`** — Tabla de fases 00–10 alineada con `deploy.sh` / `site.yml` (antes el orden era vago e incluía “hardening del jump” como paso suelto).
8. **`examples/static-ip-snippets.ps1`** — Snippets para las 5 VMs (antes solo .10/.20/.11).

## Hallazgos

### Críticos (bloqueaban o mentían al usuario) — corregidos
- Comentarios de `all.yml` que contradecían ATTACK-PATHS / `veloran.yml` (password reutilizada / ubicación FLAG-07).
- Web Enrollment sin dependencias IIS explícitas (fallo frecuente en Server limpio).
- Grupo `PKI-Operators` creado en fase 06 quedaba fuera de `OU=Groups` sin tarea de reubicación.

### Menores — corregidos
- Carpeta de transcripts del jump.
- Robustez del check de servicio Sysmon.
- README / snippets de IP incompletos.

### Limitaciones conocidas (no bloqueantes)

- **Sysmon en host-only sin Internet:** hace falta NIC NAT temporal o `Sysmon64.exe` en `roles/win_sysmon/files/` + `sysmon_local_binary: true`.
- **Contraseñas y flags en claro** en `group_vars` / `examples/sample-flags.txt` a propósito (LAB). Rotar antes de uso serio; opcional vault (`examples/vault-example.yml`).
- **Misconfigs intencionales** (Description con password, GenericWrite, RC4, ADCS legacy, Authenticated Users en share, etc.) — no “arreglarlos”.
- **`community.windows`** está en `requirements.yml` pero el lab usa sobre todo `ansible.windows` + `microsoft.ad` (inocuo).
- **Ansible desde `/mnt/c`:** puede ignorar `ansible.cfg` (documentado en `docs/ERRORES.md`); clonar en el home de WSL.
- **Promoción DC / ADCS / trust** son las fases más frágiles (DNS, clock skew, timeouts); los roles son idempotentes — relanzar la fase suele bastar.
- No se pudo ejecutar `ansible-playbook --syntax-check` aquí (Ansible no instalado en el box); sí parseo YAML + shellcheck.

## Archivos tocados

- `ansible/group_vars/all.yml`
- `ansible/roles/ad_acls_flags/tasks/main.yml`
- `ansible/roles/ad_adcs/tasks/main.yml`
- `ansible/roles/ad_users_groups/tasks/main.yml`
- `ansible/roles/win_sysmon/tasks/main.yml`
- `README.md`
- `examples/static-ip-snippets.ps1`
- `REVIEW-NOTES.md` (este archivo)
