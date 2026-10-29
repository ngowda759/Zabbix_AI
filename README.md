# Zabbix AI Assistant

A minimal starter implementation of an AI assistant embedded in the Zabbix 7.0 frontend as an external frontend module. It uses a local FastAPI backend and OpenRouter; it does not require Grafana, database migrations, new Zabbix database tables, or manual edits to Zabbix core PHP files.

## Important status

This is a starter implementation, not yet validated against your exact Zabbix 7.0.x patch. Validate it in staging or after taking a verified backup before production. The assistant is read-only: it summarizes unresolved problems and must not execute model-generated shell commands.

## Documentation

- `docs/Zabbix_AI_Assistant_Implementation_Guide.md` — complete setup and operations guide.
- `docs/Zabbix_AI_Assistant_Implementation_Guide.docx` — editable Word copy.

Read the guide before installation. In particular, configure real secrets in the backend environment file and `/etc/zabbix-ai-assistant/frontend.key`; never commit secrets. Confirm the correct Zabbix frontend module path and web-server worker group for your package.
