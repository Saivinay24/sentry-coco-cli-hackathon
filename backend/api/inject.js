// Proves the autonomous trigger for real, on demand. This does NOT call
// ANOMALY_SCAN() — it only lands a fresh, genuinely new return-rate spike on
// a SKU/warehouse Sentry has never flagged, the same way sql/09_live_autonomy
// _test.sql does by hand. RETURNS_STREAM picks it up, and ANOMALY_SCAN_TASK
// fires on its own next tick (every 1 minute) with zero further calls from
// here. That's the difference between "the agent ran because I clicked run"
// and "the agent runs because it watches," and it's the whole autonomy claim
// this track is judged on — so it has to be checkable, not just asserted.
import { cors, runQuery, text } from './_snowflake.js';

const REASONS = [
  'Screen flickering and dead pixels after first charge',
  'Damaged in transit',
  'Defective packaging - product arrived damaged, seal broken on arrival',
  'Overheating during use - battery swelling reported',
];

export default async function handler(req, res) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Use POST to inject a live anomaly.' });
  }

  try {
    const { rows: pick } = await runQuery(`
      SELECT sku, warehouse_id
      FROM (
        SELECT DISTINCT o.sku, o.warehouse_id
        FROM SENTRY_DB.OPS.ORDERS o
        WHERE NOT EXISTS (
          SELECT 1 FROM SENTRY_DB.OPS.SENTRY_TRACE t
          WHERE t.sku = o.sku AND t.warehouse_id = o.warehouse_id
        )
      )
      ORDER BY RANDOM()
      LIMIT 1
    `);

    if (!pick.length) {
      return res.status(409).json({ error: 'Every SKU/warehouse combo already has a finding. Resolve some tickets first.' });
    }

    const { SKU: sku, WAREHOUSE_ID: warehouseId } = pick[0];
    const reason = REASONS[Math.floor(Math.random() * REASONS.length)];
    const batch = Date.now().toString(36).toUpperCase();

    await runQuery(
      `
      INSERT INTO SENTRY_DB.OPS.ORDERS (order_id, order_date, sku, warehouse_id, quantity, unit_price)
      SELECT 'ORD-' || ? || '-' || SEQ4()::STRING,
             DATEADD(day, -1 * MOD(SEQ4(), 6), CURRENT_DATE()),
             ?, ?, 1, 89.00
      FROM TABLE(GENERATOR(ROWCOUNT => 35))
      `,
      { 1: text(batch), 2: text(sku), 3: text(warehouseId) }
    );

    await runQuery(
      `
      INSERT INTO SENTRY_DB.OPS.RETURNS (return_id, order_id, return_date, sku, warehouse_id, quantity, reason)
      SELECT 'RET-' || ? || '-' || SEQ4()::STRING,
             'ORD-' || ? || '-' || SEQ4()::STRING,
             CURRENT_DATE(), ?, ?, 1, ?
      FROM TABLE(GENERATOR(ROWCOUNT => 15))
      `,
      { 1: text(batch), 2: text(batch), 3: text(sku), 4: text(warehouseId), 5: text(reason) }
    );

    res.status(200).json({
      ok: true,
      sku,
      warehouse_id: warehouseId,
      reason,
      message: `Landed 15 fresh returns for ${sku} / ${warehouseId}. Nothing else was called — ANOMALY_SCAN_TASK checks RETURNS_STREAM every minute on its own and will investigate this without anyone triggering it.`,
    });
  } catch (err) {
    res.status(err.statusCode || 502).json({ error: err.message });
  }
}
