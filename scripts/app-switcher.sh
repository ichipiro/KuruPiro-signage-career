#!/bin/bash
set -euo pipefail

# ==============================================================================
# app-switcher.sh - アプリケーション切り替えスクリプト
# ==============================================================================
# このスクリプトは、メイン画面とスライドショー画面の Chromium ウィンドウを
# 既定では60秒ごとに切り替えるために使用されます。
# systemd timer から呼び出され、現在の状態に応じてアクティブを切り替えます。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"
load_kurupiro_env

SLIDESHOW_WINDOW_TITLE="${KURUPIRO_SLIDESHOW_WINDOW_TITLE:-くるぴろスライドショー - Chromium}"

find_visible_window_by_name() {
  local name="$1"

  xdotool search --onlyvisible --name "${name}" 2>/dev/null | head -n 1 || true
}

find_main_chromium_window() {
  local window_id
  local window_name

  while IFS= read -r window_id; do
    [ -n "${window_id}" ] || continue
    window_name="$(xdotool getwindowname "${window_id}" 2>/dev/null || true)"
    if [ -z "${window_name}" ]; then
      continue
    fi
    if [ "${window_name}" = "${SLIDESHOW_WINDOW_TITLE}" ]; then
      continue
    fi
    printf '%s\n' "${window_id}"
    return 0
  done < <(xdotool search --onlyvisible --name "Chromium" 2>/dev/null || true)
}

if ! ACTIVE_WINDOW=$(xdotool getactivewindow 2>/dev/null); then
  echo "[app-switcher] 警告: アクティブウィンドウを取得できませんでした" >&2
  exit 0
fi

SLIDESHOW_WINDOW="$(find_visible_window_by_name "${SLIDESHOW_WINDOW_TITLE}")"
MAIN_WINDOW="$(find_main_chromium_window)"

if [ -n "$SLIDESHOW_WINDOW" ] && [ "${ACTIVE_WINDOW}" = "${SLIDESHOW_WINDOW}" ]; then
  # スライドショーがアクティブならメイン画面をアクティブにする
  if [ -n "$MAIN_WINDOW" ]; then
    xdotool windowactivate --sync "$MAIN_WINDOW"
    echo "[app-switcher] メイン画面をアクティブに切り替えました"
  else
    echo "[app-switcher] 警告: メイン画面の Chromium ウィンドウが見つかりません" >&2
  fi
elif [ -n "$MAIN_WINDOW" ] && [ "${ACTIVE_WINDOW}" = "${MAIN_WINDOW}" ]; then
  # メイン画面がアクティブならスライドショーをアクティブにする
  if [ -n "$SLIDESHOW_WINDOW" ]; then
    xdotool windowactivate --sync "$SLIDESHOW_WINDOW"
    echo "[app-switcher] スライドショー画面をアクティブに切り替えました"
  else
    echo "[app-switcher] 警告: スライドショー用の Chromium ウィンドウが見つかりません" >&2
  fi
else
  echo "[app-switcher] 現在のアクティブウィンドウは切り替え対象の Chromium ウィンドウではありません。切り替えは行いません。"
fi
