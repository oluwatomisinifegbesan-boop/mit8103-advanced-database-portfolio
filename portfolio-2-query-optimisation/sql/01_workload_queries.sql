-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: sql/01_workload_queries.sql
-- Target: PostgreSQL 16 / 18
--
-- Description:
-- Four representative realistic workload queries representing typical
-- OLTP (transactional lookups), operational, and OLAP (analytical)
-- workloads on the 200,000 orders and 500,000 order lines dataset.
-- =====================================================================

SET search_path TO ekomart;

-- ---------------------------------------------------------------------
-- WORKLOAD QUERY 1: Customer Order History & Recent Activity (OLTP)
-- Business Context:
-- When a customer logs into the mobile app or visits the "My Orders"
-- dashboard, the application retrieves their 10 most recent orders,
-- along with current fulfillment status, shipping address, and total.
-- ---------------------------------------------------------------------
-- Query 1:
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


-- ---------------------------------------------------------------------
-- WORKLOAD QUERY 2: Filtered Date-Range Order & Revenue Lookup (Operational)
-- Business Context:
-- Customer support and warehouse dispatch teams search for orders placed
-- within a specific promotional campaign period (e.g., September 2026)
-- filtered by status ('PAID', 'SHIPPED') to inspect items and shipping.
-- ---------------------------------------------------------------------
-- Query 2:
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


-- ---------------------------------------------------------------------
-- WORKLOAD QUERY 3: Geopolitical Regional Sales & Revenue Aggregation (OLAP)
-- Business Context:
-- Management executive quarterly dashboard aggregating gross sales,
-- total units sold, and average order value broken down by Nigerian
-- geopolitical zones (South West, North Central, etc.) and top-level
-- product categories.
-- ---------------------------------------------------------------------
-- Query 3:
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


-- ---------------------------------------------------------------------
-- WORKLOAD QUERY 4: Warehouse Replenishment & Low Stock Alert (Operational)
-- Business Context:
-- Warehouse inventory controllers run automated reorder alerts to identify
-- active SKUs across warehouses whose quantity on hand has fallen below
-- their designated reorder threshold, retrieving supplier contacts.
-- ---------------------------------------------------------------------
-- Query 4:
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
