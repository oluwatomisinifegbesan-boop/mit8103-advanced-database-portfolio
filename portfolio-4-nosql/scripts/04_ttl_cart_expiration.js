// =====================================================================
// MIT 8103 Advanced Database Systems - Portfolio 4
// Case study: EkoMart Online (simulated Nigerian e-commerce platform)
// File: scripts/04_ttl_cart_expiration.js
// Target: MongoDB 7.0+ / mongosh
//
// Description:
// Demonstrates automated session expiration and ephemeral data handling
// using MongoDB Time-To-Live (TTL) Indexes:
// 1. Creation of TTL index on "updated_at" timestamp
// 2. Demonstration of sliding-window session renewal on cart update
// 3. Selective TTL expiration using partialFilterExpression
// 4. Inspection of system indexes and simulated TTL document purging
// =====================================================================

db = db.getSiblingDB("ekomart_nosql");

print("======================================================================");
print("1. THE PROBLEM: ABANDONED SHOPPING CARTS IN HIGH-SCALE E-COMMERCE");
print("======================================================================");
print("In high-volume e-commerce platforms like EkoMart Online, approximately");
print("70% of created shopping carts are abandoned without checkout.");
print("In relational systems (e.g. PostgreSQL), purging millions of stale carts");
print("requires scheduled batch DELETE queries that induce write-lock contention,");
print("table bloat, and vacuuming overhead.");
print("MongoDB provides native Time-To-Live (TTL) single-field indexes where a");
print("low-priority background thread (ttlMonitor) automatically evicts expired");
print("documents without application-level maintenance.");

// ---------------------------------------------------------------------
// 2. CREATING TTL INDEXES
// ---------------------------------------------------------------------

// Drop existing TTL indexes if any
try {
  db.shopping_carts.dropIndex("idx_cart_ttl_7days");
  db.shopping_carts.dropIndex("idx_partial_ttl_abandoned");
} catch(e) {}

// Standard TTL Index: Automatically expire cart documents 7 days (604,800 seconds) after updated_at
db.shopping_carts.createIndex(
  { updated_at: 1 },
  { 
    expireAfterSeconds: 604800, 
    name: "idx_cart_ttl_7days" 
  }
);
print("\n[SUCCESS] Created standard 7-day TTL index 'idx_cart_ttl_7days'.");

// Advanced Partial TTL Index:
// Only expire carts whose status is explicitly marked as 'ABANDONED' after 24 hours (86,400s),
// while retaining CHECKED_OUT carts for analytics.
db.shopping_carts.createIndex(
  { updated_at: 1 },
  { 
    expireAfterSeconds: 86400, 
    partialFilterExpression: { status: "ABANDONED" },
    name: "idx_partial_ttl_abandoned" 
  }
);
print("[SUCCESS] Created partial TTL index 'idx_partial_ttl_abandoned'.");


// ---------------------------------------------------------------------
// 3. DEMONSTRATING SLIDING-WINDOW SESSION RENEWAL
// ---------------------------------------------------------------------
print("\n======================================================================");
print("2. SLIDING SESSION RENEWAL: RESETTING TTL CLOCK ON USER ACTIVITY");
print("======================================================================");

// Customer 101 adds an item to their existing cart
print("Customer 101 adds a new item to their shopping cart.");
const newItem = {
  product_id: "EKM-BEA005",
  sku: "EKM-BEA005-250ML",
  title: "Organic Unrefined Nilotica Shea Butter Hair & Body Balm",
  quantity: 1,
  unit_price: 6500.00
};

// Atomically push item, increment total, and reset updated_at to now()
const updateResult = db.shopping_carts.updateOne(
  { customer_id: 101, status: "ACTIVE" },
  {
    $push: { items: newItem },
    $inc: { cart_total: 6500.00 },
    $set: { updated_at: new Date() } // Resets the 7-day TTL timer!
  }
);

print(`Cart updated. Matched: ${updateResult.matchedCount}, Modified: ${updateResult.modifiedCount}`);
const refreshedCart = db.shopping_carts.findOne({ customer_id: 101 });
printjson({
  customer_id: refreshedCart.customer_id,
  item_count: refreshedCart.items.length,
  cart_total: refreshedCart.cart_total,
  new_ttl_timestamp: refreshedCart.updated_at
});


// ---------------------------------------------------------------------
// 4. SIMULATING AND QUERYING EXPIRED SESSIONS
// ---------------------------------------------------------------------
print("\n======================================================================");
print("3. TTL THREAD EVALUATION (WHAT THE ttlMonitor SEES)");
print("======================================================================");

const sevenDaysAgo = new Date(Date.now() - (7 * 24 * 60 * 60 * 1000));
print(`Cutoff timestamp for 7-day expiration: ${sevenDaysAgo.toISOString()}`);

// Inspect documents that have crossed the expiration threshold
const expiredCarts = db.shopping_carts.find({
  updated_at: { $lt: sevenDaysAgo }
}).toArray();

print(`Total carts eligible for background deletion by MongoDB ttlMonitor: ${expiredCarts.length}`);
expiredCarts.forEach(c => {
  print(` -> Expired Cart ID: ${c._id}, Customer: ${c.customer_id}, Updated: ${c.updated_at.toISOString()}, Total: NGN ${c.cart_total}`);
});

// Verify active carts remain untouched
const activeCarts = db.shopping_carts.find({
  updated_at: { $gte: sevenDaysAgo }
}).toArray();

print(`Total active retained carts: ${activeCarts.length}`);
activeCarts.forEach(c => {
  print(` -> Retained Cart ID: ${c._id}, Customer: ${c.customer_id}, Updated: ${c.updated_at.toISOString()}, Total: NGN ${c.cart_total}`);
});
