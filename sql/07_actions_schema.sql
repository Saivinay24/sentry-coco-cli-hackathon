-- SENTRY_ACTIONS: the actual triggered output of an investigation.
-- ANOMALY_SCAN() doesn't just log a hypothesis — it opens a routed incident ticket
-- here, autonomously, as part of the same procedure run. This is the "trigger
-- contextual actions based on analysis" requirement from the problem statement,
-- not just a text recommendation sitting in a trace row.
USE DATABASE SENTRY_DB;
USE SCHEMA OPS;

CREATE TABLE IF NOT EXISTS SENTRY_ACTIONS (
    action_id STRING DEFAULT UUID_STRING(),
    trace_id STRING,
    sku STRING,
    warehouse_id STRING,
    priority STRING,
    owning_team STRING,
    action_summary STRING,
    status STRING DEFAULT 'OPEN',
    created_ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
