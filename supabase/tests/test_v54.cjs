// Server-side tests for ProTrack schema update v54 (site photos on the daily reports, in report_media with kind 'dpr', and the
// weekly and monthly internal reports taking copies of them). Loads schema.sql and every update v2 to v54 into PGlite
// (PostgreSQL in WebAssembly, so no local PostgreSQL is needed), then runs the checks as signed-in people.
// Usage: npm install @electric-sql/pglite@0.2.17 in any folder, then
//        NODE_PATH=<that folder>/node_modules node test_v54.cjs     (results in test_v54_results.json)
const fs = require('fs'), path = require('path');
const { PGlite } = require('@electric-sql/pglite');
const { uuid_ossp } = require('@electric-sql/pglite/contrib/uuid_ossp');
const HERE = __dirname, SB = path.dirname(HERE);
const PEOPLE = { fo: ['foreman', 'Faisal Foreman'], f2: ['foreman', 'Fahad Foreman'], en: ['eng', 'Essa Engineer'], e2: ['eng', 'Emad Engineer'], pm: ['pm', 'Paul Manager'], pe: ['plan', 'Pia Planner'], out: ['foreman', 'Omar Outsider'] };
const U = Object.fromEntries(Object.keys(PEOPLE).map((k, i) => [k, `00000000-0000-0000-0000-0000000054${String(i + 1).padStart(2, '0')}`]));
const results = [];
function check(name, ok, detail) { results.push({ check: name, pass: !!ok, detail: String(detail == null ? '' : typeof detail === 'string' ? detail : JSON.stringify(detail)).slice(0, 300) });
  console.log((ok ? 'PASS ' : 'FAIL ') + name + (ok ? '' : '  -> ' + String(typeof detail === 'string' ? detail : JSON.stringify(detail)).slice(0, 300))); }
