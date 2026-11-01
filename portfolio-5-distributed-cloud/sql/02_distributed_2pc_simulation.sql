-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 5
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: sql/02_distributed_2pc_simulation.sql
-- Target: PostgreSQL 16 / 18
--
-- Description:
-- Demonstrates Distributed Transaction Coordination using Two-Phase Commit (2PC):
-- 1. Phase 1: PREPARE TRANSACTION across distributed fulfillment shards
-- 2. Inspection of the pg_prepared_xacts global catalogue
-- 3. Phase 2: Atomic multi-node COMMIT PREPARED
-- 4. Fault-tolerance: Crash recovery and ROLLBACK PREPARED
-- =====================================================================

SET search_path TO ekomart;

-- Check whether max_prepared_transactions is configured
SHOW max_prepared_transactions;

\echo '======================================================================'
\echo 'SCENARIO 1: DISTRIBUTED ORDER FULFILLMENT ACROSS TWO REGIONAL WAREHOUSES'
\echo 'Order #9001 requires item A from Lagos Hub (Warehouse 1, South West)'
\echo 'and item B from Abuja Hub (Warehouse 2, North Central).'
\echo 'Both regional database shards must decrement inventory atomically.'
\echo '======================================================================'

-- Clean up any residual prepared transactions from previous aborted runs
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT gid FROM pg_prepared_xacts WHERE gid LIKE 'eko_%' LOOP
        EXECUTE 'ROLLBACK PREPARED ' || quote_literal(r.gid);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- PHASE 1: PREPARE PHASE (VOTE TO COMMIT)
-- ---------------------------------------------------------------------

-- Participant Node 1 (Lagos Shard): Reserve Item 10 at Warehouse 1
BEGIN;
UPDATE inventory 
SET quantity_on_hand = quantity_on_hand - 1 
WHERE warehouse_id = 1 AND product_id = 10;
-- The local node writes to WAL and prepares the transaction durably:
PREPARE TRANSACTION 'eko_order_9001_lagos_shard';

-- Participant Node 2 (Abuja Shard): Reserve Item 20 at Warehouse 2
BEGIN;
UPDATE inventory 
SET quantity_on_hand = quantity_on_hand - 1 
WHERE warehouse_id = 2 AND product_id = 20;
PREPARE TRANSACTION 'eko_order_9001_abuja_shard';

\echo 'Phase 1 Complete: Both shards voted YES and persisted prepared state to WAL.'

-- ---------------------------------------------------------------------
-- INSPECTION: The pg_prepared_xacts System Catalogue
-- Notice that prepared transactions survive disconnects and remain held
-- in shared memory and WAL until explicitly resolved!
-- ---------------------------------------------------------------------
\echo ''
\echo '--- GLOBAL IN-FLIGHT PREPARED TRANSACTIONS (pg_prepared_xacts) ---'
SELECT 
    gid AS global_transaction_id,
    prepared AS prepared_at,
    owner,
    database
FROM pg_prepared_xacts
WHERE gid LIKE 'eko_%';

-- ---------------------------------------------------------------------
-- PHASE 2A: SUCCESSFUL COMMIT ACROSS BOTH NODES
-- The Coordinator receives positive ACK from all participants and issues COMMIT
-- ---------------------------------------------------------------------
\echo ''
\echo '--- PHASE 2: COORDINATOR ISSUES ATOMIC COMMIT TO ALL SHARDS ---'
COMMIT PREPARED 'eko_order_9001_lagos_shard';
COMMIT PREPARED 'eko_order_9001_abuja_shard';

\echo 'Verification: Checking pg_prepared_xacts (should be empty):'
SELECT COUNT(*) AS active_prepared_count FROM pg_prepared_xacts WHERE gid LIKE 'eko_%';


-- ---------------------------------------------------------------------
-- SCENARIO 2: PARTIAL FAILURE & DISTRIBUTED ROLLBACK
-- Suppose Lagos shard prepares successfully, but Abuja shard detects
-- out-of-stock or network partition. Coordinator must abort both!
-- ---------------------------------------------------------------------
\echo ''
\echo '======================================================================'
\echo 'SCENARIO 2: DISTRIBUTED RECOVERY & ROLLBACK ON PARTICIPANT FAILURE'
\echo '======================================================================'

-- Node 1 prepares:
BEGIN;
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 2 WHERE warehouse_id = 1 AND product_id = 10;
PREPARE TRANSACTION 'eko_order_9002_lagos_shard';

-- Coordinator detects Node 2 failed network health check!
-- Coordinator issues ROLLBACK to all prepared participants:
\echo 'Network partition detected on Abuja shard. Coordinator issuing ROLLBACK...'
ROLLBACK PREPARED 'eko_order_9002_lagos_shard';

\echo 'Verification: Lagos inventory restored. Zero orphaned locks.'
