// The agent's own operating record: is it running, what is it watching, and
// every time it woke up. This is what makes the autonomy inspectable instead of
// something the UI just claims. Snowflake's TASK_HISTORY includes upcoming
// SCHEDULED rows, so the next wake-up is visible too.
import { cors, runQuery } from './_snowflake.js';

export default async function handler(req, res) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();

  const runsSql = `
    SELECT name, state,
           TO_VARCHAR(scheduled_time, 'YYYY-MM-DD HH24:MI:SS') AS scheduled_time,
           TO_VARCHAR(completed_time, 'YYYY-MM-DD HH24:MI:SS') AS completed_time,
           DATEDIFF('millisecond', query_start_time, completed_time) AS duration_ms,
           error_message
    FROM TABLE(SENTRY_DB.INFORMATION_SCHEMA.TASK_HISTORY(
      TASK_NAME => 'ANOMALY_SCAN_TASK',
      RESULT_LIMIT => 40))
    ORDER BY scheduled_time DESC
  `;

  const stateSql = `
    SELECT SYSTEM$STREAM_HAS_DATA('SENTRY_DB.OPS.RETURNS_STREAM') AS stream_has_data,
           (SELECT COUNT(*) FROM SENTRY_DB.OPS.SENTRY_TRACE) AS investigations,
           (SELECT COUNT(*) FROM SENTRY_DB.OPS.SENTRY_ACTIONS) AS tickets
  `;

  try {
    const [runsRes, stateRes] = await Promise.all([
      runQuery(runsSql),
      runQuery(stateSql),
    ]);

    const runs = runsRes.rows;
    const s = stateRes.rows[0] || {};

    const executed = runs.filter((r) => r.STATE === 'SUCCEEDED').length;
    const upcoming = runs.find((r) => r.STATE === 'SCHEDULED');

    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json({
      agent: {
        name: 'ANOMALY_SCAN_TASK',
        procedure: 'SENTRY_DB.OPS.ANOMALY_SCAN()',
        model: 'llama3.1-70b (Snowflake Cortex COMPLETE)',
        schedule: 'every 1 minute',
        watching: 'RETURNS_STREAM on SENTRY_DB.OPS.RETURNS',
        stream_has_data: String(s.STREAM_HAS_DATA) === 'true',
        next_run: upcoming ? upcoming.SCHEDULED_TIME : null,
        investigations: Number(s.INVESTIGATIONS || 0),
        tickets: Number(s.TICKETS || 0),
        executed_runs: executed,
      },
      runs,
      fetched_at: new Date().toISOString(),
    });
  } catch (err) {
    res.status(err.statusCode || 502).json({ error: err.message });
  }
}
