# nha-hard-wsl-vmware

Laboratorio de Active Directory para práctica y aprendizaje, montado a mano en **VMware Workstation** y configurado con **Ansible desde WSL2**.

> **ADVERTENCIA:** Este es un entorno de laboratorio deliberadamente inseguro. Contiene contraseñas débiles, permisos excesivos y configuraciones típicas de entornos reales mal mantenidos. **No lo uses en producción ni lo expongas a Internet.**

---

## Qué es esto

Un lab de AD con dos dominios, confianza, ADCS, Sysmon, auditoría avanzada y varios “olores” realistas (cuentas de servicio antiguas, passwords en Description, shares con configs, etc.). Está inspirado en labs tipo NHA, pero **sin Vagrant**: tú creas las VMs y Ansible hace el resto desde WSL.

## Arquitectura

| Máquina       | Rol                         | Dominio           | IP (ejemplo)   |
|---------------|-----------------------------|-------------------|----------------|
| `NYX-DC01`    | Domain Controller           | `nyxcore.lab`     | `192.168.56.10` |
| `VEL-DC01`    | Domain Controller           | `veloran.corp`    | `192.168.56.20` |
| `NYX-CA01`    | ADCS (Enterprise CA)        | `nyxcore.lab`     | `192.168.56.11` |
| `NYX-FS01`    | File server + shares        | `nyxcore.lab`     | `192.168.56.12` |
| `NYX-JUMP`    | Punto de entrada limitado   | `nyxcore.lab`     | `192.168.56.13` |

**Dominios (originales):**
- `nyxcore.lab` — dominio principal (usuarios, CA, files, jump)
- `veloran.corp` — dominio secundario con **trust bidireccional** hacia `nyxcore.lab`

**Red sugerida (VMware Host-Only o NAT custom):**
- Subred: `192.168.56.0/24`
- Gateway / DNS externo: según tu VMnet
- DNS interno: `192.168.56.10` (`NYX-DC01`) y `192.168.56.20` (`VEL-DC01`)

```
                    ┌─────────────────┐
                    │   WSL2 / Ansible │
                    │  (control node)  │
                    └────────┬────────┘
                             │ WinRM
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────▼────┐         ┌────▼────┐         ┌────▼────┐
    │ NYX-DC01│◄─trust─►│ VEL-DC01│         │ NYX-JUMP│
    │  .10    │         │  .20    │         │  .13    │
    └────┬────┘         └─────────┘         └─────────┘
         │
    ┌────┼────┐
    │         │
┌───▼───┐ ┌───▼───┐
│NYX-CA01│ │NYX-FS01│
│  .11   │ │  .12   │
└────────┘ └────────┘
```

## Requisitos

### Host
- Windows 10/11 con **WSL2** (Ubuntu 22.04+ recomendado)
- **VMware Workstation** Pro o Player
- ISO de **Windows Server 2019 o 2022** (Evaluation)
- ~16 GB RAM libres (mínimo ~2–4 GB por VM)
- ~100 GB de disco libres

### Dentro de WSL
- Ansible 2.14+
- Colecciones: `ansible.windows`, `community.windows`, `microsoft.ad`
- Python 3 + `pywinrm`

El script `scripts/setup-wsl.sh` instala lo necesario.

## Aviso de seguridad del lab

- Defender **permanece activo** en todas las máquinas.
- Sysmon (config tipo SwiftOnSecurity / Olaf Hartong) se instala vía Ansible.
- Advanced Audit Policy se habilita vía Ansible.
- Hay flags, cuentas atractivas y configs “sucias” a propósito. Trátalo como red hostil de práctica.

---

## Guía paso a paso: VMs en VMware

### 1. Red Host-Only

1. En VMware: **Edit → Virtual Network Editor**.
2. Crea o usa una red **Host-only** (ej. `VMnet1`).
3. Subred: `192.168.56.0`, máscara `255.255.255.0`.
4. Desactiva DHCP del host-only si vas a usar IPs fijas (recomendado).

### 2. Crear cada VM (repite 5 veces)

Para **cada** máquina de la tabla:

1. **File → New Virtual Machine → Custom**.
2. Hardware compatibility: Workstation 16+ (o la tuya).
3. Installer disc image: tu ISO de Windows Server.
4. Guest OS: Windows Server 2019/2022.
5. Nombre y carpeta: usa el hostname (`NYX-DC01`, etc.).
6. Firmware: **BIOS** (más simple para lab) o UEFI si prefieres.
7. Disco: **60 GB**, thin provision.
8. RAM: **2048–4096 MB** (DCs preferible 4 GB).
9. CPU: 2 vCPU.
10. Red: **Host-only** (la VMnet de arriba). Opcional: segunda NIC NAT solo si necesitas descargas; para el lab basta host-only + share de ISOs.
11. Instala Windows Server (Desktop Experience recomendado para lab).
12. Contraseña local de Administrator: usa **la misma en las 5 VMs** y ponla en `lab_admin_password` (`ansible/group_vars/all.yml`). Al promover los DCs pasa a ser la del Administrator de cada dominio.

### 3. Post-instalación mínima (en cada VM, antes de Ansible)

En la consola de cada VM, como Administrator local:

1. Pon el **hostname** correcto (`Rename-Computer -NewName NYX-DC01 -Restart`).
2. Configura IP estática, máscara, gateway y DNS:
   - DCs: DNS a sí mismos + el otro DC después.
   - Resto: DNS primario `192.168.56.10`.
