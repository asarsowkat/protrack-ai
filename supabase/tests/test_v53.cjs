// Server-side tests for ProTrack schema update v53 (client invoice formats for the Client Invoice Builder: the formats table,
// the private bucket cib-formats, cib_fmt_act, and the export noted by cib_act). Loads schema.sql and every update v2 to v53
// into PGlite (PostgreSQL in WebAssembly, so no local PostgreSQL is needed), then runs the checks as signed-in people.
// Usage: npm install @electric-sql/pglite@0.2.17 in any folder, then
//        NODE_PATH=<that folder>/node_modules node test_v53.cjs     (results in test_v53_results.json)
const fs = require('fs'), path = require('path');
const { PGlite } = require('@electric-sql/pglite');
const { uuid_ossp } = require('@electric-sql/pglite/contrib/uuid_ossp');
const HERE = __dirname, SB = path.dirname(HERE);
const PEOPLE = { pe: ['plan', 'Pia Planner'], cc: ['costing', 'Cody Costing'], pm: ['pm', 'Paul Manager'], rm: ['rm', 'Rana Regional'], fo: ['foreman', 'Faisal Foreman'] };
const U = Object.fromEntries(Object.keys(PEOPLE).map((k, i) => [k, `00000000-0000-0000-0000-0000000053${String(i + 1).padStart(2, '0')}`]));
const SU1 = '00000000-0000-0000-0000-00000000c001';
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
const fact = async (who, p) => { const r = await as(who, `select cib_fmt_act(${lit(p)}) as r`); return r.ok ? { ok: true, r: r.rows[0].r } : r; };
const act = async (who, p) => { const r = await as(who, `select cib_act(${lit(p)}) as r`); return r.ok ? { ok: true, r: r.rows[0].r } : r; };
async function yes(name, res, cond = () => true) { let good = res.ok; try { good = good && cond(res.r !== undefined ? res.r : res.rows); } catch (e) { good = false; res.err = String(e); } check(name, good, res.ok ? (res.r !== undefined ? res.r : res.rows) : res.err); return res.r !== undefined ? res.r : res.rows; }
async function no(name, res, msg) { check(name, !res.ok && (!msg || res.err.toLowerCase().includes(msg.toLowerCase())), res.ok ? res.r || res.rows : res.err); }
const MAP = { v: 1, sheets: [{ name: 'MATERIAL', state: 'visible', act: 'fill', kind: 'table' }], tables: [{ sheet: 'MATERIAL', first: 14, last: 15, itemCol: 1, comp: 'MAT', mode: 'rebuild', cols: [{ c: 9, role: 'prog_prev_pct' }] }], fields: [], ms: [], tnum: [] };
const put = (who, id) => as(who, `insert into storage.objects (bucket_id, name) values ('cib-formats', 'fmt/${id}.xlsx')`);

