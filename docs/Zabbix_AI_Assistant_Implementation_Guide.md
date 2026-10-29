# Zabbix AI Assistant
## Architecture, Design, Installation, Usage, and Automation Guide

Target: Zabbix 7.0.x on RHEL • External frontend module • Python/FastAPI • OpenRouter • No additional database tables

> Operational safety: starter package; validate on staging against your exact Zabbix 7.0.x patch before production.

## 1. Executive summary

This guide describes a minimal AI assistant that appears inside the existing Zabbix frontend as an external frontend module. A separate Python/FastAPI service reads selected current problem records from the Zabbix API and asks an OpenRouter model to summarize them.

The initial implementation is read-only. It does not acknowledge problems, change hosts or templates, run shell commands, write to the Zabbix database, or create additional database tables. It does not persist chat history. Its configuration files and service code are stored on the Linux filesystem.

Important: the supplied ZIP is a starter implementation. Validate its compatibility with the exact Zabbix 7.0.x patch and test on a staging frontend or backup before production rollout. It is not an official or certified Zabbix component.


## 2. Goals and non-goals

### Goals

- Show an AI Assistant entry in the Zabbix navigation through a separate frontend module.
- Answer questions using current unresolved problem records returned by Zabbix.
- Summarize and prioritize incidents, distinguish observed records from hypotheses, and recommend safe diagnostic checks.
- Keep OpenRouter and Zabbix API credentials on the server side.
- Allow the module and backend to be installed, stopped, upgraded, and removed independently.
- Avoid new database tables, migrations, Redis, or a separate application database.
### Non-goals in the first release

- No automatic remediation or arbitrary shell execution.
- No persistent chat memory, incident history store, vector database, or fine-tuning.
- No complete metric-based root-cause analysis: the starter currently reads problem records, not CPU/memory/disk/network history.
- No automatic ticket creation or write actions in Zabbix.

## 3. Architecture

The solution has four parts: the existing Zabbix platform, a removable PHP frontend module, a local Python API service, and OpenRouter.

### Request flow

1. An authorized operator opens Monitoring → AI Assistant in the Zabbix frontend.
1. The module submits a question to its server-side controller.
1. The PHP controller sends the question to the local FastAPI service over localhost and includes a shared internal API key.
1. FastAPI calls the Zabbix JSON-RPC API using a dedicated, least-privilege API token and retrieves a bounded list of unresolved problems.
1. FastAPI sends the question and selected problem fields to OpenRouter for a natural-language summary.
1. The result returns through FastAPI and the PHP module and is displayed in the Zabbix UI.
### Architecture diagram (text form)

```bash
Operator → Zabbix UI external module → PHP controller → http://127.0.0.1:8091 → FastAPI → Zabbix API (read-only)\n                                                                          └→ OpenRouter API → AI summary → Zabbix UI
```

### Trust boundaries

- The browser must never receive the Zabbix API token, OpenRouter key, or backend shared key.
- The backend should bind to 127.0.0.1:8091 when it shares a host with the frontend. Do not expose port 8091 publicly.
- Problem names and tags may contain hostnames, customer details, IP addresses, or other sensitive data. These fields are sent to OpenRouter in the starter design; review data-handling requirements and redact if necessary.
- The starter module is restricted to Zabbix Super Admins. This is intentional because a shared backend token does not automatically enforce each frontend user's host-group permissions.
- The LLM output is advisory text, not a trusted command or a source of truth.

## 4. Components and files

| Component/path | Purpose |
| --- | --- |
| zabbix-ai-assistant/manifest.json | Module metadata and action registration. |
| zabbix-ai-assistant/Module.php | Adds the AI Assistant navigation entry. |
| zabbix-ai-assistant/actions/Assistant.php | Server-side controller; restricts access and calls the backend. |
| zabbix-ai-assistant/views/ai.assistant.php | Renders the question form and response. |
| backend/app/main.py | FastAPI service; validates the internal key, calls Zabbix, and requests OpenRouter analysis. |
| backend/.env.example | Template for Zabbix API URL/token, OpenRouter key/model, shared key, and limits. |
| systemd/zabbix-ai-assistant.service | Runs the backend as a dedicated Linux service. |
| scripts/install.sh | Interactive starter installer; detects a module directory and installs separate files. |
| scripts/uninstall.sh | Stops service and removes module/backend code while preserving config/secrets. |

