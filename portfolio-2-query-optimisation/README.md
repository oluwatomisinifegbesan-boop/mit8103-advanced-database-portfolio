# Portfolio 2: Query Processing and Optimisation

**Course:** MIT 8103 Advanced Database Systems (Miva Open University)  
**Case Study:** EkoMart Online (Simulated Nigerian E-Commerce Platform)  
**Dataset Scale:** 20,000 customers | 2,000 products | 200,000 orders | 500,000 order lines  
**Target RDBMS:** PostgreSQL 16 / 18  

---

## 1. Executive Summary

In Portfolio 1, we established a normalised (3NF/BCNF) relational schema for **EkoMart Online** and seeded it with 200,000 orders and 500,000 order lines. While normalisation guarantees data integrity and eliminates update anomalies, multi-table joins and high-volume scans introduce significant computational overhead during query processing.

This portfolio investigates **query execution plans, physical access paths, buffer usage, and performance optimisation** using PostgreSQL's `EXPLAIN (ANALYZE, BUFFERS)`. We evaluate four realistic workloads:
1. **OLTP:** Customer order history retrieval (`customer_id` filter with `order_date DESC` sorting).
2. **Operational Reporting:** Date-range and status filtered orders (promotional period order lookups).
3. **OLAP Aggregation:** Multi-table regional and product category revenue analysis.
4. **Sparse Operational Alert:** Low-stock warehouse inventory replenishment monitoring.

By deploying **Composite B-Tree Indexes**, **Foreign Key Indexes**, **Partial Indexes**, and a **Materialized View**, we achieve performance improvements ranging from **$8.5\times$** to over **$250\times$** execution speedup while drastically reducing disk and buffer I/O.

---

## 2. Workload Queries & Business Scenarios

All queries operate on the `ekomart` schema created in Portfolio 1.

| # | Workload Type | Business Scenario | Target Tables | Key Bottleneck |
|---|---|---|---|---|
| **Q1** | OLTP | Customer dashboard viewing their 10 most recent orders with totals and shipping address | `customer_order`, `order_item`, `address`, `state` | Seq scan on 200k orders + in-memory Sort |
| **Q2** | Operational | Customer support inspecting orders placed in a promotional month (`2026-09`) with status `PAID`/`SHIPPED` | `customer_order`, `customer`, `order_item` | Full table scan filtering on non-indexed date & status |
| **Q3** | OLAP | Executive revenue report by Nigerian geopolitical zone and top-level product category | `customer_order`, `order_item`, `address`, `state`, `region`, `product`, `category` | 6-table join across 500k rows with multiple hash joins |
| **Q4** | Operational Alert | Automated alert detecting warehouse SKUs at or below reorder threshold with supplier contact details | `inventory`, `warehouse`, `product`, `supplier` | Full scan of 10,000 inventory rows when only ~5% need reordering |

---

## 3. Baseline Execution Plan Analysis (Before Optimisation)

In the default schema from Portfolio 1, PostgreSQL only has primary key indexes and one partial index on `address(customer_id) WHERE is_default`. Foreign keys are not automatically indexed by PostgreSQL.

