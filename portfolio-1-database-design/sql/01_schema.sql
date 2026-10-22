-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Case study: EkoMart Online (simulated Nigerian e-commerce platform)
-- File: 01_schema.sql - relational schema, keys and constraints
-- Target: PostgreSQL 16
-- =====================================================================

DROP SCHEMA IF EXISTS ekomart CASCADE;
CREATE SCHEMA ekomart;
SET search_path TO ekomart;

-- ---------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------

-- Geopolitical zones / delivery regions. Used later (Portfolio 5)
-- as the shard key for distributing orders.
CREATE TABLE region (
    region_id   SMALLINT     PRIMARY KEY,
    region_name VARCHAR(40)  NOT NULL UNIQUE
);

CREATE TABLE state (
    state_id    SMALLINT     PRIMARY KEY,
    state_name  VARCHAR(40)  NOT NULL UNIQUE,
    region_id   SMALLINT     NOT NULL REFERENCES region (region_id)
);

-- ---------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------

CREATE TABLE customer (
    customer_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name   VARCHAR(50)  NOT NULL,
    last_name    VARCHAR(50)  NOT NULL,
    email        VARCHAR(120) NOT NULL UNIQUE,
    phone        VARCHAR(20)  UNIQUE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_customer_email CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    CONSTRAINT chk_customer_phone CHECK (phone IS NULL OR phone ~ '^\+?[0-9]{10,15}$')
);

CREATE TABLE address (
    address_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  BIGINT       NOT NULL REFERENCES customer (customer_id) ON DELETE CASCADE,
    line1        VARCHAR(120) NOT NULL,
    city         VARCHAR(60)  NOT NULL,
    state_id     SMALLINT     NOT NULL REFERENCES state (state_id),
    is_default   BOOLEAN      NOT NULL DEFAULT false
);

-- A customer can have many addresses but at most one default address.
CREATE UNIQUE INDEX uq_address_one_default
    ON address (customer_id) WHERE is_default;

-- ---------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------

-- Self-referencing hierarchy: Electronics > Phones > Smartphones
CREATE TABLE category (
    category_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name       VARCHAR(60) NOT NULL UNIQUE,
    parent_category_id  INTEGER REFERENCES category (category_id),
    CONSTRAINT chk_category_not_own_parent CHECK (parent_category_id <> category_id)
);

CREATE TABLE supplier (
    supplier_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_name  VARCHAR(100) NOT NULL UNIQUE,
    contact_email  VARCHAR(120) NOT NULL,
    state_id       SMALLINT     NOT NULL REFERENCES state (state_id)
);

CREATE TABLE product (
    product_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku           VARCHAR(20)   NOT NULL UNIQUE,          -- natural/alternate key
    product_name  VARCHAR(150)  NOT NULL,
    category_id   INTEGER       NOT NULL REFERENCES category (category_id),
    supplier_id   INTEGER       NOT NULL REFERENCES supplier (supplier_id),
    unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),
    is_active     BOOLEAN       NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Inventory (M:N between warehouse and product)
-- ---------------------------------------------------------------------

CREATE TABLE warehouse (
    warehouse_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_name  VARCHAR(60) NOT NULL UNIQUE,
    state_id        SMALLINT    NOT NULL REFERENCES state (state_id)
);

CREATE TABLE inventory (
    warehouse_id      SMALLINT NOT NULL REFERENCES warehouse (warehouse_id),
    product_id        BIGINT   NOT NULL REFERENCES product (product_id),
    quantity_on_hand  INTEGER  NOT NULL CHECK (quantity_on_hand >= 0),  -- stock can never go negative
    reorder_level     INTEGER  NOT NULL DEFAULT 10 CHECK (reorder_level >= 0),
    PRIMARY KEY (warehouse_id, product_id)                              -- composite key
);

-- ---------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------

