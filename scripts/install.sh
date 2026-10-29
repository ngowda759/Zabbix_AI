#!/usr/bin/env bash
set -euo pipefail

MODULE_ID="zabbix-ai-assistant"
MODULE_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/zabbix-ai-assistant"
BACKEND_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/backend"
SERVICE_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/systemd/zabbix-ai-assistant.service"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

if [[ ! -f /etc/redhat-release ]]; then
  echo "This installer targets RHEL-family systems." >&2
  exit 1
fi

echo "== Zabbix AI Assistant installer (no DB tables/migrations) =="
echo "This script installs separate files only. It does not edit Zabbix core PHP files."
echo

echo "Detected packages:"
rpm -qa | grep -E '^zabbix-(web|frontend|apache-conf|nginx-conf)' | sort || true
echo

mapfile -t candidates < <(
  for d in /usr/share/zabbix/ui/modules /usr/share/zabbix/modules; do
    if [[ -d "$d" ]]; then echo "$d"; fi
  done
)

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "Could not find a Zabbix frontend modules directory." >&2
  echo "Inspect your package layout and rerun after confirming the correct modules directory." >&2
  exit 2
fi

if [[ ${#candidates[@]} -eq 1 ]]; then
  MODULES_DIR="${candidates[0]}"
else
  echo "Found multiple possible module directories:"
  printf '  %s\n' "${candidates[@]}"
  echo "Set MODULES_DIR_OVERRIDE explicitly, e.g.: sudo MODULES_DIR_OVERRIDE=/usr/share/zabbix/ui/modules ./scripts/install.sh" >&2
  exit 2
fi

if [[ -n "${MODULES_DIR_OVERRIDE:-}" ]]; then MODULES_DIR="$MODULES_DIR_OVERRIDE"; fi
TARGET="${MODULES_DIR}/ZabbixAIAssistant"

if [[ -e "$TARGET" ]]; then
  echo "Target already exists: $TARGET" >&2
  echo "Refusing to overwrite. Back it up or uninstall the existing module first." >&2
  exit 3
fi

if [[ ! -f "$MODULE_SOURCE/manifest.json" || ! -f "$MODULE_SOURCE/Module.php" ]]; then
  echo "Module source is incomplete: $MODULE_SOURCE" >&2
  exit 4
fi

if [[ ! -d "$BACKEND_SOURCE/app" || ! -f "$BACKEND_SOURCE/requirements.txt" ]]; then
  echo "Backend source is incomplete: $BACKEND_SOURCE" >&2
  exit 4
fi

echo "Module directory: $MODULES_DIR"
echo "Backend target: /opt/zabbix-ai-assistant/backend"
echo
read -r -p "Continue with file installation? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

# Install module files as a self-contained directory.
install -d -m 755 "$TARGET"
cp -a "$MODULE_SOURCE/." "$TARGET/"
chown -R root:root "$TARGET"
find "$TARGET" -type d -exec chmod 755 {} \;
find "$TARGET" -type f -exec chmod 644 {} \;

# Create service account only if absent.
if ! id zbxai >/dev/null 2>&1; then
  useradd --system --home-dir /opt/zabbix-ai-assistant --shell /sbin/nologin zbxai
fi

install -d -o zbxai -g zbxai -m 750 /opt/zabbix-ai-assistant/backend
if [[ -e /opt/zabbix-ai-assistant/backend/app ]]; then
  echo "Existing backend detected; refusing to overwrite it." >&2
  echo "Module files were installed at $TARGET; inspect and remove them if you want to cancel." >&2
  exit 5
fi
cp -a "$BACKEND_SOURCE/." /opt/zabbix-ai-assistant/backend/
chown -R zbxai:zbxai /opt/zabbix-ai-assistant/backend

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required. Install it with dnf and rerun." >&2
  exit 6
fi
python3 -m venv /opt/zabbix-ai-assistant/backend/.venv
/opt/zabbix-ai-assistant/backend/.venv/bin/pip install \
  -r /opt/zabbix-ai-assistant/backend/requirements.txt

install -d -m 750 /etc/zabbix-ai-assistant
if [[ ! -f /etc/zabbix-ai-assistant/assistant.env ]]; then
  install -o root -g zbxai -m 640 "$BACKEND_SOURCE/.env.example" \
    /etc/zabbix-ai-assistant/assistant.env
else
  echo "Preserving existing /etc/zabbix-ai-assistant/assistant.env"
  chown root:zbxai /etc/zabbix-ai-assistant/assistant.env
  chmod 640 /etc/zabbix-ai-assistant/assistant.env
fi

install -o root -g root -m 644 "$SERVICE_SOURCE" \
  /etc/systemd/system/zabbix-ai-assistant.service
systemctl daemon-reload

echo
echo "Installed module files at: $TARGET"
echo "Installed backend at: /opt/zabbix-ai-assistant/backend"
echo "Environment template: /etc/zabbix-ai-assistant/assistant.env"
echo
echo "NEXT STEPS:"
echo "1. Edit /etc/zabbix-ai-assistant/assistant.env and set the real Zabbix/OpenRouter values."
echo "2. Generate AI_API_KEY with: openssl rand -hex 32"
echo "3. Install the same key into /etc/zabbix-ai-assistant/frontend.key with the web server group."
echo "4. Enable the backend: sudo systemctl enable --now zabbix-ai-assistant"
echo "5. Validate: curl -fsS http://127.0.0.1:8091/health"
echo "6. In Zabbix: Administration > General > Modules > Scan directory, then enable the module."
echo
echo "No database tables were created or changed. The module is not enabled automatically."
