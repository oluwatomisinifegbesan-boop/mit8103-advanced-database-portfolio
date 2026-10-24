#!/usr/bin/env bash
# =====================================================================
# MIT 8103 Advanced Database Systems - Portfolio 2
# Benchmark Automation Script
# =====================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

DB_NAME="${1:-ekomart}"
DB_USER="${2:-postgres}"
DB_HOST="${3:-localhost}"
DB_PORT="${4:-5432}"

echo "================================================================="
echo "MIT 8103 - Portfolio 2: Query Processing & Optimisation Runner"
echo "Target DB: $DB_NAME on $DB_HOST:$DB_PORT (User: $DB_USER)"
echo "================================================================="

mkdir -p evidence

# Ensure psql can be located
if command -v psql >/dev/null 2>&1; then
    PSQL_BIN="psql"
elif [ -f "/Library/PostgreSQL/18/bin/psql" ]; then
    PSQL_BIN="/Library/PostgreSQL/18/bin/psql"
elif [ -f "/Library/PostgreSQL/16/bin/psql" ]; then
    PSQL_BIN="/Library/PostgreSQL/16/bin/psql"
elif [ -f "/usr/local/bin/psql" ]; then
    PSQL_BIN="/usr/local/bin/psql"
elif [ -f "/opt/homebrew/bin/psql" ]; then
    PSQL_BIN="/opt/homebrew/bin/psql"
else
    echo "Error: psql binary not found."
    exit 1
fi

echo "Running benchmarks and capturing EXPLAIN (ANALYZE, BUFFERS)..."
"$PSQL_BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/03_benchmark_runner.sql > evidence/benchmark_output.txt 2>&1

echo "Done! Output saved to evidence/benchmark_output.txt"
