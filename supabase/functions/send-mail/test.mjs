// Tests for the send-mail Edge Function, run with Node 22: node --experimental-strip-types test.mjs
// The database (PostgREST), Supabase Auth, Microsoft sign-in, Microsoft Graph and the SMTP relay are simulated in memory.
import { handle, providerOf } from './index.ts';

const res = [], check = (n, c, d) => { res.push({ check: n, pass: !!c, detail: c ? '' : JSON.stringify(d ?? '').slice(0, 300) }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  -> ' + JSON.stringify(d ?? '').slice(0, 300))); };
const SRV = 'service-key', U = { sa: 'aaaaaaaa-0000-0000-0000-000000000001', pm: 'aaaaaaaa-0000-0000-0000-000000000002', pl: 'aaaaaaaa-0000-0000-0000-000000000003', old: 'aaaaaaaa-0000-0000-0000-000000000004' };
const TOK = { 'tok-sa': U.sa, 'tok-pm': U.pm, 'tok-pl': U.pl, 'tok-old': U.old };
const PROF = { [U.sa]: { role: 'sa', active: true }, [U.pm]: { role: 'pm', active: true }, [U.pl]: { role: 'plan', active: true }, [U.old]: { role: 'pm', active: false } };
let rows, sent, graphFail, tokenFail, calls;
const id = n => `bbbbbbbb-0000-0000-0000-00000000000${n}`;
const reset = () => {
  rows = [1, 2, 3, 4, 5].map(n => ({ id: id(n), status: 'queued', attempts: 0, error: null, queued_by: n === 2 ? U.pl : U.pm, queued_at: `2026-10-2${n}T08:00:00Z`, subject: 'Daily report approved: TP1', html: '<p>Hi</p>',
    recipients: [{ id: U.pm, name: 'Paul', email: 'pm@test.local', role: 'pm' }, { id: null, name: 'bad', email: 'not an address', role: 'other' }] }));
  sent = []; graphFail = false; tokenFail = false; calls = [];
};
const ENVS = {
  graph: { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: SRV, MAIL_PROVIDER: 'graph', MAIL_FROM: 'protrack@company.com', GRAPH_TENANT_ID: 'tid', GRAPH_CLIENT_ID: 'cid', GRAPH_CLIENT_SECRET: 'secret' },
  smtp: { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: SRV, MAIL_PROVIDER: 'smtp', MAIL_FROM: 'protrack@company.com', SMTP_HOST: 'smtp.company.com', SMTP_PORT: '465', SMTP_USER: 'u', SMTP_PASS: 'p' },
  none: { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: SRV },
};
const fakeFetch = async (url, init = {}) => {
  url = String(url); calls.push({ url, method: init.method || 'GET' });
  const H = init.headers || {}, J = (b, s = 200, h = {}) => new Response(JSON.stringify(b), { status: s, headers: { 'content-type': 'application/json', ...h } });
  if (url.endsWith('/auth/v1/user')) { const t = String(H.authorization || '').replace('Bearer ', ''); return TOK[t] ? J({ id: TOK[t] }) : J({ msg: 'invalid' }, 401); }
  if (url.includes('/rest/v1/')) {
    if (H.authorization !== 'Bearer ' + SRV) return J({ message: 'not service' }, 401);
    const [path, qs] = url.split('/rest/v1/')[1].split('?'), P = new URLSearchParams(qs);
    if (path === 'profiles') { const uid = P.get('id').replace('eq.', ''); return J(PROF[uid] ? [PROF[uid]] : []); }
    if (path === 'mail_outbox') {
      let L = rows;
      if (P.get('id')) L = L.filter(r => r.id === P.get('id').replace('eq.', ''));
      if (P.get('status')) { const v = P.get('status'); L = v.startsWith('in.(') ? L.filter(r => v.slice(4, -1).split(',').includes(r.status)) : L.filter(r => r.status === v.replace('eq.', '')); }
      if (P.get('attempts')) L = L.filter(r => r.attempts < +P.get('attempts').replace('lt.', ''));
      if ((init.method || 'GET') === 'PATCH') { const b = JSON.parse(init.body); L.forEach(r => Object.assign(r, b)); return J(L.map(r => ({ ...r }))); }
      return J(L.slice().sort((a, b) => a.queued_at.localeCompare(b.queued_at)).slice(0, 25).map(r => ({ ...r })));
    }
  }
  if (url.startsWith('https://login.microsoftonline.com/tid/oauth2/v2.0/token')) return tokenFail ? J({ error: 'invalid_client', error_description: 'bad secret' }, 401) : J({ access_token: 'graph-token' });
  if (url.startsWith('https://graph.microsoft.com/v1.0/users/protrack%40company.com/sendMail')) {
    if (H.authorization !== 'Bearer graph-token') return J({ error: { message: 'no token' } }, 401);
    if (graphFail) return J({ error: { message: 'Mailbox not found' } }, 404);
    const b = JSON.parse(init.body); sent.push({ via: 'graph', to: b.message.toRecipients.map(x => x.emailAddress.address), subject: b.message.subject, html: b.message.body.content, from: b.message.from.emailAddress.address });
    return new Response(null, { status: 202, headers: { 'request-id': 'req-123' } });
  }
  return J({ error: 'unexpected ' + url }, 500);
};
const smtp = async (cfg, m) => { sent.push({ via: 'smtp', cfg, to: m.to.map(x => x.email), subject: m.subject }); return '<msg-1@company.com>'; };
const call = async (env, tok, body, method = 'POST') => {
  const r = await handle(new Request('https://fn/send-mail', { method, headers: tok ? { authorization: 'Bearer ' + tok, 'content-type': 'application/json' } : { 'content-type': 'application/json' }, body: method === 'POST' ? JSON.stringify(body) : undefined }),
    { env: k => ENVS[env][k], fetch: fakeFetch, smtp, now: () => new Date('2026-10-23T09:00:00Z') });
  return { status: r.status, body: r.status === 200 && method === 'OPTIONS' ? null : await r.json().catch(() => null) };
};

reset();
// ---- the mail service settings
check('Graph settings complete: ready', providerOf(k => ENVS.graph[k]).ready === true);
check('no provider: not ready, with the reason', /No mail service/.test(providerOf(k => ENVS.none[k]).problem));
check('SMTP on port 587 is refused with the reason (Supabase blocks it)', /blocked/.test(providerOf(k => ({ ...ENVS.smtp, SMTP_PORT: '587' })[k]).problem));
check('missing settings are named', /GRAPH_CLIENT_SECRET/.test(providerOf(k => ({ ...ENVS.graph, GRAPH_CLIENT_SECRET: '' })[k]).problem));
let r = await call('graph', null, {}, 'OPTIONS'); check('the browser preflight is answered with CORS headers', r.status === 200);
r = await call('graph', null, { ping: true }); check('nobody signed in: refused', r.status === 401, r);
r = await call('graph', 'tok-pm', { ping: true }); check('ping tells which service is set up, without secrets', r.status === 200 && r.body.provider === 'graph' && r.body.ready && !JSON.stringify(r.body).includes('secret'), r.body);
r = await call('graph', 'tok-old', { ping: true }); check('an inactive account is refused', r.status === 403, r);

// ---- sending one email through Microsoft Graph
r = await call('graph', 'tok-pm', { id: id(1) });
check('the person who queued it sends it through Microsoft Graph', r.status === 200 && r.body.status === 'sent' && sent.length === 1 && sent[0].via === 'graph', r.body);
check('it goes from the company mailbox to the recipients the server stored, invalid addresses left out', sent[0].from === 'protrack@company.com' && JSON.stringify(sent[0].to) === '["pm@test.local"]' && sent[0].subject === 'Daily report approved: TP1' && sent[0].html === '<p>Hi</p>', sent[0]);
check('the row is marked sent, with the attempt, the provider and its reference', rows[0].status === 'sent' && rows[0].attempts === 1 && rows[0].provider === 'graph' && rows[0].provider_ref === 'req-123' && rows[0].sent_at, rows[0]);
r = await call('graph', 'tok-pm', { id: id(1) }); check('asking again does not send it twice', r.body.status === 'sent' && sent.length === 1, r.body);
r = await call('graph', 'tok-pm', { id: id(2) }); check('someone else cannot send an email he did not queue', r.status === 403 && sent.length === 1, r);
r = await call('graph', 'tok-sa', { id: id(2) }); check('a super admin can', r.body.status === 'sent' && sent.length === 2, r.body);
r = await call('graph', 'tok-pm', { id: 'nope' }); check('a malformed id is refused', r.status === 400, r);
r = await call('graph', 'tok-pm', { id: 'bbbbbbbb-0000-0000-0000-000000000099' }); check('an unknown email is refused', r.status === 404, r);

// ---- failures are recorded, and limited
graphFail = true; r = await call('graph', 'tok-pm', { id: id(3) });
check('a Graph refusal marks the email failed with the reason', r.body.status === 'failed' && /Mailbox not found/.test(rows[2].error) && rows[2].status === 'failed', r.body);
graphFail = false; tokenFail = true; r = await call('graph', 'tok-pm', { id: id(3) });
check('a Microsoft sign-in failure is recorded too', r.body.status === 'failed' && /sign-in failed: bad secret/.test(rows[2].error) && rows[2].attempts === 2, rows[2]);
tokenFail = false; rows[2].attempts = 5; rows[2].status = 'failed'; r = await call('graph', 'tok-sa', { id: id(3) });
check('after 5 attempts it is not tried again until a super admin re-queues it', r.body.status === 'failed' && /5 times/.test(r.body.error) && sent.length === 2, r.body);
rows[3].status = 'sending'; r = await call('graph', 'tok-pm', { id: id(4) }); check('an email being sent is not sent twice at once', r.body.status === 'sending' && sent.length === 2, r.body);
rows[3].status = 'queued';

// ---- no service set up
r = await call('none', 'tok-pm', { id: id(4) });
check('without a mail service the email stays queued, with the reason', r.body.status === 'queued' && /No mail service/.test(rows[3].error) && rows[3].attempts === 0 && sent.length === 2, r.body);

// ---- SMTP
r = await call('smtp', 'tok-pm', { id: id(4) });
check('the SMTP relay sends it on port 465', r.body.status === 'sent' && sent[2].via === 'smtp' && sent[2].cfg.port === 465 && sent[2].cfg.host === 'smtp.company.com' && rows[3].provider === 'smtp', r.body);

// ---- the queue, for a super admin or a schedule
r = await call('graph', 'tok-pm', { pending: true }); check('only a super admin sends every queued email', r.status === 403, r);
r = await call('graph', null, { pending: true }); check('...or nobody signed in: refused', r.status === 401, r);
const res2 = await handle(new Request('https://fn/send-mail', { method: 'POST', headers: { authorization: 'Bearer ' + SRV }, body: JSON.stringify({ pending: true }) }), { env: k => ENVS.graph[k], fetch: fakeFetch, smtp });
const b2 = await res2.json();
check('a schedule with the service key sends what is still queued', res2.status === 200 && b2.sent === 1 && rows[4].status === 'sent', b2);
r = await call('graph', 'tok-sa', { pending: true }); check('nothing queued: nothing sent', r.body.sent === 0, r.body);
r = await handle(new Request('https://fn/send-mail', { method: 'POST', headers: { authorization: 'Bearer tok-pm' }, body: 'not json' }), { env: k => ENVS.graph[k], fetch: fakeFetch });
check('a body that is not JSON is refused', r.status === 400);

const passed = res.filter(x => x.pass).length;
console.log(`\n${passed}/${res.length} passed`);
process.exitCode = passed === res.length ? 0 : 1;
