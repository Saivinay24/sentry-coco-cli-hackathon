-- Sentry's tickets are worked by a human after the agent opens them, so the
-- action row needs the fields a real queue needs: who last touched it and when,
-- and a note the operator can leave. Status moves OPEN -> ACKNOWLEDGED -> RESOLVED.
USE DATABASE SENTRY_DB;
USE SCHEMA OPS;

ALTER TABLE SENTRY_ACTIONS ADD COLUMN IF NOT EXISTS updated_ts TIMESTAMP_NTZ;
ALTER TABLE SENTRY_ACTIONS ADD COLUMN IF NOT EXISTS operator_note STRING;

UPDATE SENTRY_ACTIONS SET updated_ts = created_ts WHERE updated_ts IS NULL;
