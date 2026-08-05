# Spec: ANOMALY_SCAN stored procedure

Build a Snowflake stored procedure `SENTRY_DB.OPS.ANOMALY_SCAN()` that:

1. Runs the anomaly-detection query from `sql/03_verify_anomaly.sql` (fleet-wide baseline
   z-test, `orders_current >= 15` filter) to find SKU/warehouse combos with `z_score > 3`.
2. For each anomaly found, skip it if a row already exists in `SENTRY_TRACE` for the same
   `sku` + `warehouse_id` with `run_ts` in the last hour (avoid duplicate spam on repeated
   scheduled runs).
3. For each new anomaly, gather evidence: top 5 return reasons for that sku/warehouse in the
   last 7 days, with counts (`SELECT reason, COUNT(*) FROM RETURNS WHERE ... GROUP BY reason
   ORDER BY COUNT(*) DESC LIMIT 5`).
4. Build a prompt with the numbers (current rate, baseline rate, z-score, order/return counts,
   top reasons) and call `SNOWFLAKE.CORTEX.COMPLETE` (pick a solid available model, e.g.
   `llama3.1-70b` or `claude-*` if available in this account/region — check what's actually
   enabled with `SHOW MODELS` or by testing, don't assume) asking for a JSON response with
   exactly these keys: `hypothesis` (one sentence), `evidence_summary` (one sentence citing
   the actual numbers), `confidence` (float 0-1), `recommended_action` (one concrete action).
5. Parse the JSON response robustly (LLMs sometimes wrap JSON in markdown fences — strip those
   before parsing). Insert one row into `SENTRY_TRACE` with all the numeric fields, the parsed
   hypothesis/evidence_summary/confidence/recommended_action, and the raw LLM output stored in
   `raw_llm_output` (VARIANT).
6. Return a short string summarizing how many anomalies were newly logged this run.

## Build approach

Iterate live against the Snowflake account: write the procedure, `CREATE OR REPLACE` it, call
`CALL ANOMALY_SCAN();`, check `SELECT * FROM SENTRY_TRACE ORDER BY run_ts DESC;` for a real,
sensible row (not null fields, not a JSON-parsing failure). Fix and retry until one clean
correct row exists for the planted SKU-0042/WH-03 anomaly. Save the final, working, tested SQL
into `sql/04_anomaly_scan_proc.sql`, replacing this spec file's placeholder role — the spec
stays as documentation of intent, the `.sql` file is the source of truth for what's deployed.

## Non-goals (this phase)

No autonomous trigger yet (Task/Stream) — that's the next phase. This phase only needs
`CALL ANOMALY_SCAN();` to work correctly when invoked manually.
