# Detección de señuelos (honeypots) y caminos falsos

> **SPOILER — solo para el autor/instructor del lab.** Este documento explica qué objetos son señuelos y cómo detectar que alguien los ha tocado. No lo compartas con quien vaya a practicar el lado ofensivo.

Los señuelos se despliegan en la **fase 11** (`ansible/playbooks/11-decoys.yml`, rol `ad_decoys`). No dan ningún privilegio real: su utilidad es hacer perder tiempo a quien ataca y, sobre todo, **generar alertas de alta confianza**. Nadie legítimo usa estas cuentas, así que cualquier evento con ellas es sospechoso.

## Inventario de señuelos

| Objeto | Dominio | Tipo | Cebo | Por qué es un callejón sin salida |
|---|---|---|---|---|
| `svc_sql_old` | nyxcore.lab | Usuario | SPN `MSSQLSvc/nyx-sql01...`, solo RC4, grupo `SQL-Admins-Legacy` | Password aleatoria de 40 caracteres; el host `NYX-SQL01` no existe |
| `adm.backup` | nyxcore.lab | Usuario | `adminCount=1`, OU `LegacyAdmins`, password "filtrada" en 3 sitios | Las 3 passwords filtradas son **falsas**; la real es aleatoria. Sin privilegios |
| `ext.auditor2019` | nyxcore.lab | Usuario | AS-REP roastable (sin preauth) | Hash irrompible. Helpdesk puede resetearla, pero no tiene ningún acceso |
| `vel.svc_deploy` | veloran.corp | Usuario | SPN, `adminCount=1`, grupo `Tier0-Ops-Legacy` | Password aleatoria; la del script es falsa; el grupo no tiene derechos |
| `SQL-Admins-Legacy`, `Backup-Admins-Legacy`, `SrvOps-Legacy` | nyxcore.lab | Grupos | Nombres "administrativos" | No son admins de ninguna máquina ni tienen ACEs útiles |
| `Tier0-Ops-Legacy` | veloran.corp | Grupo | "Tier 0" | Sin membresía en grupos privilegiados ni ACEs |
| `VPN-Cert-Enroll` | nyxcore.lab | Grupo | Único con Enroll en `NyxVPNLegacyAuth` | Vacío y nadie del lab puede añadirse |
| `NyxVPNLegacyAuth` | nyxcore.lab (CA) | Plantilla ADCS | Parece ESC1 (subject del solicitante + Client Auth) | Nadie alcanzable puede inscribirse |
| `Helpdesk-T1 → GenericAll → SrvOps-Legacy → GenericWrite → adm.backup` | nyxcore.lab | ACLs | Ruta que BloodHound mostrará desde el usuario inicial | Termina en una cuenta sin privilegios |
| `\\NYX-FS01\DeptConfigs\Archive\` | NYX-FS01 | Carpeta | Runbook y `.config` con credenciales | Credenciales incorrectas y hosts inexistentes |
| `\\NYX-FS01\IT-Archive$` | NYX-FS01 | Share oculto | `Groups.xml` con `cpassword` (GPP), scripts viejos | El `cpassword` descifra a una password **falsa** de `adm.backup` |

## Qué eventos genera cada señuelo

La auditoría ya viene configurada (GPO `LAB - Advanced Audit Policy` + `auditpol` local). La fase 11 añade además:
- **SACL "honeytoken"** (Everyone / ReadProperty / Success) en los usuarios y grupos señuelo → evento **4662** en el DC cada vez que alguien lee el objeto (p. ej. una enumeración LDAP tipo BloodHound).
- **SACL "honeyfile"** (Everyone / ReadData / Success) en `DeptConfigs\Archive` e `IT-Archive$` → evento **4663** en `NYX-FS01`.
- Subcategoría **File System (Success)** activada (solo registra objetos con SACL, así que el ruido es mínimo).

| Acción del atacante | Dónde mirar | Evento | Campo clave |
|---|---|---|---|
| Kerberoasting de `svc_sql_old` / `vel.svc_deploy` | DC del dominio | **4769** | `Service Name` = cuenta señuelo; `Ticket Encryption Type` = `0x17` (RC4) |
| AS-REP roasting de `ext.auditor2019` | NYX-DC01 | **4768** | `Account Name` = `ext.auditor2019`, `Pre-Authentication Type` = `0` |
| Probar la password filtrada (Kerberos) | DC | **4771** | `Failure Code` = `0x18` (password incorrecta) |
| Probar la password filtrada (NTLM / SMB / RDP) | DC y host destino | **4776**, **4625** | `Status` = `0xC000006A` |
| Spraying sobre las cuentas señuelo | DC | 4771 / 4625 en ráfaga | Varias cuentas, misma IP de origen |
| Leer los objetos señuelo por LDAP | DC | **4662** | `Object Name` = DN del señuelo |
| Resetear `ext.auditor2019` (Helpdesk) | NYX-DC01 | **4724** | `Target Account` = `ext.auditor2019` |
| Añadirse a `SrvOps-Legacy` (ACL falsa) | NYX-DC01 | **4728**, **5136** | Grupo `SrvOps-Legacy` |
| Escribir atributos de `adm.backup` (SPN, `msDS-KeyCredentialLink`) | NYX-DC01 | **5136** | `Object DN` = `adm.backup` |
| Abrir `IT-Archive$` | NYX-FS01 | **5140** | `Share Name` = `\\*\IT-Archive$` |
| Leer los ficheros señuelo | NYX-FS01 | **4663** (y **5145** si falla el acceso) | `Object Name` bajo `C:\Shares\IT-Archive` o `DeptConfigs\Archive` |
| Pedir certificado de `NyxVPNLegacyAuth` | NYX-CA01 | **4888** / **4887** | `Template` = `NyxVPNLegacyAuth` (siempre denegado) |
| Herramientas lanzadas en el jump | NYX-JUMP | Sysmon **1**, **3**; 4688; transcripciones | Línea de comandos con nombres de señuelo |

> Sysmon: en `NYX-JUMP` revisa **EID 1** (procesos con `svc_sql_old`, `adm.backup`, `IT-Archive$`... en la línea de comandos) y **EID 3** (conexiones a 88/389/445 hacia los DCs y `NYX-FS01`). En `NYX-FS01`, **EID 11** no aplica (solo lecturas), por eso se usa la SACL.

## Consultas de ejemplo (solo lectura)

En el DC correspondiente, como administrador:

```powershell
# Cuentas señuelo de nyxcore.lab (en VEL-DC01 usa: 'vel.svc_deploy')
$decoys = 'svc_sql_old','adm.backup','ext.auditor2019'

