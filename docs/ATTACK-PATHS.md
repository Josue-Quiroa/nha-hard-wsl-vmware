# Caminos de práctica (ATTACK-PATHS)

> **Solo para laboratorio.** Este documento describe **qué está mal configurado y por qué**, para practicar la **revisión de seguridad y la administración** de Active Directory. No incluye código de explotación: la idea es que investigues tú las técnicas, las ejecutes **solo en este lab** y, sobre todo, que **detectes y corrijas** cada problema.

---

## Resumen del escenario

Eres un auditor al que le dan una cuenta de dominio sin privilegios y acceso RDP a un servidor de salto. El objetivo es entender hasta dónde llega un atacante desde ahí y qué rastro deja.

| Dato inicial | Valor |
|---|---|
| Usuario | `NYXCORE\j.cortez` |
| Contraseña | `Cortez.Spring24!` |
| Acceso | RDP a `NYX-JUMP` (192.168.56.13) |

```
j.cortez ──RDP──► NYX-JUMP (FLAG-01)
   │
   └─ LDAP: Description de svc_backup_legacy ──► svc_backup_legacy
                                                  │
              \\NYX-FS01\DeptConfigs\IT-Ops ◄──────┘  (FLAG-02, db-conn.txt)
                    │                     │
           m.quiroga (password)    svc_sqlreport (SPN + delegación)
                    │                     │
         GenericWrite sobre               └─► NYX-FS01 (FLAG-03)
           adm.old.helio
                    │
     ┌──────────────┼───────────────────┐
FileShare-Admins  PKI-Operators      password reutilizada
  NYX-FS01         NYX-CA01 (FLAG-04)    │
                   plantilla legacy      ▼
                      │             VELORAN\helio.vadmin
                      ▼                  │
                 NYX-DC01 (FLAG-05)  VEL-DC01 (FLAG-06)

Enumeración a través del trust: atributo "info" en veloran.corp (FLAG-07)
```

---

## Fase 0 — Punto de entrada limitado (`NYX-JUMP`)

**Qué hay:** `j.cortez` está en `Jump-RDP-Users`, que es miembro de *Remote Desktop Users* solo en `NYX-JUMP`. No es administrador local. En el jump están activados *Script Block Logging*, *Transcription* de PowerShell, Sysmon y Defender.

**Qué practicar:**
- Inventario del host como usuario sin privilegios (qué grupos tienes, qué puedes leer).
- Enumeración de AD **con herramientas nativas** (por ejemplo `net`, `nltest`, `[adsisearcher]`, módulo ActiveDirectory si está instalado). Defender bloqueará muchas herramientas conocidas: **no lo desactives**, forma parte del reto.

**Flag:** `FLAG-01` en `C:\Lab\flags\flag01-foothold.txt` (legible por `Jump-RDP-Users`).

**Revisión defensiva:** eventos 4624 (tipo 10, RDP), 4688 + Sysmon EID 1 con línea de comandos, transcripciones en `C:\Lab\logs\transcripts`.

---

## Fase 1 — Enumeración: lo que cualquier usuario del dominio puede ver

| Hallazgo | Objeto | Por qué es un problema |
|---|---|---|
| Contraseña en el campo **Description** | `svc_backup_legacy` | Cualquier usuario autenticado puede leer `description` por LDAP. |
| Cuenta con **SPN** y solo **RC4** | `svc_sqlreport` (`msDS-SupportedEncryptionTypes = 4`) | Kerberoasting; con RC4 el ticket es más fácil de atacar offline. |
| **Pre-autenticación desactivada** | `r.lindqvist` | AS-REP roasting. |
| Contraseña "estándar" documentada | `\\NYX-FS01\DeptConfigs\HR\onboarding.txt` | Invita a *password spraying* y reutilización. |
| Política de dominio sin bloqueo | `LockoutThreshold = 0` | Spraying sin consecuencias. |
| Delegación de helpdesk | `Helpdesk-T1` → *Reset password* sobre `OU=Contractors` | Delegación legítima, pero amplía la superficie. |
| GPO "LAB - Kerberos Legacy Compat" | RC4 permitido en todo el dominio | Configuración heredada muy frecuente. |

**Pista:** empieza por el campo `description` de las cuentas de servicio.

**Revisión defensiva:** 4662 (acceso a objetos de directorio, si configuras SACL), 4769 con *Ticket Encryption Type 0x17* (RC4), 4768 con *Pre-Authentication Type 0*.

---

## Fase 2 — Recurso compartido con configuraciones (`NYX-FS01`)

**Qué hay:** `\\NYX-FS01\DeptConfigs` da lectura a *Authenticated Users* en la raíz. La subcarpeta `IT-Ops` se restringió "a medias" al grupo `IT-Ops-Readers`, del que es miembro `svc_backup_legacy`.

