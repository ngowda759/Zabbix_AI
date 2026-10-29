#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

echo "This removes only the AI Assistant module and its service files."
echo "It does not modify Zabbix hosts, triggers, templates, history, or database schema."
echo
read -r -p "Continue? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

systemctl disable --now zabbix-ai-assistant.service 2>/dev/null || true
rm -f /etc/systemd/system/zabbix-ai-assistant.service
systemctl daemon-reload

for d in /usr/share/zabbix/ui/modules/ZabbixAIAssistant /usr/share/zabbix/modules/ZabbixAIAssistant; do
  if [[ -d "$d" ]]; then
    rm -rf -- "$d"
    echo "Removed module directory: $d"
  fi
done

rm -rf /opt/zabbix-ai-assistant/backend

echo
echo "Removed module code, backend code, and service unit."
echo "Configuration/secrets under /etc/zabbix-ai-assistant were preserved."
echo "In Zabbix, open Administration > General > Modules and click Scan directory"
echo "to remove the now-missing module entry from module administration."
echo "To delete configuration/secrets later, manually review /etc/zabbix-ai-assistant first."
