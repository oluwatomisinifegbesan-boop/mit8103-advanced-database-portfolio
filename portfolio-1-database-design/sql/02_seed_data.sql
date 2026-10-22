-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- File: 02_seed_data.sql - reference data + reproducible bulk test data
--
-- Volume (approx.): 20,000 customers, 2,000 products, 200,000 orders,
-- 500,000 order lines. Large enough for meaningful execution plans in
-- Portfolio 2. setseed() makes every run generate the same data.
-- =====================================================================

SET search_path TO ekomart;
SELECT setseed(0.8103);

-- ---------------------------------------------------------------------
-- Reference data (hand-written)
-- ---------------------------------------------------------------------

INSERT INTO region (region_id, region_name) VALUES
 (1, 'North Central'), (2, 'North East'), (3, 'North West'),
 (4, 'South East'),    (5, 'South South'), (6, 'South West');

INSERT INTO state (state_id, state_name, region_id) VALUES
 ( 1,'FCT Abuja',1),( 2,'Benue',1),( 3,'Kogi',1),( 4,'Kwara',1),( 5,'Nasarawa',1),( 6,'Niger',1),( 7,'Plateau',1),
 ( 8,'Adamawa',2),( 9,'Bauchi',2),(10,'Borno',2),(11,'Gombe',2),(12,'Taraba',2),(13,'Yobe',2),
 (14,'Jigawa',3),(15,'Kaduna',3),(16,'Kano',3),(17,'Katsina',3),(18,'Kebbi',3),(19,'Sokoto',3),(20,'Zamfara',3),
 (21,'Abia',4),(22,'Anambra',4),(23,'Ebonyi',4),(24,'Enugu',4),(25,'Imo',4),
 (26,'Akwa Ibom',5),(27,'Bayelsa',5),(28,'Cross River',5),(29,'Delta',5),(30,'Edo',5),(31,'Rivers',5),
 (32,'Ekiti',6),(33,'Lagos',6),(34,'Ogun',6),(35,'Ondo',6),(36,'Osun',6),(37,'Oyo',6);

INSERT INTO category (category_name, parent_category_id) VALUES
 ('Electronics', NULL), ('Fashion', NULL), ('Home & Kitchen', NULL), ('Groceries', NULL), ('Health & Beauty', NULL);
INSERT INTO category (category_name, parent_category_id)
SELECT c.name, p.category_id
FROM (VALUES ('Phones','Electronics'), ('Laptops','Electronics'), ('Audio','Electronics'),
             ('Men''s Wear','Fashion'), ('Women''s Wear','Fashion'), ('Shoes','Fashion'),
             ('Cookware','Home & Kitchen'), ('Appliances','Home & Kitchen'),
             ('Beverages','Groceries'), ('Staples','Groceries'),
             ('Skincare','Health & Beauty'), ('Hair Care','Health & Beauty')) AS c(name, parent)
JOIN category p ON p.category_name = c.parent;

INSERT INTO warehouse (warehouse_name, state_id) VALUES
 ('Lagos Ikeja Hub', 33), ('Abuja Idu Hub', 1), ('Kano Sharada Hub', 16),
 ('Port Harcourt Trans-Amadi Hub', 31), ('Onitsha Hub', 22);

INSERT INTO supplier (supplier_name, contact_email, state_id)
SELECT 'Supplier ' || lpad(g::text, 3, '0') || ' Ltd',
       'sales' || g || '@supplier' || g || '.ng',
       1 + floor(random() * 37)::int
FROM generate_series(1, 60) g;

-- ---------------------------------------------------------------------
-- A few readable sample rows (useful for screenshots and Portfolio 3)
-- ---------------------------------------------------------------------

INSERT INTO customer (first_name, last_name, email, phone) VALUES
 ('Adaeze', 'Okonkwo', 'adaeze.okonkwo@example.com', '+2348031112222'),
 ('Tunde',  'Bakare',  'tunde.bakare@example.com',   '+2348052223333'),
 ('Fatima', 'Bello',   'fatima.bello@example.com',   '+2348063334444');

INSERT INTO address (customer_id, line1, city, state_id, is_default) VALUES
 (1, '12 Allen Avenue', 'Ikeja', 33, true),
 (2, '5 Ring Road', 'Ibadan', 37, true),
 (3, '22 Zoo Road', 'Kano', 16, true);

-- ---------------------------------------------------------------------
-- Bulk generated data
-- ---------------------------------------------------------------------

-- Customers 4..20000
INSERT INTO customer (first_name, last_name, email, phone, created_at)
SELECT (ARRAY['Chinedu','Ngozi','Emeka','Aisha','Ibrahim','Yetunde','Segun','Amaka','Musa','Bola',
              'Kelechi','Zainab','Femi','Halima','Obinna','Funke','Usman','Chioma','Tobi','Hauwa'])[1 + floor(random()*20)::int],
       (ARRAY['Okafor','Adeyemi','Musa','Eze','Abubakar','Ogunleye','Nwosu','Bello','Okoro','Adebayo',
              'Danjuma','Obi','Lawal','Ibe','Yusuf','Ojo','Nnamdi','Sani','Akande','Uche'])[1 + floor(random()*20)::int],
       'user' || g || '@example.com',
       '+23480' || lpad(g::text, 8, '0'),
       timestamptz '2024-01-01' + random() * interval '900 days'
FROM generate_series(4, 20000) g;

