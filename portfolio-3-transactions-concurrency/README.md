# Portfolio 3: Transactions and Concurrency

**Course:** MIT 8103 Advanced Database Systems (Miva Open University)  
**Case Study:** EkoMart Online (Simulated Nigerian E-Commerce Platform)  
**Database System:** PostgreSQL 16 / 18  
**Topic:** Transaction Management, ACID Properties, Isolation Levels, and Concurrency Control  

---

## 1. Executive Summary

In high-throughput e-commerce systems like **EkoMart Online**, database operations must balance two competing objectives: **data consistency** and **concurrent throughput**. When multiple customers across Lagos, Abuja, and Port Harcourt simultaneously attempt to purchase limited inventory, record payments, and generate shipping orders, uncoordinated concurrent database access leads to catastrophic data anomalies: lost updates, negative inventory, dirty reads, and deadlocks.

This portfolio presents a comprehensive practical and theoretical investigation into **transaction processing, ACID enforcement, PostgreSQL transaction isolation levels, and concurrency control mechanisms**.

### Core Deliverables Demonstrated:
1. **Atomic Multi-Table Checkout:** Orchestrating order creation, inventory decrements, payment verification, and shipment scheduling atomically, with complete `ROLLBACK` on payment decline and resilient recovery using `SAVEPOINT`.
2. **The "Flash Sale" Race Condition (Lost Update):** Reproducing the classic lost update anomaly where uncoordinated reads and writes cause stock deficits to be overwritten.
3. **Pessimistic Concurrency Control:** Resolving race conditions using row-level exclusive locks (`SELECT ... FOR UPDATE`), evaluating the `pg_locks` catalogue, and exploring `NOWAIT` and `SKIP LOCKED`.
4. **Isolation Levels Benchmarking:** Comparing `READ COMMITTED`, `REPEATABLE READ` (Snapshot Isolation & Serialization Failure `40001`), and `SERIALIZABLE` (SSI).
5. **Deadlock Analysis & Prevention:** Simulating circular wait deadlocks (`SQLSTATE 40P01`) and mathematically eliminating them using **Deterministic Resource Ordering** (`ORDER BY product_id ASC`).

---

## 2. ACID Properties Implementation in EkoMart

Transactions in EkoMart ensure reliability through the four ACID pillars:

| Property | Real-World EkoMart Scenario | Database Enforcement Mechanism | Anomaly Prevented |
|---|---|---|---|
| **Atomicity** | Customer orders 2 items; card payment gateway times out mid-checkout | `BEGIN ... ROLLBACK` or `SAVEPOINT` | Orphaned order records without payment; inventory reserved without payment |
| **Consistency** | Stock decrement cannot reduce inventory below zero; payments require timestamp | Schema constraints: `CHECK (quantity_on_hand >= 0)`, `CHECK (amount > 0)`, Foreign Keys | Negative warehouse stock; fraudulent or corrupt ledger entries |
| **Isolation** | 50 customers buying the last 5 iPhone units during a flash sale | Row-level locks (`FOR UPDATE`) & Snapshot Isolation | Lost updates; phantom stock; overselling |
| **Durability** | Server hardware crash immediately following payment confirmation | Write-Ahead Logging (WAL) & synchronous commit | Loss of confirmed customer orders upon system reboot |

---

## 3. Atomic Checkout, Rollbacks & Savepoints

The script [`sql/01_atomic_checkout_rollback.sql`](sql/01_atomic_checkout_rollback.sql) implements the complete EkoMart checkout lifecycle.

### 3.1 Successful Atomic Execution
An e-commerce order spans five interdependent relational tables:
```
customer_order ──> order_item ──> inventory (update) ──> payment ──> shipment
```
When encapsulated inside a transaction block (`BEGIN ... COMMIT`), either **all five steps persist**, or **none do**.

```sql
BEGIN;
INSERT INTO customer_order (customer_id, shipping_address_id, status) VALUES (1, 1, 'PENDING');
INSERT INTO order_item (order_id, line_no, product_id, quantity, unit_price) VALUES (currval(...), 1, 10, 2, 15000.00);
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 2 WHERE warehouse_id = 1 AND product_id = 10;
INSERT INTO payment (order_id, amount, method, status, reference, paid_at) VALUES (currval(...), 30000.00, 'CARD', 'SUCCESS', 'TXN-101', now());
UPDATE customer_order SET status = 'PAID' WHERE order_id = currval(...);
INSERT INTO shipment (order_id, warehouse_id, courier, tracking_no, status) VALUES (currval(...), 1, 'GIG Logistics', 'TRK-101', 'PREPARING');
COMMIT;
```

