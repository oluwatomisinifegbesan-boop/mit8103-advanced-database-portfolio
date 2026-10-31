// =====================================================================
// MIT 8103 Advanced Database Systems - Portfolio 4
// Case study: EkoMart Online (simulated Nigerian e-commerce platform)
// File: scripts/02_seed_catalogue_and_carts.js
// Target: MongoDB 7.0+ / mongosh
//
// Description:
// Seeds rich, realistic polymorphic product documents and shopping
// cart sessions demonstrating the document model's flexibility.
// =====================================================================

db = db.getSiblingDB("ekomart_nosql");

// ---------------------------------------------------------------------
// 1. SEED POLYMORPHIC PRODUCTS
// ---------------------------------------------------------------------
db.products.insertMany([
  // Product 1: Electronics - Smartphone
  {
    sku: "EKM-PHN001",
    title: "Tecno Camon 30 Pro 5G",
    category: "Electronics",
    subcategory: "Phones",
    brand: "Tecno",
    price: 345000.00,
    is_active: true,
    tags: ["5g", "android", "smartphone", "fast-charging"],
    attributes: {
      screen_size_inches: 6.78,
      display_type: "AMOLED 144Hz",
      ram_gb: 12,
      storage_gb: 512,
      battery_capacity_mah: 5000,
      processor: "MediaTek Dimensity 8200 Ultimate",
      is_5g_enabled: true,
      camera: {
        rear_megapixels: "50MP + 50MP + 2MP",
        front_megapixels: "50MP"
      },
      os: "Android 14 (HiOS 14)"
    },
    variants: [
      { variant_id: "v1", sku_suffix: "-SLV", color: "Iceland Silver", price_modifier: 0, stock: 45 },
      { variant_id: "v2", sku_suffix: "-BLK", color: "Clouddy White", price_modifier: 0, stock: 30 }
    ],
    created_at: new Date("2024-06-15T10:00:00Z")
  },

  // Product 2: Electronics - Laptop
  {
    sku: "EKM-LAP002",
    title: "Dell XPS 15 9530 Core i7",
    category: "Electronics",
    subcategory: "Laptops",
    brand: "Dell",
    price: 1850000.00,
    is_active: true,
    tags: ["laptop", "ultrabook", "developer", "nvidia"],
    attributes: {
      screen_size_inches: 15.6,
      processor: "Intel Core i7-13700H",
      ram_gb: 32,
      storage_gb: 1024,
      gpu: "NVIDIA GeForce RTX 4060 8GB GDDR6",
      weight_kg: 1.92,
      battery_life_hours: 10,
      ports: ["Thunderbolt 4", "USB-C 3.2", "SD Card Slot", "3.5mm Headphone Jack"]
    },
    variants: [
      { variant_id: "v1", sku_suffix: "-FHD", display: "FHD+ Non-Touch", price_modifier: 0, stock: 12 },
      { variant_id: "v2", sku_suffix: "-OLED", display: "3.5K OLED Touch", price_modifier: 250000.00, stock: 6 }
    ],
    created_at: new Date("2024-07-01T12:00:00Z")
  },

  // Product 3: Fashion - Traditional Attire
  {
    sku: "EKM-FSH003",
    title: "Men's Luxury Hand-Embroidered 3-Piece Agbada",
    category: "Fashion",
    subcategory: "Men's Wear",
    brand: "Lagos Tailors Guild",
    price: 95000.00,
    is_active: true,
    tags: ["fashion", "traditional", "agbada", "wedding", "luxury"],
    attributes: {
      fabric: "100% Super 150s Swiss Damask Cotton",
      embroidery_style: "Royal Northern Chevron",
      gender: "Male",
      pieces_included: ["Agbada Gown", "Buba Shirt", "Sokoto Trousers"],
      care_instructions: "Dry clean only. Do not bleach. Warm iron."
    },
    variants: [
      { variant_id: "v1", sku_suffix: "-M-WHT", size: "M", color: "Crisp White", price_modifier: 0, stock: 15 },
      { variant_id: "v2", sku_suffix: "-L-WHT", size: "L", color: "Crisp White", price_modifier: 0, stock: 22 },
      { variant_id: "v3", sku_suffix: "-XL-ROY", size: "XL", color: "Royal Blue", price_modifier: 5000.00, stock: 10 }
    ],
    created_at: new Date("2024-07-20T14:30:00Z")
  },

  // Product 4: Groceries - Food Staple
  {
    sku: "EKM-GRO004",
    title: "Golden Penny Semovita 10kg Bag",
    category: "Groceries",
    subcategory: "Staples",
    brand: "Flour Mills of Nigeria",
    price: 18500.00,
    is_active: true,
    tags: ["food", "groceries", "swallow", "dinner", "family-pack"],
    attributes: {
      weight_kg: 10.0,
      packaging: "Airtight Woven Polypropylene Sack",
      shelf_life_months: 12,
      nafdac_reg_no: "01-4321",
      storage_condition: "Store in a cool, dry, well-ventilated area",
      allergens: ["Wheat (Gluten)"],
      nutrition_per_100g: {
        energy_kcal: 360,
        protein_g: 11.5,
        carbohydrates_g: 74.0,
        dietary_fibre_g: 3.2
      }
    },
    variants: [
      { variant_id: "v1", sku_suffix: "-SINGLE", pack_size: "1x10kg", price_modifier: 0, stock: 150 },
      { variant_id: "v2", sku_suffix: "-BUNDLE3", pack_size: "3x10kg Bundle", price_modifier: 36000.00, stock: 40 }
    ],
    created_at: new Date("2024-08-05T09:15:00Z")
  },

  // Product 5: Health & Beauty - Natural Cosmetics
  {
    sku: "EKM-BEA005",
    title: "Organic Unrefined Nilotica Shea Butter Hair & Body Balm",
    category: "Health & Beauty",
    subcategory: "Hair Care",
    brand: "Ori Naturals",
    price: 6500.00,
    is_active: true,
    tags: ["beauty", "organic", "shea-butter", "natural", "skincare"],
    attributes: {
      volume_ml: 250,
      skin_type: ["Dry", "Sensitive", "Eczema-Prone"],
      is_organic_certified: true,
      cruelty_free: true,
      key_ingredients: ["Raw Shea Butter", "Cold-Pressed Argan Oil", "Vitamin E", "Lavender Essential Oil"],
      expiry_months_after_opening: 24
    },
    variants: [
      { variant_id: "v1", sku_suffix: "-250ML", size: "250ml Jar", price_modifier: 0, stock: 85 },
      { variant_id: "v2", sku_suffix: "-500ML", size: "500ml Family Jar", price_modifier: 5000.00, stock: 40 }
    ],
    created_at: new Date("2024-08-12T16:45:00Z")
  }
]);