Archivos interesantes:
- `IT-Ops\db-conn.txt` — cadenas de conexión "temporales" con la contraseña de `m.quiroga` y referencias a `svc_sqlreport` y al portal `/certsrv` en HTTP.
- `IT-Ops\backup-agent.config` — repite la contraseña de la cuenta de backup.
- `IT-Ops\deploy.ps1` — comentario que delata que una tarea nocturna usa `adm.old.helio`.

**Flag:** `FLAG-02` en `\\NYX-FS01\DeptConfigs\IT-Ops\flag02.txt` (solo `IT-Ops-Readers`).

**Revisión defensiva:** 5140/5145 (acceso a shares), Sysmon EID 3 hacia 445.

---

## Fase 3 — Movimiento lateral

### 3a. Delegación restringida (`svc_sqlreport`)
`svc_sqlreport` tiene `msDS-AllowedToDelegateTo = cifs/nyx-fs01.nyxcore.lab` **con transición de protocolo** (`TrustedToAuthForDelegation`). Investiga qué implica eso si alguien obtiene la contraseña o el hash de la cuenta (concepto: S4U2Self/S4U2Proxy).

### 3b. ACL sobre un admin heredado
`m.quiroga` tiene **GenericWrite** sobre `adm.old.helio` (delegación "temporal" de 2021 nunca revertida). Investiga qué atributos permite modificar GenericWrite y por qué es grave (conceptos: *targeted kerberoasting*, *shadow credentials* — el dominio tiene PKI, así que PKINIT está disponible).

**Flag:** `FLAG-03` en `NYX-FS01:C:\Lab\flags\flag03-fs-admin.txt` (solo administradores locales; `FileShare-Admins` lo es).

**Extra:** el share oculto `\\NYX-FS01\Backups$` (solo `FileShare-Admins`) contiene notas de la tarea nocturna.

**Revisión defensiva:** 5136 (cambio de atributos en AD: `servicePrincipalName`, `msDS-KeyCredentialLink`), 4769 con S4U, 4624 tipo 3 en `NYX-FS01`.

---

## Fase 4 — PKI (`NYX-CA01`)

**Qué hay:**
- Enterprise Root CA `NYXCORE-ROOT-CA`.
- Web Enrollment (`http://nyx-ca01.nyxcore.lab/certsrv`) **sobre HTTP**.
- Plantilla **`NyxLegacyUserAuth`**: *Client Authentication*, el **solicitante proporciona el subject**, sin aprobación de manager, enroll para `PKI-Operators`.
- `PKI-Operators` es además **administrador local** de `NYX-CA01`.

**Qué practicar:** auditar plantillas y la CA (herramientas como Certify/Certipy en modo *find*, `certutil -v -template`, la consola *Certificate Templates*). Identificar qué combinación de flags convierte una plantilla en peligrosa (categorías tipo **ESC1** y **ESC8** de la investigación *Certified Pre-Owned*).

**Flags:**
- `FLAG-04` en `NYX-CA01:C:\Lab\flags\flag04-pki.txt` (administradores locales).
- `FLAG-05` en `NYX-DC01:C:\Lab\flags\flag05-domain.txt` (administradores del dominio).

**Revisión defensiva:** 4886/4887 (solicitudes/emisión de certificados, requiere auditoría *Certification Services*, incluida en la GPO), 4768 con autenticación por certificado, logs de IIS en `/certsrv`.

---

## Fase 5 — Cruzar el trust (`veloran.corp`)

**Qué hay:**
- Trust de bosque **bidireccional** `nyxcore.lab ↔ veloran.corp` (SID filtering activado por defecto).
- `VELORAN\svc_sync_veloran` guarda `FLAG-07` en su atributo `info`. Cualquier usuario de `nyxcore.lab` puede leerlo **enumerando LDAP a través del trust**.
- `VELORAN\helio.vadmin` es Domain Admin de veloran y su descripción dice "cuenta espejo de NYXCORE\adm.old.helio": **misma contraseña**.
- El grupo `NYXCORE\Finance-Users` es miembro de `VELORAN\Vel-Partner-Readers` (Foreign Security Principal).

**Flags:**
- `FLAG-06` en `VEL-DC01:C:\Lab\flags\flag06-veloran.txt`.
- `FLAG-07` en el atributo `info` de `VELORAN\svc_sync_veloran`.

**Revisión defensiva:** 4624/4769 en `VEL-DC01` con cuentas de otro dominio, membresías en `CN=ForeignSecurityPrincipals`, `Get-ADTrust`.

---

## Dónde están las flags

