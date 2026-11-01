# Portfolio 5: Distributed and Cloud Database Exercise

**Course:** MIT 8103 Advanced Database Systems (Miva Open University)  
**Case Study:** EkoMart Online (Simulated Nigerian E-Commerce Platform)  
**Database Engines:** PostgreSQL 16/18 (Partitioning, 2PC & Streaming Replication) + MongoDB 7.0 (Sharding & Zone Routing)  
**Architecture:** Distributed, Horizontally Partitioned Multi-Region Cloud Database  

---

## 1. Executive Summary

As **EkoMart Online** expands from thousands of initial test orders to millions of transactions across all 36 Nigerian states and the FCT, a single monolithic database server encounters hard physical limits in CPU saturation, memory exhaustion, write I/O bottlenecks, and single points of failure (SPOF). 

Furthermore, operating across Nigeria introduces geographical latency: dispatch operations in Northern fulfillment hubs (Kano, Abuja) should not suffer network round-trip delays to a database server located solely in Lagos.

This portfolio designs, implements, and evaluates a **Horizontally Partitioned, Distributed, and High-Availability Database Architecture** for EkoMart Online:
1. **Declarative Horizontal Partitioning & Sharding:** Partitioning orders by Nigerian Geopolitical Zones (`region_id`), proving **Static Partition Pruning** where queries for Lagos/South West scan *only* the relevant regional table.
2. **Replication & High Availability (HA):** Architecting a Multi-Datacenter Disaster Recovery (DR) topology with Write-Ahead Log (WAL) streaming replication between Lagos (Primary) and Abuja (Standby).
3. **Distributed Transaction Coordination:** Implementing and evaluating **Two-Phase Commit (2PC)** using `PREPARE TRANSACTION` and `COMMIT/ROLLBACK PREPARED` for multi-warehouse order fulfillment, alongside a comparative analysis of the **Saga Pattern**.
4. **MongoDB Distributed Sharded Cluster Simulation:** Implementing Zone/Tag-Aware routing in MongoDB to pin customer documents to their nearest regional replica set.
5. **CAP Theorem, PACELC & Cloud Infrastructure Blueprint:** Analyzing trade-offs under real-world Nigerian network partition scenarios (e.g., subsea fiber cuts).

---

## 2. Horizontal Partitioning & Sharding Strategy

### 2.1 Shard Key Selection Rationale

The choice of shard key is the single most critical decision in distributed database engineering:

| Shard Key Candidate | Distribution Quality | Locality / Query Routing | Hotspot Risk | Verdict for EkoMart |
|---|---|---|---|---|
| `order_id` (Hashed) | Perfect uniform distribution | High network overhead; every regional query must fan out to all nodes (scatter-gather) | Zero | Sub-optimal for regional logistics |
| `order_date` (Range) | Poor; all current writes hit the same partition | Excellent for archival; terrible for live OLTP writes | Critical write bottleneck | **Rejected** |
| `customer_id` (Hash/List) | Good distribution | Orders for one customer are grouped, but regional warehouse dispatch cannot be isolated | Low | Sub-optimal for warehouse dispatch |
| **`region_id` (Geopolitical Zone)** | Matches business fulfillment structure (6 zones) | **Optimal:** Regional dispatch queries execute locally; queries route directly to the designated fulfillment hub | Low (mitigated by sub-partitioning) | **SELECTED** |

### 2.2 PostgreSQL Declarative List Partitioning Implementation

In [`sql/01_declarative_regional_partitioning.sql`](sql/01_declarative_regional_partitioning.sql), `partitioned_order` is partitioned into six discrete regional tables representing Nigeria's six geopolitical zones:

```sql
CREATE TABLE partitioned_order (
    order_id             BIGINT NOT NULL,
    customer_id          BIGINT NOT NULL,
    shipping_address_id  BIGINT NOT NULL,
    region_id            SMALLINT NOT NULL,
    order_date           TIMESTAMPTZ NOT NULL,
    status               VARCHAR(12) NOT NULL,
    PRIMARY KEY (order_id, region_id)
) PARTITION BY LIST (region_id);

CREATE TABLE orders_north_central PARTITION OF partitioned_order FOR VALUES IN (1); -- Abuja Hub
CREATE TABLE orders_north_east    PARTITION OF partitioned_order FOR VALUES IN (2);
CREATE TABLE orders_north_west    PARTITION OF partitioned_order FOR VALUES IN (3); -- Kano Hub
CREATE TABLE orders_south_east    PARTITION OF partitioned_order FOR VALUES IN (4); -- Onitsha Hub
CREATE TABLE orders_south_south   PARTITION OF partitioned_order FOR VALUES IN (5); -- PH Hub
CREATE TABLE orders_south_west    PARTITION OF partitioned_order FOR VALUES IN (6); -- Lagos Hub
```

### 2.3 Empirical Verification: Static Partition Pruning

When executing a regional query against the 200,000 orders dataset:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, order_date, status
FROM partitioned_order
WHERE region_id = 6
  AND order_date >= TIMESTAMPTZ '2026-10-01 00:00:00+00'
ORDER BY order_date DESC LIMIT 20;
```

#### Execution Plan Output ([`evidence/01_regional_partitioning_output.txt`](evidence/01_regional_partitioning_output.txt)):
```text
Limit (cost=0.42..15.68 rows=20) (actual time=0.038..0.065 rows=20 loops=1)
  Buffers: shared hit=21
  -> Index Scan Backward using orders_south_west_order_date_idx on orders_south_west
       Index Cond: (order_date >= '2026-10-01 00:00:00+00'::timestamptz)
       Filter: (region_id = 6)
Execution Time: 0.088 ms
```

- **Technical Analysis:**
  - The PostgreSQL query optimizer detected the static predicate `region_id = 6`.
  - **Pruning Outcome:** 5 partitions (`orders_north_central`, `orders_north_east`, `orders_north_west`, `orders_south_east`, `orders_south_south`) were **completely pruned** from the execution plan.
  - The database accessed **only 21 buffer pages** on `orders_south_west`, executing in **0.088 ms**.
  - In contrast, a cross-partition query without `region_id` (`WHERE customer_id = 1042`) required a multi-node `Append` scan across all 6 partitions (taking 0.224 ms), proving the computational advantage of shard-key alignment.

---

## 3. Replication Architecture & High Availability (HA)

### 3.1 Multi-Region Disaster Recovery Topology

EkoMart implements a **Active-Standby Streaming Replication** topology across two geographical data centers:

```
┌────────────────────────────────────────────────────────┐
│               Lagos Primary Datacenter                 │
│                                                        │
│  ┌─────────────────────────┐                           │
│  │     PostgreSQL Node 1   │                           │
│  │   (Read/Write Primary)  │                           │
│  └────────────┬────────────┘                           │
└───────────────┼────────────────────────────────────────┘
                │
                │ Synchronous / Asynchronous
                │ WAL Streaming Replication
                ▼
┌────────────────────────────────────────────────────────┐
│               Abuja DR Datacenter                      │
│                                                        │
│  ┌─────────────────────────┐                           │
│  │     PostgreSQL Node 2   │                           │
│  │     (Hot Standby Node)  │                           │
│  └─────────────────────────┘                           │
└────────────────────────────────────────────────────────┘
```

### 3.2 Replication Modes: Synchronous vs. Asynchronous Evaluation

| Metric | Asynchronous Replication | Synchronous Replication (`synchronous_commit = on`) | EkoMart Selection |
|---|---|---|---|
| **Write Latency** | Low (transaction commits as soon as local WAL writes) | High (commits only after Abuja replica acknowledges WAL receipt) | Asynchronous for normal operations; Synchronous for payments |
| **RPO (Recovery Point Objective)** | Non-zero (minor data loss if Lagos primary suddenly burns down before sync) | Zero (RPO = 0: guaranteed zero lost transactions) | **RPO = 0** on payment transactions |
| **RTO (Recovery Time Objective)** | < 30 seconds via automated Patroni failover | < 30 seconds via automated Patroni failover | < 30s |
| **Network Sensitivity** | Immune to inter-city bandwidth spikes | Transactions block if Lagos-Abuja link experiences latency | Hybrid model |

---

## 4. Distributed Transactions & Consistency Across Shards

### 4.1 Cross-Shard Fulfillment & Two-Phase Commit (2PC)

When an order requires items fulfilled from separate regional nodes (e.g., Warehouse 1 in Lagos and Warehouse 2 in Abuja), a standard single-node `COMMIT` cannot guarantee ACID atomicity across the network.

In [`sql/02_distributed_2pc_simulation.sql`](sql/02_distributed_2pc_simulation.sql), we demonstrate **Two-Phase Commit (2PC)**:

#### Phase 1: Prepare Phase
```sql
-- Shard 1 (Lagos)
BEGIN;
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE warehouse_id = 1 AND product_id = 10;
PREPARE TRANSACTION 'eko_order_9001_lagos_shard';

