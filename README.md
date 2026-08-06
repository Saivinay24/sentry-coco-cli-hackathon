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

The same run opens a prioritized, team-routed ticket in a `SENTRY_ACTIONS` table: priority is
computed from the z-score, the owning team (Quality Control, Warehouse Operations, Supply Chain,
or Customer Support) is assigned by Cortex from the evidence. That's the actual "trigger
contextual actions based on analysis" requirement from the problem statement, not just a
recommendation sitting in a log. A small Streamlit-in-Snowflake dashboard shows the anomaly feed,
each investigation's full trace, and the ticket it opened.

## Why this design

- **Real autonomy, not a button.** The trigger is a genuine Snowflake Stream + scheduled Task,
  not a polling loop faked by hand. Most one-day hackathon builds fake this part.
- **Explainable, not a black box.** Every step of the reasoning chain (the statistics, the
  evidence pulled, the model's hypothesis and confidence) is logged, not just a final answer.
- **Ends in a triggered action, not an opinion.** Every confirmed anomaly opens a routed,
  prioritized ticket in `SENTRY_ACTIONS`, autonomously, in the same procedure run.
- **Honest statistics.** The anomaly threshold is a real z-test against a fleet-wide baseline,
  verified against the seeded data before any reasoning logic was built on top of it
  (`sql/03_verify_anomaly.sql`, z-score of 29.2 on the planted anomaly, far past significance).

## How CoCo CLI was used

The Snowflake schema, seed data, stored procedure, and Stream/Task were built and debugged
live against a real Snowflake trial account using `cortex exec`: writing SQL specs, letting
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
    3. SNOWFLAKE.CORTEX.COMPLETE -> hypothesis, confidence, action, owning team
    4. INSERT INTO SENTRY_TRACE   (full reasoning, logged)
    5. INSERT INTO SENTRY_ACTIONS (priority + owning team, ticket opened)
        |
        v
  SENTRY_DASHBOARD  (Streamlit in Snowflake, reads SENTRY_TRACE + SENTRY_ACTIONS)
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
  07_actions_schema.sql            SENTRY_ACTIONS table, the triggered-ticket output
  08_actions_workflow.sql          operator workflow columns (updated_ts, operator_note)
  09_live_autonomy_test.sql        lands fresh data to prove the Task fires unprompted
streamlit/
  sentry_dashboard.py              the dashboard (Streamlit-in-Snowflake, native)
streamlit_cloud/
  app.py                           the same dashboard, for a public deploy (Streamlit Community Cloud)
  requirements.txt
  secrets.toml.example             shape of the secrets Streamlit Cloud needs (no real values)
backend/
  api/_snowflake.js                shared Snowflake SQL REST client (bindings only)
  api/sentry.js                    GET incidents + their tickets
  api/action.js                    POST ticket updates (whitelisted values only)
  api/scan.js                      POST run ANOMALY_SCAN() on demand
  api/inject.js                    POST land a fresh anomaly, proves the Task's own trigger
  api/agent.js                     GET agent status + its real Snowflake run history
docs/
  index.html                       the app itself (GitHub Pages), reads and writes via backend/
```

## Running it

1. `cortex` authenticated against a Snowflake account (`~/.snowflake/connections.toml`).
2. From `sql/`, run 01 through 06 in order (via `cortex exec` or any Snowflake SQL client).
3. Open the Streamlit app in Snowsight (Projects -> Streamlit -> SENTRY_DASHBOARD).
4. To see the autonomous path live: insert a new anomalous batch of returns into `RETURNS`
   for any SKU/warehouse, wait up to a minute, and watch `SENTRY_TRACE` gain a new row without
   calling `ANOMALY_SCAN()` by hand.

## The app (public, no Snowflake login needed)

**Live: https://saivinay24.github.io/sentry-coco-cli-hackathon/**

This is the working tool, not a write-up of it. An ops analyst opens it and can:

- **Work the queue.** Needs attention / Resolved / All, filtered by priority and owning team,
  with full-text search across SKU, warehouse, and the agent's own findings.
- **Open an incident** and read the whole investigation: the rate against the fleet baseline,
  the z-score, the confidence, the evidence Sentry pulled, and what it recommends.
- **Act on it.** Acknowledge, resolve, reassign to a different team, change priority, leave a
  note for whoever picks it up. Every one of those writes straight back to
  `SENTRY_DB.OPS.SENTRY_ACTIONS` in Snowflake and is visible to the next person who loads it.
- **Run a scan on demand** instead of waiting for the next scheduled Task tick.
- **Watch the agent itself.** The Activity page shows whether the Task is running, what it's
  watching, the five steps it takes on each wake-up, and its real run history straight out of
  Snowflake's `TASK_HISTORY`: every time it woke, whether it found anything, and how long the
  investigation took. The autonomy is inspectable rather than asserted.
- **Trigger a real anomaly and watch the agent catch it unprompted.** The Activity page's
  "Inject a live anomaly" button lands a genuine, never-before-seen return-rate spike in
  Snowflake and calls nothing else: it does not run the scan. `ANOMALY_SCAN_TASK` has to notice
  the Stream and fire on its own next tick (up to ~1 minute) for anything to happen, and the page
  confirms the moment it does. This is the difference between an agent you have to take on faith
  and one you can independently verify: click it, and get a different real SKU/warehouse and a
  different real ticket every time.

How it's wired: the page calls a small serverless API (`backend/`, on Vercel) which talks to the
Snowflake SQL REST API. The PAT stays server-side and never reaches the browser. Writes accept
only whitelisted enum values on three named columns of one table, always through bound
parameters, so a public endpoint can't be turned into arbitrary SQL.

| Endpoint | Method | Does |
| --- | --- | --- |
| `/api/sentry` | GET | current incidents joined to their tickets |
| `/api/action` | POST | update status, owning team, priority, or note on one ticket |
| `/api/scan` | POST | run `ANOMALY_SCAN()` now |
| `/api/inject` | POST | land a fresh, never-flagged return-rate spike; does not call the scan, proves the Task's own trigger |
| `/api/agent` | GET | agent status and real run history from Snowflake `TASK_HISTORY` |

To stand the backend up yourself: `cd backend && vercel --prod`, then set
`SNOWFLAKE_ACCOUNT_HOST` (e.g. `us30067.ap-southeast-7.aws`) and `SNOWFLAKE_PAT` as production
environment variables (`vercel env add <name> production`), then redeploy.

`streamlit_cloud/app.py` is also included: the same dashboard rigged for a live Streamlit
Community Cloud deployment (queries `SENTRY_TRACE` directly over a PAT connection on every
page load, not a snapshot). It's kept in the repo as the fuller live option, but Streamlit
Cloud's free tier was unreliable during build/deploy today, so GitHub Pages is the primary
public link for submission. If you want to bring the live version up:

1. Go to share.streamlit.io, sign in, "New app", point it at this repo, main file path
   `streamlit_cloud/app.py`.
2. In the app's Secrets settings, paste the contents of `streamlit_cloud/secrets.toml.example`
   with real values (account identifier, a Snowflake username, and a scoped PAT with read access
   to `SENTRY_DB.OPS.SENTRY_TRACE`). Never commit real secrets to this repo.
3. Deploy. The resulting `*.streamlit.app` URL is the public prototype link.

## Honest scope (see GAPS.md in the parent hackathon folder)

Built in roughly one day for a hackathon submission. Single data domain (returns/orders), no
multi-user auth, no production-hardened error handling beyond the happy path. Said plainly
rather than implied otherwise.
