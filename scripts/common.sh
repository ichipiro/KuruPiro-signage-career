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

KURUPIRO_PI_USER="${KURUPIRO_PI_USER:-ie-career}"
KURUPIRO_PI_UID="${KURUPIRO_PI_UID:-$(id -u "${KURUPIRO_PI_USER}" 2>/dev/null || true)}"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/home/${KURUPIRO_PI_USER}/.Xauthority}"

if [ -n "${KURUPIRO_PI_UID}" ]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${KURUPIRO_PI_UID}}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
fi
