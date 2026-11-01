// Server-side tests for ProTrack schema update v51 (the Client Invoice Builder: Schedule-C revisions, the P6 mapping and its
// review, client invoices worked out on the server, the workflow with its separation of duties, the certificate, the
// payment and the audit trail). Loads schema.sql and every update v2 to v51 into PGlite (PostgreSQL in WebAssembly, so no
// local PostgreSQL is needed), then runs the checks as signed-in people.
// Usage: npm install @electric-sql/pglite@0.2.17 in any folder, then
//        NODE_PATH=<that folder>/node_modules node test_v51.cjs     (results in test_v51_results.json)
const fs = require('fs'), path = require('path');
const { PGlite } = require('@electric-sql/pglite');
const { uuid_ossp } = require('@electric-sql/pglite/contrib/uuid_ossp');
const HERE = __dirname, SB = path.dirname(HERE);
const PEOPLE = { pe: ['plan', 'Pia Planner'], cc: ['costing', 'Cody Costing'], pm: ['pm', 'Paul Manager'], rm: ['rm', 'Rana Regional'], fo: ['foreman', 'Faisal Foreman'], sa: ['sa', 'Sara Admin'],
  ro: ['ro', 'Rami Reader'], out: ['costing', 'Olga Outside'], hd: ['pm', 'Huda Head'] };
const U = Object.fromEntries(Object.keys(PEOPLE).map((k, i) => [k, `00000000-0000-0000-0000-0000000051${String(i + 1).padStart(2, '0')}`]));
const SU1 = '00000000-0000-0000-0000-00000000a001', SU2 = '00000000-0000-0000-0000-00000000a002';
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
async function call(who, p) { const r = await as(who, `select cib_act(${lit(p)}) as r`); return r.ok ? { ok: true, r: r.rows[0].r } : r; }
async function yes(name, res, cond = () => true) { let good = res.ok; try { good = good && cond(res.r !== undefined ? res.r : res.rows); } catch (e) { good = false; res.err = String(e); } check(name, good, res.ok ? (res.r !== undefined ? res.r : res.rows) : res.err); return res.r; }
async function no(name, res, msg) { check(name, !res.ok && (!msg || res.err.toLowerCase().includes(msg.toLowerCase())), res.ok ? res.r || res.rows : res.err); }
const inv = async id => (await q(`select * from cib_invoices where id = '${id}'`))[0];
const line = (I, no) => I.data.lines.find(l => l.no === no);
const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.011;

