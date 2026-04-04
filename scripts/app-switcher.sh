#!/bin/bash
set -euo pipefail

# ==============================================================================
# app-switcher.sh - アプリケーション切り替えスクリプト
# ==============================================================================
# このスクリプトは、キャリアルーム用アプリケーションとChromiumキオスクモードを30秒ごとに切り替えるために使用されます。
# systemd timer から呼び出され、現在の状態に応じてアクティブを切り替えます。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"
load_kurupiro_env

first_window_id() {
  local name="$1"

  xdotool search --onlyvisible --name "${name}" 2>/dev/null | head -n 1 || true
}

first_window_id_by_pid() {
  local process_name="$1"
  local pid

  pid="$(pgrep -n -x "${process_name}" 2>/dev/null || true)"
  if [ -z "${pid}" ]; then
    return 0
  fi

  xdotool search --onlyvisible --pid "${pid}" 2>/dev/null | head -n 1 || true
}

if ! ACTIVE_WINDOW=$(xdotool getactivewindow 2>/dev/null); then
  echo "[app-switcher] 警告: アクティブウィンドウを取得できませんでした" >&2
  exit 0
fi

APP_WINDOW="$(first_window_id_by_pid "ebitv")"
if [ -z "${APP_WINDOW}" ]; then
  APP_WINDOW="$(first_window_id "ebitv")"
fi

CHROME_WINDOW="$(first_window_id "Chromium")"

if [ -n "$APP_WINDOW" ] && [ "${ACTIVE_WINDOW}" = "${APP_WINDOW}" ]; then
  # アプリがアクティブならChromiumをアクティブにする
  if [ -n "$CHROME_WINDOW" ]; then
    xdotool windowactivate --sync "$CHROME_WINDOW"
    echo "[app-switcher] Chromium をアクティブに切り替えました"
  else
    echo "[app-switcher] 警告: Chromium のウィンドウが見つかりません" >&2
  fi
elif [ -n "$CHROME_WINDOW" ] && [ "${ACTIVE_WINDOW}" = "${CHROME_WINDOW}" ]; then
  # Chromiumがアクティブならアプリをアクティブにする
  if [ -n "$APP_WINDOW" ]; then
    xdotool windowactivate --sync "$APP_WINDOW"
    echo "[app-switcher] キャリアルーム用アプリケーションをアクティブに切り替えました"
  else
    echo "[app-switcher] 警告: キャリアルーム用アプリケーションのウィンドウが見つかりません" >&2
  fi
else
  echo "[app-switcher] 現在のアクティブウィンドウはキャリアルーム用アプリケーションでもChromiumでもありません。切り替えは行いません。"
fi
