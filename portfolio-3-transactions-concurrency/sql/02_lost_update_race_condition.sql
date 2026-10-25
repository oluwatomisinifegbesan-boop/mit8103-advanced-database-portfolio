-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 3
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: sql/02_lost_update_race_condition.sql
-- Target: PostgreSQL 16 / 18
--
-- Description:
-- Demonstrates the classic "Lost Update" / Race Condition anomaly
-- during a high-concurrency flash sale.
--
-- Scenario:
-- Product SKU 'EKM-000099' at Warehouse 1 (Lagos Ikeja Hub) has exactly
-- 5 units in stock. Two customers attempt to buy simultaneously:
-- - Customer A intends to buy 3 units.
-- - Customer B intends to buy 4 units.
-- Combined demand (7 units) exceeds available inventory (5 units).
-- Without database locking, blind updates or uncoordinated reads cause
-- either lost updates or unexpected constraint crashes.
-- =====================================================================

SET search_path TO ekomart;

-- Reset test item inventory to exactly 5 units
UPDATE inventory 
SET quantity_on_hand = 5 
WHERE warehouse_id = 1 AND product_id = 99;

SELECT '--- INITIAL STOCK LEVEL ---' AS step;
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 99;

-- =====================================================================
-- SIMULATED CONCURRENT EXECUTION: The Lost Update Anomaly
-- =====================================================================

-- [Time t0]: Session A starts transaction and reads available stock
-- In an application, the app reads quantity_on_hand = 5 into memory
BEGIN; -- Session A
SELECT quantity_on_hand AS session_a_observed_stock 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 99;
-- Application A computes: 5 - 3 = 2 remaining units.

-- [Time t1]: Session B concurrently starts transaction and reads stock
-- Because Session A has NOT acquired an exclusive lock, Session B also reads 5
-- In another connection:
-- BEGIN; -- Session B
-- SELECT quantity_on_hand AS session_b_observed_stock FROM inventory WHERE warehouse_id = 1 AND product_id = 99;
-- Application B computes: 5 - 4 = 1 remaining unit.

-- [Time t2]: Session A writes its computed value and commits
UPDATE inventory 
SET quantity_on_hand = 2 
WHERE warehouse_id = 1 AND product_id = 99;
COMMIT; -- Session A committed

-- [Time t3]: Session B writes its computed value based on the stale read
-- Overwrites Session A's update!
BEGIN; -- Session B
UPDATE inventory 
SET quantity_on_hand = 1 
WHERE warehouse_id = 1 AND product_id = 99;
COMMIT; -- Session B committed

SELECT '--- CORRUPTED RESULT (LOST UPDATE) ---' AS step;
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 99;

\echo 'Analysis:'
\echo 'Customer A bought 3 units. Customer B bought 4 units. Total sold = 7 units.'
\echo 'Initial stock was 5. Actual physical stock should be -2 (deficit/oversold).'
\echo 'However, the database shows quantity_on_hand = 1 because Customer B overwrote Customer A.'
\echo 'Customer A update was LOST.'
