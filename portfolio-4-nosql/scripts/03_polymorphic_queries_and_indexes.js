// =====================================================================
// MIT 8103 Advanced Database Systems - Portfolio 4
// Case study: EkoMart Online (simulated Nigerian e-commerce platform)
// File: scripts/03_polymorphic_queries_and_indexes.js
// Target: MongoDB 7.0+ / mongosh
//
// Description:
// Demonstrates advanced NoSQL indexing strategies and polymorphic
// document queries:
// 1. Compound B-Tree Indexes
// 2. Multi-Key Indexes on Array Elements
// 3. Sub-document Field Indexing (Nested Objects)
// 4. Text Search Indexes (Search & Relevance)
// =====================================================================

db = db.getSiblingDB("ekomart_nosql");

// ---------------------------------------------------------------------
// 1. INDEX DEFINITIONS
// ---------------------------------------------------------------------

// Unique alternate key on SKU
db.products.createIndex({ sku: 1 }, { unique: true, name: "idx_products_sku_unique" });

// Compound index for category browsing and price range sorting
db.products.createIndex({ category: 1, price: 1 }, { name: "idx_products_cat_price" });

// Multi-key index on tags array (indexes every string element in the array)
db.products.createIndex({ tags: 1 }, { name: "idx_products_tags_multikey" });

// Sub-document index on nested technical specifications
db.products.createIndex({ "attributes.ram_gb": 1 }, { name: "idx_products_specs_ram" });
db.products.createIndex({ "attributes.skin_type": 1 }, { name: "idx_products_specs_skintype" });

// Text search index for catalogue discovery
db.products.createIndex(
  { title: "text", brand: "text", tags: "text" },
  { weights: { title: 10, brand: 5, tags: 2 }, name: "idx_products_text_search" }
);

// Unique partial index on active shopping carts (a customer can have at most one ACTIVE cart)
db.shopping_carts.createIndex(
  { customer_id: 1 },
  { unique: true, partialFilterExpression: { status: "ACTIVE" }, name: "idx_one_active_cart_per_customer" }
);

print("Created 6 specialized NoSQL indexes successfully.");


// ---------------------------------------------------------------------
// 2. POLYMORPHIC QUERIES DEMONSTRATION
// ---------------------------------------------------------------------

print("\n--- QUERY 1: Nested Subdocument Query (Laptops with >= 16GB RAM) ---");
const highRamLaptops = db.products.find(
  { 
    category: "Electronics", 
    "attributes.ram_gb": { $gte: 16 } 
  },
  { 
    sku: 1, 
    title: 1, 
    price: 1, 
    "attributes.processor": 1, 
    "attributes.ram_gb": 1, 
    "attributes.gpu": 1 
  }
).toArray();
printjson(highRamLaptops);


print("\n--- QUERY 2: Multi-Key Array Query (Cosmetics for Sensitive Skin) ---");
const sensitiveSkinProducts = db.products.find(
  { 
    category: "Health & Beauty",
    "attributes.skin_type": "Sensitive",
    "attributes.key_ingredients": "Raw Shea Butter"
  },
  {
    sku: 1,
    title: 1,
    brand: 1,
    "attributes.skin_type": 1,
    "attributes.key_ingredients": 1
  }
).toArray();
printjson(sensitiveSkinProducts);


print("\n--- QUERY 3: Full-Text Search (Search term: '5G Android') ---");
const searchResults = db.products.find(
  { $text: { $search: "5G Android" } },
  { score: { $meta: "textScore" }, sku: 1, title: 1, brand: 1, price: 1 }
).sort({ score: { $meta: "textScore" } }).toArray();
printjson(searchResults);


print("\n--- QUERY 4: Array Element Subdocument Filtering ($elemMatch on variants) ---");
// Find products that have at least one variant with stock >= 20 and price_modifier == 0
const highStockVariants = db.products.find(
  {
    variants: {
      $elemMatch: {
        stock: { $gte: 20 },
        price_modifier: 0
      }
    }
  },
  { sku: 1, title: 1, variants: 1 }
).toArray();
printjson(highStockVariants);
