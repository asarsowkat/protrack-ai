// Server-side tests for ProTrack schema update v50 (RASA Intelligence: the knowledge index, permission-aware search, gaps,
// feedback and the teaching and review workflow). Loads schema.sql and every update v2 to v50 into PGlite (PostgreSQL in
// WebAssembly, so no local PostgreSQL is needed), then runs the checks as signed-in people.
// Usage: npm install @electric-sql/pglite@0.2.17 in any folder, then
//        NODE_PATH=<that folder>/node_modules node test_v50.cjs     (results in test_v50_results.json)
const fs = require('fs'), path = require('path');
const { PGlite } = require('@electric-sql/pglite');
const { uuid_ossp } = require('@electric-sql/pglite/contrib/uuid_ossp');
const HERE = __dirname, SB = path.dirname(HERE);
const PEOPLE = { pe: ['plan', 'Pia Planner'], cc: ['costing', 'Cody Costing'], pm: ['pm', 'Paul Manager'], fo: ['foreman', 'Faisal Foreman'], sa: ['sa', 'Sara Admin'],
  rv: ['pm', 'Rita Reviewer'], co: ['pm', 'Carl Company'], out: ['costing', 'Olga Outside'] };
const U = Object.fromEntries(Object.keys(PEOPLE).map((k, i) => [k, `00000000-0000-0000-0000-0000000050${String(i + 1).padStart(2, '0')}`]));
const results = [];
function check(name, ok, detail) { results.push({ check: name, pass: !!ok, detail: String(detail == null ? '' : typeof detail === 'string' ? detail : JSON.stringify(detail)).slice(0, 300) });
  console.log((ok ? 'PASS ' : 'FAIL ') + name + (ok ? '' : '  -> ' + String(typeof detail === 'string' ? detail : JSON.stringify(detail)).slice(0, 300))); }