Paths and exact module-discovery behavior vary by Zabbix package and patch release. Confirm the actual frontend root and module directory before installation.


## 5. Requirements

- RHEL-family Linux with systemd and package-managed Zabbix frontend.
- Zabbix 7.0.x frontend and API reachable from the backend host.
- Python 3.9+ is generally suitable for the code/dependencies; Python 3.11+ is preferred where available.
- PHP cURL and mbstring extensions enabled for the frontend PHP runtime.
- Outbound HTTPS connectivity from the backend to the Zabbix API and OpenRouter.
- A dedicated Zabbix API identity with read-only access to the required host groups.
- An OpenRouter API key and model slug supported by the account.
- A staging frontend or tested backup is strongly recommended before production deployment.

## 6. Pre-install inspection (read-only)

```bash
cat /etc/redhat-release\nrpm -qa | grep -E '^zabbix-(web|frontend|apache-conf|nginx-conf|php-fpm|server)' | sort\nphp -v\nphp -m | grep -Ei 'curl|mbstring'\nsudo find /usr/share/zabbix -maxdepth 4 -type d -name modules -print\nsudo systemctl --type=service --state=running | grep -Ei 'httpd|nginx|php-fpm|zabbix'
```

Record the exact frontend patch version. Identify whether Apache or Nginx/PHP-FPM is in use, the PHP worker user/group, and the actual module directory. Do not assume /usr/share/zabbix/ui/modules exists; package layouts can differ.

Check the installer before running it. The supplied starter installer intentionally stops if it cannot identify a unique module directory. If multiple candidate directories exist, inspect the script and resolve the correct path before proceeding.


## 7. Installation and configuration

### 7.1 Transfer and extract the bundle

```bash
sudo dnf install -y unzip python3 python3-pip\nsudo mkdir -p /opt/zabbix-ai-staging\nsudo unzip /tmp/zabbix-ai-native-module-minimal.zip -d /opt/zabbix-ai-staging
```

Use the actual ZIP path on your host. Inspect the files and scripts before executing them.

### 7.2 Install the backend and module

The bundle includes scripts/install.sh. Review it before use. It installs module files under a dedicated module directory, copies the backend to /opt/zabbix-ai-assistant/backend, creates a zbxai service account if needed, creates a Python virtual environment, and installs dependencies. It does not create database tables and does not enable the module automatically.

```bash
cd /opt/zabbix-ai-staging/zabbix-ai-native-module\nless scripts/install.sh\nsudo ./scripts/install.sh
```

The directory shown after extraction may differ depending on how the ZIP was unpacked. Run the script from the extracted project root.

### 7.3 Configure secrets

```bash
sudoedit /etc/zabbix-ai-assistant/assistant.env
```

Set these values using real credentials; do not paste secrets into tickets, source control, screenshots, or chat:

```bash
ZABBIX_API_URL=https://YOUR-ZABBIX-HOST/api_jsonrpc.php\nZABBIX_API_TOKEN=DEDICATED_READ_ONLY_TOKEN\nOPENROUTER_API_KEY=YOUR_OPENROUTER_KEY\nOPENROUTER_MODEL=YOUR_SUPPORTED_MODEL_SLUG\nAI_API_KEY=LONG_RANDOM_SHARED_SECRET\nMAX_PROBLEMS=50\nHTTP_TIMEOUT_SECONDS=20
```

Generate a strong shared key with openssl rand -hex 32. Use the same value in AI_API_KEY and /etc/zabbix-ai-assistant/frontend.key. The key file should be owned by root and readable only by the actual PHP worker group, typically root:apache with mode 0640 on Apache-based RHEL installations. Determine the group first; do not assume it is apache.

```bash
openssl rand -hex 32\nsudo install -d -m 750 /etc/zabbix-ai-assistant\n# Create the key file using your actual PHP worker group, then set mode 0640.\nsudo stat -c '%U %G %a %n' /etc/zabbix-ai-assistant/assistant.env /etc/zabbix-ai-assistant/frontend.key
```

