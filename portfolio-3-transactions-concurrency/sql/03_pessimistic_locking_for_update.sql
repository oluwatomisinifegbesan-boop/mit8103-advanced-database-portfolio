-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 3
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: sql/03_pessimistic_locking_for_update.sql
-- Target: PostgreSQL 16 / 18
--
-- Description:
-- Demonstrates Pessimistic Concurrency Control using row-level locks
-- (SELECT ... FOR UPDATE).
--
-- Scenario:
-- Product SKU 'EKM-000099' at Warehouse 1 has 5 units in stock.
-- Customer A wants 3 units. Customer B wants 4 units.
-- With SELECT ... FOR UPDATE:
-- 1. Session A acquires an exclusive lock on the specific inventory row.
-- 2. Session B is blocked and safely waits for Session A to finish.
-- 3. Session A decrements stock (5 - 3 = 2) and commits.
-- 4. Session B unblocks, re-reads the updated stock (2), detects that
--    demanded quantity (4) > available stock (2), and safely aborts.
-- 5. No lost update, no overselling, perfect data consistency.
-- =====================================================================

SET search_path TO ekomart;

-- Reset inventory to 5 units
UPDATE inventory 
SET quantity_on_hand = 5 
WHERE warehouse_id = 1 AND product_id = 99;

SELECT '--- BASELINE STOCK BEFORE PESSIMISTIC LOCKING TEST ---' AS step;
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 99;

-- =====================================================================
-- STEP 1: Session A Locks Row Exclusively with FOR UPDATE
-- =====================================================================
\echo '--- [SESSION A] BEGIN TRANSACTION AND ACQUIRE ROW LOCK ---'
BEGIN;

-- Lock the row exclusively
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 99
FOR UPDATE;

-- Verify lock exists in pg_locks system catalogue
SELECT 
    l.locktype,
    l.mode,
    l.granted,
    c.relname
FROM pg_locks l
JOIN pg_class c ON c.oid = l.relation
WHERE c.relname = 'inventory' AND l.pid = pg_backend_pid();

-- Customer A purchases 3 units
UPDATE inventory 
SET quantity_on_hand = quantity_on_hand - 3
WHERE warehouse_id = 1 AND product_id = 99;

-- Commit releases the lock
COMMIT;
\echo '--- [SESSION A] COMMITTED: Stock decremented by 3 ---'


-- =====================================================================
-- STEP 2: Session B Evaluates Post-Commit Stock
-- =====================================================================
\echo '--- [SESSION B] BEGIN TRANSACTION AND ACQUIRE LOCK ---'
BEGIN;

-- Session B locks and reads the row (now seeing 2 units remaining)
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 99
FOR UPDATE;

-- Application logic check: Customer B demands 4 units, but only 2 remain!
-- Safe conditional update:
DO $$
DECLARE
    v_stock INT;
    v_demand INT := 4;
BEGIN
    SELECT quantity_on_hand INTO v_stock
    FROM inventory
    WHERE warehouse_id = 1 AND product_id = 99;

    IF v_stock >= v_demand THEN
        UPDATE inventory 
        SET quantity_on_hand = quantity_on_hand - v_demand
        WHERE warehouse_id = 1 AND product_id = 99;
        RAISE NOTICE 'Order successful!';
    ELSE
        RAISE NOTICE 'REJECTED: Demanded % units, but only % available in warehouse.', v_demand, v_stock;
    END IF;
END $$;

-- Transaction completes cleanly without corrupting stock
COMMIT;

SELECT '--- FINAL CONSISTENT STATE ---' AS step;
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 99;

\echo 'Result: Physical stock is exactly 2. Overselling was completely prevented.'


-- =====================================================================
-- STEP 3: Advanced Locking Modifiers: NOWAIT and SKIP LOCKED
-- =====================================================================
\echo '--- DEMONSTRATING SELECT FOR UPDATE NOWAIT ---'
-- If an inventory row is locked, NOWAIT immediately returns an error
-- instead of blocking indefinitely:
BEGIN;
SELECT quantity_on_hand FROM inventory WHERE warehouse_id = 1 AND product_id = 99 FOR UPDATE NOWAIT;
COMMIT;

\echo '--- DEMONSTRATING SELECT FOR UPDATE SKIP LOCKED ---'
-- For asynchronous warehouse worker pick-lists: skip already locked rows
BEGIN;
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 
LIMIT 3 
FOR UPDATE SKIP LOCKED;
COMMIT;
