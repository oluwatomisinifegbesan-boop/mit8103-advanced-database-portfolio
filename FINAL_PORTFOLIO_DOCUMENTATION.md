# Advanced Database Systems (MIT 8103)
## Continuous Assessment Final Portfolio Documentation & Technical Reflection

**Student Name:** Oluwatomisin Ifegbesan  
**Programme:** Master of Information Technology (MIT)  
**Institution:** School of Postgraduate Studies, Miva Open University  
**Academic Session:** 2026/2027 – First Semester  
**Course Code & Title:** MIT 8103: Advanced Database Systems  
**GitHub Repository Link:** [https://github.com/oluwatomisinifegbesan-boop/mit8103-advanced-database-portfolio](https://github.com/oluwatomisinifegbesan-boop/mit8103-advanced-database-portfolio)  

---

## 1. Selected Organisation & Case Study Statement

**Organisation Name:** **EkoMart Online**  
**Nature of the System:** EkoMart Online is a simulated Nigerian nationwide e-commerce marketplace and logistics platform selling electronics, fashion, groceries, home appliances, and health/beauty products. Orders are fulfilled from five strategically located regional warehouse hubs across Nigeria:
- **Lagos Ikeja Hub** (South West)
- **Abuja Idu Hub** (North Central)
- **Kano Sharada Hub** (North West)
- **Port Harcourt Trans-Amadi Hub** (South South)
- **Onitsha Hub** (South East)

### Database Users
1. **Shoppers / Customers:** Browse polymorphic catalogues, manage default delivery addresses, maintain active shopping carts, place orders, make payments, and post verified product reviews.
2. **Customer Service Representatives:** Look up order histories, verify payment status, and initiate returns or refunds.
3. **Warehouse & Fulfillment Personnel:** Monitor inventory levels, receive low-stock reorder alerts, pick multi-item orders, and update dispatch tracking numbers.
4. **Executive Management:** Execute cross-regional sales aggregation reports, track average order value, and analyze category performance.

### Key Database Operations Supported
- Atomic multi-table checkout reserving inventory and generating payment/shipment records.
- High-concurrency inventory decrement preventing overselling and lost updates during flash sales.
- Sub-millisecond order history and customer dashboard retrieval.
- Automated purging of abandoned shopping carts using sliding-window TTL indexes.
- Regional partition pruning and zone-aware query routing across Nigerian geopolitical zones.

---

## 2. Summary of Portfolio Activities & Technical Evidence

The portfolio is structured across five progressive activities, all using the consistent EkoMart Online case study:

```
mit8103-advanced-database-portfolio/
├── portfolio-1-database-design/           # Relational schema, 3NF/BCNF, 200k orders seed, constraints
├── portfolio-2-query-optimisation/        # EXPLAIN (ANALYZE, BUFFERS), composite/partial indexes, MatView
├── portfolio-3-transactions-concurrency/  # ACID enforcement, race conditions, SELECT FOR UPDATE, deadlocks
├── portfolio-4-nosql/                     # MongoDB polymorphic catalogue, TTL carts, aggregation pipelines
├── portfolio-5-distributed-cloud/         # Regional partitioning, pruning, 2PC, replication, MongoDB sharding
└── FINAL_PORTFOLIO_DOCUMENTATION.md       # LMS submission documentation and reflection
```

### Portfolio 1: Database Design and Modelling 
- **Relational Architecture:** Designed a comprehensive PostgreSQL schema encompassing 13 tables and 1 view in 3NF and BCNF. Surrogate identity keys (`GENERATED ALWAYS AS IDENTITY`) were paired with natural alternate unique keys (`product.sku`, `payment.reference`, `shipment.tracking_no`).
- **Reproducible Seed Volume:** Developed reproducible seeding scripts producing **20,000 customers**, **2,000 products**, **10,000 inventory links**, **200,000 orders**, and **500,000 order lines**.
- **Constraint Enforcement:** Implemented 17 strict database-level constraints including regex email/phone validation, positive pricing/quantity checks, non-negative stock checks (`quantity_on_hand >= 0`), delivery dates chronological sanity checks (`delivered_at >= shipped_at`), and partial unique indexes (`address WHERE is_default`).
- **Evidence:** `portfolio-1-database-design/evidence/` contains schema descriptions, row counts, and test passes for all 17 constraints.

### Portfolio 2: Query Processing and Optimisation 
- **Bottleneck Analysis:** Profiled realistic OLTP, operational, and OLAP query workloads against the 500,000 order lines dataset using `EXPLAIN (ANALYZE, BUFFERS)`.
- **Targeted Optimisation Strategies:**
  1. *Composite B-Tree Index* on `customer_order (customer_id, order_date DESC)`: Eliminated full-table sequential scans and sort steps for customer order lookups, delivering a **$93.2\times$ execution speedup** (35.4ms $\to$ 0.38ms) and a **99.5% buffer I/O reduction**.
  2. *Composite Range Index* on `customer_order (order_date, status)`: Enabled fast date-window index scans (**$8.5\times$ speedup**).
  3. *Partial / Filtered Index* on `inventory (warehouse_id, product_id) WHERE quantity_on_hand <= reorder_level`: Reduced index storage by ~95% and eliminated index maintenance overhead on healthy stock updates.
  4. *Materialized View* `mv_regional_category_sales` with unique index: Reduced executive regional sales aggregation runtime from 248.6ms to **0.95ms ($261.7\times$ speedup)** with support for non-blocking concurrent refresh.
- **Evidence:** Full baseline vs. post-optimisation query execution plans documented in `portfolio-2-query-optimisation/evidence/`.

### Portfolio 3: Transactions and Concurrency 
- **Atomic Multi-Table Checkout:** Implemented full transactional atomicity spanning 5 relational tables (`customer_order`, `order_item`, `inventory`, `payment`, `shipment`). Evaluated atomic rollback on payment decline and resilient checkout recovery using `SAVEPOINT`.
- **Race Condition Reproduction:** Simulated concurrent shoppers attempting to purchase the last remaining stock during a flash sale, proving how uncoordinated read-modify-write statements cause the **Lost Update anomaly** and phantom inventory.
- **Pessimistic Concurrency Control:** Resolved the race condition using `SELECT ... FOR UPDATE`, forcing transaction serialization in the `pg_locks` catalogue and safely rejecting out-of-stock orders without overselling. Evaluated non-blocking modifiers `NOWAIT` and `SKIP LOCKED`.
- **Isolation Level Benchmarking:** Benchmarked `READ COMMITTED`, `REPEATABLE READ` (Snapshot Isolation & First-Committer-Wins aborts with SQLSTATE `40001`), and `SERIALIZABLE` (Serializable Snapshot Isolation / SSI).
- **Deadlock Elimination:** Simulated multi-item cart circular wait deadlocks (`SQLSTATE 40P01`) and mathematically eliminated them using **Deterministic Resource Ordering** (`ORDER BY product_id ASC`).
- **Evidence:** Documented transaction traces in `portfolio-3-transactions-concurrency/evidence/`.

### Portfolio 4: NoSQL and Advanced Data Models 
- **Polyglot Persistence Architecture:** Deployed **MongoDB 7.0** alongside PostgreSQL to overcome the **Entity-Attribute-Value (EAV)** relational anti-pattern for EkoMart's highly polymorphic product catalogue (smartphones, traditional fashion, groceries, and skincare).
- **Schema Validation & Embedded Documents:** Implemented collection-level `$jsonSchema` validation and embedded variant arrays, reducing multi-table relational joins to $O(1)$ single-document reads.
- **Automated Lifecycle Purging (TTL Indexes):** Implemented single-field and partial **Time-To-Live (TTL) indexes** on `shopping_carts.updated_at` (`expireAfterSeconds: 604800`), delegating abandoned cart purging to MongoDB's internal `ttlMonitor` thread. Demonstrated sliding-window session renewal on user updates.
- **Advanced Aggregation Pipelines:** Built multi-stage aggregation pipelines (`$match`, `$unwind`, `$group`, `$facet`) that generated multi-faceted search filter sidebars (price ranges, brand shares, tag clouds) in a **single database roundtrip**.
- **Evidence:** Live MongoDB 7.0 execution logs in `portfolio-4-nosql/evidence/`.

### Portfolio 5: Distributed and Cloud Database Exercise (Score Weight: 6 Marks)
- **Declarative Horizontal Partitioning:** Implemented PostgreSQL list partitioning by Nigerian Geopolitical Zones (`region_id` 1 to 6) across 200,000 orders.
- **Partition Pruning Verification:** Verified via `EXPLAIN (ANALYZE, BUFFERS)` that a query targeting Lagos/South West (`region_id = 6`) **pruned 5 partitions** from the execution plan, accessing only 21 buffer pages in **0.088 ms**.
- **Distributed Consistency & Two-Phase Commit (2PC):** Demonstrated atomic cross-shard fulfillment between Lagos and Abuja warehouses using `PREPARE TRANSACTION`, inspecting `pg_prepared_xacts`, and testing crash-recovery rollback.
- **Zone-Aware Sharding (MongoDB):** Simulated a multi-region MongoDB sharded cluster with tag-aware routing, pinning Nigerian regional orders to geographically co-located shard replica sets.
- **CAP/PACELC & Cloud Blueprint:** Architected a multi-region AWS cloud deployment with VPC peering, asynchronous WAL streaming replication between Lagos (Primary) and Abuja (Standby DR), and connection pooling.
- **Evidence:** Partition pruning execution plans, 2PC logs, and MongoDB router logs in `portfolio-5-distributed-cloud/evidence/`.

---

## 3. Individual Technical Reflection

### Key Design Choices & Justifications
1. **Separation of Catalogue vs. Invoicing Price:** In Portfolio 1, we retained `order_item.unit_price` as a historical fact independent of `product.unit_price`. This design decision proved vital in Portfolios 2 and 3, ensuring price updates in the catalogue never corrupt historical order totals.
2. **Selective Indexing over Index Bloat:** PostgreSQL does not automatically index foreign keys. However, blindly indexing every foreign key degrades write throughput. In Portfolio 2, we specifically targeted high-impact access paths (`customer_id, order_date DESC`), utilizing **partial indexes** (`WHERE quantity_on_hand <= reorder_level`) to eliminate index write penalties on healthy stock.
3. **Polyglot Persistence vs. Relational JSONB:** While PostgreSQL offers `JSONB`, MongoDB was adopted for the product catalogue because native document databases provide document-level locking, native array multi-key indexing, and automated TTL session eviction without table vacuuming overhead.

### Challenges Faced & Engineering Solutions
- **Concurrency Contention in High-Traffic Checkout:** A major challenge was balancing lock acquisition against thread starvation. Using standard pessimistic locking (`SELECT ... FOR UPDATE`) during long external payment calls blocks connection pools. The solution was implementing short transaction windows with `NOWAIT` and evaluating optimistic concurrency control.
- **Two-Phase Commit (2PC) Blocking Vulnerability:** In distributed transactions, 2PC participants hold locks indefinitely if the coordinator fails. In production cloud deployments, we recommended transitioning cross-region order fulfillment to the **Saga Pattern with Compensating Transactions**.

### Lessons Learned
Through progressive development, I gained a profound understanding that there is no single "perfect" database engine. Real-world enterprise architectures demand **polyglot persistence**: pairing relational databases for strict ACID compliance and financial ledgers with NoSQL document stores for schema flexibility, and leveraging partitioning and streaming replication to scale horizontally across geographic regions.

---

## 4. Academic Integrity & AI Use Declaration

In accordance with Section 11 of the MIT 8103 Assessment Requirements:

| AI Tool Used | Specific Purpose of AI Use | Method of Student Verification & Testing |
|---|---|---|
| **Google Gemini / Antigravity Assistant** | 1. Scaffolding SQL DDL, seed data generators, and MongoDB scripts.<br>2. Assisting in formulating execution plan analysis and markdown documentation structure. | Every generated SQL schema, query, and script was **manually reviewed, executed, and benchmarked** against local PostgreSQL (v18) and MongoDB (v7.0 in Docker). Execution plans (`EXPLAIN ANALYZE`) and runtime outputs were captured live into `evidence/` directories. All architectural choices and reflections represent my independent understanding. |

---

## 5. References

1. PostgreSQL Global Development Group. (2024). *PostgreSQL 16 Documentation: Concurrency Control, Partitioning, and Query Optimization*. https://www.postgresql.org/docs/16/
2. MongoDB Inc. (2024). *MongoDB Manual: Document Data Modeling, Aggregation Pipeline, and Sharding*. https://www.mongodb.com/docs/v7.0/
3. Kleppmann, M. (2017). *Designing Data-Intensive Applications: The Big Ideas Behind Reliable, Scalable, and Maintainable Systems*. O'Reilly Media.
4. Silberschatz, A., Korth, H. F., & Sudarshan, S. (2020). *Database System Concepts* (7th ed.). McGraw-Hill Education.
5. Elmasri, R., & Navathe, S. B. (2015). *Fundamentals of Database Systems* (7th ed.). Pearson.
