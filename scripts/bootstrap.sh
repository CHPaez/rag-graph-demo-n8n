#!/bin/sh
# Runs before n8n starts: creates credentials and imports workflows from .env values.
# Idempotent: credentials are refreshed on every start (so a new API key applies);
# workflows are imported on the first start and again only when AI_PROVIDER or the Gemini models change,
# so edits made in the UI are not overwritten on a normal restart.
set -eu

MARKER=/home/node/.n8n/.rag-bootstrap-done
CREDS=/tmp/rag-credentials.json
WF_DIR=/tmp/rag-workflows
PROVIDER="${AI_PROVIDER:-openai}"
case "$PROVIDER" in openai|gemini) ;; *) echo "[bootstrap] Unknown AI_PROVIDER '$PROVIDER', using openai."; PROVIDER=openai ;; esac
export AI_PROVIDER="$PROVIDER"

# --- 1. Owner account (optional): needs OWNER_EMAIL and OWNER_PASSWORD -----------------
if [ -n "${OWNER_EMAIL:-}" ] && [ -n "${OWNER_PASSWORD:-}" ]; then
  N8N_INSTANCE_OWNER_PASSWORD_HASH=$(cd /usr/local/lib/node_modules/n8n && \
    node -e 'process.stdout.write(require("bcryptjs").hashSync(process.env.OWNER_PASSWORD, 10))')
  export N8N_INSTANCE_OWNER_PASSWORD_HASH
  export N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true
  echo "[bootstrap] Owner account will be created from OWNER_EMAIL / OWNER_PASSWORD."
else
  unset N8N_INSTANCE_OWNER_EMAIL || true
  echo "[bootstrap] OWNER_EMAIL/OWNER_PASSWORD not set: create the owner in the web UI."
fi

# --- 2. Credentials (Postgres + Neo4j + OpenAI + Gemini) ----------------------------------------
node -e '
const e = process.env;
const creds = [
  { id: "ragPostgresCred", name: "Postgres RAG (auto)", type: "postgres",
    data: { host: "db", port: 5432, database: e.POSTGRES_DB, user: e.POSTGRES_USER,
            password: e.POSTGRES_PASSWORD, ssl: "disable", allowUnauthorizedCerts: false,
            maxConnections: 100 } },
  { id: "ragNeo4jCred", name: "Neo4j HTTP (auto)", type: "httpBasicAuth",
    data: { user: "neo4j", password: e.NEO4J_PASSWORD || "" } },
  { id: "ragOpenAiCred", name: "OpenAI RAG (auto)", type: "openAiApi",
    data: { apiKey: e.OPENAI_API_KEY || "", url: "https://api.openai.com/v1", header: false } },
  { id: "ragGeminiCred", name: "Gemini RAG (auto)", type: "googlePalmApi",
    data: { host: "https://generativelanguage.googleapis.com", apiKey: e.GEMINI_API_KEY || "" } },
];
require("fs").writeFileSync(process.argv[1], JSON.stringify(creds));
' "$CREDS"

if n8n import:credentials --input="$CREDS" >/dev/null 2>&1; then
  echo "[bootstrap] Credentials imported."
else
  echo "[bootstrap] WARNING: could not import credentials; create them in the UI."
fi
rm -f "$CREDS"

if [ "$PROVIDER" = gemini ] && [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "[bootstrap] WARNING: GEMINI_API_KEY is empty. Set it in .env and run: docker compose up -d --force-recreate n8n"
elif [ "$PROVIDER" = openai ] && [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "[bootstrap] WARNING: OPENAI_API_KEY is empty. Set it in .env and run: docker compose up -d --force-recreate n8n"
fi

# --- 3. Workflows (first start, or when the provider changed) ---------------------------
# The marker records provider + models, so changing any of them re-imports the workflows.
# WF_REV: bump it when the bundled workflows change so existing installs re-import them.
STATE="$PROVIDER:${GEMINI_CHAT_MODEL:-}:${GEMINI_EMBED_MODEL:-}:rev2"
if [ ! -f "$MARKER" ] || [ "$(cat "$MARKER" 2>/dev/null)" != "$STATE" ]; then
  rm -rf "$WF_DIR"
  ok=1
  node /scripts/adapt-workflows.js /workflows "$WF_DIR" >/dev/null || ok=0
  if [ "$ok" = 1 ]; then
    for f in "$WF_DIR"/*.json; do
      n8n import:workflow --input="$f" >/dev/null 2>&1 || ok=0
    done
  fi
  if [ "$ok" = 1 ]; then
    # Publish the workflows that expose webhooks (used by the comparison script and workflow 06).
    for id in ragChatAgente02 ragChatGrafo04 ragChatHibrido05 ragComparador06; do
      n8n publish:workflow --id="$id" >/dev/null 2>&1 || echo "[bootstrap] WARNING: could not publish $id"
    done
    printf '%s' "$STATE" > "$MARKER"
    echo "[bootstrap] Workflows imported for provider: $PROVIDER."
  else
    echo "[bootstrap] WARNING: some workflows failed to import; retry with a restart."
  fi
  rm -rf "$WF_DIR"
fi

exec /docker-entrypoint.sh "$@"
