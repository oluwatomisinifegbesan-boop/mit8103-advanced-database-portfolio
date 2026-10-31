# Portfolio 4: NoSQL and Advanced Data Models

**Course:** MIT 8103 Advanced Database Systems (Miva Open University)  
**Case Study:** EkoMart Online (Simulated Nigerian E-Commerce Platform)  
**NoSQL Database:** MongoDB 7.0+ (Document Data Model)  
**Architecture:** Polyglot Persistence (PostgreSQL for ACID Transactions + MongoDB for Flexible Catalogues & Sessions)  

---

## 1. Executive Summary

In Portfolios 1, 2, and 3, **EkoMart Online** established a normalised (3NF/BCNF) PostgreSQL schema to guarantee transactional consistency, ACID properties, and relational constraints across core sales, payment processing, and inventory balances. However, real-world enterprise e-commerce platforms encounter two severe architectural challenges where traditional relational databases exhibit structural bottlenecks:

1. **High Polymorphism in Product Catalogues:** A modern marketplace offers tens of thousands of products spanning diverse categories—smartphones (screen size, RAM, battery, 5G), fashion (fabric, size, cut, embroidery), groceries (weight, shelf life, NAFDAC number, allergens), and cosmetics (skin type, organic certifications, ingredients). Forcing these varying attributes into rigid relational tables produces either null-riddled sparse tables or the notoriously inefficient **Entity-Attribute-Value (EAV)** anti-pattern.
2. **High-Throughput Ephemeral Shopping Carts:** Millions of shopper sessions continuously create, update, and abandon shopping carts. In relational engines, purging stale sessions demands recurring batch `DELETE` queries that cause table bloat, vacuum overhead, and row-lock contention.

This portfolio presents the design, implementation, and empirical verification of **EkoMart's NoSQL Document Layer** built with **MongoDB 7.0**:
- **JSON Schema Validation:** Enforcing domain-level constraints on mandatory metadata while allowing dynamic, schema-flexible category attributes.
- **Embedded vs. Referenced Data Modeling:** Eliminating expensive joins by embedding item variants and shopping cart items directly within parent documents.
- **Automated Lifecycle Management via TTL Indexes:** Leveraging MongoDB's internal `ttlMonitor` thread to automatically evict abandoned carts without application overhead.
- **Advanced NoSQL Indexing:** Deploying compound, multi-key array, nested sub-document, partial, and full-text search indexes.
- **Multi-Stage Aggregation Pipelines:** Executing complex analytics ($match, $unwind, $group, $project, $facet) that rival and exceed relational SQL analytical workflows.

---

## 2. Relational Limitations vs. Document Model Suitability

### 2.1 The Relational Catalogue Bottleneck: EAV vs. Polymorphic Documents

In a relational database, accommodating variable product attributes requires one of three compromises:

| Architectural Approach | Implementation in RDBMS | Limitations & Bottlenecks |
|---|---|---|
| **Sparse Table** | Add a column for every possible attribute to `product` | 90%+ of columns contain `NULL`; schema migrations required for every new category; exceeds row size limits. |
| **Entity-Attribute-Value (EAV)** | Three tables: `product`, `attribute_name`, `product_attribute_value` | Destroys referential integrity; requires $N$ self-joins to query a single product; severe performance degradation. |
| **Relational JSONB** | Store attributes in a PostgreSQL `JSONB` column | Functional, but lack of collection-level schema enforcement; complex syntax; table bloat during frequent in-place updates. |
| **Native Document Model (MongoDB)** | Natural JSON/BSON document per product | **Optimal:** Native sub-documents, multi-key indexes on arrays, schema validation, and atomic document updates. |

### 2.2 Ephemeral Shopping Carts & Lifecycle Purging

Approximately 70% of e-commerce carts are abandoned. In PostgreSQL:
```sql
-- Relational cleanup: requires cron job inducing heavy disk I/O and lock contention
DELETE FROM shopping_cart WHERE updated_at < NOW() - INTERVAL '7 days';
VACUUM ANALYZE shopping_cart;
```
In MongoDB, a **Time-To-Live (TTL) index** delegates this task entirely to the engine's background thread, evicting documents with zero application intervention.

---

## 3. Polyglot Architecture & Document Schema Design

EkoMart adopts a **Polyglot Persistence Architecture**:

```
 ┌────────────────────────────────────────────────────────┐
 │                   EkoMart Web & Mobile                 │
 └──────────────┬──────────────────────────┬──────────────┘
                │                          │
        (Product Discovery &        (Checkout, Payments,
           Shopping Carts)            Shipments, Audits)
                ▼                          ▼
 ┌─────────────────────────────┐  ┌───────────────────────┐
 │     MongoDB 7.0 (NoSQL)     │  │   PostgreSQL (RDBMS)  │
 │  - Flexible Product Cat.    │  │  - customer_order     │
 │  - Polymorphic Attributes   │  │  - order_item         │
 │  - High-Speed Text Search   │  │  - payment            │
 │  - Ephemeral Carts (TTL)    │  │  - shipment           │
 └─────────────────────────────┘  └───────────────────────┘
```

