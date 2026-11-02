// Server-side tests for ProTrack schema update v55 (the weather, constraints and recovery actions of a daily report, kept by
// dpr_notes_set with the edit rule of the daily report). Loads schema.sql and every update v2 to v55 into PGlite, then runs the
// checks as signed-in people.
// Usage: npm install @electric-sql/pglite@0.2.17 in any folder, then
//        NODE_PATH=<that folder>/node_modules node test_v55.cjs     (results in test_v55_results.json)
const fs = require('fs'), path = require('path');
const { PGlite } = require('@electric-sql/pglite');
const { uuid_ossp } = require('@electric-sql/pglite/contrib/uuid_ossp');
const HERE = __dirname, SB = path.dirname(HERE);
const PEOPLE = { fo: ['foreman', 'Faisal Foreman'], f2: ['foreman', 'Fahad Foreman'], en: ['eng', 'Essa Engineer'], pm: ['pm', 'Paul Manager'], pe: ['plan', 'Pia Planner'] };
const U = Object.fromEntries(Object.keys(PEOPLE).map((k, i) => [k, `00000000-0000-0000-0000-0000000055${String(i + 1).padStart(2, '0')}`]));
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
const notes = (who, p) => as(who, `select dpr_notes_set(${lit(p)}) as r`);
async function yes(name, res) { check(name, res.ok, res.ok ? res.rows : res.err); }
async function no(name, res, msg) { check(name, !res.ok && (!msg || res.err.toLowerCase().includes(msg.toLowerCase())), res.ok ? res.rows : res.err); }
const N = { id: 'DPR-00001', weather: 'Dust / sandstorm, 41 °C', issues: 'Crane down for 2 hours (SAMPLE)', recovery: 'Second shift on Thursday (SAMPLE)' };

(async () => {
  db = new PGlite({ extensions: { uuid_ossp } });
  const files = ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'];
  for (let v = 2; v <= 55; v++) if (fs.existsSync(path.join(SB, `schema-update-v${v}.sql`))) files.push(`schema-update-v${v}.sql`);
  for (const f of files) { try { await db.exec(fs.readFileSync(path.join(SB, f), 'utf8')); } catch (e) { console.log('setup failed: ' + f + ': ' + e.message); process.exit(1); } }
  await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v55.sql'), 'utf8'));
  check('Install: v55 runs a second time without errors', true);
  await db.exec(`insert into auth.users (id, email) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', '${k}@test.local')`).join(',')};
    insert into profiles (id, name, role) values ${Object.entries(PEOPLE).map(([k, [r, nm]]) => `('${U[k]}', '${nm}', '${r}')`).join(',')};
    insert into regions (id, name) values ('R1', 'Western'); insert into sectors (id, name) values ('S1', 'Power');
    insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values ('P1', 'Thuwal 2', 'TK2', 'R1', 'S1', '2025-01-01', '2027-12-31', 30, 'Active');
    insert into project_access (user_id, project_id) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', 'P1')`).join(',')};
    insert into approval_matrix (project_id, kind, from_user, to_user) values ('P1', 'fm', '${U.fo}', '${U.en}');
    insert into dprs (id, project_id, report_date, foreman, foreman_id, status) values ('DPR-00001', 'P1', '2026-09-21', 'Faisal Foreman', '${U.fo}', 'Draft');`);
  check('Install: media_features reports version 55 with dpr_notes', (await q(`select media_features() ->> 'version' v, media_features() ->> 'dpr_notes' n`)).every(r => r.v === '55' && r.n === 'true'));

  await no('Draft: another foreman does not change the report', await notes('f2', N), 'Only those who may edit');
  await no('Draft: the planning engineer does not change it', await notes('pe', N));
  await yes('Draft: the foreman keeps the weather, constraints and recovery actions', await notes('fo', N));
  const row = (await q(`select weather, issues_text, recovery_text from dprs where id = 'DPR-00001'`))[0];
  check('They are kept on the report', row.weather === N.weather && row.issues_text === N.issues && row.recovery_text === N.recovery, row);
  check('They are read with the report by those who see the project', (await as('pe', `select weather from dprs where id = 'DPR-00001'`)).rows?.[0]?.weather === N.weather);
  await no('The weather is 60 characters at most', await notes('fo', { ...N, weather: 'x'.repeat(61) }), '60 characters');
  await no('Constraints are 1,000 characters at most', await notes('fo', { ...N, issues: 'x'.repeat(1001) }), '1,000');
  await no('An unknown report is refused', await notes('fo', { ...N, id: 'DPR-09999' }), 'Unknown');
  await yes('Blank text clears a field', await notes('fo', { ...N, recovery: '  ' }));
  check('A cleared field is empty', (await q(`select recovery_text from dprs where id = 'DPR-00001'`))[0].recovery_text === null);
  await q(`update dprs set status = 'Submitted' where id = 'DPR-00001'`);
  await no('Submitted: the foreman no longer changes it', await notes('fo', N));
  await yes('Submitted: the assigned site engineer changes it while reviewing', await notes('en', N));
  await q(`update dprs set status = 'Approved' where id = 'DPR-00001'`);
  await no('Approved: nobody changes it', await notes('pm', N));
  await no('Nobody writes the columns directly', await as('fo', `update dprs set weather = 'x' where id = 'DPR-00001'`).then(r => r.ok && (r.rows || []).length === 0 ? { ok: false, err: 'no row changed' } : r).then(async r => { const w = (await q(`select weather from dprs where id = 'DPR-00001'`))[0].weather; return w === 'x' ? { ok: true, rows: [w] } : { ok: false, err: 'unchanged: ' + (r.err || '') }; }));

  await db.exec(fs.readFileSync(path.join(SB, 'schema-rollback-v55.sql'), 'utf8'));
  check('Rollback: version 54 again, dpr_notes_set gone, what was written kept', (await q(`select media_features() ->> 'version' v, to_regprocedure('public.dpr_notes_set(jsonb)') f, (select weather from dprs where id = 'DPR-00001') w`)).every(r => r.v === '54' && r.f === null && r.w === N.weather));
  try { await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v55.sql'), 'utf8')); check('Rollback: v55 installs again', true); } catch (e) { check('Rollback: v55 installs again', false, e.message); }

  const pass = results.filter(r => r.pass).length;
  console.log(`\n${pass}/${results.length} passed`);
  fs.writeFileSync(path.join(HERE, 'test_v55_results.json'), JSON.stringify({ run: new Date().toISOString(), pass, total: results.length, results }, null, 1));
  process.exit(pass === results.length ? 0 : 1);
})();
