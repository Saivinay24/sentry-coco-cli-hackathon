// Shared Snowflake SQL REST API client. The PAT lives only in server-side env
// vars, so the browser never sees a credential. Every caller uses bindings
// rather than string interpolation: this is a public endpoint, so no
// caller-supplied value is ever concatenated into SQL.

export function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

export async function runQuery(statement, bindings) {
  const accountHost = process.env.SNOWFLAKE_ACCOUNT_HOST;
  const pat = process.env.SNOWFLAKE_PAT;

  if (!accountHost || !pat) {
    const err = new Error('Backend is not configured with Snowflake credentials.');
    err.statusCode = 500;
    throw err;
  }

  const resp = await fetch(
    `https://${accountHost}.snowflakecomputing.com/api/v2/statements?async=false`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${pat}`,
        'X-Snowflake-Authorization-Token-Type': 'PROGRAMMATIC_ACCESS_TOKEN',
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        statement,
        ...(bindings ? { bindings } : {}),
        warehouse: 'COMPUTE_WH',
        database: 'SENTRY_DB',
        schema: 'OPS',
        role: 'ACCOUNTADMIN',
        timeout: 40,
      }),
    }
  );

  const data = await resp.json();

  if (!resp.ok) {
    const err = new Error(data.message || 'Snowflake rejected the statement.');
    err.statusCode = resp.status;
    throw err;
  }

  const cols = (data.resultSetMetaData?.rowType || []).map((c) => c.name);
  const rows = (data.data || []).map((row) =>
    Object.fromEntries(cols.map((c, i) => [c, row[i]]))
  );

  return { rows, raw: data };
}

export function text(value) {
  return { type: 'TEXT', value: String(value) };
}
