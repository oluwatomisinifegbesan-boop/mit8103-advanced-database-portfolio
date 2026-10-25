-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 3
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: sql/01_atomic_checkout_rollback.sql
-- Target: PostgreSQL 16 / 18
--
-- Description:
-- Demonstrates transaction Atomicity, Consistency, and Durability in
-- the EkoMart checkout pipeline:
-- 1. Full successful multi-table transaction with COMMIT
-- 2. Payment failure triggering complete ROLLBACK (no orphaned records)
-- 3. Resilient checkout using SAVEPOINT for fallback payment recovery
-- =====================================================================

SET search_path TO ekomart;

-- ---------------------------------------------------------------------
-- SETUP / INSPECTION: Baseline state before test
-- ---------------------------------------------------------------------
SELECT '--- BASELINE STOCK FOR PRODUCT 10 AT WAREHOUSE 1 ---' AS step;
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 10;

-- =====================================================================
-- SCENARIO 1A: Successful Atomic Checkout (All operations succeed)
-- =====================================================================
BEGIN;

-- 1. Create order
INSERT INTO customer_order (customer_id, shipping_address_id, status)
VALUES (1, 1, 'PENDING');

-- 2. Capture the newly generated order_id
-- In SQL scripts, we use a CTE or identity retrieval
WITH new_order AS (
    SELECT currval(pg_get_serial_sequence('customer_order', 'order_id')) AS id
)
-- 3. Add order line item (Product 10, Quantity 2, Price 15000.00)
INSERT INTO order_item (order_id, line_no, product_id, quantity, unit_price)
SELECT id, 1, 10, 2, 15000.00 FROM new_order;

-- 4. Decrement inventory
UPDATE inventory 
SET quantity_on_hand = quantity_on_hand - 2
WHERE warehouse_id = 1 AND product_id = 10;

-- 5. Record payment
WITH new_order AS (
    SELECT currval(pg_get_serial_sequence('customer_order', 'order_id')) AS id
)
INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
SELECT id, 30000.00, 'CARD', 'SUCCESS', 'TXN-SUCCESS-' || id, now()
FROM new_order;

-- 6. Update order status to PAID
WITH new_order AS (
    SELECT currval(pg_get_serial_sequence('customer_order', 'order_id')) AS id
)
UPDATE customer_order 
SET status = 'PAID'
WHERE order_id = (SELECT id FROM new_order);

-- 7. Create shipment record
WITH new_order AS (
    SELECT currval(pg_get_serial_sequence('customer_order', 'order_id')) AS id
)
INSERT INTO shipment (order_id, warehouse_id, courier, tracking_no, status)
SELECT id, 1, 'GIG Logistics', 'TRK-DEMO-' || id, 'PREPARING'
FROM new_order;

COMMIT;

SELECT '--- VERIFY SCENARIO 1A: ORDER COMMITTED SUCCESSFULLY ---' AS step;
SELECT o.order_id, o.status, oi.product_id, oi.quantity, p.status AS payment_status, s.status AS shipment_status
FROM customer_order o
JOIN order_item oi ON oi.order_id = o.order_id
JOIN payment p ON p.order_id = o.order_id
JOIN shipment s ON s.order_id = o.order_id
WHERE o.order_id = currval(pg_get_serial_sequence('customer_order', 'order_id'));


-- =====================================================================
-- SCENARIO 1B: Aborted Checkout with Full ROLLBACK (Payment Rejection)
-- Demonstrates Atomicity: If payment fails, the order, order item,
-- and inventory decrement MUST ALL BE UNDONE completely.
-- =====================================================================
SELECT '--- STOCK BEFORE FAILED TRANSACTION ---' AS step;
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 10;

BEGIN;

-- 1. Create order
INSERT INTO customer_order (customer_id, shipping_address_id, status)
VALUES (2, 2, 'PENDING');

-- 2. Add line item (Product 10, Quantity 5)
WITH new_order AS (
    SELECT currval(pg_get_serial_sequence('customer_order', 'order_id')) AS id
)
INSERT INTO order_item (order_id, line_no, product_id, quantity, unit_price)
SELECT id, 1, 10, 5, 15000.00 FROM new_order;

-- 3. Decrement inventory tentatively
UPDATE inventory 
SET quantity_on_hand = quantity_on_hand - 5
WHERE warehouse_id = 1 AND product_id = 10;

-- 4. Simulated payment gateway failure
-- Business rule triggers abort: Gateway returns CARD_DECLINED
\echo 'Simulated Gateway Response: INSUFFICIENT_FUNDS / DECLINED'
ROLLBACK;

SELECT '--- VERIFY SCENARIO 1B: STOCK RESTORED AFTER ROLLBACK ---' AS step;
SELECT warehouse_id, product_id, quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 10;

-- Confirm no phantom order exists
SELECT COUNT(*) AS should_be_zero
FROM customer_order 
WHERE customer_id = 2 AND status = 'PENDING' 
  AND order_date >= now() - interval '1 minute';


-- =====================================================================
-- SCENARIO 1C: Partial Rollback with SAVEPOINT (Payment Recovery)
-- Demonstrates fault-tolerant transactions: If the first payment fails,
-- rollback to savepoint and retry with an alternative payment method.
-- =====================================================================
BEGIN;

INSERT INTO customer_order (customer_id, shipping_address_id, status)
VALUES (3, 3, 'PENDING');

WITH new_order AS (
    SELECT currval(pg_get_serial_sequence('customer_order', 'order_id')) AS id
)
INSERT INTO order_item (order_id, line_no, product_id, quantity, unit_price)
SELECT id, 1, 10, 1, 15000.00 FROM new_order;

UPDATE inventory 
SET quantity_on_hand = quantity_on_hand - 1
WHERE warehouse_id = 1 AND product_id = 10;

-- Set savepoint after reserving inventory and creating order
SAVEPOINT order_prepared;

-- Attempt 1: Failed card transaction
\echo 'Attempting Payment Method 1 (CARD) - FAILS...'
-- In real app, application detects failure and rolls back to savepoint
ROLLBACK TO SAVEPOINT order_prepared;

-- Attempt 2: Fallback to Bank Transfer succeeds
\echo 'Attempting Fallback Payment Method 2 (BANK_TRANSFER) - SUCCEEDS...'
WITH new_order AS (
    SELECT currval(pg_get_serial_sequence('customer_order', 'order_id')) AS id
)
INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
SELECT id, 15000.00, 'BANK_TRANSFER', 'SUCCESS', 'TXN-FALLBACK-' || id, now()
FROM new_order;

WITH new_order AS (
    SELECT currval(pg_get_serial_sequence('customer_order', 'order_id')) AS id
)
UPDATE customer_order 
SET status = 'PAID'
WHERE order_id = (SELECT id FROM new_order);

COMMIT;

SELECT '--- VERIFY SCENARIO 1C: RECOVERED ORDER COMMITTED ---' AS step;
SELECT o.order_id, o.status, p.method, p.status AS payment_status
FROM customer_order o
JOIN payment p ON p.order_id = o.order_id
WHERE o.order_id = currval(pg_get_serial_sequence('customer_order', 'order_id'));
