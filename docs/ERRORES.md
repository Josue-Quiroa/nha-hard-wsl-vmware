# Problemas comunes y soluciones

Guía rápida de los errores más habituales al montar el lab. Están ordenados por la fase en la que suelen aparecer.

> Ejecuta los comandos de Ansible desde `ansible/` (ahí está `ansible.cfg`). Para más detalle añade `-vvv` o usa `ANSIBLE_EXTRA="-vvv" bash scripts/deploy.sh 05`.

---

## 1. WinRM

### `nc -zv 192.168.56.X 5985` no conecta
- ¿Ejecutaste `Configure-WinRM.ps1` **como Administrator**? Compruébalo en la VM:
  ```powershell
  winrm enumerate winrm/config/listener
  Get-NetFirewallRule -DisplayName 'WinRM HTTP 5985 (Lab)'
  ```
- El perfil de red es **Public** y el firewall bloquea: el script usa `-SkipNetworkProfileCheck`, pero puedes forzar Private:
  ```powershell
  Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
  ```
- La VM no tiene la IP que crees: `ipconfig` en la VM.

### `ntlm: the specified credentials were rejected by the server` / 401
- La contraseña de `Administrator` de la VM no coincide con `lab_admin_password` en `ansible/group_vars/all.yml`.
- Tras promover un DC, `Administrator` pasa a ser `NYXCORE\Administrator` / `VELORAN\Administrator` con la **misma** contraseña. Si la cambiaste a mano, actualiza `all.yml`.
- Si usas otra cuenta local que no es la `Administrator` integrada, UAC filtra el token remoto. Usa `Administrator` o, solo en lab:
  ```powershell
  Set-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System LocalAccountTokenFilterPolicy 1
  ```

### `TrustedHosts` (solo si pruebas WinRM desde PowerShell en Windows, no desde WSL)
```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value '192.168.56.*' -Force
Test-WSMan 192.168.56.10
```
Ansible/pywinrm desde WSL **no** usa TrustedHosts.

### `Operation timed out` durante promoción o ADCS
Es normal que algunas tareas tarden. Los timeouts de WinRM están en `ansible/inventory.ini` (`ansible_winrm_operation_timeout_sec` / `ansible_winrm_read_timeout_sec`). Si persiste, vuelve a ejecutar la misma fase: los roles son idempotentes.

---

## 2. Red y DNS

### WSL2 no llega a la red host-only de VMware
- Desde Windows (no WSL): `ping 192.168.56.10`. Si Windows tampoco llega, el problema es VMware (VMnet, IP de la VM).
- WSL2 en modo NAT normalmente enruta a través del host. Si no, en Windows 11 crea `%UserProfile%\.wslconfig`:
  ```ini
  [wsl2]
  networkingMode=mirrored
  ```
  y ejecuta `wsl --shutdown`.
- **Conflicto con VirtualBox**: su host-only por defecto también usa `192.168.56.0/24`. Desactiva ese adaptador o cambia la subred del lab (inventario + `all.yml`).
- Firewall del host Windows bloqueando el adaptador VMnet: prueba temporalmente con la regla de entrada/salida para VMnet1.

### `Resolve-DnsName nyxcore.lab` falla en los miembros
- El DNS de `NYX-CA01`, `NYX-FS01` y `NYX-JUMP` debe ser `192.168.56.10`. La fase 05 lo fija, pero si la VM tiene varias NICs (NAT + host-only), revisa el orden y quita DNS de la NIC NAT:
  ```powershell
  Get-DnsClientServerAddress
  Set-DnsClientServerAddress -InterfaceAlias 'Ethernet1' -ResetServerAddresses
  ```

### El DC no se resuelve a sí mismo tras la promoción
```powershell
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet0' -ServerAddresses 127.0.0.1
ipconfig /registerdns ; Restart-Service netlogon
dcdiag /test:dns
```

---

## 3. Ansible

