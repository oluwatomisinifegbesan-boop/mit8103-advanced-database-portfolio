#!/usr/bin/env bash
# =====================================================================
# MIT 8103 Advanced Database Systems - Portfolio 3
# Concurrency & Transactions Demo Runner
# =====================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

DB_NAME="${1:-ekomart}"
DB_USER="${2:-postgres}"
DB_HOST="${3:-localhost}"
DB_PORT="${4:-5432}"

echo "================================================================="
echo "MIT 8103 - Portfolio 3: Transactions & Concurrency Runner"
echo "Target DB: $DB_NAME on $DB_HOST:$DB_PORT (User: $DB_USER)"
echo "================================================================="

mkdir -p evidence

if command -v psql >/dev/null 2>&1; then
    PSQL_BIN="psql"
elif [ -f "/Library/PostgreSQL/18/bin/psql" ]; then
    PSQL_BIN="/Library/PostgreSQL/18/bin/psql"
elif [ -f "/Library/PostgreSQL/16/bin/psql" ]; then
    PSQL_BIN="/Library/PostgreSQL/16/bin/psql"
elif [ -f "/opt/anaconda3/bin/psql" ]; then
    PSQL_BIN="/opt/anaconda3/bin/psql"
else
    echo "Error: psql binary not found."
    exit 1
fi

echo "1. Running Atomic Checkout & Rollback tests..."
"$PSQL_BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/01_atomic_checkout_rollback.sql > evidence/01_atomic_rollback_output.txt 2>&1 || true

echo "2. Running Lost Update Race Condition tests..."
"$PSQL_BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/02_lost_update_race_condition.sql > evidence/02_race_condition_output.txt 2>&1 || true

echo "3. Running Pessimistic Locking (FOR UPDATE) tests..."
"$PSQL_BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/03_pessimistic_locking_for_update.sql > evidence/03_pessimistic_locking_output.txt 2>&1 || true

echo "4. Running Transaction Isolation Levels comparison..."
"$PSQL_BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/04_isolation_levels_comparison.sql > evidence/04_isolation_levels_output.txt 2>&1 || true

echo "5. Running Deadlock Detection & Deterministic Ordering tests..."
"$PSQL_BIN" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f sql/05_deadlock_detection_ordering.sql > evidence/05_deadlock_output.txt 2>&1 || true

echo "All tests completed! Evidence files saved in evidence/"
