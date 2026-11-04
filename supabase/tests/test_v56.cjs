// Server-side tests for ProTrack schema update v56 (the invoicing phase of an activity from a P6 activity code, set by
// act_inv_phase_set with the rule of import_baseline). Loads schema.sql and every update v2 to v56 into PGlite, then runs the
// checks as signed-in people.
// Usage: npm install @electric-sql/pglite@0.2.17 in any folder, then
//        NODE_PATH=<that folder>/node_modules node test_v56.cjs     (results in test_v56_results.json)
const fs = require('fs'), path = require('path');
const { PGlite } = require('@electric-sql/pglite');
const { uuid_ossp } = require('@electric-sql/pglite/contrib/uuid_ossp');
const HERE = __dirname, SB = path.dirname(HERE);
const PEOPLE = { pe: ['plan', 'Pia Planner'], p2: ['plan', 'Paolo Planner'], pm: ['pm', 'Paul Manager'], fo: ['foreman', 'Faisal Foreman'], sa: ['sa', 'Sara Admin'] };
const U = Object.fromEntries(Object.keys(PEOPLE).map((k, i) => [k, `00000000-0000-0000-0000-0000000056${String(i + 1).padStart(2, '0')}`]));
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
const setIp = (who, p) => as(who, `select act_inv_phase_set(${lit(p)}) as r`);
async function yes(name, res) { check(name, res.ok, res.ok ? res.rows : res.err); }
async function no(name, res, msg) { check(name, !res.ok && (!msg || res.err.toLowerCase().includes(msg.toLowerCase())), res.ok ? res.rows : res.err); }
const MAP = { 'Design (SAMPLE)': 'ENG', 'Supply (SAMPLE)': 'PRC', 'Testing (SAMPLE)': 'TC' };
const P = { project_id: 'P1', code_type: 'Invoice Phase', map: MAP, rows: [{ id: 'A1', phase: 'ENG' }, { id: 'A2', phase: 'PRC' }, { id: 'A3', phase: 'TC' }, { id: 'A4', phase: '' }] };
const phases = async () => Object.fromEntries((await q(`select id, inv_phase from activities where project_id = 'P1' order by id`)).map(r => [r.id, r.inv_phase]));