CREATE TABLE customer_order (
    order_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id          BIGINT      NOT NULL REFERENCES customer (customer_id),
    shipping_address_id  BIGINT      NOT NULL REFERENCES address (address_id),
    order_date           TIMESTAMPTZ NOT NULL DEFAULT now(),
    status               VARCHAR(12) NOT NULL DEFAULT 'PENDING',
    CONSTRAINT chk_order_status CHECK (status IN
        ('PENDING', 'PAID', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'REFUNDED'))
);

CREATE TABLE order_item (
    order_id    BIGINT        NOT NULL REFERENCES customer_order (order_id) ON DELETE CASCADE,
    line_no     SMALLINT      NOT NULL CHECK (line_no > 0),
    product_id  BIGINT        NOT NULL REFERENCES product (product_id),
    quantity    INTEGER       NOT NULL CHECK (quantity > 0),
    -- Price at the time of sale. This is NOT redundant with product.unit_price:
    -- it is a historical fact that must not change when the catalogue price changes.
    unit_price  NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (order_id, line_no),
    CONSTRAINT uq_order_product UNIQUE (order_id, product_id)
);

CREATE TABLE payment (
    payment_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id     BIGINT        NOT NULL REFERENCES customer_order (order_id),
    amount       NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    method       VARCHAR(15)   NOT NULL,
    status       VARCHAR(10)   NOT NULL DEFAULT 'PENDING',
    reference    VARCHAR(40)   NOT NULL UNIQUE,            -- gateway reference, prevents double-recording
    paid_at      TIMESTAMPTZ,
    CONSTRAINT chk_payment_method CHECK (method IN ('CARD', 'BANK_TRANSFER', 'USSD', 'WALLET', 'POD')),
    CONSTRAINT chk_payment_status CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED', 'REVERSED')),
    CONSTRAINT chk_payment_paid_at CHECK (status <> 'SUCCESS' OR paid_at IS NOT NULL)
);

CREATE TABLE shipment (
    shipment_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      BIGINT      NOT NULL UNIQUE REFERENCES customer_order (order_id),  -- 1:1 with order
    warehouse_id  SMALLINT    NOT NULL REFERENCES warehouse (warehouse_id),
    courier       VARCHAR(40) NOT NULL,
    tracking_no   VARCHAR(40) UNIQUE,
    status        VARCHAR(12) NOT NULL DEFAULT 'PREPARING',
    shipped_at    TIMESTAMPTZ,
    delivered_at  TIMESTAMPTZ,
    CONSTRAINT chk_shipment_status CHECK (status IN ('PREPARING', 'IN_TRANSIT', 'DELIVERED', 'RETURNED')),
    CONSTRAINT chk_shipment_dates CHECK (delivered_at IS NULL OR (shipped_at IS NOT NULL AND delivered_at >= shipped_at))
);

CREATE TABLE review (
    review_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id   BIGINT      NOT NULL REFERENCES product (product_id),
    customer_id  BIGINT      NOT NULL REFERENCES customer (customer_id),
    rating       SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment      TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_one_review_per_product UNIQUE (product_id, customer_id)
);

-- ---------------------------------------------------------------------
-- Derived data as a view instead of a stored column (keeps 3NF:
-- order total depends on order_item rows, not directly on order_id).
-- ---------------------------------------------------------------------

CREATE VIEW order_summary AS
SELECT o.order_id,
       o.customer_id,
       o.order_date,
       o.status,
       COUNT(oi.line_no)                 AS item_lines,
       SUM(oi.quantity * oi.unit_price)  AS order_total
FROM customer_order o
JOIN order_item oi ON oi.order_id = o.order_id
GROUP BY o.order_id;

-- Foreign-key columns are not indexed automatically in PostgreSQL.
-- Only the one needed for ON DELETE CASCADE is added here
-- (order_item.order_id is already covered by its primary key).
-- Query-driven indexes are added and measured in Portfolio 2.
CREATE INDEX idx_address_customer ON address (customer_id);
