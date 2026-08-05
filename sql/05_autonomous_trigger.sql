-- Autonomous trigger: Stream + Task fires ANOMALY_SCAN() when new returns arrive.
-- No human intervention needed -- the task checks every 1 minute and only runs
-- when RETURNS_STREAM has unconsumed CDC rows.
USE DATABASE SENTRY_DB;
USE SCHEMA OPS;
USE WAREHOUSE COMPUTE_WH;

-- 1. Stream: tracks inserts/updates/deletes on the RETURNS table.
CREATE OR REPLACE STREAM SENTRY_DB.OPS.RETURNS_STREAM
  ON TABLE SENTRY_DB.OPS.RETURNS;

-- 2. Task: fires every 1 minute IF the stream has data.
--    The body MUST consume the stream (SELECT into a temp table) so the offset
--    advances on commit. A bare CALL without touching the stream would leave
--    SYSTEM$STREAM_HAS_DATA permanently true.
CREATE OR REPLACE TASK SENTRY_DB.OPS.ANOMALY_SCAN_TASK
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('SENTRY_DB.OPS.RETURNS_STREAM')
AS
BEGIN
  -- Drain the stream so the offset advances (consuming the CDC rows)
  CREATE OR REPLACE TEMPORARY TABLE SENTRY_DB.OPS._STREAM_DRAIN AS
    SELECT * FROM SENTRY_DB.OPS.RETURNS_STREAM;
  -- Now run the anomaly scan
  CALL SENTRY_DB.OPS.ANOMALY_SCAN();
END;

-- 3. Resume (tasks are created suspended by default).
ALTER TASK SENTRY_DB.OPS.ANOMALY_SCAN_TASK RESUME;

-- ============================================================================
-- LIVE PROOF: insert a fresh anomaly batch (different SKU/warehouse from seed)
-- and confirm it gets detected autonomously within ~1-2 minutes.
-- ============================================================================

-- Extra orders for SKU-0015 / WH-01 in the last 7 days
INSERT INTO SENTRY_DB.OPS.ORDERS (order_id, order_date, sku, warehouse_id, quantity, unit_price)
SELECT
    'ORD-T2-' || LPAD(SEQ4(), 6, '0') AS order_id,
    DATEADD(day, -UNIFORM(0,6,RANDOM()), CURRENT_DATE()) AS order_date,
    'SKU-0015' AS sku,
    'WH-01' AS warehouse_id,
    UNIFORM(1,3,RANDOM()) AS quantity,
    ROUND(UNIFORM(1000,3000,RANDOM())/100.0, 2) AS unit_price
FROM TABLE(GENERATOR(ROWCOUNT => 200));

-- ~45% returns with a distinct reason pattern (battery overheating)
INSERT INTO SENTRY_DB.OPS.RETURNS (return_id, order_id, return_date, sku, warehouse_id, quantity, reason)
SELECT
    'RET-T2-' || LPAD(SEQ4(), 6, '0'),
    order_id,
    DATEADD(day, UNIFORM(1,2,RANDOM()), order_date),
    sku,
    warehouse_id,
    quantity,
    'Overheating during use - battery swelling reported'
FROM (
    SELECT * FROM SENTRY_DB.OPS.ORDERS
    WHERE sku = 'SKU-0015' AND warehouse_id = 'WH-01' AND order_date >= DATEADD(day,-7,CURRENT_DATE())
      AND order_id LIKE 'ORD-T2-%'
) SAMPLE (45);

-- Verification queries (run after ~90 seconds):
-- SELECT SYSTEM$STREAM_HAS_DATA('SENTRY_DB.OPS.RETURNS_STREAM');
-- SELECT * FROM SENTRY_DB.OPS.SENTRY_TRACE ORDER BY run_ts DESC;
-- SELECT * FROM TABLE(SENTRY_DB.INFORMATION_SCHEMA.TASK_HISTORY(
--   TASK_NAME => 'ANOMALY_SCAN_TASK',
--   SCHEDULED_TIME_RANGE_START => DATEADD(minute, -10, CURRENT_TIMESTAMP())
-- ));
