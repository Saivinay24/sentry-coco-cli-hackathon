// Live read of Sentry's own Snowflake output. Called by the public dashboard on
// every page load, so what a judge sees is a real query result, not a snapshot
// baked into HTML at deploy time.
export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  const accountHost = process.env.SNOWFLAKE_ACCOUNT_HOST;
  const pat = process.env.SNOWFLAKE_PAT;

  if (!accountHost || !pat) {
    res.status(500).json({ error: 'Backend not configured yet.' });
    return;
  }

  const statement = `
    SELECT t.trace_id, TO_VARCHAR(t.run_ts, 'YYYY-MM-DD HH24:MI:SS') AS run_ts,
           t.sku, t.warehouse_id, t.baseline_return_rate,
           t.current_return_rate, t.z_score, t.hypothesis, t.evidence_summary,
           t.confidence, t.recommended_action,
           a.action_id, a.priority, a.owning_team, a.status
    FROM SENTRY_DB.OPS.SENTRY_TRACE t
    LEFT JOIN SENTRY_DB.OPS.SENTRY_ACTIONS a ON a.trace_id = t.trace_id
    ORDER BY t.run_ts DESC
    LIMIT 20
  `;

  try {
    const resp = await fetch(`https://${accountHost}.snowflakecomputing.com/api/v2/statements?async=false`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${pat}`,
        'X-Snowflake-Authorization-Token-Type': 'PROGRAMMATIC_ACCESS_TOKEN',
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        statement,
        warehouse: 'COMPUTE_WH',
        database: 'SENTRY_DB',
        schema: 'OPS',
        role: 'ACCOUNTADMIN',
        timeout: 30,
      }),
    });

    const data = await resp.json();

    if (!resp.ok) {
      res.status(resp.status).json({ error: data.message || 'Snowflake query failed' });
      return;
    }

    const cols = data.resultSetMetaData.rowType.map((c) => c.name);
    const rows = (data.data || []).map((row) =>
      Object.fromEntries(cols.map((c, i) => [c, row[i]]))
    );

    res.setHeader('Cache-Control', 's-maxage=10, stale-while-revalidate=30');
    res.status(200).json({ rows, fetched_at: new Date().toISOString() });
  } catch (err) {
    res.status(502).json({ error: 'Could not reach Snowflake', detail: String(err) });
  }
}
