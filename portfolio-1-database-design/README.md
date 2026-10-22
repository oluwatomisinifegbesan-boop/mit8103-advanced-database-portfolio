# Portfolio 1: Database Design and Modelling

## 1. Case study: EkoMart Online

**Organisation:** EkoMart Online is a simulated Nigerian e-commerce platform that sells electronics, fashion, home goods, groceries and beauty products to customers in all 36 states and the FCT.

| Item | Description |
|---|---|
| Nature of the business | Online retail marketplace with its own warehouses in Lagos, Abuja, Kano, Port Harcourt and Onitsha. It buys stock from third-party suppliers. |
| Database users | Customers (browse, order, pay, review). Customer-service staff (look up orders, process refunds). Warehouse staff (stock levels, dispatch). Management (sales reports). |
| Major data stored | Customers and delivery addresses, product catalogue and categories, suppliers, warehouse stock, orders and order lines, payments, shipments, product reviews. |
| Key operations | Register customer, add or update products, place an order (check stock, then decrement it), record a payment, dispatch and track a shipment, cancel or refund an order, post a review, run sales reports. |

The same case study is used in all five portfolios:

| Portfolio | How EkoMart is used |
|---|---|
| 2 | Optimising sales reports and order lookups |
| 3 | Placing orders and handling payments while many customers buy the same stock |
| 4 | Flexible product attributes and shopping carts in MongoDB |
| 5 | Replicating and sharding orders by region |

## 2. Files

| File | Purpose |
|---|---|
| `er-diagram.md` | ER diagram in crow's-foot notation, as Mermaid. GitHub renders it. |
| `sql/01_schema.sql` | Creates the `ekomart` schema with 13 tables, 1 view, keys and constraints. |
| `sql/02_seed_data.sql` | Reference data plus reproducible bulk data: 20k customers, 2k products, 200k orders, 500k order lines. |
| `sql/03_constraint_tests.sql` | 17 tests showing each constraint rejects invalid data. |
| `evidence/` | Saved output: constraint test results, table descriptions, row counts. |

### How to run

```bash
createdb ekomart
psql -d ekomart -f sql/01_schema.sql
psql -d ekomart -f sql/02_seed_data.sql        # about 30 seconds
psql -d ekomart -f sql/03_constraint_tests.sql
```

Tested on PostgreSQL 16 and 18.

## 3. Entities and relationships

| Relationship | Cardinality | How it is implemented |
|---|---|---|
| Region to State | 1 : N | `state.region_id` FK |
| Customer to Address | 1 : N | `address.customer_id` FK, `ON DELETE CASCADE` |
| Customer to Order | 1 : N | `customer_order.customer_id` FK |
| Category to Category | 1 : N (recursive) | `category.parent_category_id` self-referencing FK |
| Order to Product | **M : N** | Resolved by the associative entity `order_item` |
| Warehouse to Product | **M : N** | Resolved by `inventory`, which also holds stock level |
| Order to Shipment | 1 : 0..1 | `shipment.order_id` is FK **and** UNIQUE |
| Order to Payment | 1 : N | Allows a failed attempt followed by a successful one |
| Customer to Product (review) | M : N | `review`, UNIQUE (product_id, customer_id) |

## 4. Keys

- **Surrogate primary keys** (`GENERATED ALWAYS AS IDENTITY`) on most tables. They are small, stable and never change, which makes them good targets for joins and foreign keys.
- **Natural / alternate keys** are kept as `UNIQUE` constraints: `product.sku`, `customer.email`, `payment.reference`, `shipment.tracking_no`. A surrogate key alone would allow two rows for the same real-world thing. For example, the same gateway payment could be recorded twice.
- **Composite primary keys** where the entity is identified by its parent:
  - `order_item (order_id, line_no)`
  - `inventory (warehouse_id, product_id)`
- **Foreign keys** on every relationship. `ON DELETE CASCADE` is used only where the child cannot exist without its parent (address, order lines). Everything else uses the default `NO ACTION`, so a product that has been sold cannot be deleted. Products are deactivated with `is_active = false` instead.

## 5. Constraints (business rules enforced by the database)