# Kerberos (4768 TGT, 4769 TGS, 4771 preauth fallida) y NTLM (4776) / logon fallido (4625)
Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4768,4769,4771,4776,4625; StartTime=(Get-Date).AddDays(-1) } |
  Where-Object {
    $xml = [xml]$_.ToXml()
    $vals = $xml.Event.EventData.Data | Where-Object { $_.Name -in 'TargetUserName','ServiceName' } | ForEach-Object { $_.'#text' }
    foreach ($d in $decoys) { if ($vals -match [regex]::Escape($d)) { return $true } }
    $false
  } |
  Select-Object TimeCreated, Id, @{n='Detalle';e={ ($_.Message -split "`n")[0] }} |
  Format-Table -AutoSize

# Lecturas de objetos señuelo (SACL honeytoken)
Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4662; StartTime=(Get-Date).AddHours(-4) } |
  Where-Object { $_.Message -match 'svc_sql_old|adm\.backup|ext\.auditor2019|Legacy|VPN-Cert-Enroll' } |
  Select-Object TimeCreated, @{n='Quien';e={ $_.Properties[1].Value }} -First 20
```

En `NYX-FS01`:

```powershell
# Accesos al share y a los ficheros señuelo
Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=5140,4663 } -MaxEvents 500 |
  Where-Object { $_.Message -match 'IT-Archive|DeptConfigs\\Archive' } |
  Select-Object TimeCreated, Id, @{n='Cuenta';e={ $_.Properties[1].Value }} | Format-Table -AutoSize
```

> 4662 en un DC puede ser ruidoso si alguien enumera todo el directorio: es justo lo que quieres ver. Si la SACL te molesta, pon `decoy_ad_sacl: false` en `group_vars/all.yml` antes de la fase 11.

## Ejercicio de detección sugerido

1. Despliega el lab completo (fases 00–11).
2. Desde `NYX-JUMP` como `j.cortez`, enumera el dominio y prueba los "hallazgos" del `Archive`.
3. En los DCs y en `NYX-FS01`, reconstruye la línea temporal **solo con eventos**: qué cuenta se usó, desde qué IP, qué señuelos se tocaron y en qué orden.
4. Escribe una regla (Sigma, KQL o un simple script programado) que alerte ante **cualquier** evento 4768/4769/4771/4625 con una cuenta señuelo.
