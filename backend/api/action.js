// Operator write-back: acknowledge, resolve, reassign, or reprioritize a ticket
// that Sentry opened. This is a public endpoint, so it accepts only whitelisted
// enum values on three named columns of one table, always via bindings. There
// is no path here to run arbitrary SQL.
import { cors, runQuery, text } from './_snowflake.js';

const STATUSES = ['OPEN', 'ACKNOWLEDGED', 'RESOLVED'];
const TEAMS = ['Quality Control', 'Warehouse Operations', 'Supply Chain', 'Customer Support'];
const PRIORITIES = ['P1', 'P2', 'P3'];
const UUID_RE = /^[0-9a-fA-F-]{36}$/;

export default async function handler(req, res) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Use POST to update a ticket.' });
  }

  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  body = body || {};

  const { action_id: actionId, status, owning_team: owningTeam, priority, note } = body;

  if (!actionId || !UUID_RE.test(actionId)) {
    return res.status(400).json({ error: 'A valid action_id is required.' });
  }

  const sets = [];
  const bindings = {};
  let i = 1;

  if (status !== undefined) {
    if (!STATUSES.includes(status)) {
      return res.status(400).json({ error: `status must be one of ${STATUSES.join(', ')}.` });
    }
    sets.push(`status = ?`);
    bindings[i++] = text(status);
  }

  if (owningTeam !== undefined) {
    if (!TEAMS.includes(owningTeam)) {
      return res.status(400).json({ error: `owning_team must be one of ${TEAMS.join(', ')}.` });
    }
    sets.push(`owning_team = ?`);
    bindings[i++] = text(owningTeam);
  }

  if (priority !== undefined) {
    if (!PRIORITIES.includes(priority)) {
      return res.status(400).json({ error: `priority must be one of ${PRIORITIES.join(', ')}.` });
    }
    sets.push(`priority = ?`);
    bindings[i++] = text(priority);
  }

  if (note !== undefined) {
    if (typeof note !== 'string' || note.length > 500) {
      return res.status(400).json({ error: 'note must be a string of 500 characters or fewer.' });
    }
    sets.push(`operator_note = ?`);
    bindings[i++] = text(note);
  }

  if (!sets.length) {
    return res.status(400).json({ error: 'Nothing to update. Send status, owning_team, priority, or note.' });
  }

  sets.push('updated_ts = CURRENT_TIMESTAMP()');
  bindings[i] = text(actionId);

  const statement = `
    UPDATE SENTRY_DB.OPS.SENTRY_ACTIONS
    SET ${sets.join(', ')}
    WHERE action_id = ?
  `;

  try {
    const { raw } = await runQuery(statement, bindings);
    const updated = Number(raw?.stats?.numRowsUpdated ?? raw?.data?.[0]?.[0] ?? 0);
    if (!updated) {
      return res.status(404).json({ error: 'No ticket found with that id.' });
    }
    res.status(200).json({ ok: true, updated });
  } catch (err) {
    res.status(err.statusCode || 502).json({ error: err.message });
  }
}