### `No module named 'winrm'` / `requests_ntlm`
El venv no está activo. `source ~/.venvs/nha-lab/bin/activate` o vuelve a ejecutar `bash scripts/setup-wsl.sh`.

### `couldn't resolve module/action 'microsoft.ad.membership'`
Faltan colecciones:
```bash
ansible-galaxy collection install -r ansible/requirements.yml --upgrade
ansible-galaxy collection list | grep -E 'ansible.windows|community.windows|microsoft.ad'
```

### `[WARNING]: Ansible is being run in a world writable directory`
Pasa si el repo está en `/mnt/c/...`. Ansible **ignora `ansible.cfg`**. Copia el repo al home de WSL:
```bash
cp -r /mnt/c/Users/<tu>/nha-hard-wsl-vmware ~/ && cd ~/nha-hard-wsl-vmware
```

### Problema de doble salto (double-hop) con NTLM
Con NTLM sobre WinRM, la sesión remota **no puede autenticarse contra un tercer equipo** (p.ej. el CA hablando con el DC). Síntomas: `Access denied`, `Unable to contact the server`, `The server has rejected the client credentials`.
- Los roles que lo necesitan (`ad_trust`, `ad_adcs`, `ad_acls_flags`, fase 08) usan `become: true` + `become_method: runas` con el administrador del dominio, que crea un token local completo.
- Si añades tareas propias que hablen con otro servidor, haz lo mismo, o usa CredSSP (`ansible_winrm_transport=credssp`, ya permitido por `Configure-WinRM.ps1`).

### Se pierde la conexión durante un reinicio
`win_reboot` y `microsoft.ad.membership (reboot: true)` lo gestionan. Si cortaste la ejecución a mitad, espera a que la VM arranque y relanza la fase.

---

## 4. Windows Defender

> El lab exige Defender **activo**. No lo desactives para "arreglar" un error.

### Defender en cuarentena con archivos del share o scripts
Los archivos de ejemplo son texto inocuo. Si aun así hay detecciones, revisa:
```powershell
Get-MpThreatDetection | Select-Object -First 5
Get-MpThreat
```
y restaura con `Remove-MpThreat` o añade una **exclusión puntual de ruta** (no desactives la protección).

### Herramientas de auditoría bloqueadas en `NYX-JUMP`
Es **intencional**: practica con herramientas nativas o ejecuta tus herramientas desde tu máquina de ataque/WSL contra los servicios de red.

### `win_defender_check` informa `RealTime=false`
Puede pasar en Server Core o si una GPO lo apagó. Revisa `Get-MpPreference | Select DisableRealtimeMonitoring` y la GPO aplicada (`gpresult /h C:\Lab\gp.html`). Puedes hacer que la fase falle activando `defender_fail_if_disabled: true`.

---

## 5. Sysmon

### La descarga falla (`win_get_url`)
Las VMs host-only no tienen Internet. Opciones:
1. Añade temporalmente una NIC NAT a la VM durante la fase 01.
2. Descarga `Sysmon.zip` en Windows, extrae `Sysmon64.exe` a `ansible/roles/win_sysmon/files/` y pon `sysmon_local_binary: true` en `all.yml`.

### `Incorrect or unsupported configuration schema version`
Tu Sysmon es antiguo. La config usa `schemaversion="4.50"` (Sysmon 13+). Actualiza Sysmon o baja el `schemaversion` y elimina `ProcessTampering`.

### `Sysmon64` no aparece como servicio
En sistemas de 32 bits el servicio se llama `Sysmon`. Ajusta `sysmon_service_name`. Comprueba:
```powershell
Get-Service Sysmon*
Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 5
```

### Cambié `sysmonconfig.xml` y no se aplica
Vuelve a ejecutar la fase 01: el handler ejecuta `Sysmon64.exe -c <config>`.

---

## 6. Kerberos y hora (clock skew)

