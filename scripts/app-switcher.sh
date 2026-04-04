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
MAIN_SCREEN_DURATION="${KURUPIRO_APP_SWITCH_INTERVAL:-60s}"
SLIDESHOW_IMAGE_DURATION_SECONDS="${KURUPIRO_SLIDESHOW_IMAGE_DURATION_SECONDS:-10}"
STATE_FILE="${KURUPIRO_APP_SWITCH_STATE_FILE:-/tmp/kurupiro-app-switcher-state}"
MANIFEST_PATH="${BASE_DIR}/www/drive-images/index.json"

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

duration_to_seconds() {
  python3 - "$1" <<'PY'
import re
import sys

value = sys.argv[1].strip().lower()
match = re.fullmatch(r"(\d+)(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours)?", value)
if not match:
    print(60)
    raise SystemExit(0)

amount = int(match.group(1))
unit = match.group(2) or "s"
if unit.startswith("h"):
    print(amount * 3600)
elif unit.startswith("m"):
    print(amount * 60)
else:
    print(amount)
PY
}

manifest_image_count() {
  python3 - "${MANIFEST_PATH}" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    images = data.get("images", [])
    print(len(images) if isinstance(images, list) else 0)
except Exception:
    print(0)
PY
}

read_state() {
  if [ -f "${STATE_FILE}" ]; then
    IFS='|' read -r STATE_MODE STATE_SINCE < "${STATE_FILE}" || true
  fi
}

write_state() {
  local mode="$1"
  local since="$2"
  printf '%s|%s\n' "${mode}" "${since}" > "${STATE_FILE}"
}

MAIN_SCREEN_DURATION_SECONDS="$(duration_to_seconds "${MAIN_SCREEN_DURATION}")"
IMAGE_COUNT="$(manifest_image_count)"
SLIDESHOW_CYCLE_DURATION_SECONDS=$((IMAGE_COUNT * SLIDESHOW_IMAGE_DURATION_SECONDS))
NOW="$(date +%s)"

STATE_MODE=""
STATE_SINCE=""
read_state

if ! ACTIVE_WINDOW=$(xdotool getactivewindow 2>/dev/null); then
  echo "[app-switcher] 警告: アクティブウィンドウを取得できませんでした" >&2
  exit 0
fi

SLIDESHOW_WINDOW="$(find_visible_window_by_name "${SLIDESHOW_WINDOW_TITLE}")"
MAIN_WINDOW="$(find_main_chromium_window)"

if [ -n "${MAIN_WINDOW}" ] && [ "${ACTIVE_WINDOW}" = "${MAIN_WINDOW}" ]; then
  if [ "${STATE_MODE}" != "main" ]; then
    write_state "main" "${NOW}"
    STATE_MODE="main"
    STATE_SINCE="${NOW}"
  fi
elif [ -n "${SLIDESHOW_WINDOW}" ] && [ "${ACTIVE_WINDOW}" = "${SLIDESHOW_WINDOW}" ]; then
  if [ "${STATE_MODE}" != "slideshow" ]; then
    write_state "slideshow" "${NOW}"
    STATE_MODE="slideshow"
    STATE_SINCE="${NOW}"
  fi
fi

if [ -z "${STATE_SINCE}" ]; then
  STATE_SINCE="${NOW}"
fi

ELAPSED_SECONDS=$((NOW - STATE_SINCE))

if [ -n "$SLIDESHOW_WINDOW" ] && [ "${ACTIVE_WINDOW}" = "${SLIDESHOW_WINDOW}" ]; then
  # スライドショーが1周したらメイン画面へ戻す
  if [ "${IMAGE_COUNT}" -le 0 ] && [ -n "${MAIN_WINDOW}" ]; then
    xdotool windowactivate --sync "$MAIN_WINDOW"
    write_state "main" "${NOW}"
    echo "[app-switcher] スライドショー画像が無いためメイン画面へ戻しました"
  elif [ "${SLIDESHOW_CYCLE_DURATION_SECONDS}" -gt 0 ] && [ "${ELAPSED_SECONDS}" -ge "${SLIDESHOW_CYCLE_DURATION_SECONDS}" ] && [ -n "${MAIN_WINDOW}" ]; then
    xdotool windowactivate --sync "$MAIN_WINDOW"
    write_state "main" "${NOW}"
    echo "[app-switcher] スライドショーを1周したためメイン画面に切り替えました"
  else
    echo "[app-switcher] スライドショー継続中 (${ELAPSED_SECONDS}s / ${SLIDESHOW_CYCLE_DURATION_SECONDS}s)"
  fi
elif [ -n "$MAIN_WINDOW" ] && [ "${ACTIVE_WINDOW}" = "${MAIN_WINDOW}" ]; then
  # メイン画面は一定時間表示したらスライドショーへ切り替える
  if [ "${IMAGE_COUNT}" -le 0 ]; then
    echo "[app-switcher] スライドショー画像が無いためメイン画面を継続します"
  elif [ "${ELAPSED_SECONDS}" -ge "${MAIN_SCREEN_DURATION_SECONDS}" ] && [ -n "${SLIDESHOW_WINDOW}" ]; then
    xdotool windowactivate --sync "$SLIDESHOW_WINDOW"
    write_state "slideshow" "${NOW}"
    echo "[app-switcher] メイン画面の表示時間が経過したためスライドショー画面に切り替えました"
  else
    echo "[app-switcher] メイン画面継続中 (${ELAPSED_SECONDS}s / ${MAIN_SCREEN_DURATION_SECONDS}s)"
  fi
else
  echo "[app-switcher] 現在のアクティブウィンドウは切り替え対象の Chromium ウィンドウではありません。切り替えは行いません。"
fi
