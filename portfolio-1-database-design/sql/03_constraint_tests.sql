-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- File: 03_constraint_tests.sql - proves that the constraints reject
-- invalid data. Each test runs a bad statement and reports PASS when
-- the database refuses it (with the error it raised).
-- =====================================================================

SET search_path TO ekomart;

CREATE FUNCTION pg_temp.expect_error(label TEXT, stmt TEXT)
RETURNS TABLE (test TEXT, result TEXT) AS $$
BEGIN
    EXECUTE stmt;
    RETURN QUERY SELECT label, 'FAIL - statement was accepted'::TEXT;
EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT label, 'PASS - ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

SELECT * FROM pg_temp.expect_error('PK: duplicate region id',
  $q$INSERT INTO region VALUES (1, 'Duplicate Zone')$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('UNIQUE: duplicate customer email',
  $q$INSERT INTO customer (first_name, last_name, email) VALUES ('X','Y','adaeze.okonkwo@example.com')$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('CHECK: invalid email format',
  $q$INSERT INTO customer (first_name, last_name, email) VALUES ('X','Y','not-an-email')$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('NOT NULL: customer without surname',
  $q$INSERT INTO customer (first_name, email) VALUES ('X','x@example.com')$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('FK: order for non-existent customer',
  $q$INSERT INTO customer_order (customer_id, shipping_address_id) VALUES (999999, 1)$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('CHECK: negative product price',
  $q$INSERT INTO product (sku, product_name, category_id, supplier_id, unit_price) VALUES ('BAD-1','Bad',6,1,-50)$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('UNIQUE: duplicate SKU',
  $q$INSERT INTO product (sku, product_name, category_id, supplier_id, unit_price) VALUES ('EKM-000001','Dup',6,1,100)$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('CHECK: stock cannot go negative',
  $q$UPDATE inventory SET quantity_on_hand = quantity_on_hand - 100000 WHERE warehouse_id = 1 AND product_id = 1$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('CHECK: unknown order status',
  $q$UPDATE customer_order SET status = 'LOST' WHERE order_id = 1$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('CHECK: zero quantity order line',
  $q$INSERT INTO order_item VALUES (1, 9, 5, 0, 100)$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('UNIQUE: same product twice in one order',
  $q$INSERT INTO order_item SELECT order_id, 9, product_id, 1, unit_price FROM order_item WHERE order_id = 1 AND line_no = 1$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('CHECK: rating outside 1-5',
  $q$INSERT INTO review (product_id, customer_id, rating) VALUES (1, 1, 6)$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('CHECK: successful payment needs paid_at',
  $q$INSERT INTO payment (order_id, amount, method, status, reference) VALUES (1, 100, 'CARD', 'SUCCESS', 'PAY-TEST-1')$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('CHECK: delivered before shipped',
  $q$UPDATE shipment SET delivered_at = shipped_at - interval '1 day' WHERE shipment_id = 1$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('PARTIAL UNIQUE: second default address',
  $q$INSERT INTO address (customer_id, line1, city, state_id, is_default) VALUES (1, '1 Test Rd', 'Ikeja', 33, true)$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('CHECK: category cannot be its own parent',
  $q$UPDATE category SET parent_category_id = category_id WHERE category_id = 1$q$)
UNION ALL SELECT * FROM pg_temp.expect_error('FK: delete product that has been ordered',
  $q$DELETE FROM product WHERE product_id = 1$q$);
