#!/usr/bin/env bash
# =====================================================================
# MIT 8103 Advanced Database Systems - Portfolio 4
# NoSQL MongoDB Demos Runner
# =====================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

mkdir -p evidence

MONGO_URI="${1:-mongodb://localhost:27017/ekomart_nosql}"
USE_DOCKER=false
DOCKER_BIN=""

if [ -f "/Users/tomiifegbesan/.docker/bin/docker" ]; then
    DOCKER_BIN="/Users/tomiifegbesan/.docker/bin/docker"
elif command -v docker >/dev/null 2>&1; then
    DOCKER_BIN="docker"
fi

if command -v mongosh >/dev/null 2>&1; then
    EXEC_CMD="mongosh \"$MONGO_URI\""
elif [ -n "$DOCKER_BIN" ]; then
    echo "[INFO] Local mongosh not detected. Using Docker container for MongoDB execution..."
    USE_DOCKER=true
else
    echo "[ERROR] Neither mongosh nor Docker is available."
    exit 1
fi

echo "================================================================="
echo "MIT 8103 - Portfolio 4: NoSQL & Advanced Data Models (MongoDB)"
echo "Target DB: ekomart_nosql"
echo "================================================================="

if [ "$USE_DOCKER" = true ]; then
    CONTAINER_NAME="ekomart_mongo_portfolio4_$$"
    echo "Starting ephemeral MongoDB 7.0 container ($CONTAINER_NAME)..."
    "$DOCKER_BIN" run -d --name "$CONTAINER_NAME" -v "$DIR/scripts:/scripts" mongo:7.0 mongod --quiet >/dev/null 2>&1
    
    # Wait for mongod to accept connections
    echo "Waiting for MongoDB instance to initialize..."
    sleep 3
    
    cleanup() {
        echo "Tearing down ephemeral MongoDB container..."
        "$DOCKER_BIN" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    RUN_SCRIPT() {
        local script_name="$1"
        local output_file="$2"
        echo "Running $script_name..."
        "$DOCKER_BIN" exec -i "$CONTAINER_NAME" mongosh "mongodb://localhost:27017/ekomart_nosql" --file "/scripts/$script_name" > "$output_file" 2>&1
    }
else
    RUN_SCRIPT() {
        local script_name="$1"
        local output_file="$2"
        echo "Running $script_name..."
        mongosh "$MONGO_URI" --file "scripts/$script_name" > "$output_file" 2>&1
    }
fi

echo "1. Applying JSON Schema Validation for Products & Carts..."
RUN_SCRIPT "01_schema_validation.js" "evidence/01_schema_validation_output.txt"

echo "2. Seeding polymorphic catalogue and shopping carts..."
RUN_SCRIPT "02_seed_catalogue_and_carts.js" "evidence/02_seed_output.txt"

echo "3. Executing polymorphic subdocument, multikey & text queries..."
RUN_SCRIPT "03_polymorphic_queries_and_indexes.js" "evidence/03_polymorphic_queries_output.txt"

echo "4. Demonstrating TTL index and sliding session cart expiration..."
RUN_SCRIPT "04_ttl_cart_expiration.js" "evidence/04_ttl_cart_output.txt"

echo "5. Running multi-stage MongoDB Aggregation Pipelines..."
RUN_SCRIPT "05_aggregation_pipeline.js" "evidence/05_aggregation_output.txt"

echo "================================================================="
echo "All Portfolio 4 NoSQL demonstrations executed successfully!"
echo "Evidence files recorded in evidence/"
echo "================================================================="
