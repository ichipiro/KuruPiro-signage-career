#!/bin/bash
set -euo pipefail

# ==============================================================================
# start.sh - 毎回起動時に実行するスクリプト
# ==============================================================================
# このスクリプトは Raspberry Pi の起動時に毎回実行され、以下を行います:
#   1. git pull で最新のコードを取得
#   1.1. Google Drive 画像同期
#   2. nginx の起動確認
#   3. Chromium で controller.html を起動
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

load_kurupiro_env

# リポジトリURL
REPO_URL="https://github.com/ichipiro/KuruPiro-signage-career.git"

# 設定値（デフォルト）
KIOSK_URL="${KURUPIRO_KIOSK_URL:-http://localhost/}"
CONTROLLER_URL="${KURUPIRO_CONTROLLER_URL:-http://localhost/controller.html}"
CHROMIUM_BIN="${KURUPIRO_CHROMIUM_BIN:-chromium}"
CHROMIUM_PROFILE_BASE="${KURUPIRO_CHROMIUM_PROFILE_BASE:-/home/${KURUPIRO_PI_USER}/.config/kurupiro}"
DISPLAY_OUTPUT="${KURUPIRO_DISPLAY_OUTPUT:-HDMI-1}"
DISPLAY_MODE="${KURUPIRO_DISPLAY_MODE:-1920x1080}"
DISPLAY_RATE="${KURUPIRO_DISPLAY_RATE:-60}"
DISPLAY_ROTATION="${KURUPIRO_DISPLAY_ROTATION:-right}"
MAIN_SCREEN_DURATION_SECONDS="$(python3 - "${KURUPIRO_APP_SWITCH_INTERVAL:-60s}" <<'PY'
import re
import sys
value = sys.argv[1].strip().lower()
match = re.fullmatch(r"(\d+)(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours)?", value)
if not match:
    print(60000)
    raise SystemExit(0)
amount = int(match.group(1))
unit = match.group(2) or "s"
if unit.startswith("h"):
    print(amount * 3600 * 1000)
elif unit.startswith("m"):
    print(amount * 60 * 1000)
else:
    print(amount * 1000)
PY
)"
IMAGE_DURATION_MS="$(python3 - "${KURUPIRO_AD_IMAGE_DURATION:-10s}" <<'PY'
import re
import sys
value = sys.argv[1].strip().lower()
match = re.fullmatch(r"(\d+)(s|sec|secs|second|seconds|m|min|mins|minute|minutes)", value)
if not match:
    print(10000)
    raise SystemExit(0)
amount = int(match.group(1))
unit = match.group(2) or "s"
if unit.startswith("m"):
    print(amount * 60 * 1000)
else:
    print(amount * 1000)
PY
)"

echo "===== くるぴろ起動スクリプト開始 ====="

# ------------------------------------------------------------------------------
# 1. git fetch & reset（最新コード取得、ローカル変更は破棄）
# ------------------------------------------------------------------------------
echo "[1/3] git fetch & reset 実行中..."
cd "${BASE_DIR}" || exit 1

# ネットワークエラーでも継続するため set +e
set +e

# リモートが未設定なら設定
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "${REPO_URL}"
fi

# ローカル変更を破棄してリモートに強制同期
if git fetch origin && git reset --hard origin/main; then
  echo "[kurupiro] git fetch & reset 成功"
else
  echo "[kurupiro] git fetch に失敗しました。前回バージョンのまま続行します。" >&2
fi

# Gitコミットハッシュをoffline.htmlに埋め込み
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
OFFLINE_HTML="${BASE_DIR}/www/offline.html"
if [ -f "$OFFLINE_HTML" ]; then
  # 毎回プレースホルダーを更新（既に置換済みでも新しいハッシュに更新）
  sed -i "s/<!--GIT_COMMIT_HASH-->/${COMMIT_HASH}/g" "$OFFLINE_HTML"
  sed -i "s/[a-f0-9]\{7\}\(-dirty\)\?/${COMMIT_HASH}/g" "$OFFLINE_HTML" 2>/dev/null || true
  echo "[kurupiro] コミットハッシュ: ${COMMIT_HASH}"
fi

# Google Drive 画像同期
if [ -x "${SCRIPT_DIR}/sync-drive-images.sh" ]; then
  echo "[1.0/3] Google Drive 画像同期..."
  if "${SCRIPT_DIR}/sync-drive-images.sh"; then
    echo "[drive-sync] 起動時同期 完了"
  else
    echo "[drive-sync] 警告: 起動時同期に失敗しました" >&2
  fi
fi

# ------------------------------------------------------------------------------
# 2. nginx 起動確認（失敗してもChromium起動は続行）
# ------------------------------------------------------------------------------
echo "[2/3] nginx 起動確認..."

# nginx起動を待つ（ネットワーク不要、ローカルサーバーなので）
NGINX_MAX_RETRY=10
NGINX_RETRY=0
NGINX_SUCCESS=false

while [ $NGINX_RETRY -lt $NGINX_MAX_RETRY ]; do
  NGINX_RETRY=$((NGINX_RETRY + 1))
  
  if systemctl is-active --quiet nginx; then
    echo "[kurupiro] nginx は起動しています"
    NGINX_SUCCESS=true
    break
  fi
  
  echo "[kurupiro] nginx 起動試行 (${NGINX_RETRY}/${NGINX_MAX_RETRY})..."
  sudo systemctl start nginx 2>/dev/null || true
  sleep 2