(async () => {
  db = new PGlite({ extensions: { uuid_ossp } });
  const files = ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'];
  for (let v = 2; v <= 53; v++) if (fs.existsSync(path.join(SB, `schema-update-v${v}.sql`))) files.push(`schema-update-v${v}.sql`);
  for (const f of files) { try { await db.exec(fs.readFileSync(path.join(SB, f), 'utf8')); } catch (e) { console.log('setup failed: ' + f + ': ' + e.message); process.exit(1); } }
  await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v53.sql'), 'utf8'));
  check('Install: v53 runs a second time without errors', true);
  await db.exec(`insert into auth.users (id, email) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', '${k}@test.local')`).join(',')};
    insert into profiles (id, name, role) values ${Object.entries(PEOPLE).map(([k, [r, n]]) => `('${U[k]}', '${n}', '${r}')`).join(',')};
    insert into regions (id, name) values ('R1', 'Western'); insert into sectors (id, name) values ('S1', 'Power');
    insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values ('P1', 'Thuwal 2', 'TK2', 'R1', 'S1', '2025-01-01', '2027-12-31', 30, 'Active');
    insert into project_access (user_id, project_id) values ${Object.keys(PEOPLE).map(k => `('${U[k]}', 'P1')`).join(',')};
    insert into schedule_updates (id, project_id, data_date, weightage, summary) values ('${SU1}', 'P1', '2026-08-31', 'client', '{}');
    insert into schedule_update_rows (update_id, project_id, act_id, w, pct, af) values ('${SU1}','P1','M1',100,50,null);`);

  check('Install: cib_features reports version 53 with formats', (await q(`select cib_features() ->> 'version' v, cib_features() ->> 'formats' f`)).every(r => r.v === '53' && r.f === 'true'));
  check('Install: the bucket cib-formats is private, 25 MB, .xlsx only',
    (await q(`select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'cib-formats'`)).every(r => r.public === false && +r.file_size_limit === 26214400 && r.allowed_mime_types.length === 1));
  check('Install: who keeps formats: costing yes (cib.setup), the project manager and a foreman no; who reads: the project manager yes, a foreman no',
    (await q(`select pt_cib_fmt_keep('${U.cc}') a, pt_cib_fmt_keep('${U.pm}') b, pt_cib_fmt_keep('${U.fo}') c, pt_cib_fmt_see('${U.pm}') d, pt_cib_fmt_see('${U.fo}') e`)).every(r => r.a && !r.b && !r.c && r.d && !r.e));

  // the fix: files in storage can be read again (the v47 rule called user_sees(), which signed-in people may not run)
  await db.exec(`insert into storage.objects (bucket_id, name) values ('report-media', 'P1/photos/month-2026-08/m1.jpg')`);
  const rmc = await as('pm', `select count(*)::int n from storage.objects where bucket_id = 'report-media'`);
  check('Fix: a signed-in person reads files in storage again (a report photo of a project they see)', rmc.ok && rmc.rows[0].n === 1, rmc.ok ? rmc.rows : rmc.err);
  check('Fix: pt_rm_see answers only for the person asking', (await as('pm', `select pt_rm_see('${U.pm}', 'P1') a, pt_rm_see('${U.cc}', 'P1') b`)).rows.every(r => r.a === true && r.b === false));

  // the file first, then the format
  const A = 'CFabc12345';
  await no('Storage: a project manager does not store a format workbook', await put('pm', 'CFpm000001'));
  await no('Storage: only fmt/<id>.xlsx is accepted', await as('cc', `insert into storage.objects (bucket_id, name) values ('cib-formats', 'other/file.xlsx')`));
  await yes('Storage: the costing engineer stores the workbook', await put('cc', A));
  await no('Format: the project manager does not keep formats', await fact('pm', { op: 'fmt_add', id: A, path: `fmt/${A}.xlsx`, name: 'Utility layout', file: 'invoice.xlsx', size: 1000, map: MAP }), 'keep the Schedule-C');
  await no('Format: a workbook that was not stored is refused', await fact('cc', { op: 'fmt_add', id: 'CFnofile001', path: 'fmt/CFnofile001.xlsx', name: 'Missing', file: 'x.xlsx', size: 10, map: MAP }), 'not stored');
  await no('Format: the path must be the format\'s own', await fact('cc', { op: 'fmt_add', id: A, path: 'fmt/CFother0001.xlsx', name: 'Utility layout', file: 'x.xlsx', size: 10, map: MAP }), 'path');
  await no('Format: a map without its tables is refused', await fact('cc', { op: 'fmt_add', id: A, path: `fmt/${A}.xlsx`, name: 'Utility layout', file: 'x.xlsx', size: 10, map: { sheets: [] } }), 'map is not valid');
  await no('Format: more than 25 MB is refused', await fact('cc', { op: 'fmt_add', id: A, path: `fmt/${A}.xlsx`, name: 'Utility layout', file: 'x.xlsx', size: 30000000, map: MAP }), '25 MB');
  await no('Format: a name of one letter is refused', await fact('cc', { op: 'fmt_add', id: A, path: `fmt/${A}.xlsx`, name: 'S', file: 'x.xlsx', size: 10, map: MAP }), 'name');
  await yes('Format: the costing engineer keeps it for a client', await fact('cc', { op: 'fmt_add', id: A, path: `fmt/${A}.xlsx`, name: 'Utility layout', client: 'SAMPLE Client', file: 'invoice.xlsx', size: 2048, hash: 'a'.repeat(64), map: MAP }), r => r.id === A);
  await yes('Format: a second workbook is stored', await put('cc', 'CFdef67890'));
  await no('Format: the same name for the same client is refused', await fact('cc', { op: 'fmt_add', id: 'CFdef67890', path: 'fmt/CFdef67890.xlsx', name: ' utility LAYOUT ', client: 'sample client', file: 'b.xlsx', size: 10, map: MAP }), 'already kept');
  await yes('Format: the same name for any client is another format', await fact('cc', { op: 'fmt_add', id: 'CFdef67890', path: 'fmt/CFdef67890.xlsx', name: 'Utility layout', file: 'b.xlsx', size: 10, map: MAP }));

  // reading
  const cnt = async (who, sql) => { const z = await as(who, sql); return z.ok ? z.rows[0].n : 'error: ' + z.err; };
  const rd = [await cnt('pm', `select count(*)::int n from cib_formats`), await cnt('pm', `select count(*)::int n from storage.objects where bucket_id = 'cib-formats'`)];
  check('Read: the project manager sees both formats and their files', rd[0] === 2 && rd[1] === 2, rd);
  const rf = [await cnt('fo', `select count(*)::int n from cib_formats`), await cnt('fo', `select count(*)::int n from storage.objects where bucket_id = 'cib-formats'`)];
  check('Read: a foreman sees neither', rf[0] === 0 && rf[1] === 0, rf);
  await no('Read: nobody writes the table directly', await as('cc', `update cib_formats set name = 'x' where id = '${A}'`));

  // the map
  await yes('Map: the costing engineer changes the name, client and map', await fact('cc', { op: 'fmt_map', id: A, name: 'Utility layout 2026', client: 'SAMPLE Client', map: { ...MAP, fields: [{ sheet: 'TAX INVOICE', addr: 'B19', field: 'inv_no' }] } }));
  const F = (await q(`select * from cib_formats where id = '${A}'`))[0];
  check('Map: kept with who changed it and the history', F.name === 'Utility layout 2026' && F.map.fields.length === 1 && F.updated_name === 'Cody Costing' && F.hist.length === 2 && F.created_name === 'Cody Costing' && F.file_hash === 'a'.repeat(64), { name: F.name, hist: F.hist.length });
  await no('Map: the project manager does not change it', await fact('pm', { op: 'fmt_map', id: A, name: 'Mine', map: MAP }), 'keep the Schedule-C');

  // deleting: the file stays while a format refers to it
  await as('cc', `delete from storage.objects where bucket_id = 'cib-formats' and name = 'fmt/${A}.xlsx'`);
  check('Delete: the workbook of a kept format cannot be removed', (await q(`select count(*)::int n from storage.objects where name = 'fmt/${A}.xlsx'`))[0].n === 1);
  await yes('Delete: the costing engineer deletes the format; the answer names its file', await fact('cc', { op: 'fmt_del', id: A }), r => r.path === `fmt/${A}.xlsx`);
  await as('cc', `delete from storage.objects where bucket_id = 'cib-formats' and name = 'fmt/${A}.xlsx'`);
  check('Delete: then its workbook is removed', (await q(`select count(*)::int n from storage.objects where name = 'fmt/${A}.xlsx'`))[0].n === 0 && (await q(`select count(*)::int n from cib_formats`))[0].n === 1);

  // the export noted
  const items = [{ no: 'X.3', comp: 'MAT', value: 10000, desc: 'Item X.3', unit: 'LT', qty: 1, rate: 10000, st: 'Active', leaf: true, limit: 100 }];
  const S1 = await yes('Export: a SAMPLE Schedule-C', await act('cc', { op: 'sch_save', pid: 'P1', head: { value: 10000, vat: 15, contract_no: 'SAMPLE-1' }, items, rules: { MAT: { t: 'split', first: 90 } } }));
  await yes('Export: approved', await act('rm', { op: 'sch_approve', pid: 'P1', sch: S1.id }));
  await yes('Export: mapped', await act('pe', { op: 'map_save', pid: 'P1', replace_p6: true, rows: [{ act: 'M1', item: 'X.3', src: 'p6', via: 'wbs' }] }));
  const r1 = await yes('Export: invoice #1 prepared', await act('cc', { op: 'inv_save', pid: 'P1', to: '2026-08-31', from: '2026-08-01' }));
  await yes('Export: the project manager exports it in a format', await act('pm', { op: 'inv_export', pid: 'P1', id: r1.id, fmt: 'Utility layout', note: '1 item row; 0 differences' }));
  const au = (await q(`select * from cib_audit where action = 'Invoice exported'`))[0];
  check('Export: the audit trail names the invoice, the format and who', au && au.ref === '#01 · Utility layout' && au.by_name === 'Paul Manager' && au.after_v.fmt === 'Utility layout' && /0 differences/.test(au.note), au);
  await no('Export: a foreman does not export', await act('fo', { op: 'inv_export', pid: 'P1', id: r1.id, fmt: 'x' }), 'not open to you');
  await yes('Export: in the ProTrackAI layout when no format is named', await act('cc', { op: 'inv_export', pid: 'P1', id: r1.id }));
  check('Export: noted as the ProTrackAI layout', (await q(`select ref from cib_audit where action = 'Invoice exported' order by id desc limit 1`))[0].ref === '#01 · ProTrackAI layout');

  // undo and again
  try { await db.exec(fs.readFileSync(path.join(SB, 'schema-rollback-v53.sql'), 'utf8')); check('Rollback: schema-rollback-v53.sql runs', true); } catch (e) { check('Rollback: schema-rollback-v53.sql runs', false, e.message); }
  check('Rollback: version 52 again; cib_fmt_act is gone', (await q(`select cib_features() ->> 'version' v, to_regprocedure('public.cib_fmt_act(jsonb)') f`)).every(r => r.v === '52' && r.f === null));
  await no('Rollback: an export is an unknown action again', await act('cc', { op: 'inv_export', pid: 'P1', id: r1.id }), 'Unknown action');
  await yes('Rollback: invoices still recalculate', await act('cc', { op: 'inv_save', pid: 'P1', id: r1.id, to: '2026-08-31', from: '2026-08-01' }));
  check('Rollback: the formats are kept on the server, unread', (await q(`select count(*)::int n from cib_formats`))[0].n === 1 && !(await as('pm', `select 1 from cib_formats`)).ok);
  try { await db.exec(fs.readFileSync(path.join(SB, 'schema-update-v53.sql'), 'utf8')); check('Rollback: v53 installs again; the kept format is read again', (await as('pm', `select count(*)::int n from cib_formats`)).rows[0].n === 1); }
  catch (e) { check('Rollback: v53 installs again; the kept format is read again', false, e.message); }

  const pass = results.filter(r => r.pass).length;
  console.log(`\n${pass}/${results.length} passed`);
  fs.writeFileSync(path.join(HERE, 'test_v53_results.json'), JSON.stringify({ run: new Date().toISOString(), pass, total: results.length, results }, null, 1));
  process.exit(pass === results.length ? 0 : 1);
})();
