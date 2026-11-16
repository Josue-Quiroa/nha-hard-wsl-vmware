# Variaciones respecto a labs básicos

Este lab se inspira en entornos tipo NHA/GOAD, pero cambia varias decisiones para que se parezca más a una red corporativa real y obligue a **revisar** en lugar de seguir una receta.

## Tabla comparativa

| Aspecto | Lab básico típico | `nha-hard-wsl-vmware` |
|---|---|---|
| Aprovisionamiento | Vagrant + boxes preconstruidas | VMs **creadas a mano** en VMware Workstation |
| Bootstrap | Scripts PowerShell largos | **Un solo** `Configure-WinRM.ps1` mínimo; el resto, Ansible desde WSL2 |
| Antivirus | Defender desactivado "para que funcione" | **Defender activo** en todas las VMs |
| Telemetría | Ninguna | **Sysmon** + **Advanced Audit Policy** (local y GPO) + logging de PowerShell en el jump |
| Dominios | Uno, o parent/child | **Dos bosques** (`nyxcore.lab`, `veloran.corp`) con **trust bidireccional** |
| Entrada | Admin local o usuario con privilegios | Usuario estándar con **RDP solo al jump** |
| Contraseñas | `Password123!` en todo | Mezcla realista: algunas fuertes, una documentada, una reutilizada entre bosques |
| Misconfigs | Muy evidentes (Domain Users = admin, etc.) | Sutiles y con "historia": delegaciones viejas, cuentas espejo, plantillas heredadas |
| ADCS | Ausente o ESC1 abierto a Domain Users | Plantilla legacy limitada a un grupo pequeño + Web Enrollment HTTP |
| Shares | `\\DC\share` con `passwords.txt` | Share departamental con permisos "a medias" y secretos en cadenas de conexión |
| Kerberos | Solo kerberoast de una cuenta obvia | SPN + RC4-only, AS-REP, delegación restringida con transición de protocolo, GPO de RC4 |
| Señuelos | Ninguno: todo lo que encuentras sirve | **Cuentas honeypot** (Kerberoast/AS-REP irrompibles, `adminCount=1` sin privilegios), **caminos falsos** (ACLs, GPP `cpassword`, share de archivo, plantilla ADCS con grupo vacío) y SACLs que alertan al tocarlos |
| Objetivo | Llegar a Domain Admin | Recorrer el camino **y** detectarlo **y** corregirlo |

## Detalle de las diferencias

### 1. Sin Vagrant
Crear las VMs a mano obliga a entender red host-only, DNS, nombres y la secuencia real de despliegue. Además evita depender de boxes de terceros.

### 2. Defender activo
Muchas técnicas "de libro" fallan con Defender. Eso es lo realista. El lab te obliga a:
- usar herramientas nativas para enumerar,
- entender **qué** detecta Defender y **por qué**,
- revisar los eventos 1116/1117 en `Microsoft-Windows-Windows Defender/Operational`.

### 3. Sysmon + Advanced Audit Policy
Cada paso del camino de ataque deja eventos (4624, 4662, 4768, 4769, 4886/4887, 5136, 5145, Sysmon 1/3/10/11). La config de Sysmon es reducida; sustitúyela por la completa de SwiftOnSecurity u Olaf Hartong si quieres más cobertura.

### 4. Menos configuraciones obvias
- `adm.old.helio` **no** es Domain Admin: su poder es lateral (FileShare-Admins, PKI-Operators).
- La plantilla ADCS vulnerable **no** está abierta a todo el dominio.
- La carpeta sensible del share **sí** está restringida… a un grupo que incluye una cuenta comprometible.
- El trust tiene SID filtering activo (comportamiento por defecto); el salto se hace por **reutilización de contraseña**, que es lo que suele pasar.

### 5. Dos bosques
Practicas DNS condicional, trusts de bosque, Foreign Security Principals y enumeración cross-forest.

### 6. Señuelos y caminos falsos
En una red real no todo lo "jugoso" es explotable, y los equipos de defensa plantan cebos a propósito. La fase 11 añade:
- **Cuentas honeypot** en ambos bosques: una kerberoastable, una AS-REP roastable, una con `adminCount=1` y otra en un grupo "Tier 0". Todas con contraseñas aleatorias de 40 caracteres y **sin privilegios**.
- **Credenciales falsas** en sitios creíbles: `DeptConfigs\Archive`, un share oculto `IT-Archive$` con un `Groups.xml` de GPP y scripts antiguos.
- **Una ruta de ACLs** que BloodHound enseña desde el usuario inicial y que termina en una cuenta inútil.
- **Una plantilla ADCS** con aspecto de ESC1 cuyo único grupo con Enroll está vacío.
- **SACLs "honeytoken"** que convierten cualquier lectura o uso de los señuelos en eventos 4662/4663/4768/4769/4771.

El alumno tiene que **verificar** cada hallazgo antes de invertir tiempo en él, y el defensor puede practicar alertas de alta confianza. Detalles (spoiler): [`DETECCION.md`](DETECCION.md).

## Variaciones opcionales (para hacerlo más difícil o distinto)

Todas se cambian en `group_vars` / defaults de los roles:

| Variable | Dónde | Efecto |
|---|---|---|
| `trust_disable_sid_filtering: true` | `roles/ad_trust/defaults` | Desactiva SID filtering en el trust (escenario SID history). |
| `adcs_enable_web_enrollment: false` | `group_vars/all.yml` | Elimina el vector HTTP de la CA. |
| `kerberos_allow_rc4: false` | `roles/ad_gpo_kerberos/defaults` | Fuerza AES (svc_sqlreport sigue en RC4 por atributo). |
| `lockout_threshold: 5` | `roles/ad_gpo_kerberos/defaults` | Añade bloqueo: el spraying se vuelve arriesgado. |
| `jump_powershell_logging: false` | `roles/ad_acls_flags/defaults` | Menos telemetría en el jump. |
| `defender_fail_if_disabled: true` | `roles/win_defender_check/defaults` | El despliegue falla si Defender está apagado. |
| `decoys_enabled: false` | `group_vars/all.yml` | Despliega el lab sin señuelos (fase 11 no hace nada). |
| `decoy_adcs_enabled: false` | `group_vars/all.yml` | Sin plantilla ADCS señuelo. |
| `decoy_ad_sacl: false` | `group_vars/all.yml` | Sin SACL honeytoken en AD (menos eventos 4662). |
| Usuarios / ACLs | `group_vars/nyxcore.yml`, `veloran.yml` | Cambia nombres, contraseñas o ACLs para crear tus propios caminos. |
