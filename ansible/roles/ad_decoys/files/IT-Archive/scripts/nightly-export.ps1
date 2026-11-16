# ==========================================================================
#  nightly-export.ps1 - Export nocturno hacia VELORAN (2020). LAB: FICTICIO
#  Ya no esta programado (tarea deshabilitada tras la fusion).
# ==========================================================================
$user = 'VELORAN\vel.svc_deploy'
$pass = ConvertTo-SecureString 'D3ploy!Vel2020' -AsPlainText -Force   # TODO: mover a boveda
$cred = New-Object System.Management.Automation.PSCredential($user, $pass)

$src = '\\NYX-FS01\DeptConfigs\Finance'
$dst = '\\vel-deploy.veloran.corp\drop$\nyxcore'

# New-PSDrive -Name DROP -PSProvider FileSystem -Root $dst -Credential $cred
# Copy-Item "$src\*" DROP:\ -Recurse -Force
Write-Output "Export deshabilitado ($(Get-Date -Format s))"