The installer does not automatically create frontend.key or populate real credentials. Complete this manual secret configuration before enabling the UI module.

### 7.4 Start and verify the backend

```bash
sudo systemctl enable --now zabbix-ai-assistant\nsudo systemctl status zabbix-ai-assistant --no-pager\ncurl -fsS http://127.0.0.1:8091/health\nsudo ss -lntp | grep ':8091'\nsudo journalctl -u zabbix-ai-assistant -n 100 --no-pager
```

The service should listen only on 127.0.0.1:8091. If health fails, inspect logs and fix configuration before enabling the module.

### 7.5 Enable module in Zabbix

1. Sign in as a Zabbix Super Admin.
1. Open Administration → General → Modules.
1. Choose Scan directory.
1. Find Zabbix AI Assistant and enable it.
1. Refresh the UI and open Monitoring → AI Assistant.
Do not edit Zabbix core PHP files. If the module is not discovered, re-check the module directory, ownership, manifest, and compatibility with the exact 7.0.x patch.


## 8. How to use the assistant

The first version is a question-and-summary interface, not a full conversational memory system. Each request fetches current unresolved problem records and asks OpenRouter to summarize them. Conversation history is not stored.

### Example questions

- “Summarize current unresolved problems and prioritize the most critical ones.”
- “Group similar alerts and identify which hosts appear affected by related symptoms.”
- “For each critical problem, separate observed facts from likely causes.”
- “Recommend safe diagnostic checks for these alerts. Do not suggest changes or destructive commands.”
- “Which alerts should an operator investigate first, and why?”
### Interpreting answers

- Use the Zabbix Problems page to confirm the current state, severity, host, and event.
- Treat likely causes as hypotheses unless corroborated by metrics, logs, topology, or other evidence.
- The current starter does not fetch historical item values. It cannot reliably diagnose CPU, memory, disk, network, or application root causes from problem names alone.
- If no unresolved problems are returned, the backend returns a no-problems response without calling the model.

## 9. Using AI for automation: safe roadmap

The recommended path is to start with read-only assistance and add automation capabilities in controlled stages. The LLM should interpret context and explain options; deterministic code should decide which action is allowed.

| Stage | Automation | Safety controls |
| --- | --- | --- |
| 1. Summaries | On-demand problem summaries and prioritization. | Read-only API; no state changes. |
| 2. Enrichment | Fetch selected item history, host inventory, trigger details, and dependencies for better evidence. | Allow-listed API methods; bounded time range and item count. |
| 3. Notifications | Send a summary to an approved channel or ticketing system. | Explicit destination allow-list; redact sensitive fields; idempotency key. |
| 4. Diagnostic jobs | Run predefined health checks or collect logs for a known host. | Fixed scripts only; host allow-list; timeout; least-privilege OS account; full audit trail. |
| 5. Remediation proposal | Recommend a known runbook and show expected impact and rollback. | Human approval required; no execution by LLM. |
| 6. Controlled remediation | Execute an approved, predefined remediation workflow. | Explicit approval, change window, pre-checks, rollback, rate limit, audit log, kill switch. |

### Example: high CPU incident workflow

1. A Zabbix problem triggers a high-CPU alert.
1. A deterministic workflow retrieves the host, trigger, timestamp, and selected CPU history for a bounded period.
1. AI summarizes the evidence and suggests safe checks, clearly marking uncertainty.
1. The operator reviews the recommendation and chooses an approved runbook.
1. A separate automation runner executes only the selected allow-listed script after authorization and records the outcome.
Do not give the LLM unrestricted SSH, shell, database, or Zabbix write access. Do not execute model-generated shell commands. The initial starter has no automation runner and cannot perform remediation.

### Suggested future automation integrations

- Incident ticket creation and update (for example, Jira or ServiceNow) after validating the event and deduplicating repeated alerts.
- Teams/email incident summaries with severity, affected host, event link, evidence, and recommended checks.
- Automated evidence collection: selected item history, host inventory, agent reachability, and approved diagnostic script output.
- Runbook recommendation based on trigger name, host group, tags, and known incident patterns.
- Post-incident summary containing timeline, alerts, actions taken, and operator-confirmed resolution.

