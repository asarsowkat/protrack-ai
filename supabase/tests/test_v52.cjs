// Server-side tests for ProTrack schema update v52 (the Client Invoice Builder reads the Schedule-C item from the WBS and
// invoices on the "Schedule C Invoicing" weight). Loads schema.sql and every update v2 to v52 into PGlite (PostgreSQL in
// WebAssembly, so no local PostgreSQL is needed), then runs the checks as signed-in people.
// Usage: npm install @electric-sql/pglite@0.2.17 in any folder, then
//        NODE_PATH=<that folder>/node_modules node test_v52.cjs     (results in test_v52_results.json)
const fs = require('fs'), path = require('path');
const { PGlite } = require('@electric-sql/pglite');
const { uuid_ossp } = require('@electric-sql/pglite/contrib/uuid_ossp');
const HERE = __dirname, SB = path.dirname(HERE);
const PEOPLE = { pe: ['plan', 'Pia Planner'], cc: ['costing', 'Cody Costing'], rm: ['rm', 'Rana Regional'] };
const U = Object.fromEntries(Object.keys(PEOPLE).map((k, i) => [k, `00000000-0000-0000-0000-0000000052${String(i + 1).padStart(2, '0')}`]));
const SU1 = '00000000-0000-0000-0000-00000000b001';
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
const inv = async id => (await q(`select * from cib_invoices where id = '${id}'`))[0];
const line = (I, no) => I.data.lines.find(l => l.no === no);
const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.011;
const maps = async () => Object.fromEntries((await q(`select act_id, item_no, src, w, via from cib_maps where project_id = 'P1'`)).map(r => [r.act_id, r]));