| ID | Host | Ubicación | Quién puede leerla |
|----|------|-----------|--------------------|
| FLAG-01 | NYX-JUMP | `C:\Lab\flags\flag01-foothold.txt` | `NYXCORE\Jump-RDP-Users` |
| FLAG-02 | NYX-FS01 | `\\NYX-FS01\DeptConfigs\IT-Ops\flag02.txt` | `NYXCORE\IT-Ops-Readers` |
| FLAG-03 | NYX-FS01 | `C:\Lab\flags\flag03-fs-admin.txt` | Administradores locales |
| FLAG-04 | NYX-CA01 | `C:\Lab\flags\flag04-pki.txt` | Administradores locales |
| FLAG-05 | NYX-DC01 | `C:\Lab\flags\flag05-domain.txt` | Domain Admins (nyxcore) |
| FLAG-06 | VEL-DC01 | `C:\Lab\flags\flag06-veloran.txt` | Domain Admins (veloran) |
| FLAG-07 | VEL-DC01 | atributo `info` de `svc_sync_veloran` | Cualquier usuario autenticado (vía trust) |

Valores concretos: `examples/sample-flags.txt` (spoiler, solo para el autor del lab).

---

## Ejercicio final: corregirlo todo

Cuando termines, practica la parte de administración. Lista de remediación sugerida:

1. Quitar la contraseña del `description` y rotar `svc_backup_legacy` (migrar a gMSA).
2. Convertir `svc_sqlreport` a AES-only, contraseña larga o gMSA; revisar si necesita delegación y, si sí, sin transición de protocolo.
3. Reactivar la pre-autenticación de `r.lindqvist`.
4. Eliminar la ACE GenericWrite de `m.quiroga` sobre `adm.old.helio`; deshabilitar `adm.old.helio` y `helio.vadmin`.
5. Sacar secretos de `DeptConfigs`, quitar *Authenticated Users* de la raíz.
6. Plantilla `NyxLegacyUserAuth`: quitar *Supply in the request* o exigir aprobación de manager; despublicarla.
7. Web Enrollment: HTTPS + EPA, o desinstalarlo.
8. GPO RC4: eliminar; política de bloqueo de cuentas > 0.
9. Revisar membresías cross-forest y la necesidad real de un trust bidireccional.

Comprueba después que cada corrección genera (o deja de generar) los eventos esperados en Security y Sysmon.

> **Ojo:** no todo lo que parece vulnerable lleva a algún sitio. El lab incluye cuentas señuelo y caminos falsos (ver la sección de spoiler al final, solo para el autor). Parte del reto es distinguir un hallazgo real de un cebo.

---

## Señuelos y caminos falsos (SPOILER — solo autor del lab)

> **No leas esta sección si vas a hacer el lab como alumno.** Está pensada para quien lo monta o lo imparte.

Desde la **fase 11** el lab incluye cuentas honeypot y caminos que **parecen** prometedores pero no llevan a ninguna parte. Ninguno modifica ni acorta la cadena real (FLAG-01 → FLAG-07), y no hay flags en ellos.

| Señuelo | Lo que ve el alumno | Realidad |
|---|---|---|
| `svc_sql_old` | Cuenta con SPN `MSSQLSvc/nyx-sql01.nyxcore.lab:1433`, solo RC4, en `SQL-Admins-Legacy` | Password aleatoria de 40 caracteres: el TGS no se rompe. `NYX-SQL01` no existe |
| `adm.backup` | `adminCount=1`, OU `LegacyAdmins`, password en un runbook, un `.bat` y un `Groups.xml` (GPP) | Las tres passwords son **incorrectas**. La cuenta no tiene ningún privilegio |
| `ext.auditor2019` | AS-REP roastable | Hash irrompible. Si Helpdesk la resetea, entra en una cuenta vacía |
| `VELORAN\vel.svc_deploy` | SPN, `adminCount=1`, miembro de `Tier0-Ops-Legacy`, credencial en `nightly-export.ps1` | Password del script falsa; `Tier0-Ops-Legacy` no tiene derechos |
| ACL `Helpdesk-T1 → GenericAll → SrvOps-Legacy → GenericWrite → adm.backup` | BloodHound muestra una ruta desde `j.cortez` | Termina en `adm.backup`, que no tiene privilegios |
| `\\NYX-FS01\DeptConfigs\Archive\` | Configs "antiguas" con credenciales | Credenciales falsas, hosts inexistentes (`NYX-SQL01`, `NYX-BKP01`) |
| `\\NYX-FS01\IT-Archive$` | Share oculto legible por todos, con export de GPO (`cpassword`) | El `cpassword` descifra a una password falsa |
| Plantilla `NyxVPNLegacyAuth` | Parece ESC1 | Enroll solo para `VPN-Cert-Enroll`, grupo vacío que nadie puede modificar |

Cada interacción con estos objetos genera eventos (4662, 4663, 4724, 4728, 4768, 4769, 4771, 4776, 4625, 5136, 5140). Los detalles, con consultas de ejemplo, están en [`DETECCION.md`](DETECCION.md).

Para desplegar el lab **sin** señuelos: `decoys_enabled: false` en `ansible/group_vars/all.yml` (o simplemente no ejecutes la fase 11).