(async () => {
  db = new PGlite({ extensions: { uuid_ossp } });
  const files = ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'];
  for (let v = 2; v <= 56; v++) if (fs.existsSync(path.join(SB, `schema-update-v${v}.sql`))) files.push(`schema-update-v${v}.sql`);
  for (const f of files) { try { await db.exec(fs.readFileSync(path.join(SB, f), 'utf8')); } catch (e) { console.log('setup failed: ' + f + ': ' + e.message); process.exit(1); } }
  await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v56.sql'), 'utf8'));
  check('Install: v56 runs a second time without errors', true);
  await db.exec(`insert into auth.users (id, email) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', '${k}@test.local')`).join(',')};
    insert into profiles (id, name, role) values ${Object.entries(PEOPLE).map(([k, [r, nm]]) => `('${U[k]}', '${nm}', '${r}')`).join(',')};
    insert into regions (id, name) values ('R1', 'Western'); insert into sectors (id, name) values ('S1', 'Power');
    insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values
      ('P1', 'Thuwal 2', 'TK2', 'R1', 'S1', '2025-01-01', '2027-12-31', 30, 'Active'), ('P2', 'Other', 'OTH', 'R1', 'S1', '2025-01-01', '2027-12-31', 10, 'Active');
    insert into project_access (user_id, project_id) values ('${U.pe}', 'P1'), ('${U.pm}', 'P1'), ('${U.fo}', 'P1'), ('${U.p2}', 'P2');
    insert into activities (id, project_id, name, cls) values ('A1', 'P1', 'Design package', 'ENG'), ('A2', 'P1', 'Transformer supply', 'PRC'),
      ('A3', 'P1', 'Testing', 'CON'), ('A4', 'P1', 'Foundations', 'CON'), ('A1', 'P2', 'Other design', 'ENG');`);
  check('Install: media_features reports version 56 with inv_phase', (await q(`select media_features() ->> 'version' v, media_features() ->> 'inv_phase' n`)).every(r => r.v === '56' && r.n === 'true'));
  check('Install: activities have no invoicing phase until one is set', Object.values(await phases()).every(v => v === null));

  await no('A project manager does not set the invoicing phase', await setIp('pm', P), 'Only planning engineers');
  await no('A foreman does not set it', await setIp('fo', P), 'Only planning engineers');
  await no('A planning engineer of another project does not set it', await setIp('p2', P), 'Only planning engineers');
  const r1 = await setIp('pe', P); await yes('The planning engineer of the project sets it after the baseline import', r1);
  check('It reports how many activities were updated', r1.ok && r1.rows[0].r.updated === 4 && r1.rows[0].r.unknown === 0, r1.rows);
  const ph = await phases();
  check('Each activity keeps its phase; an empty phase stays empty (the WBS wording)', ph.A1 === 'ENG' && ph.A2 === 'PRC' && ph.A3 === 'TC' && ph.A4 === null, ph);
  check('Only this project\'s activities change', (await q(`select inv_phase from activities where project_id = 'P2'`))[0].inv_phase === null);
  const st = (await q(`select code_type, map from project_inv_phase where project_id = 'P1'`))[0];
  check('The project keeps the code type and its map', st && st.code_type === 'Invoice Phase' && st.map['Supply (SAMPLE)'] === 'PRC', st);
  check('Those who see the project read the choice', (await as('pm', `select code_type from project_inv_phase where project_id = 'P1'`)).rows?.[0]?.code_type === 'Invoice Phase');
  check('Those who do not see it do not', ((await as('p2', `select code_type from project_inv_phase where project_id = 'P1'`)).rows || []).length === 0);
  check('The change is logged', (await q(`select text from change_log where project_id = 'P1' order by 1 desc`)).some(r => /activity code "Invoice Phase": 4 activities/.test(r.text)));
  await no('An unknown phase in the map is refused', await setIp('pe', { ...P, map: { X: 'DES' } }), 'Unknown phase');
  await no('An unknown phase on an activity is refused', await setIp('pe', { ...P, rows: [{ id: 'A1', phase: 'MAT' }] }), 'ENG, PRC, CON or TC');
  await no('An activity without its ID is refused', await setIp('pe', { ...P, rows: [{ phase: 'ENG' }] }), 'needs its ID');
  await no('The table refuses another phase written directly', await q(`update activities set inv_phase = 'DES' where id = 'A1' and project_id = 'P1'`).then(r => ({ ok: true, rows: r }), e => ({ ok: false, err: e.message })), 'activities_inv_phase_ok');
  const r2 = await setIp('pe', { ...P, rows: [{ id: 'A1', phase: 'CON' }, { id: 'ZZ', phase: 'ENG' }] });
  check('An activity not on the project is counted as unknown, the rest is set', r2.ok && r2.rows[0].r.updated === 1 && r2.rows[0].r.unknown === 1 && (await phases()).A1 === 'CON', r2.rows || r2.err);
  await yes('A super admin sets it too', await setIp('sa', P));
  await yes('An empty code type goes back to the WBS wording', await setIp('pe', { project_id: 'P1', code_type: '', map: {}, rows: P.rows.map(x => ({ id: x.id, phase: '' })) }));
  check('... the project choice is removed and the phases cleared', !(await q(`select 1 from project_inv_phase where project_id = 'P1'`)).length && Object.values(await phases()).every(v => v === null));
  // writing activities directly follows the table's own rule (ac_plan: the planning or costing right), unchanged by v56
  await no('A foreman does not write the phase on the activities directly', await as('fo', `update activities set inv_phase = 'ENG' where id = 'A1' and project_id = 'P1'`).then(async r => { const v = (await phases()).A1; return v === 'ENG' ? { ok: true, rows: [v] } : { ok: false, err: 'unchanged: ' + (r.err || '') }; }));

  await db.exec(fs.readFileSync(path.join(SB, 'schema-rollback-v56.sql'), 'utf8'));
  check('Rollback: the function is gone, media_features reports 55, the column stays', (await q(`select to_regprocedure('act_inv_phase_set(jsonb)') f, media_features() ->> 'version' v`)).every(r => r.f === null && r.v === '55')
    && (await q(`select count(*) n from information_schema.columns where table_name = 'activities' and column_name = 'inv_phase'`))[0].n == 1);
  await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v56.sql'), 'utf8'));
  check('v56 runs again after the rollback', (await q(`select media_features() ->> 'version' v`))[0].v === '56');

  const pass = results.filter(r => r.pass).length;
  fs.writeFileSync(path.join(HERE, 'test_v56_results.json'), JSON.stringify({ run: new Date().toISOString(), pass, fail: results.length - pass, results }, null, 1));
  console.log(`\n${pass} of ${results.length} passed`); process.exit(pass === results.length ? 0 : 1);
})();