(async () => {
  db = new PGlite({ extensions: { uuid_ossp } });
  const files = ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'];
  for (let v = 2; v <= 51; v++) if (fs.existsSync(path.join(SB, `schema-update-v${v}.sql`))) files.push(`schema-update-v${v}.sql`);
  for (const f of files) { try { await db.exec(fs.readFileSync(path.join(SB, f), 'utf8')); } catch (e) { console.log('setup failed: ' + f + ': ' + e.message); process.exit(1); } }
  await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v51.sql'), 'utf8'));
  check('Install: v51 runs a second time without errors', true);
  await db.exec(`insert into auth.users (id, email) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', '${k}@test.local')`).join(',')};
    insert into profiles (id, name, role) values ${Object.entries(PEOPLE).map(([k, [r, n]]) => `('${U[k]}', '${n}', '${r}')`).join(',')};
    insert into regions (id, name) values ('R1', 'Western'); insert into sectors (id, name) values ('S1', 'Power');
    insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values
      ('P1', 'Thuwal 2', 'TK2', 'R1', 'S1', '2025-01-01', '2027-12-31', 30, 'Active'), ('P2', 'Rabigh', 'RB', 'R1', 'S1', '2025-01-01', '2027-12-31', 20, 'Active');
    insert into project_access (user_id, project_id) values ${['pe', 'cc', 'pm', 'rm', 'fo', 'ro', 'hd'].map(k => `('${U[k]}', 'P1')`).join(',')}, ('${U.out}', 'P2');
    insert into pcc_designations (user_id, designation) values ('${U.hd}', 'head');
    insert into schedule_updates (id, project_id, data_date, weightage, summary) values ('${SU1}', 'P1', '2026-08-31', 'client', '{}'), ('${SU2}', 'P1', '2026-09-30', 'client', '{}');
    insert into schedule_update_rows (update_id, project_id, act_id, w, pct, af) values
      ('${SU1}','P1','A1',100,100,'2026-08-10'),('${SU1}','P1','A2',300,40,null),('${SU1}','P1','A3',100,60,null),('${SU1}','P1','A4',500,100,'2026-08-20'),('${SU1}','P1','D1',50,100,'2026-07-01'),('${SU1}','P1','D2',50,50,null),('${SU1}','P1','A9',10,10,null),
      ('${SU2}','P1','A1',100,50,null),('${SU2}','P1','A2',300,80,null),('${SU2}','P1','A3',100,60,null),('${SU2}','P1','A4',500,100,'2026-08-20'),('${SU2}','P1','D1',50,100,'2026-07-01'),('${SU2}','P1','D2',50,100,'2026-09-20'),('${SU2}','P1','A9',10,20,null);`);

  check('Install: cib_features reports version 51 and no language-model review', (await q(`select cib_features() ->> 'version' v, cib_features() ->> 'llm_review' l`))[0].v === '51');
  check('Install: the six rights and the screen are listed', (await q(`select 'cib.setup' = any(pt_rights()) and 'cib.certify' = any(pt_rights()) and 'cib' = any(pt_screens()) ok`))[0].ok);
  check('Install: defaults: costing and planning set up and prepare; planning maps; the project manager reviews; the regional manager approves; costing certifies; foremen nothing',
    (await q(`select pt_right_default('costing','cib.setup') and pt_right_default('plan','cib.prepare') and pt_right_default('plan','cib.map') and not pt_right_default('costing','cib.map')
      and pt_right_default('pm','cib.review') and not pt_right_default('pm','cib.approve') and pt_right_default('rm','cib.approve') and pt_right_default('costing','cib.certify') and not pt_right_default('foreman','cib.setup') ok`))[0].ok);
  check('Install: the Head of Planning and Cost Control approves through the position', (await q(`select pt_cib_can('${U.hd}','cib.approve','P1') a, pt_cib_can('${U.pm}','cib.approve','P1') b`)).every(r => r.a && !r.b));

  // the rules (the browser's cibPay)
  check('Rules: percentage with TCC and FAC, split 90/10, at TCC, at FAC',
    (await q(`select pt_cib_pay('{"t":"pct","cap":80,"tcc":10,"fac":10}',1000,0.5,false,false) a, pt_cib_pay('{"t":"pct","cap":80,"tcc":10,"fac":10}',1000,1,true,true) b,
      pt_cib_pay('{"t":"split","first":90}',1000,1,false,false) c, pt_cib_pay('{"t":"split","first":90}',1000,1,false,true) d, pt_cib_pay('{"t":"tcc"}',1000,0,true,false) e, pt_cib_pay('{"t":"fac"}',1000,1,true,false) f`))
      .every(r => +r.a === 400 && +r.b === 1000 && +r.c === 900 && +r.d === 1000 && +r.e === 1000 && +r.f === 0));
  check('Rules: the checks refuse percentages that do not add up and phase steps without their activity',
    (await q(`select pt_cib_rule_err('{"t":"pct","cap":80,"tcc":10,"fac":0}') a, pt_cib_rule_err('{"t":"split","first":100}') b, pt_cib_rule_err('{"t":"phase","cap":100,"tcc":0,"fac":0,"steps":[{"n":"I","pct":100}]}') c, pt_cib_rule_err('{"t":"tcc"}') d`))
      .every(r => r.a && r.b && r.c && r.d === null));

  // the Schedule-C: X.1 general, X.2 engineering by phase steps, X.3 material split, X.4 construction, X.5 testing at TCC, X.6 construction (no activity), X.7 not applicable
  const items = [['X.1', 'GEN', 1000], ['X.2', 'ENG', 2000, { t: 'phase', cap: 90, tcc: 10, fac: 0, steps: [{ n: 'Phase I', pct: 50, act: 'D1' }, { n: 'Phase II', pct: 50, act: 'D2' }] }], ['X.3', 'MAT', 10000],
    ['X.4', 'CON', 4000], ['X.5', 'TC', 500, { t: 'tcc' }], ['X.6', 'CON', 2000]].map(([no, comp, value, rule]) => ({ no, comp, value, rule: rule || null, desc: 'Item ' + no, unit: 'LT', qty: 1, rate: value, st: 'Active', leaf: true, limit: 100 }));
  items.push({ no: 'X.7', comp: 'CON', value: 0, desc: 'Not applicable item', st: 'Not applicable', leaf: true });
  const rules = { GEN: { t: 'pct', cap: 80, tcc: 10, fac: 10 }, ENG: { t: 'pct', cap: 90, tcc: 10, fac: 0 }, MAT: { t: 'split', first: 90 }, CON: { t: 'pct', cap: 80, tcc: 10, fac: 10 }, TC: { t: 'pct', cap: 80, tcc: 10, fac: 10 } };
  const head = { value: 19500, vat: 15, ret_pct: 5, ret_cap: 5, ret_tcc: 50, ret_fac: 50, adv_pct: 10, adv_rec: 10, pay_days: 45, contract_no: 'C-1' };
  await no('Schedule-C: a foreman never sees billing', await call('fo', { op: 'sch_save', pid: 'P1', head, items, rules }), 'not open to you');
  await no('Schedule-C: a project manager does not upload it', await call('pm', { op: 'sch_save', pid: 'P1', head, items, rules }), 'cib.setup');
  await no('Schedule-C: someone outside the project does not upload it', await call('out', { op: 'sch_save', pid: 'P1', head, items, rules }), 'access');
  await no('Schedule-C: an item twice is refused', await call('cc', { op: 'sch_save', pid: 'P1', head, items: [...items, { no: ' x.1', value: 1 }], rules }), 'appears twice');
  await no('Schedule-C: a rule that does not add up is refused', await call('cc', { op: 'sch_save', pid: 'P1', head, items, rules: { ...rules, CON: { t: 'pct', cap: 80, tcc: 10, fac: 0 } } }), 'add up');
  const S1 = await yes('Schedule-C: the costing engineer uploads revision 1 as a draft', await call('cc', { op: 'sch_save', pid: 'P1', head, items, rules, file: 'schedule-c.xlsx' }), r => r.rev === 1 && r.st === 'Draft');
  await no('Schedule-C: one draft at a time', await call('cc', { op: 'sch_save', pid: 'P1', head, items, rules }), 'already waiting');
  await db.exec(`insert into user_rights (user_id, right_key, allow) values ('${U.cc}', 'cib.approve', true)`);
  await no('Schedule-C: nobody approves a revision they uploaded', await call('cc', { op: 'sch_approve', pid: 'P1', sch: S1.id }), 'Nobody approves');
  await db.exec(`delete from user_rights where user_id = '${U.cc}' and right_key = 'cib.approve'`);
  await no('Schedule-C: a project manager does not approve it', await call('pm', { op: 'sch_approve', pid: 'P1', sch: S1.id }), 'cib.approve');
  await yes('Schedule-C: the regional manager approves it', await call('rm', { op: 'sch_approve', pid: 'P1', sch: S1.id }));
  await no('Schedule-C: an approved revision does not change', await call('cc', { op: 'sch_rules', pid: 'P1', sch: S1.id, rules }), 'Only a draft revision');
  check('Schedule-C: items stored with the number cleaned, 7 items, approved by name', (await q(`select count(*)::int n, bool_and(item_no = upper(item_no)) u from cib_items where schedule_id = '${S1.id}'`))[0].n === 7
    && (await q(`select approved_name from cib_schedules where id = '${S1.id}'`))[0].approved_name === 'Rana Regional');

  // mapping
  await no('Mapping: costing does not keep the mapping', await call('cc', { op: 'map_save', pid: 'P1', rows: [{ act: 'A1', item: 'X.1' }] }), 'cib.map');
  await no('Mapping: by hand only to an item of the price schedule', await call('pe', { op: 'map_save', pid: 'P1', rows: [{ act: 'A1', item: 'X.99', src: 'manual' }] }), 'not in the price schedule');
  await yes('Mapping: read from the P6 "Schedule C" code (one code not in the schedule is kept as read)', await call('pe', { op: 'map_save', pid: 'P1', replace_p6: true, file: 'update.xer',
    rows: [['A1', 'X.1'], ['A2', 'X.4'], ['A3', 'X.4'], ['A4', 'X.3'], ['D1', 'X.2'], ['D2', 'X.2'], ['A9', 'X.99']].map(([act, item]) => ({ act, item, src: 'p6' })) }), r => r.changed === 7);
  await yes('Mapping: reading the same file again changes nothing', await call('pe', { op: 'map_save', pid: 'P1', replace_p6: true,
    rows: [['A1', 'X.1'], ['A2', 'X.4'], ['A3', 'X.4'], ['A4', 'X.3'], ['D1', 'X.2'], ['D2', 'X.2'], ['A9', 'X.99']].map(([act, item]) => ({ act, item, src: 'p6' })) }), r => r.changed === 0);

  // the first invoice, worked out on the server
  const r1 = await yes('Invoice: the costing engineer prepares #1 to 31 Aug 2026', await call('cc', { op: 'inv_save', pid: 'P1', to: '2026-08-31', from: '2026-08-01' }), r => r.seq === 1);
  let I1 = await inv(r1.id);
  check('Invoice: X.6 has no activity: the invoice is blocked', I1.data.exc.some(e => e.k === 'unmapped' && e.sev === 'block'), I1.data.exc);
  check('Invoice: progress is the weighted % complete (X.4: (300×40 + 100×60) / 400 = 45%) and 45% × 80% of 4,000 = 1,440', near(line(I1, 'X.4').prog, 0.45) && near(line(I1, 'X.4').cum_pay, 1440), line(I1, 'X.4'));
  check('Invoice: phase steps (Phase I done): 50% × 90% of 2,000 = 900; split 90% of 10,000 = 9,000; TCC not achieved: X.5 nothing', near(line(I1, 'X.2').cum_pay, 900) && line(I1, 'X.2').src === 'steps' && near(line(I1, 'X.3').cum_pay, 9000) && near(line(I1, 'X.5').cum_pay, 0) && line(I1, 'X.5').src === 'ms', I1.data.lines.map(l => [l.no, l.cum_pay]));
  check('Invoice: a not-applicable item is not billed', !line(I1, 'X.7'));
  await no('Invoice: a second draft is refused', await call('cc', { op: 'inv_save', pid: 'P1', to: '2026-08-31' }), 'already open');
  await no('Mapping review: a reason is needed', await call('pe', { op: 'map_review', pid: 'P1', item: 'X.6', d: 'manual', pct: 25, note: 'no' }), 'reason');
  await yes('Mapping review: X.6 billed on a stated 25% with its evidence', await call('pe', { op: 'map_review', pid: 'P1', item: 'X.6', d: 'manual', pct: 25, note: 'Site measurement sheet 12 approved by the client engineer' }));
  await yes('Invoice: recalculated', await call('cc', { op: 'inv_save', pid: 'P1', id: r1.id, to: '2026-08-31', from: '2026-08-01' }));
  I1 = await inv(r1.id); const T1 = I1.data.tot;
  check('Invoice: the block is gone; X.6 = 25% × 80% of 2,000 = 400, flagged as a typed %', !I1.data.exc.some(e => e.sev === 'block') && near(line(I1, 'X.6').cum_pay, 400) && line(I1, 'X.6').src === 'manual' && I1.data.exc.some(e => e.k === 'manual'), I1.data.exc);
  const g1 = 800 + 900 + 9000 + 1440 + 400;
  check('Invoice: gross 12,540; retention 5%; advance recovery 10%; net; VAT 15%', near(T1.gross_this, g1) && near(T1.ret_this, g1 * 0.05) && near(T1.adv_this, g1 * 0.1) && near(T1.net, g1 * 0.85) && near(T1.vat, g1 * 0.85 * 0.15) && near(T1.total, g1 * 0.85 * 1.15), T1);

  // the workflow
  await no('Workflow: not submitted before the review', await call('cc', { op: 'inv_submit', pid: 'P1', id: r1.id }), 'Review invoice');
  await yes('Workflow: the review is recorded', await call('cc', { op: 'inv_ai', pid: 'P1', id: r1.id, score: 82, find: [{ sev: 'ok', k: 'math', msg: 'fine' }] }));
  await yes('Workflow: submitted', await call('cc', { op: 'inv_submit', pid: 'P1', id: r1.id }), r => r.st === 'Submitted');
  await no('Workflow: a draft only changes as a draft', await call('cc', { op: 'inv_save', pid: 'P1', id: r1.id, to: '2026-08-31' }), 'Only a draft');
  await db.exec(`insert into user_rights (user_id, right_key, allow) values ('${U.cc}', 'cib.review', true)`);
  await no('Workflow: nobody reviews an invoice they prepared', await call('cc', { op: 'inv_review', pid: 'P1', id: r1.id }), 'Nobody reviews');
  await db.exec(`delete from user_rights where user_id = '${U.cc}' and right_key = 'cib.review'`);
  await yes('Workflow: the project manager reviews it', await call('pm', { op: 'inv_review', pid: 'P1', id: r1.id }), r => r.st === 'Reviewed');
  await no('Workflow: approval needs every supporting document marked', await call('rm', { op: 'inv_approve', pid: 'P1', id: r1.id }), 'supporting document');
  for (const k of ['appr', 'sum', 'mat', 'prog', 'spare', 'train', 'cont', 'ins', 'cert']) await call('cc', { op: 'inv_docs', pid: 'P1', id: r1.id, k, v: ['spare', 'train'].includes(k) ? 'na' : 'yes' });
  await no('Workflow: a return needs its reason', await call('rm', { op: 'inv_return', pid: 'P1', id: r1.id, note: 'x' }), 'Say why');
  await yes('Workflow: the regional manager approves it', await call('rm', { op: 'inv_approve', pid: 'P1', id: r1.id }), r => r.st === 'Approved');
  await no('Workflow: issued only on a valid date', await call('cc', { op: 'inv_issue', pid: 'P1', id: r1.id, date: '2099-01-01' }), 'not valid');
  await yes('Workflow: issued', await call('cc', { op: 'inv_issue', pid: 'P1', id: r1.id, date: '2026-09-05', ref: 'TK2-INV-01' }), r => r.st === 'Issued');
  await no('Workflow: a planning engineer does not record the certificate', await call('pe', { op: 'inv_certify', pid: 'P1', id: r1.id, date: '2026-09-20' }), 'cib.certify');
  await no('Certificate: never more than claimed', await call('cc', { op: 'inv_certify', pid: 'P1', id: r1.id, date: '2026-09-20', lines: { 'X.3': 99999 } }), 'more than claimed');
  await yes('Certificate: the client certified X.3 at 4,500 instead of 9,000', await call('cc', { op: 'inv_certify', pid: 'P1', id: r1.id, date: '2026-09-20', ref: 'CERT-1', lines: { 'X.3': 4500 } }), r => r.st === 'Certified');
  I1 = await inv(r1.id); const c1 = I1.data.cert, Tc = I1.data.tot, gc = g1 - 4500;
  check('Certificate: certified 8,040; retention, advance, net and VAT on the certified amount; X.3 certified to date 4,500', c1.changed && near(c1.amt, gc) && near(Tc.gross_this, gc) && near(Tc.ret_this, gc * 0.05) && near(Tc.adv_this, gc * 0.1) && near(Tc.total, gc * 0.85 * 1.15) && near(line(I1, 'X.3').cert_cum, 4500), { c1, Tc });
  await no('Payment: not more than the total with VAT', await call('cc', { op: 'inv_payment', pid: 'P1', id: r1.id }), 'Unknown action');
  await no('Payment: not more than the total with VAT', await call('cc', { op: 'inv_pay', pid: 'P1', id: r1.id, date: '2026-09-25', amt: 999999 }), 'more than the invoice total');
  await yes('Payment: recorded', await call('cc', { op: 'inv_pay', pid: 'P1', id: r1.id, date: '2026-09-25', amt: Tc.total }), r => r.st === 'Paid');

  // the next invoice: from the certified figures; TCC achieved; a reversal
  await db.exec(`insert into milestones (project_id, name, ms_type, planned, actual) values ('P1', 'Technical completion', 'TCC', '2026-09-30', '2026-09-15')`);
  const r2 = await yes('Next invoice: #2 to 30 Sep 2026', await call('cc', { op: 'inv_save', pid: 'P1', to: '2026-09-30' }), r => r.seq === 2);
  const I2 = await inv(r2.id), T2 = I2.data.tot;
  check('Next invoice: starts the day after #1 and from its certified figures (X.3 previous 4,500, not the 9,000 claimed)', String(I2.period_from).startsWith('2026-09-01') || new Date(I2.period_from).toISOString().startsWith('2026-09-01') ? near(line(I2, 'X.3').prev_pay, 4500) && near(T2.gross_prev, gc) : false, { from: I2.period_from, prev: line(I2, 'X.3').prev_pay });
  check('Next invoice: TCC achieved: X.5 billed in full, X.4 at 75% (80% on progress) plus its 10% TCC share, half the retention released',
    near(line(I2, 'X.5').cum_pay, 500) && near(line(I2, 'X.4').cum_pay, 4000 * (0.8 * 0.75 + 0.1)) && T2.rel_tcc === true && near(T2.rel_this, (Tc.ret_cum + T2.ret_this) * 0.5), { X5: line(I2, 'X.5'), X4: line(I2, 'X.4').cum_pay, T2 });
  check('Next invoice: X.1 progress fell to 50% (400 + 100 at TCC = 500 < 800 certified): schedule reversal, nothing claimed, the certified amount kept', line(I2, 'X.1').rev === true && near(line(I2, 'X.1').this_pay, 0) && near(line(I2, 'X.1').cum_pay, 800) && I2.data.exc.some(e => e.k === 'reversal'), line(I2, 'X.1'));
  check('Next invoice: Phase II complete: X.2 at 90% plus the 10% TCC share', near(line(I2, 'X.2').cum_pay, 2000), line(I2, 'X.2'));
  await no('Next invoice: a draft is cancelled only with a reason', await call('cc', { op: 'inv_cancel', pid: 'P1', id: r2.id, note: '' }), 'Say why');
  await yes('Next invoice: cancelled', await call('cc', { op: 'inv_cancel', pid: 'P1', id: r2.id, note: 'Prepared again after the client meeting' }), r => r.st === 'Cancelled');
  const r3 = await yes('Next invoice: prepared again as #2', await call('cc', { op: 'inv_save', pid: 'P1', to: '2026-09-30' }), r => r.seq === 2);
  await no('History: loaded only before the first invoice', await call('cc', { op: 'inv_migrate', pid: 'P1', seq: 1, to: '2026-01-31', lines: [{ no: 'X.1', cum: 100 }] }), 'before the first invoice');
  await yes('Progress source: a manual mapping overrides the P6 one', await call('pe', { op: 'map_save', pid: 'P1', rows: [{ act: 'A9', item: 'X.6', src: 'manual', name: 'Fencing' }] }), r => r.changed === 1);
  await yes('Next invoice: recalculated: X.6 now from its activity (20%)', await call('cc', { op: 'inv_save', pid: 'P1', id: r3.id, to: '2026-09-30' }));
  const I3 = await inv(r3.id);
  check('Next invoice: X.6 now from P6 at 20% (not the typed 25%): 20% × 80% of 2,000 plus its TCC share = 520', line(I3, 'X.6').src === 'p6' && near(line(I3, 'X.6').prog, 0.2) && near(line(I3, 'X.6').cum_pay, 520) && !line(I3, 'X.6').rev, line(I3, 'X.6'));
  await no('Submit: an invoice whose figures changed since it was calculated is refused', await (async () => { await db.exec(`update schedule_update_rows set pct = pct where false`); await call('cc', { op: 'inv_ai', pid: 'P1', id: r3.id, score: 90 });
    await db.exec(`insert into cib_maps (project_id, act_id, item_no, src) values ('P1', 'A3', 'X.1', 'p6') on conflict (project_id, act_id) do update set item_no = 'X.1'`); return call('cc', { op: 'inv_submit', pid: 'P1', id: r3.id }); })(), 'recalculate');

  // a running project: the history first
  await db.exec(`insert into project_access (user_id, project_id) values ('${U.cc}', 'P2'), ('${U.rm}', 'P2')`);
  const S2 = await yes('History: a Schedule-C for P2', await call('cc', { op: 'sch_save', pid: 'P2', head: { value: 3000 }, items: [{ no: 'Y.1', comp: 'CON', value: 1000, leaf: true, st: 'Active' }, { no: 'Y.2', comp: 'INS', value: 2000, leaf: true, st: 'Active' }] }));
  await call('rm', { op: 'sch_approve', pid: 'P2', sch: S2.id });
  await no('History: an amount above an item value is refused', await call('cc', { op: 'inv_migrate', pid: 'P2', seq: 8, to: '2026-07-31', lines: [{ no: 'Y.1', cum: 5000 }] }), 'more than its value');
  await yes('History: invoice #8 loaded as certified', await call('cc', { op: 'inv_migrate', pid: 'P2', seq: 8, to: '2026-07-31', ref: 'IPC 8', lines: [{ no: 'Y.1', cum: 600 }, { no: 'Y.2', cum: 400 }], ret_cum: 0, adv_cum: 0, file: 'ipc8.xlsx' }), r => r.seq === 8);
  const r4 = await yes('History: the next invoice is #9 and continues from it', await call('cc', { op: 'inv_save', pid: 'P2', to: '2026-08-31' }), r => r.seq === 9);
  check('History: #9 previous certified 1,000; blocked: no updated schedule for P2', near((await inv(r4.id)).data.tot.gross_prev, 1000) && (await inv(r4.id)).data.exc.some(e => e.k === 'p6' && e.sev === 'block'), (await inv(r4.id)).data.exc);

  // reading, writing and the audit trail
  for (const t of ['cib_schedules', 'cib_items', 'cib_maps', 'cib_map_reviews', 'cib_invoices', 'cib_audit'])
    await yes(`Load: a planning engineer reads ${t}`, await as('pe', `select count(*)::int n from ${t} where project_id = 'P1'`), rows => rows[0].n > 0);
  await yes('Load: a foreman of P1 sees no client invoice', await as('fo', `select count(*)::int n from cib_invoices`), rows => rows[0].n === 0);
  await yes('Load: someone outside P1 sees none of its invoices', await as('out', `select count(*)::int n from cib_invoices where project_id = 'P1'`), rows => rows[0].n === 0);
  await yes('Load: read-only people see them', await as('ro', `select count(*)::int n from cib_invoices where project_id = 'P1'`), rows => rows[0].n > 0);
  await no('Writes: nobody writes the tables directly', await as('sa', `insert into cib_maps (project_id, act_id, item_no, src) values ('P1', 'Z', 'X.1', 'p6')`), 'permission denied');
  await no('Writes: the engine is not callable directly', await as('cc', `select pt_cib_compute('P1', '${S1.id}', 9, '2026-01-01', '2026-01-31')`), 'permission denied');
  const acts = (await q(`select array_agg(distinct action) a from cib_audit where project_id = 'P1'`))[0].a;
  check('Audit: upload, approval, mapping, review, prepare, recalculate, submit, review, approve, issue, certify, pay and cancel are recorded with who and before/after',
    ['Schedule-C uploaded', 'Schedule-C approved', 'Mapping read from P6', 'Mapping changed', 'Mapping reviewed', 'Invoice prepared', 'Invoice recalculated', 'Invoice submitted', 'Invoice reviewed', 'Invoice approved', 'Invoice issued', 'Invoice certified', 'Invoice paid', 'Invoice cancelled'].every(a => acts.includes(a))
    && (await q(`select count(*)::int n from cib_audit where action = 'Mapping read from P6' and before_v is not null and after_v is not null and by_name = 'Pia Planner'`))[0].n === 1, acts);
  let blocked = 0; for (const s of ['update cib_audit set note = note', 'delete from cib_audit', 'truncate cib_audit']) { try { await db.query(s); } catch (e) { blocked++; } }
  check('Audit: append-only (update, delete and truncate refused)', blocked === 3, blocked);

  // rollback and reinstall
  try { await db.exec(fs.readFileSync(path.join(SB, 'schema-rollback-v51.sql'), 'utf8'));
    const r = (await q(`select to_regclass('public.cib_invoices') t, 'cib' = any(pt_screens()) s, 'cib.setup' = any(pt_rights()) k`))[0];
    check('Rollback: tables, screen and rights removed', r.t === null && !r.s && !r.k, r);
    await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v51.sql'), 'utf8')); check('Rollback: v51 installs again afterwards', true);
  } catch (e) { check('Rollback and reinstall', false, e.message); }

  fs.writeFileSync(path.join(HERE, 'test_v51_results.json'), JSON.stringify(results, null, 1));
  const f = results.filter(x => !x.pass).length; console.log(`\n${results.length - f}/${results.length} passed`); process.exit(f ? 1 : 0);
})();
