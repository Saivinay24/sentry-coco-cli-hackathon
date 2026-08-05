# Sentry

An autonomous ops-anomaly investigation agent, built end to end on Snowflake with the CoCo CLI.
Snowflake CoCo CLI Hackathon 2026, Track: Intelligent Workflow Automation Agent.

## What it does

Sentry watches an e-commerce operations dataset (orders, returns, products, warehouses) living
entirely in Snowflake. When a SKU/warehouse combination's return rate spikes well above the
fleet-wide baseline, a Snowflake Stream + Task catches it on its own schedule, no human trigger.
A stored procedure then:

1. Runs a proportion z-test comparing the SKU/warehouse's current 7-day return rate to the
   fleet-wide baseline rate.
2. Pulls the actual return reasons behind the spike as evidence.
3. Calls Snowflake Cortex COMPLETE with that evidence to produce a root-cause hypothesis,
   a confidence score, and a concrete recommended action.
4. Logs the full trace (numbers, evidence, and the model's reasoning) to a table.

A small Streamlit-in-Snowflake dashboard shows the anomaly feed and each investigation's trace.

## Why this design

- **Real autonomy, not a button.** The trigger is a genuine Snowflake Stream + scheduled Task,
  not a polling loop faked by hand. Most one-day hackathon builds fake this part.
- **Explainable, not a black box.** Every step of the reasoning chain (the statistics, the
  evidence pulled, the model's hypothesis and confidence) is logged, not just a final answer.
- **Honest statistics.** The anomaly threshold is a real z-test against a fleet-wide baseline,
  verified against the seeded data before any reasoning logic was built on top of it
  (`sql/03_verify_anomaly.sql` — z-score of 29.2 on the planted anomaly, far past significance).

## How CoCo CLI was used

The Snowflake schema, seed data, stored procedure, and Stream/Task were built and debugged
live against a real Snowflake trial account using `cortex exec` — writing SQL specs, letting
CoCo CLI execute them against Snowflake, read the real errors, and iterate until each phase's
verifier passed. See `sql/04_procedure_spec.md` and `sql/05_autonomous_trigger_spec.md` for the
specs handed to CoCo CLI, and the corresponding numbered `.sql` files for what actually shipped.

## Architecture

```
ORDERS / RETURNS  (synthetic e-commerce data, seeded in Snowflake)
        |
        v
   RETURNS_STREAM  (Snowflake Stream, tracks new return rows)
        |
        v
 ANOMALY_SCAN_TASK  (Snowflake Task, scheduled, fires on new stream data)
        |
        v
  ANOMALY_SCAN()    (stored procedure)
    1. z-test vs fleet baseline
    2. pull evidence (top return reasons)
    3. SNOWFLAKE.CORTEX.COMPLETE -> hypothesis, confidence, action
    4. INSERT INTO SENTRY_TRACE
        |
        v
  SENTRY_DASHBOARD  (Streamlit in Snowflake, reads SENTRY_TRACE)
```

## Repo layout

```
sql/
  01_schema.sql                    tables
  02_seed_data.sql                 synthetic data + planted anomaly
  03_verify_anomaly.sql            statistical verifier for the anomaly
  04_procedure_spec.md             spec handed to CoCo CLI
  04_anomaly_scan_proc.sql         the reasoning chain, deployed
  05_autonomous_trigger_spec.md    spec handed to CoCo CLI
  05_autonomous_trigger.sql        Stream + Task, deployed
  06_deploy_streamlit.sql          registers the dashboard in Snowflake
streamlit/
  sentry_dashboard.py              the dashboard
docs/
  DEMO_SCRIPT.md                   what to show, in order
```

## Running it

1. `cortex` authenticated against a Snowflake account (`~/.snowflake/connections.toml`).
2. From `sql/`, run 01 through 06 in order (via `cortex exec` or any Snowflake SQL client).
3. Open the Streamlit app in Snowsight (Projects -> Streamlit -> SENTRY_DASHBOARD).
4. To see the autonomous path live: insert a new anomalous batch of returns into `RETURNS`
   for any SKU/warehouse, wait up to a minute, and watch `SENTRY_TRACE` gain a new row without
   calling `ANOMALY_SCAN()` by hand.

## Honest scope (see GAPS.md in the parent hackathon folder)

Built in roughly one day for a hackathon submission. Single data domain (returns/orders), no
multi-user auth, no production-hardened error handling beyond the happy path. Said plainly
rather than implied otherwise.
