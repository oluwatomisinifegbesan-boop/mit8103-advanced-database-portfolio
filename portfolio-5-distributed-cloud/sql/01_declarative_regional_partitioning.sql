-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 5
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: sql/01_declarative_regional_partitioning.sql
-- Target: PostgreSQL 16 / 18
--
-- Description:
-- Implements Horizontal Partitioning / Sharding by Nigerian Geopolitical
-- Zones (region_id). Demonstrates:
-- 1. Declarative List Partitioning on region_id (1 to 6)
-- 2. Data distribution from the 200,000 orders dataset
-- 3. Partition Pruning verification using EXPLAIN (ANALYZE, BUFFERS)
-- 4. Single-partition query speedup vs full-table scans
-- =====================================================================

SET search_path TO ekomart;

-- Drop previous partitioned table if existing
DROP TABLE IF EXISTS partitioned_order CASCADE;

-- ---------------------------------------------------------------------
-- 1. DECLARATIVE LIST PARTITIONING BY GEOPOLITICAL ZONE (region_id)
-- ---------------------------------------------------------------------
-- In distributed and partitioned architectures, the partition/shard key
-- must be part of the primary key to ensure local index uniqueness.
CREATE TABLE partitioned_order (
    order_id             BIGINT NOT NULL,
    customer_id          BIGINT NOT NULL,
    shipping_address_id  BIGINT NOT NULL,
    region_id            SMALLINT NOT NULL,
    order_date           TIMESTAMPTZ NOT NULL,
    status               VARCHAR(12) NOT NULL,
    PRIMARY KEY (order_id, region_id)
) PARTITION BY LIST (region_id);

-- Partition 1: North Central (Abuja, Benue, Kogi, Kwara, Nasarawa, Niger, Plateau)
CREATE TABLE orders_north_central PARTITION OF partitioned_order
    FOR VALUES IN (1);

-- Partition 2: North East (Adamawa, Bauchi, Borno, Gombe, Taraba, Yobe)
CREATE TABLE orders_north_east PARTITION OF partitioned_order
    FOR VALUES IN (2);

-- Partition 3: North West (Jigawa, Kaduna, Kano, Katsina, Kebbi, Sokoto, Zamfara)
CREATE TABLE orders_north_west PARTITION OF partitioned_order
    FOR VALUES IN (3);

-- Partition 4: South East (Abia, Anambra, Ebonyi, Enugu, Imo)
CREATE TABLE orders_south_east PARTITION OF partitioned_order
    FOR VALUES IN (4);

-- Partition 5: South South (Akwa Ibom, Bayelsa, Cross River, Delta, Edo, Rivers)
CREATE TABLE orders_south_south PARTITION OF partitioned_order
    FOR VALUES IN (5);

-- Partition 6: South West (Ekiti, Lagos, Ogun, Ondo, Osun, Oyo)
CREATE TABLE orders_south_west PARTITION OF partitioned_order
    FOR VALUES IN (6);

-- ---------------------------------------------------------------------
-- 2. PARTITION-LOCAL INDEXES
-- In PostgreSQL, indexes created on the partitioned parent automatically
-- cascade down to each partition, creating local B-Trees.
-- ---------------------------------------------------------------------
CREATE INDEX idx_part_order_customer ON partitioned_order (customer_id);
CREATE INDEX idx_part_order_date ON partitioned_order (order_date DESC);

-- ---------------------------------------------------------------------
-- 3. POPULATE PARTITIONED TABLE FROM SEED DATA (200,000 ORDERS)
-- Routing automatically places each row into its regional partition!
-- ---------------------------------------------------------------------
INSERT INTO partitioned_order (order_id, customer_id, shipping_address_id, region_id, order_date, status)
SELECT 
    o.order_id,
    o.customer_id,
    o.shipping_address_id,
    s.region_id,
    o.order_date,
    o.status
FROM customer_order o
JOIN address a ON a.address_id = o.shipping_address_id
JOIN state s ON s.state_id = a.state_id;

ANALYZE partitioned_order;

-- ---------------------------------------------------------------------
-- 4. VERIFY DATA DISTRIBUTION ACROSS PARTITIONS
-- ---------------------------------------------------------------------
SELECT '--- REGIONAL ROW DISTRIBUTION ACROSS PARTITIONS ---' AS step;

SELECT 
    'orders_north_central (Abuja Hub)' AS partition_name, COUNT(*) AS order_count FROM orders_north_central
UNION ALL
SELECT 'orders_north_east', COUNT(*) FROM orders_north_east
UNION ALL
SELECT 'orders_north_west (Kano Hub)', COUNT(*) FROM orders_north_west
UNION ALL
SELECT 'orders_south_east (Onitsha Hub)', COUNT(*) FROM orders_south_east
UNION ALL
SELECT 'orders_south_south (PH Hub)', COUNT(*) FROM orders_south_south
UNION ALL
SELECT 'orders_south_west (Lagos Hub)', COUNT(*) FROM orders_south_west;


-- ---------------------------------------------------------------------
-- 5. PARTITION PRUNING DEMONSTRATION WITH EXPLAIN (ANALYZE, BUFFERS)
-- ---------------------------------------------------------------------

\echo ''
\echo '======================================================================'
\echo 'TEST 1: REGIONAL QUERY WITH EXPLICIT SHARD KEY (PARTITION PRUNING ACTIVE)'
\echo 'Query target: Orders for Lagos & South West (region_id = 6)'
\echo 'Expected Behavior: Planner scans ONLY orders_south_west; 5 partitions pruned.'
\echo '======================================================================'

EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, order_date, status
FROM partitioned_order
WHERE region_id = 6
  AND order_date >= TIMESTAMPTZ '2026-10-01 00:00:00+00'
ORDER BY order_date DESC
LIMIT 20;

\echo ''
\echo '======================================================================'
\echo 'TEST 2: CROSS-PARTITION QUERY (FAN-OUT ACROSS ALL REGIONS)'
\echo 'Query target: Orders with customer_id = 1042 without region filter'
\echo 'Expected Behavior: Planner must scan index on ALL 6 partitions (scatter-gather).'
\echo '======================================================================'

EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, region_id, order_date, status
FROM partitioned_order
WHERE customer_id = 1042
ORDER BY order_date DESC;