-- One default address per generated customer; state weighted towards Lagos (33)
INSERT INTO address (customer_id, line1, city, state_id, is_default)
SELECT c.customer_id,
       (1 + floor(random()*200)::int) || ' Market Street',
       'City ' || s.state_id,
       s.state_id,
       true
FROM customer c
CROSS JOIN LATERAL (SELECT CASE WHEN random() < 0.35 THEN 33
                                ELSE 1 + floor(random()*37)::int END AS state_id
                    WHERE c.customer_id > 0) s
WHERE c.customer_id > 3;

-- 2,000 products spread over the leaf categories
INSERT INTO product (sku, product_name, category_id, supplier_id, unit_price, is_active, created_at)
SELECT 'EKM-' || lpad(g::text, 6, '0'),
       c.category_name || ' item ' || g,
       c.category_id,
       1 + floor(random()*60)::int,
       round((500 + random() * 450000)::numeric, 2),
       random() > 0.05,
       timestamptz '2024-01-01' + random() * interval '600 days'
FROM generate_series(1, 2000) g
CROSS JOIN LATERAL (SELECT category_id, category_name FROM category
                    WHERE parent_category_id IS NOT NULL
                    ORDER BY category_id OFFSET (g % 12) LIMIT 1) c;

-- Every product stocked in every warehouse
INSERT INTO inventory (warehouse_id, product_id, quantity_on_hand, reorder_level)
SELECT w.warehouse_id, p.product_id, floor(random()*500)::int, 20
FROM warehouse w CROSS JOIN product p;

-- 200,000 orders. Recent orders are more likely to still be in progress.
INSERT INTO customer_order (customer_id, shipping_address_id, order_date, status)
SELECT a.customer_id, a.address_id, d.order_date,
       CASE WHEN d.order_date > timestamptz '2026-10-10' THEN (ARRAY['PENDING','PAID','SHIPPED'])[1 + floor(random()*3)::int]
            WHEN random() < 0.05 THEN 'CANCELLED'
            WHEN random() < 0.02 THEN 'REFUNDED'
            ELSE 'DELIVERED' END
FROM generate_series(1, 200000) g
CROSS JOIN LATERAL (SELECT timestamptz '2024-06-01' + random() * interval '870 days' AS order_date
                    WHERE g > 0) d
JOIN address a ON a.customer_id = 1 + ((g * 7919) % 20000) AND a.is_default;

-- 1-4 lines per order, price copied from the catalogue at time of sale
INSERT INTO order_item (order_id, line_no, product_id, quantity, unit_price)
SELECT o.order_id, l.line_no, p.product_id, 1 + floor(random()*3)::int, p.unit_price
FROM customer_order o
CROSS JOIN LATERAL generate_series(1, 1 + (o.order_id % 4)::int) AS l(line_no)
JOIN product p ON p.product_id = 1 + ((o.order_id * 31 + l.line_no * 977) % 2000);

-- Payments for every order that got past PENDING
INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
SELECT s.order_id, s.order_total,
       (ARRAY['CARD','BANK_TRANSFER','USSD','WALLET','POD'])[1 + floor(random()*5)::int],
       CASE WHEN o.status = 'REFUNDED' THEN 'REVERSED' ELSE 'SUCCESS' END,
       'PAY-' || s.order_id || '-' || substr(md5(s.order_id::text), 1, 8),
       o.order_date + interval '5 minutes'
FROM order_summary s
JOIN customer_order o ON o.order_id = s.order_id
WHERE o.status NOT IN ('PENDING', 'CANCELLED');

-- Shipments for shipped/delivered orders
INSERT INTO shipment (order_id, warehouse_id, courier, tracking_no, status, shipped_at, delivered_at)
SELECT o.order_id,
       1 + (o.order_id % 5)::int,
       (ARRAY['GIG Logistics','DHL Nigeria','Kwik','In-house'])[1 + (o.order_id % 4)::int],
       'TRK' || lpad(o.order_id::text, 10, '0'),
       CASE o.status WHEN 'SHIPPED' THEN 'IN_TRANSIT' WHEN 'REFUNDED' THEN 'RETURNED' ELSE 'DELIVERED' END,
       o.order_date + interval '1 day',
       CASE WHEN o.status = 'SHIPPED' THEN NULL ELSE o.order_date + interval '1 day' + random() * interval '6 days' END
FROM customer_order o
WHERE o.status IN ('SHIPPED', 'DELIVERED', 'REFUNDED');

-- Reviews on roughly 1 in 10 delivered order lines (one per customer/product)
INSERT INTO review (product_id, customer_id, rating, comment, created_at)
SELECT DISTINCT ON (oi.product_id, o.customer_id)
       oi.product_id, o.customer_id,
       1 + floor(power(random(), 0.4) * 5)::int,        -- skewed towards good ratings
       'Sample review',
       o.order_date + interval '8 days'
FROM order_item oi
JOIN customer_order o ON o.order_id = oi.order_id
WHERE o.status = 'DELIVERED' AND random() < 0.1;

ANALYZE;

-- Row counts for the README / evidence
SELECT 'customer' AS table_name, COUNT(*) FROM customer
UNION ALL SELECT 'address', COUNT(*) FROM address
UNION ALL SELECT 'product', COUNT(*) FROM product
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL SELECT 'customer_order', COUNT(*) FROM customer_order
UNION ALL SELECT 'order_item', COUNT(*) FROM order_item
UNION ALL SELECT 'payment', COUNT(*) FROM payment
UNION ALL SELECT 'shipment', COUNT(*) FROM shipment
UNION ALL SELECT 'review', COUNT(*) FROM review;
