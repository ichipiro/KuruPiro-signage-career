# くるぴろサイネージ（Raspberry Pi デジタルサイネージ）

# キャリアセンター版

Raspberry Pi 4B（8GB）を使って、バス時刻表などの Web コンテンツをサイネージ表示するための構成です。  
HDMI でディスプレイに出力し、指定した時間で自動起動・自動シャットダウンします。

ネットワーク障害時にも「接続エラー画面を出さず、ローカルのオフライン画面を常に表示する」ことを重視しています。

---

## 📦 システム構成概要

- **Raspberry Pi 4B 8GB**
- **Raspberry Pi OS (64bit / Desktop)**
- **Chromium キオスクモード**
- **nginx（ローカル Web サーバ）**
  - 上流の本番サイトに proxy
  - 接続失敗時は `offline.html` を返す（エラー画面を出さない）
- **GitHub からの起動時 `git pull` 更新**
- **毎日指定時刻に自動シャットダウン**（`.env` で設定可能）
- **USB キーボード・マウス禁止（usbhid 無効化）**
- **アプリ切り替えタイマー**（30秒ごとにアプリケーションを切り替える）
- **キャリアルーム用アプリケーション**（定期的にダウンロードして起動）
- **Google Drive 画像同期**（共有フォルダの画像を定期チェックしてローカル反映）

---

## 🗂 ディレクトリ構成

```
/opt/kurupiro
├─ scripts/
│   ├─ app-switcher.sh # アプリ切り替えタイマー
│   ├─ setup.sh      # 初回セットアップ
│   ├─ start.sh      # 起動時の git pull + Chromium キオスク起動
│   ├─ reload.sh     # 軽いリロード（xdotool F5）
│   ├─ sync-drive-images.sh # Google Drive 画像同期
│   └─ common.sh     # 共通設定読み込み
├─ apps/
│  └─ ebitv/
│       ├─ ebitv # キャリアルーム用アプリケーション
│       ├─ config.ini # アプリケーションの設定ファイル
│       └─ data/  # アプリケーションのデータ保存先
├─ www/
│   └─ offline.html  # オフライン時に表示する画面
│      drive-images/ # Google Drive から同期した画像
├─ .env.sample       # URL などの設定サンプル
├─ .env              # 手動作成（Git に含めない）
└─ README.md
```

---

## 🔧 セットアップ手順

### 1️⃣ Raspberry Pi OS の準備

- Raspberry Pi OS（64bit / Desktop）をインストール
- 初期セットアップを完了

### 2️⃣ タイムゾーンを日本に設定

```bash
sudo raspi-config
```

- `5 Localisation Options` → `L2 Timezone` → `Asia` → `Tokyo` を選択

### 3️⃣ リポジトリのクローン(careerブランチ)

```bash
sudo mkdir -p /opt/kurupiro
sudo chown $USER:$USER /opt/kurupiro
git clone -b career https://github.com/ichipiro/KuruPiro-signage.git /opt/kurupiro
cd /opt/kurupiro
```

### 4️⃣ セットアップスクリプトの実行

```bash
sudo bash ./scripts/setup.sh
```

### 5️⃣ .env の編集

```bash
nano .env
```

表示するURLやシャットダウン時刻を設定してください。

```bash
# 表示する上流URL（nginx がプロキシする先）
KURUPIRO_UPSTREAM_URL="https://example.com/kurupiro"

# ChromiumでアクセスするURL（通常は localhost）
KURUPIRO_KIOSK_URL="http://localhost/"

# 自動シャットダウン時刻（HH:MM形式）
KURUPIRO_SHUTDOWN_TIME="21:57"

# Google Drive の公開フォルダURL
KURUPIRO_GOOGLE_DRIVE_FOLDER_URL="https://drive.google.com/drive/folders/xxxxxxxxxxxxxxxxxxxx"

# Google Drive 画像同期の実行間隔
KURUPIRO_DRIVE_SYNC_INTERVAL="10min"
```

### 6️⃣ 再起動

```bash
sudo reboot
```

---

## 📝 補足

- **起動時**: `start.sh` が自動実行され、`git pull` → Chromium キオスク起動
- **起動時**: Google Drive 画像を1回同期
- **30秒ごと**: `app-switcher.sh` でアプリケーション切り替え
- **2時間ごと**: `reload.sh` で F5 リロード
- **10分ごと（既定）**: `sync-drive-images.sh` で Google Drive 画像を同期
- **シャットダウン**: `.env` で設定した時刻に自動シャットダウン
- **USB HID 無効化**: 再起動後に有効

## Google Drive 画像同期

- `.env` の `KURUPIRO_GOOGLE_DRIVE_FOLDER_URL` に、公開共有された Google Drive フォルダ URL を設定します。
- 同期対象は `png`, `jpg`, `jpeg`, `webp`, `gif` です。
- Google Drive で削除された画像は、ローカルの `www/drive-images/` からも削除されます。
- 新しく追加された画像は自動でダウンロードされます。
- オフライン画面では `www/drive-images/index.json` を読み、取得済み画像があれば 30 秒ごとに順送り表示します。
- 同期画像が 0 件なら既存の `ad-01.png` を表示します。
