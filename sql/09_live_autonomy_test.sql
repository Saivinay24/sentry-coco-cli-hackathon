-- Live autonomy proof. Lands a fresh batch of orders and then returns for a
-- SKU/warehouse Sentry has never flagged. Nothing here calls ANOMALY_SCAN().
-- The RETURNS insert is what the Stream watches, so the scheduled Task should
-- pick it up on its next tick and produce a trace row and a routed ticket with
-- no human involvement.
USE DATABASE SENTRY_DB;
USE SCHEMA OPS;

-- 40 recent orders for SKU-0025 at WH-04
INSERT INTO ORDERS (order_id, order_date, sku, warehouse_id, quantity, unit_price)
SELECT
    'ORD-LIVE-' || SEQ4()::STRING,
    DATEADD(day, -1 * MOD(SEQ4(), 6), CURRENT_DATE()),
    'SKU-0025',
    'WH-04',
    1,
    129.00
FROM TABLE(GENERATOR(ROWCOUNT => 40));

-- 18 of those orders come back with the same defect signature
INSERT INTO RETURNS (return_id, order_id, return_date, sku, warehouse_id, quantity, reason)
SELECT
    'RET-LIVE-' || SEQ4()::STRING,
    'ORD-LIVE-' || SEQ4()::STRING,
    CURRENT_DATE(),
    'SKU-0025',
    'WH-04',
    1,
    'Screen flickering and dead pixels after first charge'
FROM TABLE(GENERATOR(ROWCOUNT => 18));
