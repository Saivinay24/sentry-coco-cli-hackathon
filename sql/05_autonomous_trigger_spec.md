# Spec: autonomous trigger (Stream + Task)

Wire up real autonomous invocation of `ANOMALY_SCAN()` — no human clicking a button.

1. `CREATE OR REPLACE STREAM RETURNS_STREAM ON TABLE SENTRY_DB.OPS.RETURNS;`
2. `CREATE OR REPLACE TASK ANOMALY_SCAN_TASK` on `COMPUTE_WH`, schedule every 1 minute (trial
   account minimum granularity), `WHEN SYSTEM$STREAM_HAS_DATA('RETURNS_STREAM')`. The task body
   must itself query `RETURNS_STREAM` (e.g. into a temp table) so the stream offset actually
   advances on commit — a bare `CALL ANOMALY_SCAN()` that never touches the stream object will
   leave `SYSTEM$STREAM_HAS_DATA` permanently true and the task will refire needlessly forever.
   Then `CALL ANOMALY_SCAN();` in the same task body.
3. `ALTER TASK ANOMALY_SCAN_TASK RESUME;` — tasks are created suspended by default.
4. Live proof: insert a fresh batch of anomalous returns (reuse the pattern from
   `sql/02_seed_data.sql`'s anomaly insert, or a new SKU/warehouse combo so it's visibly a NEW
   anomaly, not a re-detection of the SKU-0042/WH-03 one already logged) directly into
   `RETURNS`/`ORDERS`, then wait ~1-2 minutes and confirm a new row lands in `SENTRY_TRACE`
   WITHOUT calling `ANOMALY_SCAN()` manually. Check `SELECT SYSTEM$STREAM_HAS_DATA(...)`,
   `SHOW TASKS;`, and `SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(...))` if it doesn't
   fire, to see why.
5. Save the final, tested SQL into `sql/05_autonomous_trigger.sql`.

## Fallback (per PLAN.md / DECISION.md kill criteria)

If Task/Stream doesn't reliably fire within a reasonable debugging window, do NOT keep burning
time — fall back to a manual-trigger stored procedure call and disclose that honestly in the
demo script (`docs/DEMO_SCRIPT.md`) as "trigger simulated for the demo, the reasoning chain
itself is real." Report back which path was taken.