### 3.2 Atomic Rollback on Failure
When a payment gateway declines a card or raises an exception:
```sql
\echo 'Gateway Response: CARD_DECLINED'
ROLLBACK;
```
- **Result:** The reserved inventory is immediately returned to its original level, and no partial `customer_order` or `order_item` records are left in the database.

### 3.3 Resilient Recovery via `SAVEPOINT`
In modern e-commerce, aborting the entire transaction when a payment fails is bad user experience, as it empties the customer's cart. With `SAVEPOINT`:
```sql
SAVEPOINT order_prepared;
-- Attempt Card Payment -> Fails
ROLLBACK TO SAVEPOINT order_prepared;
-- Fallback to Bank Transfer -> Succeeds
INSERT INTO payment (..., method) VALUES (..., 'BANK_TRANSFER');
COMMIT;
```
The order and reserved items remain intact while the payment attempt is retried.

---

## 4. The Flash Sale Race Condition (The Lost Update Anomaly)

The script [`sql/02_lost_update_race_condition.sql`](sql/02_lost_update_race_condition.sql) demonstrates what happens when two transactions execute concurrently without concurrency controls.

### 4.1 Chronological Anomaly Trace

- **Initial State:** Product 99 at Lagos Hub has `quantity_on_hand = 5`.
- **Customer A** attempts to buy 3 units.
- **Customer B** attempts to buy 4 units.
- **Combined Demand:** 7 units (exceeds inventory by 2).

```
Timeline:
[t0] Session A: BEGIN; SELECT quantity_on_hand FROM inventory WHERE product_id=99;  --> Reads 5
[t1] Session B: BEGIN; SELECT quantity_on_hand FROM inventory WHERE product_id=99;  --> Reads 5 (Unaware of A)
[t2] Session A computes 5 - 3 = 2:
     UPDATE inventory SET quantity_on_hand = 2 WHERE product_id=99;
     COMMIT;                                                                        --> Stock in DB = 2
[t3] Session B computes 5 - 4 = 1 (based on stale read of 5):
     UPDATE inventory SET quantity_on_hand = 1 WHERE product_id=99;
     COMMIT;                                                                        --> Stock in DB = 1!
```

### 4.2 Impact Analysis
- 7 physical items were sold to two customers.
- Physical stock should be $-2$ (oversold).
- However, the database records `quantity_on_hand = 1`.
- **Customer A's update was completely LOST.** The business will attempt to fulfill orders it cannot physically deliver.

---

## 5. Concurrency Control: Pessimistic Row-Level Locking

The script [`sql/03_pessimistic_locking_for_update.sql`](sql/03_pessimistic_locking_for_update.sql) resolves the race condition using **Pessimistic Concurrency Control**.

### 5.1 Mechanism: `SELECT ... FOR UPDATE`

```sql
BEGIN;
SELECT quantity_on_hand 
FROM inventory 
WHERE warehouse_id = 1 AND product_id = 99
FOR UPDATE;
```

1. **Lock Acquisition:** Session A acquires an exclusive `RowShareLock` / `ExclusiveLock` on the target row tuple.
2. **Forced Serialisation:** When Session B requests the same row `FOR UPDATE`, PostgreSQL pauses Session B, placing it in a waiting queue.
3. **Committed State Re-read:** When Session A updates stock ($5 - 3 = 2$) and commits, Session A releases the lock.
4. **Conditional Safety:** Session B immediately wakes up, locks the row, and re-reads the *fresh, committed stock* ($2$).
5. **Rejection:** In the PL/pgSQL evaluation block:
   ```sql
   IF v_stock >= v_demand THEN
       UPDATE inventory ...;
   ELSE
       RAISE NOTICE 'REJECTED: Demanded 4 units, but only 2 available.';
   END IF;
   ```
   Customer B's order is cleanly rejected, and stock remains exactly 2. Overselling is 100% prevented.

### 5.2 Non-Blocking Locking Modifiers: `NOWAIT` & `SKIP LOCKED`

In ultra-high-traffic checkout events, waiting on locks can exhaust database connection pools:
- **`SELECT ... FOR UPDATE NOWAIT`:** Rather than blocking, immediately returns `ERROR: could not obtain lock on row in relation "inventory"` (`SQLSTATE 55P03`). The application instantly notifies the user that another buyer is currently purchasing that item.
- **`SELECT ... FOR UPDATE SKIP LOCKED`:** Ideal for background warehouse dispatch workers picking orders. Workers skip rows locked by other workers, preventing contention across concurrent queues.

---

## 6. Comparative Analysis of Transaction Isolation Levels

The script [`sql/04_isolation_levels_comparison.sql`](sql/04_isolation_levels_comparison.sql) evaluates ANSI SQL isolation levels as implemented in PostgreSQL:

