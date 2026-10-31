// =====================================================================
// MIT 8103 Advanced Database Systems - Portfolio 4
// Case study: EkoMart Online (simulated Nigerian e-commerce platform)
// File: scripts/05_aggregation_pipeline.js
// Target: MongoDB 7.0+ / mongosh
//
// Description:
// Demonstrates advanced MongoDB Aggregation Pipelines as an alternative
// to relational SQL GROUP BY, JOINs, and Window Functions:
// 1. Pipeline 1: Category Inventory, Pricing & Stock Value Summary ($match, $unwind, $group, $sort)
// 2. Pipeline 2: Variant-Level Inventory Reorder Alert ($unwind, $match, $project, $cond)
// 3. Pipeline 3: Multi-Faceted E-Commerce Search & Filter ($facet, $bucket, $sortByCount)
// 4. Pipeline 4: Active Shopping Cart Pipeline Revenue Analytics
// =====================================================================

db = db.getSiblingDB("ekomart_nosql");

print("======================================================================");
print("PIPELINE 1: CATEGORY INVENTORY & VALUATION SUMMARY");
print("Business Objective: Management quarterly inventory audit by category");
print("======================================================================");

const categorySummary = db.products.aggregate([
  // Stage 1: Filter to active items
  { $match: { is_active: true } },

  // Stage 2: Deconstruct variants array to inspect stock per SKU
  { $unwind: "$variants" },

  // Stage 3: Group by top-level category
  {
    $group: {
      _id: "$category",
      total_products: { $addToSet: "$_id" },
      total_variants: { $sum: 1 },
      total_stock_units: { $sum: "$variants.stock" },
      min_price: { $min: "$price" },
      max_price: { $max: "$price" },
      avg_price: { $avg: "$price" },
      estimated_inventory_value: {
        $sum: {
          $multiply: [
            { $add: ["$price", "$variants.price_modifier"] },
            "$variants.stock"
          ]
        }
      }
    }
  },

  // Stage 4: Reshape and format output
  {
    $project: {
      _id: 0,
      category: "$_id",
      unique_product_count: { $size: "$total_products" },
      total_variant_skus: "$total_variants",
      total_units_on_hand: "$total_stock_units",
      min_price_ngn: { $round: ["$min_price", 2] },
      max_price_ngn: { $round: ["$max_price", 2] },
      avg_price_ngn: { $round: ["$avg_price", 2] },
      total_inventory_value_ngn: { $round: ["$estimated_inventory_value", 2] }
    }
  },

  // Stage 5: Sort by inventory value descending
  { $sort: { total_inventory_value_ngn: -1 } }
]).toArray();

printjson(categorySummary);


print("\n======================================================================");
print("PIPELINE 2: VARIANT-LEVEL LOW-STOCK REORDER ALERT");
print("Business Objective: Automated replenishment alert for warehouse managers");
print("======================================================================");

const lowStockAlerts = db.products.aggregate([
  { $match: { is_active: true } },
  { $unwind: "$variants" },
  // Filter variants whose stock has fallen to or below 15 units
  { $match: { "variants.stock": { $lte: 15 } } },
  {
    $project: {
      _id: 0,
      parent_sku: "$sku",
      product_title: "$title",
      category: "$category",
      variant_sku: { $concat: ["$sku", "$variants.sku_suffix"] },
      stock_level: "$variants.stock",
      urgency: {
        $cond: {
          if: { $lte: ["$variants.stock", 5] },
          then: "CRITICAL",
          else: "WARNING"
        }
      }
    }
  },
  { $sort: { stock_level: 1 } }
]).toArray();

printjson(lowStockAlerts);


print("\n======================================================================");
print("PIPELINE 3: MULTI-FACETED E-COMMERCE SIDEBAR SEARCH ($facet)");
print("Business Objective: Produce complete faceted filter panel in 1 database roundtrip");
print("======================================================================");

const facetedSearch = db.products.aggregate([
  { $match: { is_active: true } },
  {
    $facet: {
      // Facet A: Price distribution buckets
      price_ranges: [
        {
          $bucket: {
            groupBy: "$price",
            boundaries: [0, 50000, 200000, 1000000, 5000000],
            default: "Other",
            output: {
              count: { $sum: 1 },
              sample_products: { $push: "$title" }
            }
          }
        }
      ],
      // Facet B: Top brands distribution
      brand_distribution: [
        { $sortByCount: "$brand" }
      ],
      // Facet C: Popular tags
      tag_cloud: [
        { $unwind: "$tags" },
        { $sortByCount: "$tags" },
        { $limit: 6 }
      ]
    }
  }
]).toArray();

printjson(facetedSearch);


print("\n======================================================================");
print("PIPELINE 4: ACTIVE SHOPPING CARTS CONVERSION & PIPELINE VALUE");
print("Business Objective: Real-time marketing funnel & cart abandonment analysis");
print("======================================================================");

const cartAnalytics = db.shopping_carts.aggregate([
  {
    $group: {
      _id: "$status",
      session_count: { $sum: 1 },
      total_pipeline_value: { $sum: "$cart_total" },
      avg_cart_value: { $avg: "$cart_total" }
    }
  },
  {
    $project: {
      _id: 0,
      status: "$_id",
      session_count: 1,
      total_pipeline_value_ngn: { $round: ["$total_pipeline_value", 2] },
      avg_cart_value_ngn: { $round: ["$avg_cart_value", 2] }
    }
  },
  { $sort: { session_count: -1 } }
]).toArray();

printjson(cartAnalytics);
