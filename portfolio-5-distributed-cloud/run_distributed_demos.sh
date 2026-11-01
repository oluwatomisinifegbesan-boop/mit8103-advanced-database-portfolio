#!/usr/bin/env bash
# =====================================================================
# MIT 8103 Advanced Database Systems - Portfolio 5
# Distributed & Cloud Database Runner
# =====================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

mkdir -p evidence

DB_NAME="${1:-ekomart}"
DB_USER="${2:-postgres}"
DB_HOST="${3:-localhost}"
DB_PORT="${4:-5432}"

echo "================================================================="
echo "MIT 8103 - Portfolio 5: Distributed & Cloud Database Runner"
echo "Target PostgreSQL: $DB_NAME on $DB_HOST:$DB_PORT (User: $DB_USER)"
echo "================================================================="

# Locate psql
if command -v psql >/dev/null 2>&1; then
    PSQL_BIN="psql"
elif [ -f "/Library/PostgreSQL/18/bin/psql" ]; then
    PSQL_BIN="/Library/PostgreSQL/18/bin/psql"
elif [ -f "/Library/PostgreSQL/16/bin/psql" ]; then
    PSQL_BIN="/Library/PostgreSQL/16/bin/psql"
elif [ -f "/opt/anaconda3/bin/psql" ]; then
    PSQL_BIN="/opt/anaconda3/bin/psql"
fi

# Locate Docker / mongosh
DOCKER_BIN=""
if [ -f "/Users/tomiifegbesan/.docker/bin/docker" ]; then
    DOCKER_BIN="/Users/tomiifegbesan/.docker/bin/docker"
elif command -v docker >/dev/null 2>&1; then
    DOCKER_BIN="docker"
fi

if [ -n "$PSQL_BIN" ]; then
    echo "1. Running PostgreSQL Regional Declarative Partitioning & Pruning tests..."
    "$PSQL_BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/01_declarative_regional_partitioning.sql > evidence/01_regional_partitioning_output.txt 2>&1 || true

    echo "2. Running PostgreSQL Two-Phase Commit (2PC) simulation..."
    "$PSQL_BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/02_distributed_2pc_simulation.sql > evidence/02_distributed_2pc_output.txt 2>&1 || true
fi

echo "3. Running MongoDB Sharding & Zone Routing simulation..."
if command -v mongosh >/dev/null 2>&1; then
    mongosh --file scripts/03_mongodb_sharding_simulation.js > evidence/03_mongodb_sharding_output.txt 2>&1
elif [ -n "$DOCKER_BIN" ]; then
    CNAME="ekomart_mongo_p5_$$"
    "$DOCKER_BIN" rm -f "$CNAME" >/dev/null 2>&1 || true
    "$DOCKER_BIN" run -d --name "$CNAME" -v "$DIR/scripts:/scripts" mongo:7.0 mongod --quiet >/dev/null 2>&1
    sleep 3
    "$DOCKER_BIN" exec -i "$CNAME" mongosh "mongodb://localhost:27017/ekomart_distributed" --file "/scripts/03_mongodb_sharding_simulation.js" > evidence/03_mongodb_sharding_output.txt 2>&1 || true
    "$DOCKER_BIN" rm -f "$CNAME" >/dev/null 2>&1 || true
else
    echo "Skipping MongoDB simulation (no Docker or mongosh found)."
fi

echo "================================================================="
echo "All Portfolio 5 demonstrations executed! Evidence saved in evidence/"
echo "================================================================="