3. Copia `scripts/Configure-WinRM.ps1` a la VM (USB virtual, share, o pegar contenido).
4. Ejecuta en PowerShell **como Administrator**:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Configure-WinRM.ps1
```

5. Verifica desde WSL:

```bash
nc -zv 192.168.56.10 5985
```

Repite para las 5 IPs.

> No desactives Windows Defender. El script de WinRM **no** toca Defender.

### 4. Orden recomendado de despliegue Ansible

1. `setup-wsl.sh` (una vez en WSL).
2. Ajusta `ansible/inventory.ini` y `ansible/group_vars/all.yml` (contraseñas, IPs).
3. Ejecuta `bash scripts/deploy.sh` (o por fases). El orden **no se puede cambiar**:

| Fase | Playbook | Qué hace |
|------|----------|----------|
| 00 | `00-ping.yml` | Conectividad WinRM |
| 01 | `01-baseline.yml` | Carpetas, Defender ON, Sysmon, auditoría local |
| 02 | `02-domain-nyxcore.yml` | Bosque `nyxcore.lab` en `NYX-DC01` |
| 03 | `03-domain-veloran.yml` | Bosque `veloran.corp` en `VEL-DC01` |
| 04 | `04-trust.yml` | DNS condicional + trust bidireccional |
| 05 | `05-domain-join.yml` | Une `NYX-CA01`, `NYX-FS01`, `NYX-JUMP` |
| 06 | `06-adcs.yml` | Enterprise CA + plantilla legacy + `/certsrv` |
| 07 | `07-ad-objects.yml` | OUs, grupos, usuarios, SPNs |
| 08 | `08-gpo-audit-kerberos.yml` | GPO auditoría + Kerberos/contraseñas |
| 09 | `09-shares.yml` | `\\NYX-FS01\DeptConfigs` (+ `Backups$`) |
| 10 | `10-acls-flags.yml` | ACLs, flags, jump limitado (RDP + logging) |

Equivalente a todo de una vez: `cd ansible && ansible-playbook -i inventory.ini playbooks/site.yml`.
Ejemplos: `bash scripts/deploy.sh ping` · `bash scripts/deploy.sh 06` · `bash scripts/deploy.sh 06 10`.

---

## Inicio rápido (después de crear las VMs)

```bash
# En WSL, clona o copia este repo
cd nha-hard-wsl-vmware

# Instalar Ansible y colecciones
bash scripts/setup-wsl.sh

# Editar inventario y secretos
nano ansible/inventory.ini
nano ansible/group_vars/all.yml

# Desplegar todo (o por fases; ver deploy.sh)
bash scripts/deploy.sh
```

Comprueba conectividad:

```bash
cd ansible
ansible all -i inventory.ini -m win_ping
```

---

## Estructura del repositorio

```
nha-hard-wsl-vmware/
├── README.md
├── scripts/
│   ├── Configure-WinRM.ps1   # Único script PowerShell (mínimo)
│   ├── setup-wsl.sh          # Prep del nodo de control en WSL
│   └── deploy.sh             # Orquesta playbooks
├── ansible/
│   ├── inventory.ini
│   ├── ansible.cfg
│   ├── requirements.yml
│   ├── group_vars/
│   ├── host_vars/
│   ├── playbooks/
│   └── roles/
├── docs/
│   ├── ERRORES.md            # WinRM, red, Ansible, Defender, Sysmon
│   ├── ATTACK-PATHS.md       # Pistas / caminos de práctica
│   └── VARIACIONES.md        # Diferencias vs labs básicos
├── examples/
│   ├── sample-flags.txt          # Spoiler de flags (autor del lab)
│   ├── vault-example.yml
│   ├── inventory-custom-subnet.ini
│   └── static-ip-snippets.ps1
├── .gitignore
└── LICENSE
```

---

## Elementos “realistas” incluidos

Configurados principalmente con Ansible:

| Elemento | Dónde |
|----------|--------|
| Sysmon (SwiftOnSecurity / Hartong style) | Todas las VMs Windows |
| Advanced Audit Policy | Dominio + locales |
| Defender activo | Todas |
| Cuentas de ejemplo atractivas | `nyxcore.lab` / `veloran.corp` |
| Password reutilizada / en Description | Usuarios de servicio legacy |
| Share con configs de ejemplo | `NYX-FS01` (`\\NYX-FS01\DeptConfigs`) |
| ADCS | `NYX-CA01` |
| Trust | `nyxcore.lab` ↔ `veloran.corp` |
| Kerberos / ACL quirks | Roles `ad_users_groups`, `ad_gpo_kerberos`, `ad_acls_flags` |
| Flags | Varias máquinas (ver `docs/ATTACK-PATHS.md`) |

Nombres de ejemplo (cámbialos si quieres):
- Dominios: `nyxcore.lab`, `veloran.corp`
- Usuarios: `svc_backup_legacy`, `adm.old.helio`, `j.cortez`, `m.quiroga`
- Share: `DeptConfigs` con un `IT-Ops\db-conn.txt` “olvidado”

---

## Documentación adicional

- [Problemas comunes](docs/ERRORES.md) — WinRM, red, Ansible, Defender, Sysmon
- [Caminos de ataque / flags](docs/ATTACK-PATHS.md)
- [Variaciones respecto a labs básicos](docs/VARIACIONES.md)

---

## Principios de diseño

1. **Sin Vagrant** — VMs creadas a mano en VMware.
2. **Un solo script PS mínimo** — solo WinRM inicial.
3. **Todo lo demás desde WSL + Ansible**.
4. **Defender ON** — no se desactiva para “facilitar” el lab.
5. **Menos “lab spoiler”** — configs sutiles, no solo misconfigs de tutorial.

---

## Licencia y uso

Uso educativo y de laboratorio personal. Eres responsable de aislar la red host-only y de no conectar este lab a redes de producción.

Si publicas el repo en GitHub, **rota o cambia** todas las contraseñas del inventario antes de cualquier uso serio, e incluye este aviso de laboratorio en tu fork.
