// Runs the same investigation the scheduled Task runs, on demand. The Task
// still fires on its own every minute; this exists so an operator who just
// loaded new data doesn't have to wait for the next tick. No parameters, so
// there is nothing here a caller can inject into.
import { cors, runQuery } from './_snowflake.js';

export default async function handler(req, res) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Use POST to run a scan.' });
  }

  try {
    const { rows } = await runQuery('CALL SENTRY_DB.OPS.ANOMALY_SCAN()');
    const result = rows.length ? Object.values(rows[0])[0] : 'Scan complete.';
    res.status(200).json({ ok: true, result });
  } catch (err) {
    res.status(err.statusCode || 502).json({ error: err.message });
  }
}
