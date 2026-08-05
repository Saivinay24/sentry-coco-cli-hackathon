-- Verifier: confirm the planted anomaly is statistically obvious.
-- Compares each SKU/warehouse's current 7-day return rate against the FLEET-WIDE
-- baseline rate (all combos, prior 28 days) via a one-sample proportion z-test.
-- This is more robust than a per-combo baseline, which is too thin-sampled per SKU/warehouse.
USE DATABASE SENTRY_DB;
USE SCHEMA OPS;

WITH baseline AS (
    SELECT COUNT(DISTINCT r.return_id)::FLOAT / COUNT(DISTINCT o.order_id) AS baseline_rate
    FROM ORDERS o
    LEFT JOIN RETURNS r ON r.order_id = o.order_id
    WHERE o.order_date >= DATEADD(day,-35,CURRENT_DATE()) AND o.order_date < DATEADD(day,-7,CURRENT_DATE())
),
current_window AS (
    SELECT o.sku, o.warehouse_id,
        COUNT(DISTINCT o.order_id) AS orders_current,
        COUNT(DISTINCT r.return_id) AS returns_current
    FROM ORDERS o
    LEFT JOIN RETURNS r ON r.order_id = o.order_id
    WHERE o.order_date >= DATEADD(day,-7,CURRENT_DATE())
    GROUP BY 1,2
)
SELECT c.sku, c.warehouse_id, c.orders_current, c.returns_current,
    c.returns_current::FLOAT / c.orders_current AS current_rate,
    b.baseline_rate,
    (c.returns_current::FLOAT / c.orders_current - b.baseline_rate)
        / SQRT(b.baseline_rate * (1 - b.baseline_rate) / c.orders_current) AS z_score
FROM current_window c
CROSS JOIN baseline b
WHERE c.orders_current >= 15
ORDER BY z_score DESC
LIMIT 10;
