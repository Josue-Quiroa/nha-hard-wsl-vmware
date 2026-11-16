#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Despliega el laboratorio nha-hard-wsl-vmware por fases.
#
# Uso:
#   bash scripts/deploy.sh            # todas las fases, en orden
#   bash scripts/deploy.sh ping       # solo prueba de conectividad
#   bash scripts/deploy.sh 05         # solo una fase (por número)
#   bash scripts/deploy.sh 06 11      # desde la fase 06 hasta la 11
#   bash scripts/deploy.sh list       # lista las fases
#
# Variables de entorno opcionales:
#   ANSIBLE_EXTRA="-vv"               # verbosidad u opciones extra
#   VAULT=1                           # pide la contraseña de ansible-vault
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
VENV_DIR="${HOME}/.venvs/nha-lab"

# Activa el venv si existe y no está activo
if [[ -z "${VIRTUAL_ENV:-}" && -f "${VENV_DIR}/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "${VENV_DIR}/bin/activate"
fi

command -v ansible-playbook >/dev/null || {
    echo "[!] ansible-playbook no encontrado. Ejecuta primero: bash scripts/setup-wsl.sh"
    exit 1
}

cd "${ANSIBLE_DIR}"
mkdir -p logs

# Orden SEGURO de fases. No cambiar el orden: cada fase depende de la anterior.
PHASES=(
    "00:playbooks/00-ping.yml:Conectividad WinRM"
    "01:playbooks/01-baseline.yml:Baseline (Defender, Sysmon, auditoría local, carpetas)"
    "02:playbooks/02-domain-nyxcore.yml:Promoción NYX-DC01 (bosque nyxcore.lab)"
    "03:playbooks/03-domain-veloran.yml:Promoción VEL-DC01 (bosque veloran.corp)"
    "04:playbooks/04-trust.yml:DNS condicional + trust bidireccional"
    "05:playbooks/05-domain-join.yml:Unir CA01, FS01 y JUMP a nyxcore.lab"
    "06:playbooks/06-adcs.yml:ADCS (Enterprise CA) en NYX-CA01"
    "07:playbooks/07-ad-objects.yml:OUs, usuarios, grupos, SPNs"
    "08:playbooks/08-gpo-audit-kerberos.yml:GPO de auditoría + ajustes Kerberos"
    "09:playbooks/09-shares.yml:Share DeptConfigs en NYX-FS01"
    "10:playbooks/10-acls-flags.yml:ACLs intencionales + flags + jump limitado"
    "11:playbooks/11-decoys.yml:Señuelos (honeypots) y caminos falsos"
)

EXTRA_ARGS=()
[[ -n "${ANSIBLE_EXTRA:-}" ]] && read -r -a EXTRA_ARGS <<< "${ANSIBLE_EXTRA}"
[[ "${VAULT:-0}" == "1" ]] && EXTRA_ARGS+=("--ask-vault-pass")

LOG="logs/deploy-$(date +%Y%m%d-%H%M%S).log"

run_phase() {
    local id="$1" pb="$2" desc="$3"
    echo
    echo "=================================================================="
    echo " FASE ${id}: ${desc}"
    echo " Playbook: ${pb}"
    echo "=================================================================="
    # pipefail + tee: si el playbook falla, el script se detiene (fail fast)
    ansible-playbook -i inventory.ini "${pb}" "${EXTRA_ARGS[@]}" 2>&1 | tee -a "${LOG}"
}

list_phases() {
    for p in "${PHASES[@]}"; do
        IFS=':' read -r id pb desc <<< "${p}"
        printf "  %s  %-40s %s\n" "${id}" "${pb}" "${desc}"
    done
}

FROM="${1:-00}"
TO="${2:-${1:-11}}"

case "${FROM}" in
    list|-l|--list) list_phases; exit 0 ;;
    ping)           FROM="00"; TO="00" ;;
    all|"")         FROM="00"; TO="11" ;;
esac
# Sin argumentos: todas las fases
[[ $# -eq 0 ]] && { FROM="00"; TO="11"; }

echo "[*] Log: ansible/${LOG}"
for p in "${PHASES[@]}"; do
    IFS=':' read -r id pb desc <<< "${p}"
    if ((10#${id} >= 10#${FROM} && 10#${id} <= 10#${TO})); then
        run_phase "${id}" "${pb}" "${desc}"
    fi
done

echo
echo "[OK] Fases ${FROM}..${TO} completadas. Revisa docs/ATTACK-PATHS.md para empezar."
