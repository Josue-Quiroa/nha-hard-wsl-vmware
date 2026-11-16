# =============================================================================
# examples/static-ip-snippets.ps1 — Referencia (NO es parte del despliegue).
# Comandos para la post-instalación manual de cada VM (README, paso 3).
# Confirma el alias de interfaz con Get-NetAdapter (puede no ser 'Ethernet0').
#
# Si la NIC aún tiene una IP por DHCP, quítala antes de asignar la estática:
#   Get-NetIPAddress -InterfaceAlias Ethernet0 -AddressFamily IPv4 |
#     Where-Object { $_.PrefixOrigin -ne 'Manual' } |
#     Remove-NetIPAddress -Confirm:$false
#   Set-NetIPInterface -InterfaceAlias Ethernet0 -AddressFamily IPv4 -Dhcp Disabled
#
# En host-only puro no hace falta DefaultGateway. Si tu VMnet tiene gateway
# (p.ej. 192.168.56.1), añádelo a New-NetIPAddress:
#   -DefaultGateway 192.168.56.1
# =============================================================================

# --- NYX-DC01 (192.168.56.10) ---
# Rename-Computer -NewName NYX-DC01 -Restart
# New-NetIPAddress -InterfaceAlias Ethernet0 -IPAddress 192.168.56.10 -PrefixLength 24
# Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses 127.0.0.1

# --- VEL-DC01 (192.168.56.20) ---
# Rename-Computer -NewName VEL-DC01 -Restart
# New-NetIPAddress -InterfaceAlias Ethernet0 -IPAddress 192.168.56.20 -PrefixLength 24
# Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses 127.0.0.1

# --- NYX-CA01 (192.168.56.11) ---
# Rename-Computer -NewName NYX-CA01 -Restart
# New-NetIPAddress -InterfaceAlias Ethernet0 -IPAddress 192.168.56.11 -PrefixLength 24
# Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses 192.168.56.10

# --- NYX-FS01 (192.168.56.12) ---
# Rename-Computer -NewName NYX-FS01 -Restart
# New-NetIPAddress -InterfaceAlias Ethernet0 -IPAddress 192.168.56.12 -PrefixLength 24
# Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses 192.168.56.10

# --- NYX-JUMP (192.168.56.13) ---
# Rename-Computer -NewName NYX-JUMP -Restart
# New-NetIPAddress -InterfaceAlias Ethernet0 -IPAddress 192.168.56.13 -PrefixLength 24
# Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses 192.168.56.10
