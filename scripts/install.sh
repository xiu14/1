#!/usr/bin/env bash
set -euo pipefail

PORT=8787
DATA_DIR="/root/sillytavern/data"
BACKUP_DIR="/opt/st-remote-backup/backups"
BASIC_USER="st"
BASIC_PASS="2025"
CRON_EXPR=""
NO_FIREWALL=0

APP_DIR="/opt/st-remote-backup"
PUBLIC_DIR="$APP_DIR/public"
REPO_RAW="https://raw.githubusercontent.com/xiu14/1/main"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port) PORT="$2"; shift 2 ;;
    -d|--data) DATA_DIR="$2"; shift 2 ;;
    -b|--backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    -u|--user) BASIC_USER="$2"; shift 2 ;;
    -w|--pass) BASIC_PASS="$2"; shift 2 ;;
    --cron) CRON_EXPR="$2"; shift 2 ;;
    --no-firewall) NO_FIREWALL=1; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "[i] Installing to $APP_DIR"
echo "    PORT=$PORT"
echo "    DATA_DIR=$DATA_DIR"
echo "    BACKUP_DIR=$BACKUP_DIR"

$SUDO mkdir -p "$APP_DIR" "$PUBLIC_DIR" "$BACKUP_DIR"

if [[ -f "$REPO_DIR/server.js" && -f "$REPO_DIR/public/index.html" && -f "$REPO_DIR/package.json" ]]; then
  echo "[i] Local repo detected, installing local files..."
  $SUDO cp -f "$REPO_DIR/server.js" "$APP_DIR/server.js"
  $SUDO cp -f "$REPO_DIR/package.json" "$APP_DIR/package.json"
  if [[ -f "$REPO_DIR/package-lock.json" ]]; then
    $SUDO cp -f "$REPO_DIR/package-lock.json" "$APP_DIR/package-lock.json"
  fi
  $SUDO mkdir -p "$PUBLIC_DIR"
  $SUDO cp -f "$REPO_DIR/public/index.html" "$PUBLIC_DIR/index.html"
else
  echo "[i] Local repo not found, downloading latest files from GitHub..."
  $SUDO curl -fsSL "$REPO_RAW/server.js" -o "$APP_DIR/server.js"
  $SUDO curl -fsSL "$REPO_RAW/package.json" -o "$APP_DIR/package.json"
  $SUDO curl -fsSL "$REPO_RAW/package-lock.json" -o "$APP_DIR/package-lock.json"
  $SUDO mkdir -p "$PUBLIC_DIR"
  $SUDO curl -fsSL "$REPO_RAW/public/index.html" -o "$PUBLIC_DIR/index.html"
fi

cd "$APP_DIR"

if ! command -v node >/dev/null 2>&1; then
  echo "[!] Node.js >= 18 is required."
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[!] npm is required."
  exit 1
fi

if ! command -v pm2 >/dev/null 2>&1; then
  echo "[i] Installing pm2 globally..."
  $SUDO npm i -g pm2
fi

echo "[i] Installing dependencies..."
if [[ -f package-lock.json ]]; then
  $SUDO npm ci --omit=dev
else
  $SUDO npm install --omit=dev
fi

echo "[i] Restarting service..."
PORT="$PORT" \
DATA_DIR="$DATA_DIR" \
BACKUP_DIR="$BACKUP_DIR" \
BASIC_USER="$BASIC_USER" \
BASIC_PASS="$BASIC_PASS" \
pm2 start "$APP_DIR/server.js" --name st-backup --update-env || pm2 restart st-backup --update-env
pm2 save

if [[ "$NO_FIREWALL" -eq 0 ]]; then
  if command -v ufw >/dev/null 2>&1; then
    $SUDO ufw allow "$PORT"/tcp >/dev/null 2>&1 || true
    $SUDO ufw reload >/dev/null 2>&1 || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    $SUDO firewall-cmd --permanent --add-port="$PORT"/tcp >/dev/null 2>&1 || true
    $SUDO firewall-cmd --reload >/dev/null 2>&1 || true
  fi
fi

if [[ -n "$CRON_EXPR" ]]; then
  echo "[i] Updating cron job..."
  $SUDO tee /usr/local/bin/st-backup.sh >/dev/null <<EOS
#!/usr/bin/env bash
set -euo pipefail
sleep 10
curl -sS --fail -u '${BASIC_USER}:${BASIC_PASS}' -X POST 'http://127.0.0.1:${PORT}/backup' >/dev/null
EOS
  $SUDO chmod +x /usr/local/bin/st-backup.sh
  (crontab -l 2>/dev/null | grep -v "/usr/local/bin/st-backup.sh" || true; echo "$CRON_EXPR /usr/local/bin/st-backup.sh >> /var/log/st-backup.cron.log 2>&1") | crontab -
fi

echo "[ok] Install complete."
echo "     URL: http://YOUR_IP:$PORT/"
echo "     Login: $BASIC_USER / $BASIC_PASS"
