#!/usr/bin/env bash
# =============================================================================
# setup-wsl.sh — Prepara WSL2 (Ubuntu) como nodo de control de Ansible.
#
# Uso:   bash scripts/setup-wsl.sh
# Idempotente: se puede ejecutar varias veces sin romper nada.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
VENV_DIR="${HOME}/.venvs/nha-lab"

info()  { echo -e "\e[36m[*]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[33m[!]\e[0m $*"; }

if ! grep -qi microsoft /proc/version 2>/dev/null; then
    warn "No parece WSL. Continúo igualmente (funciona en cualquier Linux con apt)."
fi

# -----------------------------------------------------------------------------
# 1. Paquetes del sistema
# -----------------------------------------------------------------------------
info "Actualizando apt e instalando dependencias base..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo -E apt-get install -y \
    python3 python3-pip python3-venv \
    git curl unzip netcat-openbsd

# -----------------------------------------------------------------------------
# 2. Entorno virtual con Ansible + pywinrm
#    (evita conflictos con el Python del sistema / PEP 668)
# -----------------------------------------------------------------------------
if [[ ! -d "${VENV_DIR}" ]]; then
    info "Creando venv en ${VENV_DIR}..."
    python3 -m venv "${VENV_DIR}"
fi
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

info "Instalando Ansible, pywinrm y extras..."
pip install --upgrade pip wheel
pip install --upgrade "ansible-core>=2.14" "pywinrm>=0.4.3" "pywinrm[credssp]" requests-ntlm

# -----------------------------------------------------------------------------
# 3. Colecciones de Ansible
# -----------------------------------------------------------------------------
info "Instalando colecciones de Ansible Galaxy..."
if [[ -f "${ANSIBLE_DIR}/requirements.yml" ]]; then
    ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml" --upgrade
else
    ansible-galaxy collection install ansible.windows community.windows microsoft.ad --upgrade
fi

# -----------------------------------------------------------------------------
# 4. Directorios auxiliares
# -----------------------------------------------------------------------------
mkdir -p "${ANSIBLE_DIR}/logs" "${ANSIBLE_DIR}/roles/win_sysmon/files"

# -----------------------------------------------------------------------------
# 5. Activación automática del venv (opcional, una sola vez)
# -----------------------------------------------------------------------------
if ! grep -q "nha-lab venv" "${HOME}/.bashrc" 2>/dev/null; then
    {
        echo ""
        echo "# nha-lab venv (añadido por setup-wsl.sh)"
        echo "[ -f \"${VENV_DIR}/bin/activate\" ] && source \"${VENV_DIR}/bin/activate\""
    } >> "${HOME}/.bashrc"
    ok "Activación del venv añadida a ~/.bashrc"
fi

# -----------------------------------------------------------------------------
# 6. Resumen
# -----------------------------------------------------------------------------
echo
ok "Ansible: $(ansible --version | head -n1)"
ok "Colecciones instaladas:"
ansible-galaxy collection list 2>/dev/null | grep -E "ansible.windows|community.windows|microsoft.ad" || true
echo
info "Siguiente paso:"
echo "    source ${VENV_DIR}/bin/activate"
echo "    nano ansible/inventory.ini ansible/group_vars/all.yml"
echo "    bash scripts/deploy.sh ping"