(async () => {
  db = new PGlite({ extensions: { uuid_ossp } });
  const files = ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'];
  for (let v = 2; v <= 52; v++) if (fs.existsSync(path.join(SB, `schema-update-v${v}.sql`))) files.push(`schema-update-v${v}.sql`);
  for (const f of files) { try { await db.exec(fs.readFileSync(path.join(SB, f), 'utf8')); } catch (e) { console.log('setup failed: ' + f + ': ' + e.message); process.exit(1); } }
  await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v52.sql'), 'utf8'));
  check('Install: v52 runs a second time without errors', true);
  await db.exec(`insert into auth.users (id, email) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', '${k}@test.local')`).join(',')};
    insert into profiles (id, name, role) values ${Object.entries(PEOPLE).map(([k, [r, n]]) => `('${U[k]}', '${n}', '${r}')`).join(',')};
    insert into regions (id, name) values ('R1', 'Western'); insert into sectors (id, name) values ('S1', 'Power');
    insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values ('P1', 'Thuwal 2', 'TK2', 'R1', 'S1', '2025-01-01', '2027-12-31', 30, 'Active');
    insert into project_access (user_id, project_id) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', 'P1')`).join(',')};
    insert into schedule_updates (id, project_id, data_date, weightage, summary) values ('${SU1}', 'P1', '2026-08-31', 'client', '{}');
    insert into schedule_update_rows (update_id, project_id, act_id, w, pct, af) values
      ('${SU1}','P1','M-PR',100,100,'2026-03-01'),('${SU1}','P1','M-MFG',300,100,'2026-07-01'),('${SU1}','P1','M-INSP',100,40,null),('${SU1}','P1','M-INSP2',100,80,null),
      ('${SU1}','P1','C1',300,40,null),('${SU1}','P1','C2',100,60,null);`);

  check('Install: cib_features reports version 52 with the invoicing weight', (await q(`select cib_features() ->> 'version' v, cib_features() ->> 'inv_weight' w`)).every(r => r.v === '52' && r.w === 'true'));
  check('Install: cib_maps has the invoicing weight and where the item came from',
    (await q(`select count(*)::int n from information_schema.columns where table_name = 'cib_maps' and column_name in ('w','via')`))[0].n === 2);

  // a SAMPLE Schedule-C: X.3 material (split 90/10), X.4 construction (80/10/10)
  const items = [['X.3', 'MAT', 10000], ['X.4', 'CON', 4000]].map(([no, comp, value]) => ({ no, comp, value, desc: 'Item ' + no, unit: 'LT', qty: 1, rate: value, st: 'Active', leaf: true, limit: 100 }));
  const rules = { MAT: { t: 'split', first: 90 }, CON: { t: 'pct', cap: 80, tcc: 10, fac: 10 } };
  const head = { value: 14000, vat: 15, ret_pct: 0, adv_pct: 0, adv_rec: 0, pay_days: 45, contract_no: 'SAMPLE-1' };
  const S1 = await yes('Setup: the SAMPLE Schedule-C is uploaded', await call('cc', { op: 'sch_save', pid: 'P1', head, items, rules, file: 'SAMPLE.xlsx' }));
  await yes('Setup: and approved', await call('rm', { op: 'sch_approve', pid: 'P1', sch: S1.id }));

  // the mapping read from P6: X.3 from the WBS, only the inspection after delivery carries the "Schedule C Invoicing" weight
  const P6 = [{ act: 'M-PR', item: 'X.3', via: 'wbs' }, { act: 'M-MFG', item: 'X.3', via: 'wbs' }, { act: 'M-INSP', item: 'X.3', via: 'wbs', w: 10000 },
    { act: 'C1', item: 'X.4', via: 'code' }, { act: 'C2', item: 'X.4', via: 'code' }].map(x => ({ ...x, src: 'p6' }));
  await yes('Mapping: read from the WBS field and the activity code, with the invoicing weight', await call('pe', { op: 'map_save', pid: 'P1', replace_p6: true, file: 'SAMPLE.xer', rows: P6 }), r => r.changed === 5);
  let M = await maps();
  check('Mapping: the weight and the source are stored (inspection 10,000 from the WBS; PR without a weight; C1 from the code)',
    +M['M-INSP'].w === 10000 && M['M-INSP'].via === 'wbs' && M['M-PR'].w === null && M['M-PR'].via === 'wbs' && M['C1'].via === 'code', M);
  await yes('Mapping: reading the same file again changes nothing', await call('pe', { op: 'map_save', pid: 'P1', replace_p6: true, rows: P6 }), r => r.changed === 0);

  const r1 = await yes('Invoice: #1 to 31 Aug 2026 is prepared', await call('cc', { op: 'inv_save', pid: 'P1', to: '2026-08-31', from: '2026-08-01' }), r => r.seq === 1);
  let I1 = await inv(r1.id);
  check('Invoice: X.3 earns on the inspection only: 40% (not the 88% of PR, PO and manufacturing by schedule weight); 40% × 90% of 10,000 = 3,600',
    near(line(I1, 'X.3').prog, 0.4) && near(line(I1, 'X.3').cum_pay, 3600) && line(I1, 'X.3').iw === true && line(I1, 'X.3').acts === 1, line(I1, 'X.3'));
  check('Invoice: X.4 has no invoicing weight: all its activities by schedule weight, 45% × 80% of 4,000 = 1,440, not marked invoicing-weighted',
    near(line(I1, 'X.4').prog, 0.45) && near(line(I1, 'X.4').cum_pay, 1440) && line(I1, 'X.4').iw === false, line(I1, 'X.4'));
  check('Invoice: a warning names the mapped item without the invoicing weight', I1.data.exc.some(e => e.k === 'weight' && e.sev === 'warn' && e.msg.includes('X.4')), I1.data.exc);

  // a second inspection activity: the weighted average of the weighted activities
  const P6b = P6.concat([{ act: 'M-INSP2', item: 'X.3', via: 'wbs', w: 30000, src: 'p6' }]);
  await yes('Mapping: a second weighted activity is read', await call('pe', { op: 'map_save', pid: 'P1', replace_p6: true, rows: P6b }), r => r.changed === 1);
  await yes('Invoice: recalculated', await call('cc', { op: 'inv_save', pid: 'P1', id: r1.id, to: '2026-08-31', from: '2026-08-01' }));
  I1 = await inv(r1.id);
  check('Invoice: X.3 = (10,000 × 40 + 30,000 × 80) / 40,000 = 70%; 70% × 90% of 10,000 = 6,300', near(line(I1, 'X.3').prog, 0.7) && near(line(I1, 'X.3').cum_pay, 6300) && line(I1, 'X.3').acts === 2, line(I1, 'X.3'));

  await yes('Mapping: a changed weight is a change', await call('pe', { op: 'map_save', pid: 'P1', replace_p6: true, rows: P6b.map(x => x.act === 'M-INSP' ? { ...x, w: 30000 } : x) }), r => r.changed === 1);
  M = await maps(); check('Mapping: the new weight is stored', +M['M-INSP'].w === 30000, M['M-INSP']);
  await yes('Mapping: a weight of zero, below zero or not a number is stored as none', await call('pe', { op: 'map_save', pid: 'P1', rows: [{ act: 'C1', item: 'X.4', src: 'p6', via: 'code', w: -5 }, { act: 'C2', item: 'X.4', src: 'p6', via: 'code', w: 'abc' }, { act: 'M-PR', item: 'X.3', src: 'p6', via: 'wbs', w: 0 }] }));
  M = await maps(); check('Mapping: no weight on C1, C2 and the PR', M['C1'].w === null && M['C2'].w === null && M['M-PR'].w === null, M);
  await yes('Mapping: an activity mapped by hand', await call('pe', { op: 'map_save', pid: 'P1', rows: [{ act: 'C2', item: 'X.3', src: 'manual', w: 999, via: 'wbs' }] }));
  M = await maps(); check('Mapping: by hand carries no invoicing weight and no P6 source', M['C2'].src === 'manual' && M['C2'].w === null && M['C2'].via === null, M['C2']);
  const au = await q(`select action from cib_audit where project_id = 'P1' order by at_time`);
  check('Audit: the mapping changes are in the audit trail', au.filter(a => /Mapping/.test(a.action)).length >= 4, au.map(a => a.action));

  // undo and again
  try { await db.exec(fs.readFileSync(path.join(SB, 'schema-rollback-v52.sql'), 'utf8')); check('Rollback: schema-rollback-v52.sql runs', true); } catch (e) { check('Rollback: schema-rollback-v52.sql runs', false, e.message); }
  check('Rollback: version 51 again and the two columns are gone', (await q(`select cib_features() ->> 'version' v`))[0].v === '51'
    && (await q(`select count(*)::int n from information_schema.columns where table_name = 'cib_maps' and column_name in ('w','via')`))[0].n === 0);
  await yes('Rollback: the invoice still recalculates', await call('cc', { op: 'inv_save', pid: 'P1', id: r1.id, to: '2026-08-31', from: '2026-08-01' }));
  I1 = await inv(r1.id); check('Rollback: X.3 earns on the schedule weight of all its activities again', line(I1, 'X.3').prog > 0.7 && line(I1, 'X.3').iw === undefined, line(I1, 'X.3'));
  try { await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v52.sql'), 'utf8')); check('Rollback: v52 installs again afterwards', (await q(`select cib_features() ->> 'version' v`))[0].v === '52'); } catch (e) { check('Rollback: v52 installs again afterwards', false, e.message); }

  const pass = results.filter(r => r.pass).length;
  console.log(`\n${pass}/${results.length} passed`);
  fs.writeFileSync(path.join(HERE, 'test_v52_results.json'), JSON.stringify({ run: new Date().toISOString(), pass, total: results.length, results }, null, 1));
  process.exit(pass === results.length ? 0 : 1);
})();