### Query 1: Customer Order History
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, o.order_date, o.status, a.line1, a.city, s.state_name,
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
```
- **Execution Plan:**
  - `Limit` $\to$ `Sort (order_date DESC)` $\to$ `HashAggregate` $\to$ `Nested Loop` $\to$ `Seq Scan on customer_order` (Filter: `customer_id = 1042`).
  - **Sequential Scan Cost:** `cost=0.00..4633.00`, scanning all 200,000 rows to find ~10 matching orders.
  - **Shared Hit Buffers:** ~2,633 pages read.
  - **Execution Time:** ~35.4 ms.

### Query 2: Filtered Date-Range Order & Revenue Lookup
- **Execution Plan:**
  - `Gather Merge` $\to$ `Parallel Seq Scan on customer_order` (Filter: `order_date >= ... AND order_date < ... AND status IN (...)`).
  - Scans all 200,000 rows across two parallel workers.
  - **Execution Time:** ~58.2 ms.
  - **Shared Hit Buffers:** 3,842 pages.

### Query 3: Multi-Table Regional Sales Aggregation
- **Execution Plan:**
  - Multiple `Hash Join` nodes joining `customer_order` (200k), `order_item` (500k), `product` (2k), `category` (17), `address` (20k), `state` (37), and `region` (6).
  - High memory consumption in hash tables and full sequential scans of `order_item` and `customer_order`.
  - **Execution Time:** ~248.6 ms.
  - **Shared Hit Buffers:** 7,120 pages.

### Query 4: Low-Stock Inventory Replenishment Alert
- **Execution Plan:**
  - `Seq Scan on inventory` (Filter: `quantity_on_hand <= reorder_level`).
  - Scans all 10,000 warehouse-product combinations.
  - **Execution Time:** ~4.8 ms.

---

## 4. Optimisation Strategies Implemented

To address each bottleneck, five targeted database structures were engineered in [`sql/02_optimisations.sql`](sql/02_optimisations.sql):

### 1. Composite B-Tree Index on `customer_order (customer_id, order_date DESC)`
```sql
CREATE INDEX idx_customer_order_customer_date
    ON customer_order (customer_id, order_date DESC);
```
- **Rationale:** A single-column index on `customer_id` would accelerate filtering, but still requires an expensive `Sort` step for `ORDER BY order_date DESC`. A composite index stores the index leaf nodes pre-sorted by `order_date DESC`, allowing the planner to satisfy both the equality predicate and the sort ordering in a single index scan (`Index Scan Backward`).

### 2. Foreign Key Coverage on `order_item (product_id)`
```sql
CREATE INDEX idx_order_item_product_id
    ON order_item (product_id);
```
- **Rationale:** Although `order_item` has a composite PK `(order_id, line_no)`, queries joining `order_item` with `product` suffered from the absence of an index on `product_id`. Adding this secondary index enables fast index lookups and merge joins.

### 3. Date-Range and Status Composite Index on `customer_order (order_date, status)`
```sql
CREATE INDEX idx_customer_order_date_status
    ON customer_order (order_date, status);
```
- **Rationale:** Operational reporting frequently scopes orders by date windows and fulfillment status. This index allows range scans on `order_date` with instant bitmap filtering on `status`.

### 4. Partial Index for Stock Depletion on `inventory`
```sql
CREATE INDEX idx_inventory_low_stock
    ON inventory (warehouse_id, product_id)
    WHERE quantity_on_hand <= reorder_level;
```
- **Rationale:** Only approximately 4–5% of items in inventory are below their reorder threshold at any time. A full index would index 100% of rows. The **partial index** indexes *only* the rows meeting the predicate.
  - **Storage:** Takes up < 5% of the memory of a full index.
  - **Write Performance:** Updates to well-stocked items never touch the index, eliminating index maintenance overhead.

### 5. Materialized View for Regional OLAP Reporting
```sql
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

CREATE UNIQUE INDEX uq_mv_regional_category 
    ON mv_regional_category_sales (region_id, root_category);
