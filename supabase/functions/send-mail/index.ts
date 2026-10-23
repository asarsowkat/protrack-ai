// ProTrack Edge Function "send-mail" (ProTrackAI v3.34, needs schema-update-v38.sql).
// Sends an email the database has queued (mail_outbox), through the company mailbox (Microsoft Graph) or an SMTP relay,
// and records the result. The app never chooses the recipients: mail_queue() on the server worked them out and stored
// them with the email; this function only sends what is in the row.
//
// Calls (POST, JSON), from the signed-in app (its own token) or a schedule (the service role key):
//   {"id": "<mail_outbox id>"}  send that email. Allowed to the person who queued it and to super admins.
//   {"pending": true}           send every queued email (up to 25), oldest first. Super admins and schedules only.
//   {"ping": true}              which mail service is set up (no secrets). Anyone signed in.
//
// Settings (Supabase -> Edge Functions -> Secrets). SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are
// provided by Supabase. MAIL_FROM is the sending address (for example protrack@company.com); MAIL_FROM_NAME is optional.
//   MAIL_PROVIDER=graph  GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET: an Entra ID app registration with the
//                        Mail.Send application permission, limited by IT to the MAIL_FROM mailbox.
//   MAIL_PROVIDER=smtp   SMTP_HOST, SMTP_PORT (465: Supabase does not allow ports 25 and 587), SMTP_USER, SMTP_PASS.
//   anything else        nothing is sent; emails stay queued with the reason, listed in Settings -> Email.
// Deploy: Supabase -> Edge Functions -> Deploy a new function -> name send-mail -> paste this file. See STAGE-32-SETUP.md.

declare const Deno: any;

export type Env = (k: string) => string | undefined;
export type SmtpSend = (cfg: { host: string; port: number; user: string; pass: string }, msg: Msg) => Promise<string>;
export interface Deps { env: Env; fetch: typeof fetch; smtp?: SmtpSend; now?: () => Date }
export interface Msg { from: string; fromName: string; to: { name: string; email: string }[]; subject: string; html: string }