done

# nginxがまだ起動していなければ強制的に起動を試みる
if [ "$NGINX_SUCCESS" = false ]; then
  echo "[kurupiro] nginx が起動していません。再度起動を試みます..."
  sudo systemctl restart nginx || true
  sleep 3
  
  if systemctl is-active --quiet nginx; then
    echo "[kurupiro] nginx 起動成功"
    NGINX_SUCCESS=true
  else
    echo "[kurupiro] 警告: nginx の起動に失敗しました" >&2
    echo "[kurupiro] オフラインページを直接表示します" >&2
    # nginx なしの場合、ローカルHTMLファイルを直接表示
    KIOSK_URL="file://${BASE_DIR}/www/offline.html"
  fi
fi

# ------------------------------------------------------------------------------
# 3. Chromium キオスク起動
# ------------------------------------------------------------------------------
echo "[3/3] Chromium キオスク起動..."

# X が立ち上がるまで少し待つ（必要に応じて調整）
sleep 5

# X11が利用可能になるまで待機
MAX_WAIT=30
WAITED=0
while ! xset q >/dev/null 2>&1; do
  if [ $WAITED -ge $MAX_WAIT ]; then
    echo "[kurupiro] エラー: X11サーバーに接続できません（${MAX_WAIT}秒待機）" >&2
    exit 1
  fi
  echo "[kurupiro] X11サーバーを待機中... (${WAITED}/${MAX_WAIT}秒)"
  sleep 1
  WAITED=$((WAITED + 1))
done
echo "[kurupiro] X11サーバーに接続しました"

# スクリーンセーバー・画面ブランク・DPMS無効化（常時表示）
xset s off 2>/dev/null || true
xset s noblank 2>/dev/null || true
xset s 0 0 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset dpms 0 0 0 2>/dev/null || true
echo "[kurupiro] スクリーンセーバー・DPMSを無効化しました"

# 背景を黒に設定
xsetroot -solid black 2>/dev/null || true

# 解像度と画面回転を適用
if [ -n "${DISPLAY_OUTPUT}" ]; then
  XRANDR_ARGS=(--output "${DISPLAY_OUTPUT}")
  if [ -n "${DISPLAY_MODE}" ]; then
    XRANDR_ARGS+=(--mode "${DISPLAY_MODE}")
  fi
  if [ -n "${DISPLAY_RATE}" ]; then
    XRANDR_ARGS+=(--rate "${DISPLAY_RATE}")
  fi
  if [ -n "${DISPLAY_ROTATION}" ]; then
    XRANDR_ARGS+=(--rotate "${DISPLAY_ROTATION}")
  fi

  if xrandr "${XRANDR_ARGS[@]}" 2>/tmp/kurupiro-xrandr.log; then
    echo "[kurupiro] 表示設定を適用しました: output=${DISPLAY_OUTPUT} mode=${DISPLAY_MODE} rate=${DISPLAY_RATE} rotate=${DISPLAY_ROTATION}"
  else
    echo "[kurupiro] 警告: 表示設定の適用に失敗しました" >&2
  fi
fi

if [ "${NGINX_SUCCESS}" = true ]; then
  CONTROLLER_LAUNCH_URL="$(
  python3 - "${CONTROLLER_URL}" "${KIOSK_URL}" "${MAIN_SCREEN_DURATION_SECONDS}" "${IMAGE_DURATION_MS}" <<'PY'
import sys
from urllib.parse import urlencode

base = sys.argv[1]
params = urlencode({
    "main": sys.argv[2],
    "mainDurationMs": sys.argv[3],
    "imageDurationMs": sys.argv[4],
})
separator = "&" if "?" in base else "?"
print(f"{base}{separator}{params}")
PY
)"
else
  CONTROLLER_LAUNCH_URL="${KIOSK_URL}"
fi

echo "[kurupiro] URL: ${KIOSK_URL}"
echo "[kurupiro] Controller URL: ${CONTROLLER_LAUNCH_URL}"

mkdir -p "${CHROMIUM_PROFILE_BASE}/controller"

CHROMIUM_COMMON_ARGS=(
  --incognito
  --noerrdialogs
  --disable-session-crashed-bubble
  --autoplay-policy=no-user-gesture-required
  --disable-translate
  --disable-features=Translate
  --no-first-run
  --no-default-browser-check
  --password-store=basic
  --disable-sync
)

# キャッシュウォームアップをバックグラウンドで開始
# （ネットワーク不安定環境対策: 起動後に数回リロードしてキャッシュを蓄積）
"${SCRIPT_DIR}/warmup-reload.sh" &
WARMUP_PID=$!
echo "[kurupiro] キャッシュウォームアップ開始 (PID: ${WARMUP_PID})"

pkill -f "${CONTROLLER_URL}" 2>/dev/null || true
pkill -f "${KIOSK_URL}" 2>/dev/null || true

nohup setsid "${CHROMIUM_BIN}" \
  --kiosk "${CONTROLLER_LAUNCH_URL}" \
  --user-data-dir="${CHROMIUM_PROFILE_BASE}/controller" \
  "${CHROMIUM_COMMON_ARGS[@]}" \
  >/tmp/kurupiro-main-chromium.log 2>&1 </dev/null &

echo "===== くるぴろ起動スクリプト終了 ====="
