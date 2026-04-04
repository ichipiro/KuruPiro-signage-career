#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"
load_kurupiro_env

SYNC_DIR="${BASE_DIR}/www/drive-images"
MANIFEST_PATH="${SYNC_DIR}/index.json"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}

write_empty_manifest() {
  mkdir -p "${SYNC_DIR}"
  cat > "${MANIFEST_PATH}" <<'EOF'
{
  "updatedAt": null,
  "images": []
}
EOF
}

trap cleanup EXIT

DRIVE_FOLDER_URL="${KURUPIRO_GOOGLE_DRIVE_FOLDER_URL:-}"

if [ -z "${DRIVE_FOLDER_URL}" ]; then
  echo "[drive-sync] Google Drive フォルダURLが未設定です。空のマニフェストを書き込みます。"
  write_empty_manifest
  exit 0
fi

FOLDER_ID="$(
  python3 - "${DRIVE_FOLDER_URL}" <<'PY'
import re
import sys
from urllib.parse import parse_qs, urlparse

url = sys.argv[1]
parsed = urlparse(url)
match = re.search(r"/folders/([a-zA-Z0-9_-]+)", parsed.path)
if match:
    print(match.group(1))
    raise SystemExit(0)

query_id = parse_qs(parsed.query).get("id", [""])[0]
if query_id:
    print(query_id)
PY
)"

if [ -z "${FOLDER_ID}" ]; then
  echo "[drive-sync] エラー: Google Drive フォルダIDを抽出できませんでした: ${DRIVE_FOLDER_URL}" >&2
  exit 1
fi

LISTING_HTML="${TMP_DIR}/listing.html"
if ! curl -fsSL --retry 2 --connect-timeout 10 \
  "https://drive.google.com/embeddedfolderview?id=${FOLDER_ID}" \
  -o "${LISTING_HTML}"; then
  echo "[drive-sync] エラー: Google Drive フォルダ一覧の取得に失敗しました" >&2
  exit 1
fi

LISTING_TSV="${TMP_DIR}/listing.tsv"
python3 - "${LISTING_HTML}" "${LISTING_TSV}" <<'PY'
import html
import os
import re
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin

listing_html_path, listing_tsv_path = sys.argv[1], sys.argv[2]
allowed_exts = {".png", ".jpg", ".jpeg", ".webp", ".gif"}
base_url = "https://drive.google.com"

class DriveFolderParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.entries = []
        self._current_href = None
        self._text_parts = []

    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        href = dict(attrs).get("href", "")
        if "/file/d/" not in href:
            return
        self._current_href = urljoin(base_url, href)
        self._text_parts = []

    def handle_data(self, data):
        if self._current_href is not None:
            self._text_parts.append(data)

    def handle_endtag(self, tag):
        if tag != "a" or self._current_href is None:
            return
        text = html.unescape("".join(self._text_parts)).strip()
        self.entries.append((self._current_href, text))
        self._current_href = None
        self._text_parts = []

parser = DriveFolderParser()
with open(listing_html_path, "r", encoding="utf-8") as fh:
    parser.feed(fh.read())

seen = set()
rows = []
for href, raw_name in parser.entries:
    match = re.search(r"/file/d/([a-zA-Z0-9_-]+)", href)
    if not match:
      continue
    file_id = match.group(1)
    if file_id in seen:
      continue
    seen.add(file_id)

    name = raw_name.strip() or f"{file_id}.bin"
    ext = os.path.splitext(name)[1].lower()
    if ext not in allowed_exts:
      continue
    rows.append((file_id, name))

with open(listing_tsv_path, "w", encoding="utf-8") as fh:
    for file_id, name in rows:
        fh.write(f"{file_id}\t{name}\n")
PY

mkdir -p "${SYNC_DIR}"

ACTIVE_FILES="${TMP_DIR}/active-files.txt"
touch "${ACTIVE_FILES}"

while IFS=$'\t' read -r file_id original_name; do
  [ -n "${file_id}" ] || continue

  safe_name="$(
    python3 - "${file_id}" "${original_name}" <<'PY'
import os
import re
import sys

file_id, original_name = sys.argv[1], sys.argv[2]
base, ext = os.path.splitext(original_name)
base = re.sub(r"[^A-Za-z0-9._-]+", "-", base).strip("-") or "image"
print(f"{file_id}__{base}{ext.lower()}")
PY
  )"

  target_path="${SYNC_DIR}/${safe_name}"
  tmp_download="${TMP_DIR}/${safe_name}"
  download_url="https://drive.google.com/uc?export=download&id=${file_id}"

  if curl -fsSL --retry 2 --connect-timeout 20 "${download_url}" -o "${tmp_download}"; then
    mv "${tmp_download}" "${target_path}"
    echo "${safe_name}" >> "${ACTIVE_FILES}"
    echo "[drive-sync] 同期: ${original_name} -> ${safe_name}"
  else
    echo "[drive-sync] 警告: ダウンロードに失敗しました: ${original_name}" >&2
    rm -f "${tmp_download}"
  fi
done < "${LISTING_TSV}"

find "${SYNC_DIR}" -maxdepth 1 -type f \
  ! -name 'index.json' \
  ! -name '.gitkeep' \
  | while IFS= read -r existing_file; do
      file_name="$(basename "${existing_file}")"
      if ! grep -Fxq "${file_name}" "${ACTIVE_FILES}"; then
        rm -f "${existing_file}"
        echo "[drive-sync] 削除: ${file_name}"
      fi
    done

python3 - "${SYNC_DIR}" "${MANIFEST_PATH}" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

sync_dir, manifest_path = sys.argv[1], sys.argv[2]
ignored = {"index.json", ".gitkeep"}
images = []

for name in sorted(os.listdir(sync_dir)):
    if name in ignored:
        continue
    full_path = os.path.join(sync_dir, name)
    if not os.path.isfile(full_path):
        continue
    images.append({
        "name": name,
        "path": f"./drive-images/{name}",
    })

manifest = {
    "updatedAt": datetime.now(timezone.utc).isoformat(),
    "images": images,
}

with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

echo "[drive-sync] 完了: $(wc -l < "${ACTIVE_FILES}" | tr -d ' ') 件"
