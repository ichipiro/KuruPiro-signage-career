#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

load_kurupiro_env() {
  local env_file="${BASE_DIR}/.env"

  if [ -f "${env_file}" ]; then
    set -a
    # shellcheck disable=SC1090
    . "${env_file}"
    set +a
  fi
}

export DISPLAY="${DISPLAY:-:0}"
KURUPIRO_PI_USER="${KURUPIRO_PI_USER:-ie-career}"
export XAUTHORITY="${XAUTHORITY:-/home/${KURUPIRO_PI_USER}/.Xauthority}"