### 3.1 Collection-Level JSON Schema Validation

Implemeted in [`scripts/01_schema_validation.js`](scripts/01_schema_validation.js), MongoDB's `$jsonSchema` ensures structural consistency while permitting attribute flexibility:

```javascript
db.createCollection("products", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["sku", "title", "category", "price", "is_active", "created_at"],
      properties: {
        sku: { bsonType: "string", pattern: "^EKM-[A-Z0-9]{3,8}$" },
        title: { bsonType: "string", minLength: 3, maxLength: 200 },
        category: { 
          bsonType: "string", 
          enum: ["Electronics", "Fashion", "Groceries", "Health & Beauty", "Home & Kitchen"] 
        },
        price: { bsonType: ["double", "int", "decimal"], minimum: 0.01 },
        is_active: { bsonType: "bool" },
        attributes: { bsonType: "object" }, // Polymorphic category specs!
        variants: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["variant_id", "sku_suffix", "price_modifier"],
            properties: {
              variant_id: { bsonType: "string" },
              sku_suffix: { bsonType: "string" },
              price_modifier: { bsonType: ["double", "int", "decimal"] },
              stock: { bsonType: "int", minimum: 0 }
            }
          }
        },
        tags: { bsonType: "array", items: { bsonType: "string" } },
        created_at: { bsonType: "date" }
      }
    }
  }
});
```

### 3.2 Embedding vs. Referencing Design Decision

- **Embedded Variants:** Product variants (sizes, colors, storage options) are embedded directly within the product document. Because variants are always retrieved alongside the parent product and rarely exceed 20 entries, embedding avoids an expensive join and guarantees **atomic updates** within a single document boundary.
- **Embedded Cart Items:** A shopping cart embeds its item lines. Reading the cart takes exactly **one disk read** ($O(1)$) rather than a multi-table relational join (`shopping_cart` JOIN `cart_item` JOIN `product`).

---

## 4. Ephemeral Carts & MongoDB TTL Expiration

Implemented in [`scripts/04_ttl_cart_expiration.js`](scripts/04_ttl_cart_expiration.js), EkoMart establishes automated session lifecycles.

### 4.1 TTL Index Specification
```javascript
// Automatically expire carts 7 days (604,800 seconds) after last update
db.shopping_carts.createIndex(
  { updated_at: 1 },
  { expireAfterSeconds: 604800, name: "idx_cart_ttl_7days" }
);

// Advanced Partial TTL: Purge explicitly ABANDONED carts after 24 hours
db.shopping_carts.createIndex(
  { updated_at: 1 },
  { 
    expireAfterSeconds: 86400, 
    partialFilterExpression: { status: "ABANDONED" },
    name: "idx_partial_ttl_abandoned" 
  }
);
```

### 4.2 Sliding-Window Session Renewal
Whenever a customer modifies an active cart, MongoDB executes an atomic update that resets `updated_at` to `new Date()`, automatically extending the TTL expiration window:

```javascript
db.shopping_carts.updateOne(
  { customer_id: 101, status: "ACTIVE" },
  {
    $push: { items: newItem },
    $inc: { cart_total: 6500.00 },
    $set: { updated_at: new Date() } // Resets the 7-day TTL countdown!
  }
);
```

---

## 5. Advanced NoSQL Indexing Strategies

Implemented in [`scripts/03_polymorphic_queries_and_indexes.js`](scripts/03_polymorphic_queries_and_indexes.js):

| Index Name | Specification | Type | Query Acceleration |
|---|---|---|---|
| `idx_products_sku_unique` | `{ sku: 1 }` | Unique B-Tree | Guarantees SKU alternate key integrity. |
| `idx_products_cat_price` | `{ category: 1, price: 1 }` | Compound B-Tree | Accelerates catalogue category filtering sorted by price. |
| `idx_products_tags_multikey` | `{ tags: 1 }` | Multi-Key Index | Indexes every discrete element in the `tags` array. |
| `idx_products_specs_ram` | `{ "attributes.ram_gb": 1 }` | Sub-document B-Tree | Allows fast lookups on nested technical specifications. |
| `idx_products_text_search` | `{ title: "text", brand: "text", tags: "text" }` | Inverted Text Index | Full-text relevance ranking with custom weights (`title: 10, brand: 5`). |
| `idx_one_active_cart` | `{ customer_id: 1 }` | Partial Unique Index | Enforces that a customer has at most one `ACTIVE` cart session. |

---

## 6. Multi-Stage Aggregation Pipelines vs. Relational SQL

Implemented in [`scripts/05_aggregation_pipeline.js`](scripts/05_aggregation_pipeline.js), MongoDB Aggregation Pipelines replace relational `JOIN`, `GROUP BY`, and `HAVING` operations.

### 6.1 Comparison: Relational SQL vs. MongoDB Pipeline Stages

