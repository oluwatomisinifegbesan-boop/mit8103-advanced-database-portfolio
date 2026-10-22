# EkoMart Online - ER Diagram

Crow's-foot notation. GitHub renders this diagram automatically. To export it as an image, paste the code block into <https://mermaid.live> and download a PNG into `evidence/`.

```mermaid
erDiagram
    REGION ||--|{ STATE : contains
    STATE ||--o{ ADDRESS : "located in"
    STATE ||--o{ WAREHOUSE : "located in"
    STATE ||--o{ SUPPLIER : "based in"

    CUSTOMER ||--o{ ADDRESS : has
    CUSTOMER ||--o{ CUSTOMER_ORDER : places
    CUSTOMER ||--o{ REVIEW : writes
    ADDRESS ||--o{ CUSTOMER_ORDER : "ships to"

    CATEGORY |o--o{ CATEGORY : "parent of"
    CATEGORY ||--o{ PRODUCT : groups
    SUPPLIER ||--o{ PRODUCT : supplies

    WAREHOUSE ||--o{ INVENTORY : stocks
    PRODUCT ||--o{ INVENTORY : "stocked as"

    CUSTOMER_ORDER ||--|{ ORDER_ITEM : contains
    PRODUCT ||--o{ ORDER_ITEM : "sold as"
    CUSTOMER_ORDER ||--o{ PAYMENT : "paid by"
    CUSTOMER_ORDER ||--o| SHIPMENT : "fulfilled by"
    WAREHOUSE ||--o{ SHIPMENT : dispatches
    PRODUCT ||--o{ REVIEW : receives

    REGION {
        smallint region_id PK
        varchar region_name UK
    }
    STATE {
        smallint state_id PK
        varchar state_name UK
        smallint region_id FK
    }
    CUSTOMER {
        bigint customer_id PK
        varchar first_name
        varchar last_name
        varchar email UK
        varchar phone UK
        timestamptz created_at
    }
    ADDRESS {
        bigint address_id PK
        bigint customer_id FK
        varchar line1
        varchar city
        smallint state_id FK
        boolean is_default
    }
    CATEGORY {
        int category_id PK
        varchar category_name UK
        int parent_category_id FK
    }
    SUPPLIER {
        int supplier_id PK
        varchar supplier_name UK
        varchar contact_email
        smallint state_id FK
    }
    PRODUCT {
        bigint product_id PK
        varchar sku UK
        varchar product_name
        int category_id FK
        int supplier_id FK
        numeric unit_price
        boolean is_active
    }
    WAREHOUSE {
        smallint warehouse_id PK
        varchar warehouse_name UK
        smallint state_id FK
    }
    INVENTORY {
        smallint warehouse_id PK,FK
        bigint product_id PK,FK
        int quantity_on_hand
        int reorder_level
    }
    CUSTOMER_ORDER {
        bigint order_id PK
        bigint customer_id FK
        bigint shipping_address_id FK
        timestamptz order_date
        varchar status
    }
    ORDER_ITEM {
        bigint order_id PK,FK
        smallint line_no PK
        bigint product_id FK
        int quantity
        numeric unit_price
    }
    PAYMENT {
        bigint payment_id PK
        bigint order_id FK
        numeric amount
        varchar method
        varchar status
        varchar reference UK
        timestamptz paid_at
    }
    SHIPMENT {
        bigint shipment_id PK
        bigint order_id FK,UK
        smallint warehouse_id FK
        varchar courier
        varchar tracking_no UK
        varchar status
        timestamptz shipped_at
        timestamptz delivered_at
    }
    REVIEW {
        bigint review_id PK
        bigint product_id FK
        bigint customer_id FK
        smallint rating
        text comment
    }
```