const MAX_ATTEMPTS = 5, MAX_TO = 450;
const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type', 'access-control-allow-methods': 'POST, OPTIONS' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, 'content-type': 'application/json' } });
const EMAIL = /^[^\s@,;<>"]+@[^\s@,;<>"]+\.[^\s@,;<>"]+$/;

export function providerOf(env: Env) {
  const p = (env('MAIL_PROVIDER') || '').trim().toLowerCase(), from = (env('MAIL_FROM') || '').trim();
  const need = p === 'graph' ? ['GRAPH_TENANT_ID', 'GRAPH_CLIENT_ID', 'GRAPH_CLIENT_SECRET', 'MAIL_FROM'] : p === 'smtp' ? ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASS', 'MAIL_FROM'] : [];
  const missing = need.filter(k => !(env(k) || '').trim());
  const port = Number(env('SMTP_PORT') || 465);
  let problem = '';
  if (p !== 'graph' && p !== 'smtp') problem = 'No mail service is set up (MAIL_PROVIDER is not graph or smtp)';
  else if (missing.length) problem = 'The mail service settings are incomplete: ' + missing.join(', ');
  else if (!EMAIL.test(from)) problem = 'MAIL_FROM is not a valid address';
  else if (p === 'smtp' && (port === 25 || port === 587)) problem = `SMTP port ${port} is blocked on Supabase; use port 465 or Microsoft Graph`;
  return { provider: p || 'none', from, ready: !problem, problem };
}

// ---- the database, through its REST interface with the service role key
function db(env: Env, f: typeof fetch) {
  const url = (env('SUPABASE_URL') || '').replace(/\/$/, ''), key = env('SUPABASE_SERVICE_ROLE_KEY') || '';
  const h = { apikey: key, authorization: 'Bearer ' + key, 'content-type': 'application/json', prefer: 'return=representation' };
  const call = async (path: string, init: RequestInit = {}) => {
    const r = await f(url + '/rest/v1/' + path, { ...init, headers: { ...h, ...(init.headers || {}) } });
    if (!r.ok) throw new Error('database ' + r.status + ': ' + (await r.text()).slice(0, 200));
    return r.status === 204 ? [] : await r.json();
  };
  return {
    role: async (uid: string) => ((await call(`profiles?id=eq.${encodeURIComponent(uid)}&select=role,active`))[0] || null),
    row: async (id: string) => ((await call(`mail_outbox?id=eq.${encodeURIComponent(id)}&select=*`))[0] || null),
    pending: async () => await call(`mail_outbox?status=eq.queued&attempts=lt.${MAX_ATTEMPTS}&select=*&order=queued_at.asc&limit=25`),
    // claim the row: only one sender at a time, and only while it is queued or failed
    claim: async (id: string, attempts: number, now: string) => ((await call(`mail_outbox?id=eq.${encodeURIComponent(id)}&status=in.(queued,failed)&attempts=lt.${MAX_ATTEMPTS}`,
      { method: 'PATCH', body: JSON.stringify({ status: 'sending', attempts: attempts + 1, updated_at: now }) }))[0] || null),
    finish: async (id: string, patch: Record<string, unknown>) => await call(`mail_outbox?id=eq.${encodeURIComponent(id)}`, { method: 'PATCH', body: JSON.stringify(patch) }),
  };
}

async function userOf(env: Env, f: typeof fetch, auth: string) {
  const url = (env('SUPABASE_URL') || '').replace(/\/$/, '');
  const r = await f(url + '/auth/v1/user', { headers: { apikey: env('SUPABASE_ANON_KEY') || '', authorization: auth } });
  if (!r.ok) return null;
  const u = await r.json();
  return u && u.id ? { id: String(u.id) } : null;
}

// ---- the two ways out
async function graphSend(env: Env, f: typeof fetch, m: Msg) {
  const t = await f(`https://login.microsoftonline.com/${encodeURIComponent(env('GRAPH_TENANT_ID') || '')}/oauth2/v2.0/token`, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: env('GRAPH_CLIENT_ID') || '', client_secret: env('GRAPH_CLIENT_SECRET') || '', scope: 'https://graph.microsoft.com/.default', grant_type: 'client_credentials' }).toString() });
  const tj = await t.json().catch(() => ({}));
  if (!t.ok || !tj.access_token) throw new Error('Microsoft sign-in failed: ' + (tj.error_description || tj.error || t.status));
  const r = await f(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(m.from)}/sendMail`, {
    method: 'POST', headers: { authorization: 'Bearer ' + tj.access_token, 'content-type': 'application/json' },
    body: JSON.stringify({ message: { subject: m.subject, body: { contentType: 'HTML', content: m.html },
      from: { emailAddress: { address: m.from, name: m.fromName } },
      toRecipients: m.to.map(x => ({ emailAddress: { address: x.email, name: x.name } })) }, saveToSentItems: true }) });
  if (r.status !== 202 && !r.ok) { const e = await r.json().catch(() => ({})); throw new Error('Microsoft Graph refused the email: ' + ((e.error && e.error.message) || r.status)); }
  return r.headers.get('request-id') || 'graph';
}
const smtpDefault: SmtpSend = async (cfg, m) => {
  const nodemailer = (await import('npm:nodemailer@6.9.16')).default;
  const tr = nodemailer.createTransport({ host: cfg.host, port: cfg.port, secure: cfg.port === 465, auth: { user: cfg.user, pass: cfg.pass } });
  const info = await tr.sendMail({ from: { name: m.fromName, address: m.from }, to: m.to.map(x => ({ name: x.name, address: x.email })), subject: m.subject, html: m.html });
  return String(info.messageId || 'smtp');
};

// ---- send one row
async function sendRow(deps: Deps, D: ReturnType<typeof db>, row: any) {
  const P = providerOf(deps.env), now = (deps.now ? deps.now() : new Date()).toISOString();
  if (row.status === 'sent') return { id: row.id, status: 'sent', note: 'already sent' };
  if (row.status === 'sending') return { id: row.id, status: 'sending', note: 'already being sent' };
  if (!P.ready) { await D.finish(row.id, { error: P.problem, updated_at: now }); return { id: row.id, status: row.status, error: P.problem }; }
  const to = (Array.isArray(row.recipients) ? row.recipients : []).filter((x: any) => x && EMAIL.test(String(x.email || '')))
    .map((x: any) => ({ name: String(x.name || x.email), email: String(x.email) }));
  if (!to.length) { await D.finish(row.id, { status: 'failed', error: 'No valid recipient', updated_at: now }); return { id: row.id, status: 'failed', error: 'No valid recipient' }; }
  if (to.length > MAX_TO) { await D.finish(row.id, { status: 'failed', error: `More than ${MAX_TO} recipients`, updated_at: now }); return { id: row.id, status: 'failed', error: `More than ${MAX_TO} recipients` }; }
  const claimed = await D.claim(row.id, Number(row.attempts) || 0, now);
  if (!claimed) return { id: row.id, status: row.status, error: Number(row.attempts) >= MAX_ATTEMPTS ? `Tried ${MAX_ATTEMPTS} times; a super admin can send it again` : 'Not available to send' };
  const m: Msg = { from: P.from, fromName: (deps.env('MAIL_FROM_NAME') || 'ProTrack').trim(), to, subject: String(row.subject), html: String(row.html) };
  try {
    const ref = P.provider === 'graph' ? await graphSend(deps.env, deps.fetch, m)
      : await (deps.smtp || smtpDefault)({ host: deps.env('SMTP_HOST') || '', port: Number(deps.env('SMTP_PORT') || 465), user: deps.env('SMTP_USER') || '', pass: deps.env('SMTP_PASS') || '' }, m);
    const done = (deps.now ? deps.now() : new Date()).toISOString();
    await D.finish(row.id, { status: 'sent', error: null, provider: P.provider, provider_ref: String(ref).slice(0, 200), sent_at: done, updated_at: done });
    return { id: row.id, status: 'sent', n: to.length };
  } catch (e) {
    const msg = String((e as Error).message || e).slice(0, 500);
    await D.finish(row.id, { status: 'failed', error: msg, provider: P.provider, updated_at: (deps.now ? deps.now() : new Date()).toISOString() });
    return { id: row.id, status: 'failed', error: msg };
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Use POST' }, 405);
  const auth = req.headers.get('authorization') || '';
  const service = !!deps.env('SUPABASE_SERVICE_ROLE_KEY') && auth === 'Bearer ' + deps.env('SUPABASE_SERVICE_ROLE_KEY');
  let body: any = {};
  try { body = await req.json(); } catch { return json({ error: 'The request is not JSON' }, 400); }
  const D = db(deps.env, deps.fetch);
  let uid = '', sa = false;
  if (!service) {
    const u = auth.startsWith('Bearer ') ? await userOf(deps.env, deps.fetch, auth) : null;
    if (!u) return json({ error: 'Sign in first' }, 401);
    const p = await D.role(u.id);
    if (!p || p.active === false) return json({ error: 'Your account is not active' }, 403);
    uid = u.id; sa = p.role === 'sa';
  }
  try {
    if (body.ping) { const P = providerOf(deps.env); return json({ provider: P.provider, from: P.from, ready: P.ready, problem: P.problem || null }); }
    if (body.pending) {
      if (!service && !sa) return json({ error: 'Only a super admin sends the queued emails' }, 403);
      const rows = await D.pending(), out = [];
      for (const r of rows) out.push(await sendRow(deps, D, r));
      return json({ sent: out.filter(x => x.status === 'sent').length, results: out });
    }
    const id = String(body.id || '');
    if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: 'Say which email to send' }, 400);
    const row = await D.row(id);
    if (!row) return json({ error: 'Unknown email' }, 404);
    if (!service && !sa && row.queued_by !== uid) return json({ error: 'Only the person who queued this email, or a super admin, sends it' }, 403);
    return json(await sendRow(deps, D, row));
  } catch (e) {
    return json({ error: String((e as Error).message || e).slice(0, 300) }, 500);
  }
}

if (typeof Deno !== 'undefined' && Deno.serve) Deno.serve((req: Request) => handle(req, { env: (k: string) => Deno.env.get(k), fetch }));
