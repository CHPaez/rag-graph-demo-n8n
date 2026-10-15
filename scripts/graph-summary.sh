#!/usr/bin/env bash
# Prints node/relationship counts and a sample of the knowledge graph stored in Neo4j.
set -euo pipefail
cd "$(dirname "$0")/.."
PW=$(sed -n 's/^NEO4J_PASSWORD=//p' .env | head -n1)
run() { docker compose exec -T neo4j cypher-shell -u neo4j -p "$PW" --format plain "$1"; }
echo "== Nodes by label";        run "MATCH (n) UNWIND labels(n) AS l RETURN l, count(*) ORDER BY l"
echo "== Relationships by type"; run "MATCH ()-[r]->() RETURN type(r) AS type, count(*) AS n ORDER BY n DESC"
echo "== Sample triples";        run "MATCH (a:Entity)-[r]->(b:Entity) RETURN a.name, type(r), b.name LIMIT 25"
