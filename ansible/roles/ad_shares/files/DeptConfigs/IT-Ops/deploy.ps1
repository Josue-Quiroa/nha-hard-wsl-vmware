# Script de despliegue interno (LAB, ejemplo inofensivo).
param([string]$Env = "prod")
$share = "\\NYX-FS01\DeptConfigs"
Write-Host "Usando configuraciones de $share para entorno $Env"
# TODO(helio): la tarea nocturna sigue corriendo con mi cuenta antigua
#              (adm.old.helio). Migrar a gMSA cuando haya tiempo.
