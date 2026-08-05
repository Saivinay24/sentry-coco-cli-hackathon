-- Deploy the Sentry dashboard as a Streamlit-in-Snowflake app.
-- Assumes sentry_dashboard.py has been PUT into a stage first (see deploy notes in README).
USE DATABASE SENTRY_DB;
USE SCHEMA OPS;

CREATE STAGE IF NOT EXISTS SENTRY_STAGE;

CREATE STREAMLIT IF NOT EXISTS SENTRY_DASHBOARD
    ROOT_LOCATION = '@SENTRY_DB.OPS.SENTRY_STAGE'
    MAIN_FILE = 'sentry_dashboard.py'
    QUERY_WAREHOUSE = COMPUTE_WH;
