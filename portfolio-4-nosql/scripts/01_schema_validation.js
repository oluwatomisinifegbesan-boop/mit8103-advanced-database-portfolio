// =====================================================================
// MIT 8103 Advanced Database Systems - Portfolio 4
// Case study: EkoMart Online (simulated Nigerian e-commerce platform)
// File: scripts/01_schema_validation.js
// Target: MongoDB 7.0+ / mongosh
//
// Description:
// Establishes collection-level JSON Schema validation for EkoMart:
// 1. "products" collection: Enforces mandatory core metadata while
//    accommodating highly polymorphic category-specific attributes.
// 2. "shopping_carts" collection: Validates embedded cart lines and
//    session metadata for high-throughput ephemeral shopping carts.
// =====================================================================

// Switch to ekomart database
db = db.getSiblingDB("ekomart_nosql");

// Drop collections if existing for reproducible setup
db.products.drop();
db.shopping_carts.drop();

// ---------------------------------------------------------------------
// 1. PRODUCT CATALOGUE WITH POLYMORPHIC ATTRIBUTES VALIDATION
// ---------------------------------------------------------------------
db.createCollection("products", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["sku", "title", "category", "price", "is_active", "created_at"],
      properties: {
        sku: {
          bsonType: "string",
          pattern: "^EKM-[A-Z0-9]{3,8}$",
          description: "Unique product SKU identifier (must match pattern EKM-XXXXX)"
        },
        title: {
          bsonType: "string",
          minLength: 3,
          maxLength: 200,
          description: "Human-readable product title"
        },
        category: {
          bsonType: "string",
          enum: ["Electronics", "Fashion", "Groceries", "Health & Beauty", "Home & Kitchen"],
          description: "Top-level product category classification"
        },
        subcategory: {
          bsonType: "string",
          description: "Specific subcategory classification"
        },
        brand: {
          bsonType: "string",
          description: "Manufacturer or brand name"
        },
        price: {
          bsonType: ["double", "int", "decimal"],
          minimum: 0.01,
          description: "Catalogue base unit price in Nigerian Naira (NGN)"
        },
        is_active: {
          bsonType: "bool",
          description: "Flag indicating whether product is live for sale"
        },
        // Embedded polymorphic attributes: structure varies by category!
        attributes: {
          bsonType: "object",
          description: "Flexible subdocument for category-specific specifications"
        },
        // Embedded variants (e.g. storage/color options or sizes)
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
        tags: {
          bsonType: "array",
          items: { bsonType: "string" }
        },
        created_at: {
          bsonType: "date",
          description: "Timestamp of catalogue insertion"
        }
      }
    }
  },
  validationLevel: "moderate",
  validationAction: "error"
});

print("Created 'products' collection with JSON Schema validation.");

// ---------------------------------------------------------------------
// 2. SHOPPING CARTS WITH EMBEDDED ITEMS VALIDATION
// ---------------------------------------------------------------------
db.createCollection("shopping_carts", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["customer_id", "status", "items", "created_at", "updated_at"],
      properties: {
        customer_id: {
          bsonType: "int",
          description: "Customer identifier linking to the relational customer record"
        },
        status: {
          bsonType: "string",
          enum: ["ACTIVE", "CHECKED_OUT", "ABANDONED"],
          description: "Lifecycle status of the cart session"
        },
        items: {
          bsonType: "array",
          description: "Embedded list of cart item documents",
          items: {
            bsonType: "object",
            required: ["product_id", "sku", "title", "quantity", "unit_price"],
            properties: {
              product_id: { bsonType: "string" },
              sku: { bsonType: "string" },
              title: { bsonType: "string" },
              quantity: { bsonType: "int", minimum: 1 },
              unit_price: { bsonType: ["double", "int", "decimal"], minimum: 0.01 }
            }
          }
        },
        cart_total: {
          bsonType: ["double", "int", "decimal"],
          minimum: 0
        },
        created_at: {
          bsonType: "date"
        },
        updated_at: {
          bsonType: "date",
          description: "Crucial timestamp utilized by the TTL expiration index"
        }
      }
    }
  }
});

print("Created 'shopping_carts' collection with JSON Schema validation.");