-- Shard 2 (Abuja)
BEGIN;
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE warehouse_id = 2 AND product_id = 20;
PREPARE TRANSACTION 'eko_order_9001_abuja_shard';
```
- Both nodes write changes to their local Write-Ahead Log (WAL), acquire persistent transaction locks, and vote **YES** by remaining in `pg_prepared_xacts`.

#### Phase 2: Commit or Rollback
- **Success Case:** The Coordinator receives positive votes from both nodes and issues:
  ```sql
  COMMIT PREPARED 'eko_order_9001_lagos_shard';
  COMMIT PREPARED 'eko_order_9001_abuja_shard';
  ```
- **Failure / Crash Case:** If Abuja detects a stock deficit or network partition during Phase 1:
  ```sql
  ROLLBACK PREPARED 'eko_order_9001_lagos_shard';
  ```
  The Lagos reservation is released cleanly with zero orphaned records.

### 4.2 2PC Limitations vs. The Saga Pattern

While 2PC provides strict serializability, it is a **blocking protocol**: if the coordinator crashes during Phase 2, participants hold row locks indefinitely.

**EkoMart's Long-Term Architectural Recommendation:** Adopt the **Saga Pattern (Orchestration)** for long-running workflows:
- Each regional fulfillment step commits locally as an independent transaction.
- If a subsequent step fails, the orchestrator triggers **Compensating Transactions** (e.g., `refundPayment()`, `restockInventory()`), ensuring eventual consistency without distributed blocking locks.

---

## 5. MongoDB Distributed Sharded Cluster Simulation

Implemented in [`scripts/03_mongodb_sharding_simulation.js`](scripts/03_mongodb_sharding_simulation.js), EkoMart establishes a horizontally sharded document architecture.

### 5.1 Cluster Topology

- **Routers (`mongos`):** Stateless routing instances running in Lagos and Abuja.
- **Config Server Replica Set (`cfg-repl`):** 3-member Raft consensus group storing chunk boundaries and routing metadata.
- **Shard Replica Sets:**
  - `shard_sw_lagos`: Primary storage for South West orders.
  - `shard_nc_abuja`: Primary storage for Northern regions.
  - `shard_eastern_ph`: Primary storage for Eastern and Niger Delta hubs.

### 5.2 Zone / Tag-Aware Routing

```javascript
// Pin Nigerian Geopolitical Zones directly to geographic shard clusters
sh.addShardTag("shard_sw_lagos", "ZONE_SOUTH_WEST");
sh.addShardTag("shard_nc_abuja", "ZONE_NORTH_CENTRAL");
sh.addShardTag("shard_eastern_ph", "ZONE_EASTERN");

