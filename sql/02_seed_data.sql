-- Sentry: synthetic data, generated in-warehouse (no external files).
-- Baseline ~4% return rate everywhere. One planted anomaly: SKU-0042 at WH-03
-- spikes to a much higher return rate in the last 7 days, reason "defective packaging".
USE DATABASE SENTRY_DB;
USE SCHEMA OPS;
USE WAREHOUSE COMPUTE_WH;

TRUNCATE TABLE WAREHOUSES;
TRUNCATE TABLE PRODUCTS;
TRUNCATE TABLE ORDERS;
TRUNCATE TABLE RETURNS;

INSERT INTO WAREHOUSES (warehouse_id, warehouse_name, region) VALUES
('WH-01', 'North Distribution Center', 'North'),
('WH-02', 'South Distribution Center', 'South'),
('WH-03', 'East Distribution Center', 'East'),
('WH-04', 'West Distribution Center', 'West'),
('WH-05', 'Central Distribution Center', 'Central');

INSERT INTO PRODUCTS (sku, product_name, category)
SELECT
    'SKU-' || LPAD(SEQ4()+1, 4, '0') AS sku,
    'Product ' || (SEQ4()+1) AS product_name,
    ARRAY_CONSTRUCT('Electronics','Home','Apparel','Toys','Sports')[UNIFORM(0,4,RANDOM())] AS category
FROM TABLE(GENERATOR(ROWCOUNT => 50));

-- Baseline order volume: 90 days, ~8000 orders spread across all SKU/warehouse combos.
INSERT INTO ORDERS (order_id, order_date, sku, warehouse_id, quantity, unit_price)
SELECT
    'ORD-' || LPAD(SEQ4(), 6, '0') AS order_id,
    DATEADD(day, -UNIFORM(0,89,RANDOM()), CURRENT_DATE()) AS order_date,
    'SKU-' || LPAD(UNIFORM(1,50,RANDOM()), 4, '0') AS sku,
    'WH-' || LPAD(UNIFORM(1,5,RANDOM()), 2, '0') AS warehouse_id,
    UNIFORM(1,5,RANDOM()) AS quantity,
    ROUND(UNIFORM(500,5000,RANDOM())/100.0, 2) AS unit_price
FROM TABLE(GENERATOR(ROWCOUNT => 8000));

-- Extra order volume for the anomaly combo in the last 7 days, so the spike has a real sample size.
INSERT INTO ORDERS (order_id, order_date, sku, warehouse_id, quantity, unit_price)
SELECT
    'ORD-A' || LPAD(SEQ4(), 6, '0') AS order_id,
    DATEADD(day, -UNIFORM(0,6,RANDOM()), CURRENT_DATE()) AS order_date,
    'SKU-0042' AS sku,
    'WH-03' AS warehouse_id,
    UNIFORM(1,3,RANDOM()) AS quantity,
    ROUND(UNIFORM(1500,2500,RANDOM())/100.0, 2) AS unit_price
FROM TABLE(GENERATOR(ROWCOUNT => 220));

-- Baseline returns: ~4% of all orders EXCLUDING the anomaly window, normal reasons.
INSERT INTO RETURNS (return_id, order_id, return_date, sku, warehouse_id, quantity, reason)
SELECT
    'RET-' || LPAD(SEQ4(), 6, '0'),
    order_id,
    DATEADD(day, UNIFORM(1,5,RANDOM()), order_date),
    sku,
    warehouse_id,
    quantity,
    ARRAY_CONSTRUCT('Changed mind','Wrong size','Not as described','Damaged in transit')[UNIFORM(0,3,RANDOM())]
FROM ORDERS
SAMPLE (4)
WHERE NOT (sku = 'SKU-0042' AND warehouse_id = 'WH-03' AND order_date >= DATEADD(day,-7,CURRENT_DATE()));

-- Planted anomaly: ~42% return rate for SKU-0042 / WH-03 in the last 7 days.
INSERT INTO RETURNS (return_id, order_id, return_date, sku, warehouse_id, quantity, reason)
SELECT
    'RET-ANOM-' || LPAD(SEQ4(), 6, '0'),
    order_id,
    DATEADD(day, UNIFORM(1,2,RANDOM()), order_date),
    sku,
    warehouse_id,
    quantity,
    'Defective packaging - product arrived damaged, seal broken on arrival'
FROM (
    SELECT * FROM ORDERS
    WHERE sku = 'SKU-0042' AND warehouse_id = 'WH-03' AND order_date >= DATEADD(day,-7,CURRENT_DATE())
) SAMPLE (42);

-- Sanity check
SELECT COUNT(*) AS order_count FROM ORDERS;
SELECT COUNT(*) AS return_count FROM RETURNS;
