<#
    Configure-WinRM.ps1
    -------------------------------------------------------------------
    Script MINIMO para preparar WinRM en cada VM Windows Server del lab.
    Ejecutar UNA sola vez, como Administrator local, antes de usar Ansible.

        Set-ExecutionPolicy Bypass -Scope Process -Force
        .\Configure-WinRM.ps1

    NOTA: Este script NO toca Windows Defender. Defender debe quedar ACTIVO.
          Solo habilita WinRM/HTTP (5985) con auth NTLM para el lab.
    -------------------------------------------------------------------
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Write-Host '[*] Habilitando PowerShell Remoting / WinRM...' -ForegroundColor Cyan
Enable-PSRemoting -Force -SkipNetworkProfileCheck

Write-Host '[*] Permitiendo WinRM sobre HTTP (solo para el lab)...' -ForegroundColor Cyan
# Ansible usa NTLM sobre HTTP (5985) en este lab. No usar en produccion.
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\Basic       -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\CredSSP      -Value $true

Write-Host '[*] Asegurando listener HTTP en 5985...' -ForegroundColor Cyan
if (-not (Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -match 'Transport=HTTP' })) {
    New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address * -Force | Out-Null
}

Write-Host '[*] Abriendo firewall para WinRM HTTP (5985)...' -ForegroundColor Cyan
Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'WinRM HTTP 5985 (Lab)' `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985 `
    -ErrorAction SilentlyContinue | Out-Null

Write-Host '[*] Reiniciando servicio WinRM...' -ForegroundColor Cyan
Restart-Service WinRM

Write-Host ''
Write-Host '[OK] WinRM listo. Prueba desde WSL:  nc -zv <IP> 5985' -ForegroundColor Green
Write-Host '[OK] Windows Defender NO fue modificado (sigue activo).' -ForegroundColor Green
