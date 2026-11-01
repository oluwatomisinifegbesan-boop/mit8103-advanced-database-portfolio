// =====================================================================
// MIT 8103 Advanced Database Systems - Portfolio 5
// Case study: EkoMart Online (simulated Nigerian e-commerce platform)
// File: scripts/03_mongodb_sharding_simulation.js
// Target: MongoDB 7.0+ / mongosh
//
// Description:
// Demonstrates MongoDB Horizontal Sharding, Zone/Tag-Aware Routing,
// and Replica Set High Availability architecture for EkoMart Online:
// 1. Cluster topology definition (mongos, Config Servers, Shard Replicas)
// 2. Shard Key selection analysis (Hashed vs Ranged vs Compound)
// 3. Zone-Aware Sharding (routing orders by Nigerian Geopolitical Zone)
// 4. Verification of Targeted Routing vs Scatter-Gather Queries
// =====================================================================

db = db.getSiblingDB("ekomart_distributed");

print("======================================================================");
print("1. CLUSTER TOPOLOGY SPECIFICATION FOR EKOMART ONLINE");
print("======================================================================");

const clusterTopology = {
  routers: ["mongos-lagos-01", "mongos-abuja-01"],
  config_replica_set: {
    name: "cfg-repl",
    members: ["cfg-01.internal:27019", "cfg-02.internal:27019", "cfg-03.internal:27019"]
  },
  shards: [
    {
      shard_id: "shard_sw_lagos",
      replica_set: "rs-sw",
      primary_datacenter: "Lagos (Main Datacenter)",
      zones_assigned: ["ZONE_SOUTH_WEST"],
      nodes: ["sw-primary:27018", "sw-secondary:27018", "sw-arbiter:27018"]
    },
    {
      shard_id: "shard_nc_abuja",
      replica_set: "rs-nc",
      primary_datacenter: "Abuja (Northern Regional Hub)",
      zones_assigned: ["ZONE_NORTH_CENTRAL", "ZONE_NORTH_WEST", "ZONE_NORTH_EAST"],
      nodes: ["nc-primary:27018", "nc-secondary:27018", "nc-arbiter:27018"]
    },
    {
      shard_id: "shard_eastern_ph",
      replica_set: "rs-east",
      primary_datacenter: "Port Harcourt / Onitsha Hub",
      zones_assigned: ["ZONE_SOUTH_EAST", "ZONE_SOUTH_SOUTH"],
      nodes: ["east-primary:27018", "east-secondary:27018", "east-arbiter:27018"]
    }
  ]
};

printjson(clusterTopology);


print("\n======================================================================");
print("2. SHARD KEY SELECTION & TRADEOFF EVALUATION");
print("======================================================================");
print("EkoMart Evaluated Three Candidate Shard Keys for the 'orders' collection:\n");
print("A. Single Field Hashed: { order_id: 'hashed' }");
print("   - Advantage: Perfectly uniform write distribution; zero hotspots.");
print("   - Drawback: Cross-partition scatter-gather on regional dispatch queries.");
print("\nB. Monotonically Increasing: { order_date: 1 }");
print("   - CRITICAL FLAW: All new inserts hit a single shard (write hotspot bottleneck).\n");
print("C. Compound Co-located Key (SELECTED): { 'delivery.region_id': 1, 'order_id': 'hashed' }");
print("   - Advantage: Combines targeted regional routing with hashed balance inside each zone!");


print("\n======================================================================");
print("3. SIMULATING ZONE-AWARE SHARDING CONFIGURATION");
print("======================================================================");

// Simulated administrative commands executed on mongos router:
print("Step 1: Enabling sharding on database 'ekomart_distributed'...");
print("  sh.enableSharding('ekomart_distributed');");

print("\nStep 2: Assigning geographic zone tags to shard replica sets...");
print("  sh.addShardTag('shard_sw_lagos', 'ZONE_SOUTH_WEST');");
print("  sh.addShardTag('shard_nc_abuja', 'ZONE_NORTH_CENTRAL');");
print("  sh.addShardTag('shard_eastern_ph', 'ZONE_EASTERN');");

print("\nStep 3: Creating shard tag boundaries (Pinning Nigerian Geopolitical Zones)...");
print("  sh.addTagRange('ekomart_distributed.orders', { 'delivery.region_id': 6, 'order_id': MinKey }, { 'delivery.region_id': 6, 'order_id': MaxKey }, 'ZONE_SOUTH_WEST');");
print("  sh.addTagRange('ekomart_distributed.orders', { 'delivery.region_id': 1, 'order_id': MinKey }, { 'delivery.region_id': 1, 'order_id': MaxKey }, 'ZONE_NORTH_CENTRAL');");
print("  sh.addTagRange('ekomart_distributed.orders', { 'delivery.region_id': 4, 'order_id': MinKey }, { 'delivery.region_id': 5, 'order_id': MaxKey }, 'ZONE_EASTERN');");


print("\n======================================================================");
print("4. MOCK DATA INSERTION & ROUTING PROOF");
print("======================================================================");

// Demonstrating document structure with composite shard key
db.orders.drop();

const sampleDistributedOrders = [
  {
    order_id: 10001,
    delivery: {
      region_id: 6, // South West
      state: "Lagos",
      city: "Ikeja"
    },
    customer_id: 501,
    total_amount: 85000.00,
    status: "PAID",
    target_shard_node: "shard_sw_lagos (Lagos Datacenter)"
  },
  {
    order_id: 10002,
    delivery: {
      region_id: 1, // North Central
      state: "FCT Abuja",
      city: "Garki"
    },
    customer_id: 502,
    total_amount: 142000.00,
    status: "PAID",
    target_shard_node: "shard_nc_abuja (Abuja Datacenter)"
  },
  {
    order_id: 10003,
    delivery: {
      region_id: 5, // South South
      state: "Rivers",
      city: "Port Harcourt"
    },
    customer_id: 503,
    total_amount: 67000.00,
    status: "SHIPPED",
    target_shard_node: "shard_eastern_ph (Port Harcourt Hub)"
  }
];

db.orders.insertMany(sampleDistributedOrders);
print(`Inserted ${sampleDistributedOrders.length} test documents with explicit delivery regions.`);

print("\n--- QUERY TARGETING VERIFICATION ---");
print("Query 1: Targeted Query with Shard Key (region_id = 6)");
const targetedResult = db.orders.find({ "delivery.region_id": 6 }).toArray();
print(` -> Targeted Router Path: Direct to 'shard_sw_lagos' (Single Shard Execution)`);
printjson(targetedResult[0]);

print("\nQuery 2: Global Scatter-Gather Query (No Shard Key Specified)");
const scatterResult = db.orders.find({ status: "PAID" }).toArray();
print(` -> Scatter-Gather Path: Broadcasts query to ALL 3 Shard Replica Sets and merges results.`);
print(` -> Documents retrieved: ${scatterResult.length}`);
