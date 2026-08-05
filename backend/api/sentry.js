// Live read of Sentry's own Snowflake output, called by the dashboard on load
// and on every refresh, so what an operator sees is a real query result.
import { cors, runQuery } from './_snowflake.js';

export default async function handler(req, res) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();

  const statement = `
    SELECT t.trace_id,
           TO_VARCHAR(t.run_ts, 'YYYY-MM-DD HH24:MI:SS') AS run_ts,
           t.sku, t.warehouse_id, t.baseline_return_rate,
           t.current_return_rate, t.z_score, t.hypothesis, t.evidence_summary,
           t.confidence, t.recommended_action,
           a.action_id, a.priority, a.owning_team, a.status, a.operator_note,
           TO_VARCHAR(a.updated_ts, 'YYYY-MM-DD HH24:MI:SS') AS updated_ts
    FROM SENTRY_DB.OPS.SENTRY_TRACE t
    LEFT JOIN SENTRY_DB.OPS.SENTRY_ACTIONS a ON a.trace_id = t.trace_id
    ORDER BY t.run_ts DESC
    LIMIT 200
  `;

  try {
    const { rows } = await runQuery(statement);
    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json({ rows, fetched_at: new Date().toISOString() });
  } catch (err) {
    res.status(err.statusCode || 502).json({ error: err.message });
  }
}