print("Successfully seeded polymorphic product documents.");

// ---------------------------------------------------------------------
// 2. SEED SHOPPING CARTS (ACTIVE & STALE FOR TTL VERIFICATION)
// ---------------------------------------------------------------------
const now = new Date();
const eightDaysAgo = new Date(now.getTime() - (8 * 24 * 60 * 60 * 1000));
const twoHoursAgo = new Date(now.getTime() - (2 * 60 * 60 * 1000));

db.shopping_carts.insertMany([
  // Cart 1: Active cart (Customer 101)
  {
    customer_id: 101,
    status: "ACTIVE",
    items: [
      {
        product_id: "EKM-PHN001",
        sku: "EKM-PHN001-SLV",
        title: "Tecno Camon 30 Pro 5G (Iceland Silver)",
        quantity: 1,
        unit_price: 345000.00
      },
      {
        product_id: "EKM-GRO004",
        sku: "EKM-GRO004-SINGLE",
        title: "Golden Penny Semovita 10kg Bag",
        quantity: 2,
        unit_price: 18500.00
      }
    ],
    cart_total: 382000.00,
    created_at: twoHoursAgo,
    updated_at: twoHoursAgo
  },

  // Cart 2: Active Cart (Customer 102)
  {
    customer_id: 102,
    status: "ACTIVE",
    items: [
      {
        product_id: "EKM-FSH003",
        sku: "EKM-FSH003-L-WHT",
        title: "Men's Luxury Hand-Embroidered 3-Piece Agbada (Size L)",
        quantity: 1,
        unit_price: 95000.00
      }
    ],
    cart_total: 95000.00,
    created_at: now,
    updated_at: now
  },

  // Cart 3: Abandoned Stale Cart (8 days old -> Eligible for TTL Expiration)
  {
    customer_id: 103,
    status: "ABANDONED",
    items: [
      {
        product_id: "EKM-LAP002",
        sku: "EKM-LAP002-OLED",
        title: "Dell XPS 15 9530 Core i7 (OLED)",
        quantity: 1,
        unit_price: 2100000.00
      }
    ],
    cart_total: 2100000.00,
    created_at: eightDaysAgo,
    updated_at: eightDaysAgo
  }
]);

print("Successfully seeded shopping cart sessions.");
