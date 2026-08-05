-- Sentry: schema setup
CREATE DATABASE IF NOT EXISTS SENTRY_DB;
CREATE SCHEMA IF NOT EXISTS SENTRY_DB.OPS;
USE DATABASE SENTRY_DB;
USE SCHEMA OPS;
USE WAREHOUSE COMPUTE_WH;

CREATE OR REPLACE TABLE WAREHOUSES (
    warehouse_id STRING PRIMARY KEY,
    warehouse_name STRING,
    region STRING
);

CREATE OR REPLACE TABLE PRODUCTS (
    sku STRING PRIMARY KEY,
    product_name STRING,
    category STRING
);

CREATE OR REPLACE TABLE ORDERS (
    order_id STRING PRIMARY KEY,
    order_date DATE,
    sku STRING,
    warehouse_id STRING,
    quantity NUMBER,
    unit_price NUMBER(10,2)
);

CREATE OR REPLACE TABLE RETURNS (
    return_id STRING PRIMARY KEY,
    order_id STRING,
    return_date DATE,
    sku STRING,
    warehouse_id STRING,
    quantity NUMBER,
    reason STRING
);

CREATE OR REPLACE TABLE SENTRY_TRACE (
    trace_id STRING DEFAULT UUID_STRING(),
    run_ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    sku STRING,
    warehouse_id STRING,
    baseline_return_rate FLOAT,
    current_return_rate FLOAT,
    z_score FLOAT,
    hypothesis STRING,
    evidence_summary STRING,
    confidence FLOAT,
    recommended_action STRING,
    raw_llm_output VARIANT
);
