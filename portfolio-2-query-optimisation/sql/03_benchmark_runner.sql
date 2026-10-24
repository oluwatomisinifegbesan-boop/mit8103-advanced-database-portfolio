-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: sql/03_benchmark_runner.sql
-- Target: PostgreSQL 16 / 18
--
-- Description:
-- Automated benchmark runner that measures execution plans and buffer
-- usage before and after optimisation using EXPLAIN (ANALYZE, BUFFERS).
--
-- Usage:
--   psql -d ekomart -f sql/03_benchmark_runner.sql > evidence/benchmark_output.txt
-- =====================================================================

SET search_path TO ekomart;
\timing on

-- Clear any existing portfolio 2 indexes/materialized views for a clean baseline
DROP INDEX IF EXISTS idx_customer_order_customer_date;
DROP INDEX IF EXISTS idx_order_item_product_id;
DROP INDEX IF EXISTS idx_customer_order_date_status;
DROP INDEX IF EXISTS idx_inventory_low_stock;
DROP MATERIALIZED VIEW IF EXISTS mv_regional_category_sales;

ANALYZE;

\echo '======================================================================'
\echo 'PART 1: BASELINE EXECUTION PLANS (BEFORE OPTIMISATION)'
\echo '======================================================================'

\echo ''
\echo '--- [BASELINE] QUERY 1: Customer Order History (customer_id = 1042) ---'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    o.order_id,
    o.order_date,
    o.status,
    a.line1 AS delivery_address,
    a.city,
    s.state_name,
    COUNT(oi.line_no) AS total_items,
    SUM(oi.quantity * oi.unit_price) AS total_amount
FROM customer_order o
JOIN address a ON a.address_id = o.shipping_address_id
JOIN state s ON s.state_id = a.state_id
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.customer_id = 1042
GROUP BY o.order_id, o.order_date, o.status, a.line1, a.city, s.state_name
ORDER BY o.order_date DESC
LIMIT 10;

\echo ''
\echo '--- [BASELINE] QUERY 2: Filtered Date-Range Order & Revenue Lookup ---'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    o.order_id,
    o.order_date,
    o.status,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.email AS customer_email,
    COUNT(oi.line_no) AS line_item_count,
    SUM(oi.quantity * oi.unit_price) AS order_total
FROM customer_order o
JOIN customer c ON c.customer_id = o.customer_id
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-09-01 00:00:00+00'
  AND o.order_date <  TIMESTAMPTZ '2026-10-01 00:00:00+00'
  AND o.status IN ('PAID', 'SHIPPED')
GROUP BY o.order_id, o.order_date, o.status, c.first_name, c.last_name, c.email
ORDER BY o.order_date DESC
LIMIT 50;

\echo ''
\echo '--- [BASELINE] QUERY 3: Geopolitical Regional Sales & Revenue Aggregation ---'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    r.region_name,
    COALESCE(parent_cat.category_name, cat.category_name) AS root_category,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(oi.quantity) AS total_units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_revenue,
    ROUND(AVG(oi.quantity * oi.unit_price), 2) AS avg_line_value
FROM customer_order o
JOIN address a ON a.address_id = o.shipping_address_id
JOIN state st ON st.state_id = a.state_id
JOIN region r ON r.region_id = st.region_id
JOIN order_item oi ON oi.order_id = o.order_id
JOIN product p ON p.product_id = oi.product_id
JOIN category cat ON cat.category_id = p.category_id
LEFT JOIN category parent_cat ON parent_cat.category_id = cat.parent_category_id
WHERE o.status NOT IN ('CANCELLED', 'REFUNDED')
GROUP BY r.region_name, COALESCE(parent_cat.category_name, cat.category_name)
ORDER BY r.region_name, total_revenue DESC;

\echo ''
\echo '--- [BASELINE] QUERY 4: Warehouse Replenishment & Low Stock Alert ---'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    w.warehouse_name,
    p.sku,
    p.product_name,
    i.quantity_on_hand,
    i.reorder_level,
    (i.reorder_level - i.quantity_on_hand) AS deficit,
    s.supplier_name,
    s.contact_email AS supplier_email
FROM inventory i
JOIN warehouse w ON w.warehouse_id = i.warehouse_id
JOIN product p ON p.product_id = i.product_id
JOIN supplier s ON s.supplier_id = p.supplier_id
WHERE p.is_active = true
  AND i.quantity_on_hand <= i.reorder_level
ORDER BY deficit DESC, w.warehouse_name
LIMIT 100;


\echo ''
\echo '======================================================================'
\echo 'PART 2: APPLYING OPTIMISATIONS'
\echo '======================================================================'

\i sql/02_optimisations.sql


\echo ''
\echo '======================================================================'
\echo 'PART 3: OPTIMISED EXECUTION PLANS (AFTER OPTIMISATION)'
\echo '======================================================================'

\echo ''
\echo '--- [OPTIMISED] QUERY 1: Customer Order History (customer_id = 1042) ---'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    o.order_id,
    o.order_date,
    o.status,
    a.line1 AS delivery_address,
    a.city,
    s.state_name,
    COUNT(oi.line_no) AS total_items,
    SUM(oi.quantity * oi.unit_price) AS total_amount
FROM customer_order o
JOIN address a ON a.address_id = o.shipping_address_id
JOIN state s ON s.state_id = a.state_id
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.customer_id = 1042
GROUP BY o.order_id, o.order_date, o.status, a.line1, a.city, s.state_name
ORDER BY o.order_date DESC
LIMIT 10;

\echo ''
\echo '--- [OPTIMISED] QUERY 2: Filtered Date-Range Order & Revenue Lookup ---'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    o.order_id,
    o.order_date,
    o.status,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.email AS customer_email,
    COUNT(oi.line_no) AS line_item_count,
    SUM(oi.quantity * oi.unit_price) AS order_total
FROM customer_order o
JOIN customer c ON c.customer_id = o.customer_id
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.order_date >= TIMESTAMPTZ '2026-09-01 00:00:00+00'
  AND o.order_date <  TIMESTAMPTZ '2026-10-01 00:00:00+00'
  AND o.status IN ('PAID', 'SHIPPED')
GROUP BY o.order_id, o.order_date, o.status, c.first_name, c.last_name, c.email
ORDER BY o.order_date DESC
LIMIT 50;

\echo ''
\echo '--- [OPTIMISED] QUERY 3: Geopolitical Regional Sales via Materialized View ---'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    region_name,
    root_category,
    total_orders,
    total_units_sold,
    total_revenue,
    avg_line_value
FROM mv_regional_category_sales
ORDER BY region_name, total_revenue DESC;

\echo ''
\echo '--- [OPTIMISED] QUERY 4: Warehouse Replenishment via Partial Index ---'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    w.warehouse_name,
    p.sku,
    p.product_name,
    i.quantity_on_hand,
    i.reorder_level,
    (i.reorder_level - i.quantity_on_hand) AS deficit,
    s.supplier_name,
    s.contact_email AS supplier_email
FROM inventory i
JOIN warehouse w ON w.warehouse_id = i.warehouse_id
JOIN product p ON p.product_id = i.product_id
JOIN supplier s ON s.supplier_id = p.supplier_id
WHERE p.is_active = true
  AND i.quantity_on_hand <= i.reorder_level
ORDER BY deficit DESC, w.warehouse_name
LIMIT 100;
