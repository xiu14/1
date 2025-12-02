#!/usr/bin/env bash
set -euo pipefail

# SillyTavern Remote Backup (8787) one-click installer
# Author: xiu14
# Update: Added auto-download from GitHub

# Default Settings
PORT=8787
DATA_DIR="/root/sillytavern/data"
BACKUP_DIR="/opt/st-remote-backup/backups"
BASIC_USER="st"
BASIC_PASS="2025"
CRON_EXPR=""
KEEP_NUM=5
NO_FIREWALL=0

# GitHub Raw Source (Used when local files are missing)
REPO_RAW="https://raw.githubusercontent.com/xiu14/1/main"

# Detect sudo
if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else SUDO=""; fi

# Parse Args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port) PORT="$2"; shift 2;;
    -d|--data) DATA_DIR="$2"; shift 2;;
    -b|--backup-dir) BACKUP_DIR="$2"; shift 2;;
    -u|--user) BASIC_USER="$2"; shift 2;;
    -w|--pass) BASIC_PASS="$2"; shift 2;;
    --cron) CRON_EXPR="$2"; shift 2;;
    --keep) KEEP_NUM="$2"; shift 2;;
    --no-firewall) NO_FIREWALL=1; shift;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

APP_DIR="/opt/st-remote-backup"
PUBLIC_DIR="$APP_DIR/public"
LOCAL_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Try to find local repo files (parent of script dir)
LOCAL_REPO_DIR="$(dirname "$LOCAL_SCRIPT_DIR")"

echo "[i] Installing/Updating to $APP_DIR"
echo "    PORT=$PORT, DATA=$DATA_DIR"

$SUDO mkdir -p "$APP_DIR" "$PUBLIC_DIR"

# --- CORE LOGIC: Local Copy vs Remote Download ---

# Check if we are running inside the repo (Local Install)
if [[ -f "$LOCAL_REPO_DIR/files/server.js" && -f "$LOCAL_REPO_DIR/files/public/index.html" ]]; then
  echo "[i] Local files detected. Installing from local directory..."
  $SUDO cp -f "$LOCAL_REPO_DIR/files/server.js" "$APP_DIR/server.js"
  $SUDO cp -f "$LOCAL_REPO_DIR/files/public/index.html" "$PUBLIC_DIR/index.html"
else
  # Remote Install (curl install.sh case)
  echo "[i] Local files not found. Downloading latest version from GitHub..."
  
  echo "    Fetching server.js ..."
  $SUDO curl -fsSL "$REPO_RAW/files/server.js" -o "$APP_DIR/server.js"
  
  echo "    Fetching index.html ..."
  $SUDO curl -fsSL "$REPO_RAW/files/public/index.html" -o "$PUBLIC_DIR/index.html"
fi
# -------------------------------------------------

cd "$APP_DIR"

# Check Node.js
if ! command -v node >/dev/null 2>&1; then
  echo "[!] Node.js is required. Please install Node.js >= 18."
  # Try to install node if apt is available? (Optional, kept simple for now)
  exit 1
fi

# Install/Update PM2
if ! command -v pm2 >/dev/null 2>&1; then
  echo "[i] Installing pm2 globally..."
  $SUDO npm i -g pm2 >/dev/null 2>&1 || true
fi

# Init package.json if missing
if [[ ! -f package.json ]]; then
  $SUDO npm init -y >/dev/null 2>&1 || true
fi

# Install dependencies
echo "[i] Installing dependencies..."
$SUDO npm i express tar basic-auth >/dev/null 2>&1 || $SUDO npm i express tar basic-auth

# Start Service
echo "[i] Reloading service..."
PORT="$PORT" DATA_DIR="$DATA_DIR" BACKUP_DIR="$BACKUP_DIR" BASIC_USER="$BASIC_USER" BASIC_PASS="$BASIC_PASS" \
  pm2 start "$APP_DIR/server.js" --name st-backup --update-env --no-autorestart || pm2 restart st-backup --update-env
pm2 save

# Firewall (Best Effort)
if [[ "$NO_FIREWALL" -eq 0 ]]; then
  if command -v ufw >/dev/null 2>&1; then
    $SUDO ufw allow "$PORT"/tcp >/dev/null 2>&1 || true
    $SUDO ufw reload >/dev/null 2>&1 || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    $SUDO firewall-cmd --permanent --add-port=$PORT/tcp >/dev/null 2>&1 || true
    $SUDO firewall-cmd --reload >/dev/null 2>&1 || true
  fi
fi

# Cron Setup
if [[ -n "$CRON_EXPR" ]]; then
  echo "[i] Updating cron job..."
  $SUDO tee /usr/local/bin/st-backup.sh >/dev/null <<EOS
#!/usr/bin/env bash
set -euo pipefail
# Wait for network (optional)
sleep 10
AUTH='$BASIC_USER:$BASIC_PASS'
BASE='http://127.0.0.1:$PORT'
BACKUP_DIR='$BACKUP_DIR'
KEEP=$KEEP_NUM
# Trigger backup
curl -sS --fail -u "\$AUTH" -X POST "\$BASE/backup" >/dev/null
# Cleanup old files
mkdir -p "\$BACKUP_DIR"
mapfile -t _FILES < <(ls -1t "\$BACKUP_DIR"/st-data-*.tar.gz 2>/dev/null || true)
if (( \${#_FILES[@]} > KEEP )); then
  printf '%s\0' "\${_FILES[@]:KEEP}" | xargs -0 -r rm -f --
fi
EOS
  $SUDO chmod +x /usr/local/bin/st-backup.sh
  # Remove old cron job if exists to avoid duplicates (simple regex match)
  (crontab -l 2>/dev/null | grep -v "/usr/local/bin/st-backup.sh" || true; echo "$CRON_EXPR /usr/local/bin/st-backup.sh >> /var/log/st-backup.cron.log 2>&1") | crontab -
fi

echo "[ok] Update/Install Complete!"
echo "     URL: http://YOUR_IP:$PORT/"