| Isolation Level | Dirty Read ($G_1$) | Non-Repeatable Read ($G_{2a}$) | Phantom Read ($A3$) | Serialization Anomaly / Write Skew | PostgreSQL Concurrency Behavior |
|---|---|---|---|---|---|
| **READ COMMITTED** *(Default)* | **Prevented** | Allowed | Allowed | Allowed | Takes a new snapshot at the start of *each SQL statement*. Reading the same row twice in one transaction can yield different data if an external transaction committed in between. |
| **REPEATABLE READ** | **Prevented** | **Prevented** | **Prevented** | Allowed | Uses **Snapshot Isolation**. All statements in the transaction see the exact same snapshot taken at the start of the *transaction*. Employs **First-Committer-Wins**: concurrent update to the same row triggers `ERROR 40001: could not serialize access`. |
| **SERIALIZABLE** | **Prevented** | **Prevented** | **Prevented** | **Prevented** | Uses **Serializable Snapshot Isolation (SSI)**. Tracks SIREAD locks in shared memory to detect cycles in the serialization graph ($rw$-antidependency cycles). Guarantees true serial equivalence. |

---

## 7. Deadlock Analysis, Detection & Prevention

The script [`sql/05_deadlock_detection_ordering.sql`](sql/05_deadlock_detection_ordering.sql) addresses multi-resource locking contention.

### 7.1 The Circular Wait Mechanism

A deadlock occurs when two transactions hold locks on resources the other requires:
```
Session 1 holds Lock(Product 101) ───waits for───> Lock(Product 102) [Held by Session 2]
    ▲                                                              │
    └──────────────────waits for───────────────────────────────────┘
```

When this cycle forms, PostgreSQL's internal background deadlock engine wakes up after `deadlock_timeout` (default: 1 second), inspects the lock wait-for graph, selects one transaction as a victim, and terminates it:
```text
ERROR:  deadlock detected
DETAIL: Process 28412 waits for ExclusiveLock on tuple (0,15) of relation "inventory"; 
        blocked by process 28415.
        Process 28415 waits for ExclusiveLock on tuple (0,14) of relation "inventory"; 
        blocked by process 28412.
HINT:   See server log for query details.
SQLSTATE: 40P01
```

### 7.2 Deadlock Prevention: Deterministic Lock Acquisition Ordering

Rather than relying on reactive deadlock aborts, we implement **Deterministic Resource Ordering**:

```sql
-- Always acquire locks in canonical ascending primary key order:
SELECT warehouse_id, product_id, quantity_on_hand
FROM inventory
WHERE warehouse_id = 1 AND product_id IN (102, 101)
ORDER BY product_id ASC
FOR UPDATE;
```

#### Mathematical Proof:
Let all resources $R$ possess a total ordering defined by their primary key: $r_1 < r_2 < \dots < r_n$.  
If every transaction acquires locks in strictly increasing order ($r_i$ before $r_j$ where $i < j$), it is mathematically impossible to produce a directed cycle in the resource allocation graph ($DAG$). Thus, **deadlocks are eliminated by design**.

---

## 8. Technical Reflection & Design Trade-offs

### 1. Lock Contention vs Throughput
While pessimistic locking (`SELECT ... FOR UPDATE`) guarantees zero lost updates, holding row locks during slow external operations (e.g., waiting for an HTTP response from Paystack or Flutterwave) holds database resources hostage, causing thread starvation.
**Best Practice in EkoMart:** Pre-allocate stock with a short TTL reservation, execute external payment over HTTP, and finalize the database transaction in under 10 milliseconds.

### 2. Pessimistic vs Optimistic Concurrency Control (OCC)
- **Pessimistic Locking** is ideal when write conflict probability is high (flash sales, high-demand items).
- **Optimistic Concurrency Control** (using version columns: `WHERE version = expected_version`) is superior when conflicts are rare (e.g., updating user profiles), as it avoids lock overhead entirely.

### 3. Distributed Implications (Transition to Portfolio 5)
In a single-instance PostgreSQL database, ACID transactions rely on shared memory lock managers and local WAL. When EkoMart shards orders by Nigerian geopolitical zones across independent database nodes in Portfolio 5, local `BEGIN ... COMMIT` cannot span nodes. Distributed consistency will require Two-Phase Commit (2PC) or asynchronous Saga patterns.

---

## 9. Reproduction Guide & Evidence Execution

To run all concurrency demonstrations against your PostgreSQL instance:

```bash
cd portfolio-3-transactions-concurrency
./run_concurrency_demos.sh ekomart postgres localhost 5432
```

Outputs will be saved in `evidence/`:
- `evidence/01_atomic_rollback_output.txt`
- `evidence/02_race_condition_output.txt`
- `evidence/03_pessimistic_locking_output.txt`
- `evidence/04_isolation_levels_output.txt`
- `evidence/05_deadlock_output.txt`
