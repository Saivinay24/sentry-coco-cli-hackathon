# Demo script

~2-3 minutes, in order.

1. **The problem, in one line.** "Ops teams find out about return spikes days late, from a
   spreadsheet someone remembered to check. Sentry catches it the moment the data shifts, and
   tells you why, not just that."

2. **Show the dashboard first.** Open SENTRY_DASHBOARD in Snowsight. Point at the SKU-0042 /
   WH-03 card: 40% return rate vs a 3.6% baseline, z-score 29, hypothesis, evidence, recommended
   action, and the auto-opened P1 ticket routed to Quality Control, all populated with no human
   having clicked anything to produce it.

3. **Prove the autonomy, live.** In a Snowsight worksheet, insert a fresh batch of anomalous
   returns for a different SKU/warehouse (a short prepared INSERT). Do not call ANOMALY_SCAN()
   manually. Wait for the scheduled Task to fire (up to ~1 minute) and refresh the dashboard:
   a new card appears on its own, ticket already opened.

4. **Show the trace and the triggered action, not just the answer.** Open SENTRY_TRACE in a
   worksheet: the raw numbers, the evidence pulled, the exact prompt-driven reasoning. Then open
   SENTRY_ACTIONS next to it: the ticket that same run opened, with a priority computed from the
   z-score and a team assigned by Cortex. "This is why 'explainable' isn't a slide, it's a table,
   and it's why 'autonomous' means it actually did something, not just wrote an opinion down."

5. **Close on how it was built.** "The schema, the procedure, the Stream and Task were all
   built and debugged live against this Snowflake account using CoCo CLI itself, iterating
   against real errors, not written blind."

## Numbers to keep consistent across README, this script, and the pitch deck

- Seeded anomaly: SKU-0042 / WH-03, 40.3% return rate vs 3.6% fleet baseline, z-score 29.2.
- Live-demo anomaly (proves autonomy, already verified once during build): SKU-0015 / WH-01,
  ~46% return rate, reason "battery overheating / swelling." Task fired and logged a new trace
  row in about 1 minute with zero manual triggering, then correctly stayed quiet on the next
  scheduled run since the stream was drained. For the actual demo, insert data for a THIRD,
  unused SKU/warehouse combo so it's visibly live, not a replay.
- Task schedule: every 1 minute (Snowflake trial account minimum granularity).