| Operation | PostgreSQL SQL Equivalent | MongoDB Aggregation Stage |
|---|---|---|
| **Filter** | `WHERE is_active = true` | `$match: { is_active: true }` |
| **Array Deconstruction** | `CROSS JOIN LATERAL UNNEST(variants)` | `$unwind: "$variants"` |
| **Group & Aggregate** | `GROUP BY category, SUM(...), AVG(...)` | `$group: { _id: "$category", ... }` |
| **Field Projection / Math** | `SELECT col AS alias, ROUND(...)` | `$project: { ... }` |
| **Ordering** | `ORDER BY total_value DESC` | `$sort: { total_inventory_value_ngn: -1 }` |
| **Multi-Query Faceting** | 3 separate `SELECT` queries | `$facet: { price_ranges: [...], brand_dist: [...] }` |

### 6.2 Key Aggregation Pipeline Outputs

1. **Pipeline 1: Category Inventory Valuation Summary**
   - Deconstructs variants across all active products.
   - Calculates total distinct SKUs, total physical stock on hand, min/max price, and estimated total inventory valuation in Nigerian Naira (NGN).
2. **Pipeline 2: Variant-Level Low-Stock Reorder Alert**
   - Filters embedded variants where `stock <= 15`.
   - Generates automated replenishment notices with dynamic conditional urgency flags (`CRITICAL` vs `WARNING`) via `$cond`.
3. **Pipeline 3: Multi-Faceted E-Commerce Search (`$facet`)**
   - In a **single database roundtrip**, computes:
     - Automatic price histogram buckets (`$bucket`).
     - Brand market share distribution (`$sortByCount`).
     - Tag cloud frequencies (`$sortByCount`).
4. **Pipeline 4: Cart Conversion & Pipeline Value**
   - Aggregates live cart sessions by status (`ACTIVE`, `ABANDONED`) to provide instant marketing revenue estimates.

---

## 7. Distributed Consistency, CAP / PACELC, and Storage Engine

### 7.1 Storage Engine: WiredTiger
MongoDB uses the **WiredTiger** storage engine:
- **Document-Level Concurrency:** Provides ticket-based concurrency with document-level locking, ensuring that concurrent cart writes never block adjacent sessions.
- **Snappy Compression:** Reduces on-disk catalogue footprint by up to 60% compared to uncompressed relational tables.
- **Checkpointing & Journaling:** Writes changes to an append-only write-ahead log (journal) every 100ms or on sync, ensuring Durability ($D$ in ACID).

### 7.2 CAP Theorem & PACELC Analysis
- **Under CAP:** MongoDB is typically classified as a **CP** system (Consistency over Partition tolerance). In the event of network partition across a replica set, secondary nodes reject writes until a new primary is elected.
- **Under PACELC:** If partitioned ($P$), trade off Availability ($A$) for Consistency ($C$); Else ($E$), trade off Latency ($L$) for Consistency ($C$).
- **Configurable Consistency in EkoMart:**
  - **Catalogue Reads:** `readPreference: "nearest"` (optimises latency for Nigerian mobile shoppers across regions).
  - **Checkout / Order Handover:** `writeConcern: { w: "majority", j: true }` (guarantees acknowledgement only after persistence to the majority of nodes).

---

## 8. Empirical Evidence & Output Logs

All scripts have been executed and validated against a live **MongoDB 7.0 engine**. Output artifacts are preserved in the [`evidence/`](evidence/) directory:

- [`evidence/01_schema_validation_output.txt`](evidence/01_schema_validation_output.txt): Confirms creation of `products` and `shopping_carts` collections with strict `$jsonSchema` rules.
- [`evidence/02_seed_output.txt`](evidence/02_seed_output.txt): Confirms seeding of diverse polymorphic product models and shopping cart sessions.
- [`evidence/03_polymorphic_queries_output.txt`](evidence/03_polymorphic_queries_output.txt): Demonstrates nested sub-document queries, multi-key array lookups, full-text search scores, and `$elemMatch`.
- [`evidence/04_ttl_cart_output.txt`](evidence/04_ttl_cart_output.txt): Demonstrates 7-day TTL index creation, sliding-window session updates, and `ttlMonitor` cutoff evaluation.
- [`evidence/05_aggregation_output.txt`](evidence/05_aggregation_output.txt): Displays formatted JSON output for category valuations, low-stock reorder alerts, faceted sidebar results, and cart revenue metrics.

---

## 9. Reproduction Guide

To execute the test suite locally:

### Option A: Using the Automated Runner (Docker or Local mongosh)
```bash
cd portfolio-4-nosql
./run_nosql_demos.sh
```

### Option B: Using Local `mongosh` Manually
```bash
mongosh "mongodb://localhost:27017/ekomart_nosql" --file scripts/01_schema_validation.js
mongosh "mongodb://localhost:27017/ekomart_nosql" --file scripts/02_seed_catalogue_and_carts.js
mongosh "mongodb://localhost:27017/ekomart_nosql" --file scripts/03_polymorphic_queries_and_indexes.js
mongosh "mongodb://localhost:27017/ekomart_nosql" --file scripts/04_ttl_cart_expiration.js
mongosh "mongodb://localhost:27017/ekomart_nosql" --file scripts/05_aggregation_pipeline.js
```