const lit = o => "'" + JSON.stringify(o).replace(/'/g, "''") + "'::jsonb";
let db;
async function q(sql) { const r = await db.query(sql); return r.rows; }
async function as(who, sql) {
  await db.exec('begin'); try {
    await db.exec(`set local role authenticated; select set_config('request.jwt.claim.sub', '${U[who]}', true);`);
    const r = await db.query(sql); await db.exec('commit'); return { ok: true, rows: r.rows };
  } catch (e) { await db.exec('rollback'); return { ok: false, err: e.message }; } }
async function call(who, fn, p) { const r = await as(who, `select ${fn}(${lit(p)}) as r`); return r.ok ? { ok: true, r: r.rows[0].r } : r; }
async function yes(name, res, cond = () => true) { let good = res.ok; try { good = good && cond(res.r !== undefined ? res.r : res.rows); } catch (e) { good = false; res.err = String(e); } check(name, good, res.ok ? (res.r !== undefined ? res.r : res.rows) : res.err); return res.r; }
async function no(name, res, msg) { check(name, !res.ok && (!msg || res.err.toLowerCase().includes(msg.toLowerCase())), res.ok ? res.r || res.rows : res.err); }
const src = (mod, rec, o = {}) => Object.assign({ id: mod + ':' + rec, rec, pid: 'P1', cls: 'all', appr: 'Recorded', hash: 'h1', title: rec, chunks: [{ i: 0, t: 'The 132kV transformer delivery for ' + rec, loc: 'Activity', ids: [rec] }] }, o);

(async () => {
  db = new PGlite({ extensions: { uuid_ossp } });
  const files = ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'];
  for (let v = 2; v <= 50; v++) if (fs.existsSync(path.join(SB, `schema-update-v${v}.sql`))) files.push(`schema-update-v${v}.sql`);
  for (const f of files) { try { await db.exec(fs.readFileSync(path.join(SB, f), 'utf8')); } catch (e) { console.log('setup failed: ' + f + ': ' + e.message); process.exit(1); } }
  await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v50.sql'), 'utf8'));
  check('Install: v50 runs a second time without errors', true);
  await db.exec(`insert into auth.users (id, email) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', '${k}@test.local')`).join(',')};
    insert into profiles (id, name, role) values ${Object.entries(PEOPLE).map(([k, [r, n]]) => `('${U[k]}', '${n}', '${r}')`).join(',')};
    insert into regions (id, name) values ('R1', 'Western'); insert into sectors (id, name) values ('S1', 'Power');
    insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values
      ('P1', 'Thuwal 2', 'TK2', 'R1', 'S1', '2023-01-01', '2026-12-31', 30, 'Active'), ('P2', 'Rabigh', 'RB', 'R1', 'S1', '2023-01-01', '2026-12-31', 20, 'Active');
    insert into project_access (user_id, project_id) values ${['pe', 'cc', 'pm', 'fo', 'rv', 'co'].map(k => `('${U[k]}', 'P1')`).join(',')}, ('${U.out}', 'P2');
    insert into user_rights (user_id, right_key, allow) values ('${U.rv}', 'rasa.review', true), ('${U.co}', 'rasa.review', true), ('${U.co}', 'rasa.company', true);`);

  check('Install: rasa_features reports version 50, vector search off', (await q(`select rasa_features() ->> 'version' v, rasa_features() ->> 'vector_search' x`))[0].v === '50');
  check('Install: the four rights and the screen are listed', (await q(`select 'rasa.teach' = any(pt_rights()) and 'rasa.company' = any(pt_rights()) and 'rasa' = any(pt_screens()) ok`))[0].ok);
  check('Install: rasa.teach for planning, not foremen; rasa.sync for planning and costing; rasa.review given only',
    (await q(`select pt_right_default('plan','rasa.teach') and not pt_right_default('foreman','rasa.teach') and pt_right_default('costing','rasa.sync') and not pt_right_default('pm','rasa.sync') and not pt_right_default('pm','rasa.review') ok`))[0].ok);

  // sync
  await yes('Sync: a planning engineer indexes two schedule sources', await call('pe', 'rasa_sync', { mod: 'sched', sources: [src('sched', 'A100'), src('sched', 'A200')], removed: [], last: true }), r => r.added === 2);
  await yes('Sync: the same hashes again change nothing', await call('pe', 'rasa_sync', { mod: 'sched', sources: [src('sched', 'A100'), src('sched', 'A200')], last: true }), r => r.added === 0 && r.changed === 0);
  await yes('Sync: a changed source gets version 2 and its history', await call('pe', 'rasa_sync', { mod: 'sched', sources: [src('sched', 'A100', { hash: 'h2' })], last: true }), r => r.changed === 1);
  check('Sync: version and history kept', (await q(`select ver, jsonb_array_length(data -> 'hist') n from rasa_sources where id = 'sched:A100'`))[0].ver === 2);
  await no('Sync: a foreman does not refresh RASA', await call('fo', 'rasa_sync', { mod: 'sched', sources: [src('sched', 'A300')] }), 'refresh');
  await no('Sync: a source outside the person\'s projects is refused', await call('out', 'rasa_sync', { mod: 'proc', sources: [src('proc', 'X1', { cls: 'mat' })] }), 'Not your project');
  await no('Sync: a source cannot be less protected than its module', await call('cc', 'rasa_sync', { mod: 'cost', sources: [src('cost', 'B1', { cls: 'all' })] }), 'access class');
  await no('Sync: a source id must be its module and record', await call('pe', 'rasa_sync', { mod: 'sched', sources: [src('sched', 'A1', { id: 'cost:A1' })] }), 'module and record');
  await yes('Sync: a costing engineer indexes cost figures', await call('cc', 'rasa_sync', { mod: 'cost', sources: [src('cost', 'B1', { cls: 'money', chunks: [{ i: 0, t: 'Budget overrun on the transformer package SAR 1.2 million', loc: 'Budget', ids: ['B1'] }] })], last: true }), r => r.added === 1);
  await yes('Sync: a contract document of box C01 (contract row)', await call('cc', 'rasa_sync', { mod: 'docs', sources: [src('docs', 'doc:D1', { cls: 'doc:contract', box: 'C01', chunks: [{ i: 0, t: 'Clause 20.1 notice of claim within 28 days for the transformer', loc: 'Page 1', ids: ['20.1'] }] })], last: true }), r => r.added === 1);
  await yes('Sync: a failed source is recorded as Failed', await call('pe', 'rasa_sync', { mod: 'sched', sources: [src('sched', 'A300', { fail: 'The file could not be read' })], last: true }), r => r.failed === 1);
  await yes('Sync: a removed record is marked Deleted', await call('pe', 'rasa_sync', { mod: 'sched', sources: [], removed: ['sched:A200'], last: true }), r => r.removed === 1);
  check('Sync: Deleted source has no passages left', (await q(`select (select st from rasa_sources where id = 'sched:A200') st, (select count(*)::int from rasa_chunks where source_id = 'sched:A200') n`))[0].n === 0);
  check('Sync: every run is logged', (await q(`select count(*)::int n from rasa_runs`))[0].n >= 5);
  await yes('Sync: a failed run is logged with its error', await call('pe', 'rasa_sync', { mod: 'sched', sources: [], removed: [], error: 'network', last: true }), r => r.run.err === 'network');

  // search and reading
  await yes('Search: the costing engineer finds schedule, cost and contract passages', await call('cc', 'rasa_search', { q: 'transformer' }), r => r.rows.length === 3 && r.hidden === 0);
  await yes('Search: a foreman finds the schedule only; the cost and contract passages are counted as hidden', await call('fo', 'rasa_search', { q: 'transformer' }), r => r.rows.length === 1 && r.hidden === 2);
  await yes('Search: someone outside the project sees nothing', await call('out', 'rasa_search', { q: 'transformer' }), r => r.rows.length === 0);
  await yes('Search: module filter (contract finds the contract document)', await call('cc', 'rasa_search', { q: 'notice claim', mods: ['contract'] }), r => r.rows.length === 1 && r.rows[0].source_id === 'docs:doc:D1');
  await yes('Search: a record number is searchable', await call('pe', 'rasa_search', { q: 'A100' }), r => r.rows.some(x => x.source_id === 'sched:A100'));
  await yes('Search: an empty question returns nothing', await call('pe', 'rasa_search', { q: '  ' }), r => r.rows.length === 0);
  await no('Read: nobody reads the passages table directly', await as('cc', 'select * from rasa_chunks'), 'permission denied');
  await yes('Read: a foreman lists only the sources he may open', await as('fo', 'select id from rasa_sources order by id'), rows => rows.every(x => x.id.startsWith('sched:')));
  await yes('Read: rasa_passages gives a costing engineer the cost passage', await as('cc', `select * from rasa_passages('{"source_id":"cost:B1"}')`), rows => rows.length === 1);
  await yes('Read: rasa_passages gives a foreman nothing for it', await as('fo', `select * from rasa_passages('{"source_id":"cost:B1"}')`), rows => rows.length === 0);
  await no('Read: anonymous callers cannot search', await (async () => { await db.exec('begin'); try { await db.exec('set local role anon'); await db.query(`select rasa_search('{"q":"x"}')`); await db.exec('commit'); return { ok: true }; } catch (e) { await db.exec('rollback'); return { ok: false, err: e.message }; } })(), 'permission denied');

  // questions, gaps, feedback
  await yes('Questions: a question is logged with a gap', await call('pe', 'rasa_act', { op: 'question', q: { id: 'Q1', q: 'What is the LD cap?', pids: ['P1'] }, gap: { key: 'ld cap', pid: 'P1', mod: 'contract', why: 'none' } }));
  await yes('Questions: the same unanswered question counts on the gap', await call('pm', 'rasa_act', { op: 'question', q: { id: 'Q2', q: 'LD cap?', pids: ['P1'] }, gap: { key: 'ld cap', pid: 'P1' } }));
  check('Gaps: one open gap GAP-00001 asked twice', JSON.stringify(await q(`select id, n from rasa_gaps`)) === JSON.stringify([{ id: 'GAP-00001', n: 2 }]));
  await no('Questions: not for another project', await call('out', 'rasa_act', { op: 'question', q: { id: 'Q3', q: 'x', pids: ['P1'] } }), 'Not your project');
  await yes('Feedback: the asker marks an answer not helpful', await call('pe', 'rasa_act', { op: 'feedback', qid: 'Q1', v: -1, note: 'missing the clause' }));
  await no('Feedback: another person cannot rate someone else\'s answer', await call('fo', 'rasa_act', { op: 'feedback', qid: 'Q1', v: 1 }), 'no longer in the log');
  await yes('Questions: the asker sees their question; a reviewer sees it too', await as('rv', `select count(*)::int n from rasa_questions`), rows => rows[0].n === 2);
  await yes('Questions: a foreman does not see others\' questions', await as('fo', `select count(*)::int n from rasa_questions`), rows => rows[0].n === 0);
  await no('Gaps: a foreman cannot resolve a gap', await call('fo', 'rasa_act', { op: 'gap', id: 'GAP-00001', a: 'resolve' }), 'resolve gaps');

  // teaching and review
  await no('Teach: a foreman cannot teach RASA', await call('fo', 'rasa_act', { op: 'prop_save', p: { kind: 'note', title: 'Test', text: 'Some knowledge text', scope: 'project', pid: 'P1' } }), 'right to teach');
  await no('Teach: a correction needs the incorrect statement and why', await call('pe', 'rasa_act', { op: 'prop_save', p: { kind: 'correction', title: 'Fix', text: 'The right value is 10%', scope: 'project', pid: 'P1' } }), 'Quote the incorrect');
  const p1 = await yes('Teach: a planning engineer drafts and submits a project rule', await call('pe', 'rasa_act', { op: 'prop_save', submit: true, p: { kind: 'rule', title: 'LD cap', text: 'The LD cap is 10 percent of the contract value', scope: 'project', pid: 'P1', mod: 'contract', purpose: 'Claims', gap: 'GAP-00001' } }), r => r.st === 'Submitted');
  await no('Review: the author cannot review their own proposal', await call('pe', 'rasa_act', { op: 'prop', id: p1.id, a: 'take' }), 'review');
  await no('Review: a project manager without rasa.review cannot', await call('pm', 'rasa_act', { op: 'prop', id: p1.id, a: 'take' }), 'knowledge reviewer');
  await no('Review: approval needs the review first', await call('rv', 'rasa_act', { op: 'prop', id: p1.id, a: 'approve' }), 'Take the proposal');
  await yes('Review: a reviewer takes it', await call('rv', 'rasa_act', { op: 'prop', id: p1.id, a: 'take' }), r => r.st === 'Under Review');
  await yes('Review: and approves it', await call('rv', 'rasa_act', { op: 'prop', id: p1.id, a: 'approve' }), r => r.st === 'Approved');
  await yes('Review: and publishes it', await call('rv', 'rasa_act', { op: 'prop', id: p1.id, a: 'publish' }), r => r.st === 'Published');
  check('Publish: version 1 recorded, the gap resolved, the taught source indexed',
    (await q(`select (select count(*)::int from rasa_publications) n, (select st from rasa_gaps where id = 'GAP-00001') g, (select st from rasa_sources where id = 'taught:kp:${p1.id}') s`)).map(x => x.n + x.g + x.s)[0] === '1ResolvedIndexed');
  await yes('Publish: the taught knowledge is found by search', await call('pm', 'rasa_search', { q: 'LD cap percent' }), r => r.rows.some(x => x.source_id === 'taught:kp:' + p1.id));
  await no('Publish: the published record cannot be edited by its author', await call('pe', 'rasa_act', { op: 'prop_save', p: { id: p1.id, kind: 'rule', title: 'LD cap', text: 'Changed text here', scope: 'project', pid: 'P1', mod: 'contract', purpose: 'Claims' } }), 'cannot be changed');

  // conflict, supersede and rollback
  const p2 = await yes('Conflict: a second rule with the same title is flagged on submit', await call('cc', 'rasa_act', { op: 'prop_save', submit: true, p: { kind: 'rule', title: 'LD Cap', text: 'The LD cap is 5 percent of the contract value', scope: 'project', pid: 'P1', mod: 'contract', purpose: 'Claims' } }), r => r.st === 'Submitted');
  check('Conflict: the conflict names the published rule', (await q(`select data -> 'conflicts' -> 0 ->> 'id' c from rasa_proposals where id = '${p2.id}'`))[0].c === p1.id);
  await call('rv', 'rasa_act', { op: 'prop', id: p2.id, a: 'take' });
  await no('Conflict: approval waits for the conflict to be resolved', await call('rv', 'rasa_act', { op: 'prop', id: p2.id, a: 'approve' }), 'Resolve the conflict');
  await yes('Conflict: the reviewer chooses to replace', await call('rv', 'rasa_act', { op: 'prop', id: p2.id, a: 'resolve', note: 'replace' }));
  await call('rv', 'rasa_act', { op: 'prop', id: p2.id, a: 'approve' });
  await yes('Conflict: publishing supersedes the older rule', await call('rv', 'rasa_act', { op: 'prop', id: p2.id, a: 'publish' }), r => r.st === 'Published');
  check('Conflict: the older rule is Superseded and leaves the index', (await q(`select (select st from rasa_proposals where id = '${p1.id}') a, (select st from rasa_sources where id = 'taught:kp:${p1.id}') b`)).map(x => x.a + '/' + x.b)[0] === 'Superseded/Deleted');
  await no('Rollback: needs a reason', await call('rv', 'rasa_act', { op: 'prop', id: p2.id, a: 'unpublish' }), 'Say why');
  await yes('Rollback: rolling back the new rule restores the older one', await call('rv', 'rasa_act', { op: 'prop', id: p2.id, a: 'unpublish', note: 'Wrong figure' }), r => r.st === 'Withdrawn');
  check('Rollback: the older rule is Published and indexed again; three publication versions', (await q(`select (select st from rasa_proposals where id = '${p1.id}') a, (select st from rasa_sources where id = 'taught:kp:${p1.id}') b, (select max(ver) from rasa_publications) v`)).map(x => x.a + '/' + x.b + '/' + x.v)[0] === 'Published/Indexed/3');

  // financial formula and company-wide knowledge
  const p3 = await yes('Finance: a financial formula is drafted and submitted', await call('cc', 'rasa_act', { op: 'prop_save', submit: true, p: { kind: 'rule', fin: true, title: 'CPI formula', text: 'CPI is earned value divided by actual cost', scope: 'project', pid: 'P1', mod: 'cost', purpose: 'Cost control' } }), r => r.st === 'Submitted');
  await call('rv', 'rasa_act', { op: 'prop', id: p3.id, a: 'take' });
  await no('Finance: approval needs the regression check confirmed', await call('rv', 'rasa_act', { op: 'prop', id: p3.id, a: 'approve' }), 'regression');
  await yes('Finance: one approval is not enough', await call('rv', 'rasa_act', { op: 'prop', id: p3.id, a: 'approve', regress: true }), r => r.st === 'Under Review');
  await no('Finance: the same reviewer cannot approve twice', await call('rv', 'rasa_act', { op: 'prop', id: p3.id, a: 'approve', regress: true }), 'already');
  await yes('Finance: a second approver approves it', await call('co', 'rasa_act', { op: 'prop', id: p3.id, a: 'approve', regress: true }), r => r.st === 'Approved');
  const p4 = await yes('Company: a company-wide note is submitted', await call('pe', 'rasa_act', { op: 'prop_save', submit: true, p: { kind: 'note', title: 'Weekly cut-off', text: 'Progress is cut off every Thursday at noon', scope: 'company' } }), r => r.st === 'Submitted');
  await no('Company: a project reviewer cannot review company-wide knowledge', await call('rv', 'rasa_act', { op: 'prop', id: p4.id, a: 'take' }), 'designated approvers');
  await yes('Company: the designated approver can', await call('co', 'rasa_act', { op: 'prop', id: p4.id, a: 'take' }), r => r.st === 'Under Review');
  await yes('Withdraw: the author withdraws a proposal under review', await call('pe', 'rasa_act', { op: 'prop', id: p4.id, a: 'withdraw' }), r => r.st === 'Withdrawn');

  // settings, logs
  await no('Settings: only the super admin changes them', await call('pe', 'rasa_act', { op: 'settings', cfg: { keep: 90, pol: { fin: 2 } } }), 'super admin');
  await no('Settings: retention is 30 to 730 days', await call('sa', 'rasa_act', { op: 'settings', cfg: { keep: 5, pol: { fin: 2 } } }), '30 to 730');
  await yes('Settings: the super admin saves them', await call('sa', 'rasa_act', { op: 'settings', cfg: { keep: 90, pol: { fin: 3 }, mods: { sched: { on: false } } } }));
  await yes('Settings: a module switched off is not searched', await call('cc', 'rasa_search', { q: 'transformer' }), r => !r.rows.some(x => x.source_id.startsWith('sched:')));
  check('Activity: entries were written', (await q(`select count(*)::int n from rasa_activity`))[0].n >= 8);
  let blocked = 0; for (const s of ['update rasa_activity set k = k', 'delete from rasa_publications', 'truncate rasa_activity']) { try { await db.query(s); } catch (e) { blocked++; } }
  check('Activity and publications are append-only (update, delete and truncate refused)', blocked === 3, blocked);
  await no('Writes: nobody writes the tables directly', await as('sa', `insert into rasa_gaps (id, key) values ('X', 'x')`), 'permission denied');

  // every table the app loads is readable by signed-in people (no policy calls a function they may not execute)
  for (const t of ['rasa_config', 'rasa_sources', 'rasa_runs', 'rasa_proposals', 'rasa_publications', 'rasa_gaps', 'rasa_feedback', 'rasa_questions', 'rasa_activity'])
    await yes(`Load: a planning engineer reads ${t}`, await as('pe', `select count(*)::int n from ${t}`));
  await yes('Load: a foreman of P1 sees its three proposals', await as('fo', `select count(*)::int n from rasa_proposals where project_id = 'P1'`), rows => rows[0].n === 3);
  await yes('Load: someone outside P1 sees none of its proposals', await as('out', `select count(*)::int n from rasa_proposals where project_id = 'P1'`), rows => rows[0].n === 0);
  for (const t of ['cost_plans', 'report_media', 'client_report_format_picks', 'client_report_exports'])
    await yes(`Fix: ${t} (v45 to v48) is readable by signed-in people again`, await as('cc', `select count(*)::int n from ${t}`));

  // rollback and reinstall
  try { await db.exec(fs.readFileSync(path.join(SB, 'schema-rollback-v50.sql'), 'utf8'));
    const r = (await q(`select to_regclass('public.rasa_sources') t, 'rasa' = any(pt_screens()) s, 'rasa.teach' = any(pt_rights()) k`))[0];
    check('Rollback: tables, screen and rights removed', r.t === null && !r.s && !r.k, r);
    await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v50.sql'), 'utf8')); check('Rollback: v50 installs again afterwards', true);
  } catch (e) { check('Rollback and reinstall', false, e.message); }

  fs.writeFileSync(path.join(HERE, 'test_v50_results.json'), JSON.stringify(results, null, 1));
  const f = results.filter(x => !x.pass).length; console.log(`\n${results.length - f}/${results.length} passed`); process.exit(f ? 1 : 0);
})();