| Rule | Constraint |
|---|---|
| Stock can never go negative | `CHECK (quantity_on_hand >= 0)` |
| Prices and quantities must be positive | `CHECK (unit_price > 0)`, `CHECK (quantity > 0)` |
| Order, payment and shipment status must be one of a fixed set | `CHECK (status IN (...))` |
| Ratings are 1 to 5 | `CHECK (rating BETWEEN 1 AND 5)` |
| One review per customer per product | `UNIQUE (product_id, customer_id)` |
| The same product appears at most once per order | `UNIQUE (order_id, product_id)` |
| A successful payment must have a payment time | `CHECK (status <> 'SUCCESS' OR paid_at IS NOT NULL)` |
| Delivery cannot happen before dispatch | `CHECK (delivered_at >= shipped_at)` |
| At most one default address per customer | Partial unique index `ON address (customer_id) WHERE is_default` |
| Valid email and phone formats | Regex `CHECK` constraints |

All 17 constraint tests pass. Full output is in [`evidence/constraint_test_results.txt`](evidence/constraint_test_results.txt).

## 6. Normalisation

The design was normalised step by step from a single flat "order record" a business might keep in a spreadsheet:

```
ORDER_RECORD(order_id, order_date, customer_name, customer_email, customer_phone,
             delivery_address, state, region,
             {product_sku, product_name, category, supplier, supplier_email, qty, price}, ...,
             payment_ref, payment_method, courier, tracking_no)
```

**First normal form (1NF).** The repeating group of products is moved into its own rows, so every column holds one atomic value. Each row is identified by (order_id, product_sku).

**Second normal form (2NF).** With the composite key (order_id, product_sku), several attributes depend on only *part* of the key. These partial dependencies are removed:
- `order_date, customer_*, delivery_address` depend only on `order_id`. They move to `customer_order`.
- `product_name, category, supplier` depend only on `product_sku`. They move to `product`.
- Only `quantity` and `unit_price` depend on the whole key. They stay in `order_item`.

**Third normal form (3NF).** Transitive dependencies (non-key attribute depends on another non-key attribute) are removed:
- `order_id → customer_id → customer_email, phone`. Customer details move to `customer`.
- `address → state → region`. This gives `address.state_id`, then `state.region_id`, then `region`.
- `product → supplier_id → supplier_email`. Supplier details move to `supplier`.
- `product → category → parent_category`. This gives the `category` hierarchy.

**BCNF.** In every table, each determinant is a candidate key. For example, in `inventory` the only determinant is (warehouse_id, product_id). In `product`, both `product_id` and `sku` are candidate keys, and both are declared (PK and UNIQUE).

### Deliberate design decisions

1. **`order_item.unit_price` is kept even though `product.unit_price` exists.** This is not redundancy. The order line stores the price *at the time of sale*, which is a different fact from the current catalogue price. Without it, a price change would silently change every past invoice.
2. **The order total is not stored.** It is derived (`SUM(quantity * unit_price)`) and exposed through the `order_summary` view. A stored total could fall out of step with the order lines. Portfolio 2 measures whether the computation is fast enough.
3. **`customer_order.shipping_address_id` points to an address row.** It does not copy the address text. Because addresses can be edited, a real system would either make addresses immutable after use or snapshot them. This is noted as a known limitation.
4. **`order` is a reserved word in SQL**, so the table is named `customer_order`.

## 7. Evidence

| Evidence | Shows |
|---|---|
| [`evidence/er_diagram.png`](evidence/er_diagram.png) | ER diagram exported as an image |
| [`evidence/01_schema_created.png`](evidence/01_schema_created.png) | `01_schema.sql` running in psql: 13 tables, 1 view, 2 indexes created |
| [`evidence/02_seed_row_counts.png`](evidence/02_seed_row_counts.png) | `02_seed_data.sql` loading 200,000 orders and 500,000 order lines |
| [`evidence/03_tables_and_sample_orders.png`](evidence/03_tables_and_sample_orders.png) | Table list and sample rows from the `order_summary` view |
| [`evidence/constraint_test_results.txt`](evidence/constraint_test_results.txt) | All 17 constraint tests PASS |
| [`evidence/schema_description.txt`](evidence/schema_description.txt) | `\dt` and `\d` output for the main tables |
| [`evidence/row_counts.txt`](evidence/row_counts.txt) | Row count of every table after seeding |
