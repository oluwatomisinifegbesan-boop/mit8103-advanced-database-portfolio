-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 3
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: sql/05_deadlock_detection_ordering.sql
-- Target: PostgreSQL 16 / 18
--
-- Description:
-- Demonstrates:
-- 1. How multi-item shopping carts cause DEADLOCKS when locked in opposite order
-- 2. PostgreSQL's automatic deadlock detector (deadlock_timeout, SQLSTATE 40P01)
-- 3. Deadlock prevention using Deterministic Resource Ordering (ORDER BY product_id ASC)
-- =====================================================================

SET search_path TO ekomart;

-- Setup test stock for two products in Lagos Hub (warehouse_id = 1)
UPDATE inventory SET quantity_on_hand = 20 WHERE warehouse_id = 1 AND product_id IN (101, 102);

\echo '======================================================================'
\echo 'PART 1: THE DEADLOCK MECHANISM (CIRCULAR WAIT)'
\echo '======================================================================'

\echo 'Scenario:'
\echo 'Customer 1 cart: Product 101, then Product 102'
\echo 'Customer 2 cart: Product 102, then Product 101'
\echo ''
\echo 'Step 1: Session 1 locks Product 101:'
\echo '  BEGIN; SELECT * FROM inventory WHERE warehouse_id=1 AND product_id=101 FOR UPDATE;'
\echo ''
\echo 'Step 2: Session 2 locks Product 102:'
\echo '  BEGIN; SELECT * FROM inventory WHERE warehouse_id=1 AND product_id=102 FOR UPDATE;'
\echo ''
\echo 'Step 3: Session 1 requests Product 102 -> BLOCKED waiting for Session 2.'
\echo 'Step 4: Session 2 requests Product 101 -> BLOCKED waiting for Session 1.'
\echo ''
\echo 'Circular Wait Created: Session 1 -> Session 2 -> Session 1'
\echo 'After deadlock_timeout (default 1s), PostgreSQL aborts one transaction:'
\echo '  ERROR: deadlock detected'
\echo '  DETAIL: Process A waits for ShareLock on transaction B; Process B waits on A.'
\echo '  HINT: See server log for query details.'
\echo '  SQLSTATE: 40P01'


-- =====================================================================
-- PART 2: INSPECTING POSTGRESQL DEADLOCK CONFIGURATION
-- =====================================================================
\echo ''
\echo '--- POSTGRESQL DEADLOCK CONFIGURATION ---'
SHOW deadlock_timeout;
SHOW lock_timeout;
SHOW statement_timeout;


-- =====================================================================
-- PART 3: PROVEN SOLUTION - DETERMINISTIC RESOURCE ORDERING
-- =====================================================================
\echo ''
\echo '======================================================================'
\echo 'PART 3: DEADLOCK PREVENTION VIA DETERMINISTIC LOCK ORDERING'
\echo '======================================================================'

\echo 'Rule: Always lock multi-row resources sorted by their primary key ascending!'
\echo 'Query:'
\echo 'SELECT * FROM inventory'
\echo 'WHERE warehouse_id = 1 AND product_id IN (102, 101)'
\echo 'ORDER BY product_id ASC'
\echo 'FOR UPDATE;'

-- Execution of deterministic lock acquisition:
BEGIN;

-- Regardless of what order items were placed in customer cart,
-- sort by product_id ASC before locking!
SELECT warehouse_id, product_id, quantity_on_hand
FROM inventory
WHERE warehouse_id = 1 AND product_id IN (102, 101)
ORDER BY product_id ASC
FOR UPDATE;

-- Verify both locks acquired safely without risk of circular deadlock:
SELECT 
    l.locktype,
    l.mode,
    l.granted,
    c.relname
FROM pg_locks l
JOIN pg_class c ON c.oid = l.relation
WHERE c.relname = 'inventory' AND l.pid = pg_backend_pid();

COMMIT;

\echo 'Deterministic ordering successfully acquired locks in canonical order (101 then 102).'
\echo 'Deadlock condition is mathematically impossible because no transaction can request in reverse order.'