## 10. Security and privacy

- Use a dedicated Zabbix API identity, not an administrator's personal token.
- Keep the backend on localhost. Do not open port 8091 to the internet.
- Keep OpenRouter, Zabbix, and internal shared keys outside the repository and browser.
- Restrict the module to Super Admins for the initial pilot. The current shared token does not implement per-user host-group scoping.
- Review alert names/tags for confidential information before sending them to OpenRouter; apply redaction if required.
- Set OpenRouter spending limits and use a model slug available to the account.
- Rotate secrets if exposed and avoid logging request headers or environment variables.
- Before production, add rate limiting, audit logging, CSRF testing, and monitoring for the assistant service.

## 11. Validation checklist

- The exact Zabbix 7.0.x version and module directory are recorded.
- The module files are separate; no core frontend files were edited.
- The backend health endpoint returns HTTP 200.
- The backend binds only to 127.0.0.1:8091.
- A dedicated API token can read only the intended data.
- The assistant output matches current problems visible in Zabbix.
- Invalid X-AI-API-Key requests are rejected.
- The PHP module is restricted to Super Admins for the pilot.
- OpenRouter data handling and spend limits have been reviewed.
- Stopping the assistant does not affect normal Zabbix monitoring.
- No database schema changes, tables, or migrations were introduced.

## 12. Troubleshooting

| Symptom | Checks |
| --- | --- |
| Module does not appear | Confirm correct module directory, manifest.json, ownership/permissions, scan directory, and exact Zabbix patch compatibility. |
| Backend service fails | Check systemctl status, journalctl, Python dependencies, and /etc/zabbix-ai-assistant/assistant.env permissions. |
| HTTP 401 from backend | Ensure X-AI-API-Key equals AI_API_KEY and frontend.key has no extra whitespace. |
| Zabbix API failure | Verify API URL, TLS certificate, token validity, role permissions, and outbound connectivity. |
| OpenRouter request fails | Verify API key, supported model slug, account limits, outbound HTTPS, and provider availability. |
| PHP page reports backend unavailable | Check backend health, localhost binding, PHP cURL availability, internal key file permissions, and service logs. |
| No problems listed | Confirm there are unresolved problems visible to the API token and that problem.get returns records. |


## 13. Uninstall and rollback

The supplied uninstaller removes the assistant module code, backend code, and systemd service unit. It deliberately preserves /etc/zabbix-ai-assistant so credentials are not silently destroyed.

```bash
cd /path/to/extracted/project\nless scripts/uninstall.sh\nsudo ./scripts/uninstall.sh
```

After removing the module files, open Administration → General → Modules and scan the directory to clear the stale module entry. Confirm the module is no longer enabled.

Only after reviewing the contents should you remove secrets/configuration from /etc/zabbix-ai-assistant. Do not remove or alter Zabbix configuration directories, database files, hosts, templates, triggers, or history as part of this rollback.

```bash
sudo systemctl status zabbix-ai-assistant --no-pager || true\nsudo test ! -d /opt/zabbix-ai-assistant/backend && echo 'Backend code removed'
```


## 14. Known limitations and production-readiness notes

- The ZIP is a starter implementation and has not been tested against the user's exact Zabbix 7.0.x patch or RHEL package layout.
- Installer behavior depends on the module directory found on the host. Review the script and do not run it blindly in production.
- The installer does not create or populate frontend.key. This must be configured with correct ownership/group permissions before UI requests can authenticate.
- The starter uses a shared backend token; Super Admin-only access is a temporary guard, not full per-user authorization.
- The assistant currently uses current problem records only. Metric history, service topology, log correlation, tickets, and automations are future enhancements.
- No database tables are created, and no database migration is required.

## 15. Official references

- Zabbix 7.0 frontend modules: https://www.zabbix.com/documentation/7.0/en/devel/modules
- Zabbix 7.0 API reference: https://www.zabbix.com/documentation/7.0/en/manual/api
- OpenRouter API documentation: https://openrouter.ai/docs/api-reference/overview
- OpenRouter API key management: https://openrouter.ai/settings/keys