const lit = o => "'" + JSON.stringify(o).replace(/'/g, "''") + "'::jsonb";
let db, n = 0;
async function q(sql) { const r = await db.query(sql); return r.rows; }
async function as(who, sql) {
  await db.exec('begin'); try {
    await db.exec(`set local role authenticated; select set_config('request.jwt.claim.sub', '${U[who]}', true);`);
    const r = await db.query(sql); await db.exec('commit'); return { ok: true, rows: r.rows };
  } catch (e) { await db.exec('rollback'); return { ok: false, err: e.message }; } }
const act = async (who, p) => { const r = await as(who, `select report_media_act(${lit(p)}) as r`); return r.ok ? { ok: true, r: r.rows[0].r } : r; };
async function yes(name, res, cond = () => true) { let good = res.ok; try { good = good && cond(res.r !== undefined ? res.r : res.rows); } catch (e) { good = false; res.err = String(e); } check(name, good, res.ok ? (res.r !== undefined ? res.r : res.rows) : res.err); return res.r !== undefined ? res.r : res.rows; }
async function no(name, res, msg) { check(name, !res.ok && (!msg || res.err.toLowerCase().includes(msg.toLowerCase())), res.ok ? res.r || res.rows : res.err); }
const uid = () => `5400${String(++n).padStart(4, '0')}-0000-4000-8000-000000000000`;
// the file first (as the person), then the record
const put = (who, p) => as(who, `insert into storage.objects (bucket_id, name) values ('report-media', '${p}')`);
async function addPhoto(who, did, opts = {}) {
  const id = uid(), ext = opts.ext || 'jpg', pth = `P1/dpr/dpr-${did}/${id}.${ext}`;
  const s = await put(who, pth); if (!s.ok) return s;
  return act(who, { action: 'add', id, project_id: 'P1', kind: 'dpr', period_type: 'dpr', period: did, path: pth, name: 'site.jpg', mime: opts.mime || 'image/jpeg', size: 1000, caption: opts.caption || 'Zone A', taken_on: '2026-09-21' });
}
const setStatus = (did, st) => q(`update dprs set status = '${st}' where id = '${did}'`);

(async () => {
  db = new PGlite({ extensions: { uuid_ossp } });
  const files = ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'];
  for (let v = 2; v <= 54; v++) if (fs.existsSync(path.join(SB, `schema-update-v${v}.sql`))) files.push(`schema-update-v${v}.sql`);
  for (const f of files) { try { await db.exec(fs.readFileSync(path.join(SB, f), 'utf8')); } catch (e) { console.log('setup failed: ' + f + ': ' + e.message); process.exit(1); } }
  await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v54.sql'), 'utf8'));
  check('Install: v54 runs a second time without errors', true);
  await db.exec(`insert into auth.users (id, email) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', '${k}@test.local')`).join(',')};
    insert into profiles (id, name, role) values ${Object.entries(PEOPLE).map(([k, [r, nm]]) => `('${U[k]}', '${nm}', '${r}')`).join(',')};
    insert into regions (id, name) values ('R1', 'Western'); insert into sectors (id, name) values ('S1', 'Power');
    insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values ('P1', 'Thuwal 2', 'TK2', 'R1', 'S1', '2025-01-01', '2027-12-31', 30, 'Active');
    insert into project_access (user_id, project_id) values ${Object.keys(PEOPLE).filter(k => k !== 'out').map(k => `('${U[k]}', 'P1')`).join(',')};
    insert into approval_matrix (project_id, kind, from_user, to_user) values ('P1', 'fm', '${U.fo}', '${U.en}');
    insert into dprs (id, project_id, report_date, foreman, foreman_id, status) values
      ('DPR-00001', 'P1', '2026-09-21', 'Faisal Foreman', '${U.fo}', 'Draft'),
      ('DPR-00002', 'P1', '2026-09-22', 'Faisal Foreman', '${U.fo}', 'Approved'),
      ('DPR-00003', 'P1', '2026-09-21', 'Fahad Foreman', '${U.f2}', 'Draft');`);

  check('Install: media_features reports version 54 with dpr_media', (await q(`select media_features() ->> 'version' v, media_features() ->> 'dpr_media' d`)).every(r => r.v === '54' && r.d === 'true'));

  // who adds photos to a draft
  await no('Draft: a foreman does not add photos to another foreman\'s report', await addPhoto('f2', 'DPR-00001'));
  await no('Draft: someone without access to the project adds nothing', await addPhoto('out', 'DPR-00001'));
  await no('Draft: the planning engineer (no dpr.create) adds nothing', await addPhoto('pe', 'DPR-00001'));
  const p1 = await yes('Draft: the foreman adds a photo to their own report', await addPhoto('fo', 'DPR-00001', { caption: 'Zone A slab pour' }), r => !!r.id);
  await yes('Draft: the site engineer adds a photo', await addPhoto('en', 'DPR-00001'));
  await yes('Draft: the project manager adds a photo', await addPhoto('pm', 'DPR-00001'));
  await no('A daily report takes photos only (no video)', await addPhoto('fo', 'DPR-00001', { ext: 'mp4', mime: 'video/mp4' }), 'photos only');
  const pth = `P1/dpr/dpr-DPR-00001/${uid()}.jpg`;
  await put('fo', pth);
  await no('The stored path must be the report\'s own', await act('fo', { action: 'add', id: uid(), project_id: 'P1', kind: 'dpr', period_type: 'dpr', period: 'DPR-00003', path: pth, name: 'x.jpg', mime: 'image/jpeg', size: 10 }));
  await no('The report must exist on that project', await addPhoto('pm', 'DPR-09999'));
  await no('Storage: a foreman does not store a file under another foreman\'s report', await put('f2', `P1/dpr/dpr-DPR-00001/${uid()}.jpg`));

  // editing captions and the date, and removing
  await yes('Draft: the foreman changes a caption and the date', await act('fo', { action: 'update', id: p1.id, caption: 'Zone A slab pour, east bay', taken_on: '2026-09-21' }));
  check('The caption is kept', (await q(`select caption from report_media where id = '${p1.id}'`))[0].caption === 'Zone A slab pour, east bay');

  // after submitting: only the assigned site engineer, those with dpr.approve, the super admin
  await setStatus('DPR-00001', 'Submitted');
  await no('Submitted: the foreman no longer adds photos', await addPhoto('fo', 'DPR-00001'));
  await no('Submitted: the foreman no longer removes one', await act('fo', { action: 'delete', id: p1.id }), 'locked');
  await no('Submitted: a site engineer who is not the reviewer adds nothing', await addPhoto('e2', 'DPR-00001'));
  await yes('Submitted: the assigned site engineer adds a photo while reviewing', await addPhoto('en', 'DPR-00001'));
  await yes('Submitted: the project manager (dpr.approve) changes a caption', await act('pm', { action: 'update', id: p1.id, caption: 'Checked on site' }));
  await setStatus('DPR-00001', 'Approved');
  await no('Approved: nobody adds photos', await addPhoto('pm', 'DPR-00001'));
  await no('Approved: nobody removes one', await act('pm', { action: 'delete', id: p1.id }), 'locked');
  await no('Approved report from the start: nothing added', await addPhoto('en', 'DPR-00002'));

  // the limit
  await setStatus('DPR-00003', 'Draft');
  for (let i = 0; i < 20; i++) { const r = await addPhoto('f2', 'DPR-00003'); if (!r.ok) { check('Limit: 20 photos are taken', false, r.err); break; } }
  await no('Limit: the 21st photo of a daily report is refused', await addPhoto('f2', 'DPR-00003'), 'At most 20');

  // reading
  const cnt = async (who, sql) => { const z = await as(who, sql); return z.ok ? z.rows[0].n : 'error: ' + z.err; };
  const rd = [await cnt('pe', `select count(*)::int n from report_media where kind = 'dpr'`), await cnt('pe', `select count(*)::int n from storage.objects where bucket_id = 'report-media' and name like 'P1/dpr/%'`)];
  check('Read: the planning engineer sees the daily photos and their files (to pick from)', rd[0] >= 24 && rd[1] >= rd[0], rd);
  const ro = [await cnt('out', `select count(*)::int n from report_media`), await cnt('out', `select count(*)::int n from storage.objects where bucket_id = 'report-media'`)];
  check('Read: someone without access to the project sees none', ro[0] === 0 && ro[1] === 0, ro);
  await no('Nobody writes the table directly', await as('fo', `update report_media set caption = 'x' where id = '${p1.id}'`));

  // the weekly report takes a copy of a daily photo, as its own
  const wid = uid(), wp = `P1/planning/week-2026-W39/${wid}.jpg`;
  await yes('Weekly: the planning engineer stores the copy under the weekly report', await put('pe', wp));
  await yes('Weekly: and adds it with the photo it came from', await act('pe', { action: 'add', id: wid, project_id: 'P1', kind: 'planning', period_type: 'week', period: '2026-W39', path: wp, name: 'site.jpg', mime: 'image/jpeg', size: 1000, caption: 'Checked on site', taken_on: '2026-09-21', from: p1.id }));
  check('Weekly: the copy remembers its daily photo', (await q(`select copied_from from report_media where id = '${wid}'`))[0].copied_from === p1.id);
  await no('Weekly: kind and period type must match (a daily photo cannot be filed under a week)', await (async () => { const id = uid(), x = `P1/dpr/week-2026-W39/${id}.jpg`; await q(`insert into storage.objects (bucket_id, name) values ('report-media', '${x}')`); return act('pe', { action: 'add', id, project_id: 'P1', kind: 'dpr', period_type: 'week', period: '2026-W39', path: x, name: 'x.jpg', mime: 'image/jpeg', size: 10 }); })());
  const mid = uid(), mp = `P1/planning/month-2026-09/${mid}.jpg`;
  await put('pe', mp);
  await yes('Monthly: the planning engineer adds a copy of the weekly photo', await act('pe', { action: 'add', id: mid, project_id: 'P1', kind: 'planning', period_type: 'month', period: '2026-09', path: mp, name: 'site.jpg', mime: 'image/jpeg', size: 1000, from: wid }));
  let tblErr = null; try { await q(`insert into report_media (id, project_id, kind, period_type, period, path, name, mime, size_bytes) values ('${uid()}', 'P1', 'dpr', 'dpr', 'DPR-00003', 'P1/dpr/dpr-DPR-00003/v.mp4', 'v', 'video/mp4', 10)`); } catch (e) { tblErr = e.message; }
  check('The table itself refuses a daily record that is not a photo', !!tblErr && /report_media_dpr_check/.test(tblErr), tblErr);

  // rollback
  await db.exec(fs.readFileSync(path.join(SB, 'schema-rollback-v54.sql'), 'utf8'));
  check('Rollback: version 47 again; pt_dpr_edit is gone', (await q(`select media_features() ->> 'version' v, to_regprocedure('public.pt_dpr_edit(uuid,text,text)') f`)).every(r => r.v === '47' && r.f === null));
  check('Rollback: the daily photos\' records are removed; the weekly and monthly copies stay', (await q(`select count(*) filter (where kind = 'dpr')::int d, count(*) filter (where kind = 'planning')::int p from report_media`)).every(r => r.d === 0 && r.p === 2));
  await no('Rollback: a daily photo is refused again', await addPhoto('pm', 'DPR-00003'));
  try { await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v54.sql'), 'utf8')); await setStatus('DPR-00003', 'Draft'); check('Rollback: v54 installs again', true); await yes('Rollback: after installing again, daily photos are taken again', await addPhoto('f2', 'DPR-00003')); }
  catch (e) { check('Rollback: v54 installs again', false, e.message); }

  const pass = results.filter(r => r.pass).length;
  console.log(`\n${pass}/${results.length} passed`);
  fs.writeFileSync(path.join(HERE, 'test_v54_results.json'), JSON.stringify({ run: new Date().toISOString(), pass, total: results.length, results }, null, 1));
  process.exit(pass === results.length ? 0 : 1);
})();
