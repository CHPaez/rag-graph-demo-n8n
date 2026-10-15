#!/usr/bin/env bash
# Asks the same question to the vector, graph and hybrid agents (workflow 06) and prints the
# three answers plus what each one retrieved.   Usage: ./scripts/compare.sh "your question"
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=$(sed -n 's/^N8N_PORT=//p' .env 2>/dev/null | head -n1)
PORT=${PORT:-5679}
Q=${1:?usage: $0 "question"}
curl -sS --max-time 300 -H 'content-type: application/json' \
  -d "$(python3 -I -c 'import json,sys; print(json.dumps({"question": sys.argv[1]}))' "$Q")" \
  "http://127.0.0.1:${PORT}/webhook/compare" |
  python3 -I -c 'import json,sys; d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d; print(d.get("output", d))'
