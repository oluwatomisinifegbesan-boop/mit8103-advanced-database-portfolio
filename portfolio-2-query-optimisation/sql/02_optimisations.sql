-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: sql/02_optimisations.sql
-- Target: PostgreSQL 16 / 18
--
-- Description:
-- Targeted database optimisation strategies including:
-- 1. Composite B-Tree Indexes (eliminating sequential scans and sorts)
-- 2. Foreign Key Indexes (addressing PostgreSQL's lack of automatic FK indexing)
-- 3. Partial / Filtered Indexes (minimising index size for sparse criteria)
-- 4. Materialized Views with Concurrent Refresh (accelerating OLAP aggregates)
-- =====================================================================

SET search_path TO ekomart;

-- ---------------------------------------------------------------------
-- OPTIMISATION 1: Composite Index for Customer Order Lookups (Query 1)
-- Rationale:
-- In customer_order, queries look up orders by customer_id and sort by
-- order_date DESC. A single-column index on customer_id still requires
-- a costly Sort step. A composite B-Tree index on (customer_id, order_date DESC)
-- allows the PostgreSQL planner to satisfy both the equality filter AND the
-- sort order directly in a single index scan pass (Index Scan Backward).
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_customer_order_customer_date
    ON customer_order (customer_id, order_date DESC);

-- ---------------------------------------------------------------------
-- OPTIMISATION 2: Foreign Key Index on order_item (Query 1 & Query 2 & Query 3)
-- Rationale:
-- In relational schema design, primary keys are automatically indexed,
-- but PostgreSQL DOES NOT automatically index foreign keys.
-- The order_item table has a composite PK (order_id, line_no). While
-- order_id is the leading column, adding explicit foreign key coverage
-- and product_id indexing enables rapid hash/merge joins across large tables.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_order_item_product_id
    ON order_item (product_id);

-- ---------------------------------------------------------------------
-- OPTIMISATION 3: Filtered Date-Range & Status Index (Query 2)
-- Rationale:
-- Operations teams regularly filter by order_date and status.
-- A composite B-Tree index on (order_date, status) provides high selectivity,
-- allowing index range scans over date windows without scanning all 200k rows.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_customer_order_date_status
    ON customer_order (order_date, status);

-- ---------------------------------------------------------------------
-- OPTIMISATION 4: Partial / Filtered Index for Stock Alerts (Query 4)
-- Rationale:
-- In a healthy warehouse inventory, only a small minority of SKUs (~4-6%)
-- are at or below their reorder_level at any given time.
-- An unindexed or fully-indexed inventory table requires scanning all 10,000
-- warehouse-product pairs. A partial index (WHERE quantity_on_hand <= reorder_level)
-- indexes ONLY the deficient rows.
--
-- Benefits:
-- - Index size is ~95% smaller than a full index.
-- - INSERT/UPDATE operations on normal, healthy stock do NOT modify this index!
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_inventory_low_stock
    ON inventory (warehouse_id, product_id)
    WHERE quantity_on_hand <= reorder_level;

-- ---------------------------------------------------------------------
-- OPTIMISATION 5: Materialized View for OLAP Regional Reporting (Query 3)
-- Rationale:
-- Query 3 joins 6 tables across 200,000 orders and 500,000 order lines to
-- compute regional revenue. Running this ad-hoc requires multiple large hash
-- joins and aggregate calculations taking hundreds of milliseconds.
--
-- A Materialized View precomputes and physically persists the aggregated
-- results. By adding a UNIQUE index, the view can be refreshed concurrently
-- (REFRESH MATERIALIZED VIEW CONCURRENTLY) in production without locking reads.
-- ---------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_regional_category_sales;

CREATE MATERIALIZED VIEW mv_regional_category_sales AS
SELECT 
    r.region_id,
    r.region_name,
    COALESCE(parent_cat.category_name, cat.category_name) AS root_category,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(oi.quantity) AS total_units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_revenue,
    ROUND(AVG(oi.quantity * oi.unit_price), 2) AS avg_line_value,
    MAX(o.order_date) AS latest_order_date
FROM customer_order o
JOIN address a ON a.address_id = o.shipping_address_id
JOIN state st ON st.state_id = a.state_id
JOIN region r ON r.region_id = st.region_id
JOIN order_item oi ON oi.order_id = o.order_id
JOIN product p ON p.product_id = oi.product_id
JOIN category cat ON cat.category_id = p.category_id
LEFT JOIN category parent_cat ON parent_cat.category_id = cat.parent_category_id
WHERE o.status NOT IN ('CANCELLED', 'REFUNDED')
GROUP BY r.region_id, r.region_name, COALESCE(parent_cat.category_name, cat.category_name);

-- Unique index required for CONCURRENT refresh:
CREATE UNIQUE INDEX uq_mv_regional_category 
    ON mv_regional_category_sales (region_id, root_category);

-- Update query statistics
ANALYZE;