Kerberos tolera **5 minutos** de diferencia. Síntomas: `KRB_AP_ERR_SKEW`, fallos al unir al dominio, trust que no valida.
```powershell
w32tm /query /status
w32tm /resync /force
```
- En `NYX-DC01` (PDC) configura una fuente fiable o, en lab aislado, el reloj local:
  ```powershell
  w32tm /config /syncfromflags:manual /manualpeerlist:"time.windows.com" /reliable:yes /update
  ```
- **VMware Tools** puede pelearse con w32time. En los miembros deja que sincronicen con el DC y desactiva *Synchronize guest time with host* en la VM.
- Si suspendes las VMs (snapshot/suspend), al reanudar ejecuta `w32tm /resync` en todas.

---

## 7. Trust entre bosques

### `The specified domain either does not exist or could not be contacted`
Falta DNS condicional. Verifica en cada DC:
```powershell
Get-DnsServerZone | Where-Object ZoneType -eq 'Forwarder'
Resolve-DnsName _ldap._tcp.dc._msdcs.veloran.corp -Type SRV   # en NYX-DC01
Resolve-DnsName _ldap._tcp.dc._msdcs.nyxcore.lab -Type SRV    # en VEL-DC01
```
Si no existe:
```powershell
Add-DnsServerConditionalForwarderZone -Name veloran.corp -MasterServers 192.168.56.20 -ReplicationScope Forest
```

### Validar el trust
```powershell
Get-ADTrust -Filter *
netdom trust nyxcore.lab /domain:veloran.corp /verify /twoway /UserD:VELORAN\Administrator /PasswordD:*
```
Puertos necesarios entre DCs: 53, 88, 135, 389, 445, 464, 3268 y RPC dinámico (49152-65535).

---

## 8. Unión al dominio y ADCS

### `microsoft.ad.membership` falla con `The network path was not found`
DNS (ver sección 2) o el DC aún no ha terminado de arrancar. Espera 2-3 minutos y relanza la fase 05.

### `Add-CATemplate: The requested template was not found`
La plantilla tarda en replicarse/verse. El rol reintenta 10 veces; si aun así falla:
```powershell
Restart-Service certsvc
certutil -SetCATemplates +NyxLegacyUserAuth
```

### Web Enrollment no responde
```powershell
Get-WebApplication -Site 'Default Web Site' -Name CertSrv
iisreset
```

---

## 9. GPO y auditoría

```powershell
gpupdate /force
gpresult /r /scope computer
auditpol /get /category:*
```
Si la auditoría avanzada no se aplica, comprueba que `audit.csv` existe en `C:\Windows\SYSVOL\domain\Policies\{GUID}\Machine\Microsoft\Windows NT\Audit\` y que la GPO `LAB - Advanced Audit Policy` está enlazada a la raíz del dominio.

---

## 10. Señuelos (fase 11)

### `Get-Acl -Audit` / `Set-Acl` falla con *privilegio no disponible*
Las SACL requieren `SeSecurityPrivilege`. Ansible conecta como `Administrator`, que lo tiene; si usas otra cuenta, añádela a *Manage auditing and security log* o pon `decoy_ad_sacl: false`.

### Defender pone en cuarentena `Groups.xml` o `nightly-export.ps1`
Son archivos de texto inofensivos, pero algunas firmas detectan `cpassword` o credenciales en claro. Revisa `Get-MpThreatDetection`; **no desactives Defender**: restaura el archivo o añade una exclusión de ruta solo para `C:\Shares\IT-Archive` si lo necesitas.

### La plantilla `NyxVPNLegacyAuth` falla con *debe estar VACÍO*
La fase 11 se niega a dejar Enroll a `VPN-Cert-Enroll` si el grupo tiene miembros (la plantilla dejaría de ser un señuelo y abriría un ESC1 real). Vacía el grupo y vuelve a ejecutar `bash scripts/deploy.sh 11`.

### Quiero cambiar la password de un señuelo
No hace falta: es aleatoria y se fija solo al crear la cuenta. Si borras la cuenta y relanzas la fase 11, se genera otra distinta.