sh.addTagRange(
  "ekomart_distributed.orders",
  { "delivery.region_id": 6, "order_id": MinKey },
  { "delivery.region_id": 6, "order_id": MaxKey },
  "ZONE_SOUTH_WEST"
);
```

#### Verification Result ([`evidence/03_mongodb_sharding_output.txt`](evidence/03_mongodb_sharding_output.txt)):
- A query targeting `{ "delivery.region_id": 6 }` routes **directly to `shard_sw_lagos`**, executing on a single shard node.
- A global query lacking the shard key (`{ status: "PAID" }`) executes as a **scatter-gather broadcast** to all three shards, merging results at the router.

---

## 6. CAP Theorem, PACELC & Cloud Infrastructure Blueprint

### 6.1 CAP & PACELC Analysis for Nigerian Infrastructure

Operating distributed cloud databases in emerging markets requires handling infrastructure realities: power fluctuations, municipal fiber cuts, and subsea cable outages.

```
       CAP THEOREM                   PACELC THEOREM
     ┌──────────────┐              ┌────────────────┐
     │      C       │              │ If P:   PC     │  (Trade off Availability for Consistency)
     │     / \      │              │ Else:   PA/EL  │  (Trade off Latency for Consistency)
     │    /   \     │              └────────────────┘
     │   /  ★  \    │
     │  A ───── P   │              ★ EkoMart Configuration:
     └──────────────┘                - Orders/Payments: Strong Consistency (CP)
                                     - Catalogue/Carts: High Availability (AP / PA/EL)
```

- **Under Network Partition ($P$):** EkoMart prioritizes **Consistency ($C$)** for financial ledgers and stock reservations. If the Lagos-Abuja link is severed, secondary nodes reject writes to prevent split-brain inventory discrepancies.
- **Under Normal Operation ($E$):** For product browsing, EkoMart prioritizes **Latency ($L$)** by routing mobile reads to the nearest regional read replica (`readPreference: "nearest"`).

### 6.2 AWS / Multi-Region Cloud Deployment Blueprint

```
                      [ Nigerian Internet Users & Mobile Apps ]
                                          │
                                   [ Route 53 DNS ]
                                          │
                   ┌──────────────────────┴──────────────────────┐
                   │                                             │
      ┌────────────▼─────────────┐                 ┌─────────────▼────────────┐
      │   Lagos VPC (af-south-1) │                 │   Abuja VPC (DR Region)  │
      │  ┌─────────────────────┐ │                 │  ┌─────────────────────┐ │
      │  │ Application Servers │ │                 │  │ Application Servers │ │
      │  └──────────┬──────────┘ │                 │  └──────────┬──────────┘ │
      │             │            │                 │             │            │
      │  ┌──────────▼──────────┐ │   Cross-Region  │  ┌──────────▼──────────┐ │
      │  │ PostgreSQL Primary  ├─┼───WAL Stream───►│  │ PostgreSQL Standby  │ │
      │  └─────────────────────┘ │   (VPC Peering) │  └─────────────────────┘ │
      │  ┌─────────────────────┐ │                 │  ┌─────────────────────┐ │
      │  │ MongoDB Shard SW    │ │                 │  │ MongoDB Shard NC    │ │
      │  └─────────────────────┘ │                 │  └─────────────────────┘ │
      └──────────────────────────┘                 └──────────────────────────┘
```

---

## 7. Empirical Evidence & Output Logs

All architectural models and simulations have been executed and logged in [`evidence/`](evidence/):

- [`evidence/01_regional_partitioning_output.txt`](evidence/01_regional_partitioning_output.txt): Confirms creation of 6 regional partitions, row distribution across 200,000 orders, and `EXPLAIN (ANALYZE, BUFFERS)` output proving **0.088 ms partition pruning**.
- [`evidence/02_distributed_2pc_output.txt`](evidence/02_distributed_2pc_output.txt): Confirms two-phase commit execution, inspection of `pg_prepared_xacts`, and crash-recovery `ROLLBACK PREPARED`.
- [`evidence/03_mongodb_sharding_output.txt`](evidence/03_mongodb_sharding_output.txt): Confirms cluster topology, zone-aware shard tag configuration, and targeted router vs scatter-gather execution traces.

---

## 8. Reproduction Guide

To execute all distributed tests:

```bash
cd portfolio-5-distributed-cloud
./run_distributed_demos.sh ekomart postgres localhost 5432
```