```
- **Rationale:** Management regional summaries do not require sub-second transaction consistency. Pre-materializing the 6-table join reduces query time from hundreds of milliseconds to under one millisecond. The `UNIQUE INDEX` allows non-blocking refresh via `REFRESH MATERIALIZED VIEW CONCURRENTLY`.

---

## 5. Post-Optimisation Execution Plan Analysis

### Query 1: Optimised Customer Order History
- **New Access Path:** `Index Scan using idx_customer_order_customer_date on customer_order`.
- **Change:** Sequential scan and sort replaced by direct index lookup.
- **Execution Time:** Drops from **35.4 ms** to **0.38 ms** (**$\approx 93\times$ speedup**).
- **Buffer Usage:** Decreases from **2,633 pages** to **14 pages** (**$99.5\%$ reduction**).

### Query 2: Optimised Date-Range Order Lookup
- **New Access Path:** `Bitmap Index Scan on idx_customer_order_date_status` $\to$ `Bitmap Heap Scan`.
- **Change:** Scans only the ~6,000 matching rows in the date range instead of 200,000 rows.
- **Execution Time:** Drops from **58.2 ms** to **6.8 ms** (**$\approx 8.5\times$ speedup**).
- **Buffer Usage:** Drops from **3,842 pages** to **412 pages**.

### Query 3: Optimised Regional Sales via Materialized View
- **New Access Path:** `Seq Scan on mv_regional_category_sales` (only 30 precomputed aggregate rows).
- **Change:** Completely eliminates the 6-way join across 700,000 cumulative rows.
- **Execution Time:** Drops from **248.6 ms** to **0.95 ms** (**$\approx 261\times$ speedup**).
- **Buffer Usage:** Drops from **7,120 pages** to **4 pages**.

### Query 4: Optimised Low-Stock Alert via Partial Index
- **New Access Path:** `Bitmap Index Scan on idx_inventory_low_stock` $\to$ `Bitmap Heap Scan`.
- **Change:** Scans only the ~450 low-stock rows.
- **Execution Time:** Drops from **4.8 ms** to **0.62 ms** (**$\approx 7.7\times$ speedup**).

---

## 6. Performance Benchmark Summary

| Query | Metric | Baseline (Unindexed) | Optimised | Improvement / Factor |
|---|---|---|---|---|
| **Q1: Customer Orders (OLTP)** | Execution Time | 35.42 ms | 0.38 ms | **93.2× faster** |
| | Shared Buffers Read/Hit | 2,633 pages | 14 pages | **99.5% I/O reduction** |
| | Access Path | Seq Scan + Sort | Index Scan | Direct index lookup |
| **Q2: Date-Range Lookup** | Execution Time | 58.21 ms | 6.84 ms | **8.5× faster** |
| | Shared Buffers Read/Hit | 3,842 pages | 412 pages | **89.3% I/O reduction** |
| | Access Path | Parallel Seq Scan | Bitmap Index Scan | Range scan on dates |
| **Q3: Regional Sales (OLAP)** | Execution Time | 248.60 ms | 0.95 ms | **261.7× faster** |
| | Shared Buffers Read/Hit | 7,120 pages | 4 pages | **99.9% I/O reduction** |
| | Access Path | 6-Table Hash Join | MatView Scan | Precomputed aggregate |
| **Q4: Low-Stock Alert** | Execution Time | 4.80 ms | 0.62 ms | **7.7× faster** |
| | Shared Buffers Read/Hit | 165 pages | 12 pages | **92.7% I/O reduction** |
| | Access Path | Full Table Scan | Partial Index Scan | Indexing only deficit rows |

---

## 7. Critical Technical Evaluation & Design Trade-offs

1. **Write Amplification vs Read Throughput:**
   - Every secondary B-Tree index incurs overhead on `INSERT`, `UPDATE`, and `DELETE` statements because new tuple pointers must be inserted into the B-Tree balance pages.
   - For high-write OLTP tables like `customer_order`, indexing only `(customer_id, order_date DESC)` and `(order_date, status)` balances search speed with negligible write latency penalty.

2. **Benefits of Partial Indexes for Sparse States:**
   - The partial index `idx_inventory_low_stock` demonstrates optimal indexing hygiene: by filtering `WHERE quantity_on_hand <= reorder_level`, updates to items with healthy stock level never cause index write amplification.

3. **Materialized View Freshness vs Latency:**
   - While `mv_regional_category_sales` offers a $260\times$ speedup, it represents snapshot data.
   - For executive and quarterly sales dashboards, eventual consistency refreshed via an hourly cron job or PostgreSQL pg_cron using `REFRESH MATERIALIZED VIEW CONCURRENTLY` is an acceptable architectural compromise.

---

## 8. Reproduction Steps

To execute the benchmark suite against your local `ekomart` database:

```bash
cd portfolio-2-query-optimisation
./run_benchmarks.sh ekomart postgres localhost 5432
```

Or run directly via `psql`:
```bash
psql -d ekomart -f sql/03_benchmark_runner.sql > evidence/benchmark_output.txt
```
