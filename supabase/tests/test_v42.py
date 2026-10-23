#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v42 (Budget & Cost Management stage 4: SAP report import with templates,
frozen reports and figures by WBS worked out on the server; the SAP loading workbook of an approved budget version, its
confirmation with the SAP reference, or its return). Loads schema.sql and every update v2 to v42. Usage: python3 test_v42.py"""
import json, os, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v42_test'
results = []
def find(name):
    for d in (HERE, os.path.dirname(HERE)):
        if os.path.exists(os.path.join(d, name)): return os.path.join(d, name)
    return None
def psql(sql=None, file=None):
    p = subprocess.run(PG + ['-d', DBN] + (['-f', file] if file else ['-c', sql]), capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()
def q(sql):
    rc, out, err = psql(sql)
    if rc: raise SystemExit('setup failed: ' + err + '\n' + sql)
    return {'t': 'true', 'f': 'false'}.get(out, out)
PEOPLE = {'c3': ('costing', 'Cora Costing'), 'sa': ('sa', 'Sara Admin'), 'ap': ('pm', 'Adam Approver'), 'co': ('costing', 'Carla Costing'), 'c2': ('costing', 'Chris Costing'),
          'pm': ('pm', 'Paul Manager'), 'pl': ('plan', 'Peter Planner'), 'fo': ('foreman', 'Faisal Foreman'), 'out': ('costing', 'Olga Outside'), 'ex': ('exec', 'Eva Executive')}
U = {k: f'00000000-0000-0000-0000-0000000042{i:02d}' for i, k in enumerate(PEOPLE, start=1)}
def run_as(who, body):
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write(f"begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub', '{U[who]}', true) \\g /dev/null\n{body}\ncommit;\n"); path = f.name
    try: return psql(file=path)
    finally: os.unlink(path)
def check(name, ok, detail=''):
    results.append({'check': name, 'pass': bool(ok), 'detail': str(detail)[:300]})
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '  -> ' + str(detail)[:300]))
def lit(o): return "'" + json.dumps(o).replace("'", "''") + "'::jsonb"
def call(who, fn, p):
    rc, out, err = run_as(who, f"select {fn}({lit(p)});")
    return rc, (json.loads(out.splitlines()[-1]) if rc == 0 and out else None), err
def ok_(name, res, cond=lambda r: True):
    rc, r, err = res
    try: good = rc == 0 and cond(r)
    except Exception as e: good, err = False, repr(e)
    check(name, good, r if rc == 0 else err); return r
def no_(name, res, msg=None):
    rc, r, err = res; check(name, rc != 0 and (msg is None or msg.lower() in err.lower()), err or r)
def one(who, sql):
    rc, out, err = run_as(who, sql.rstrip().rstrip(';') + ';')
    o = out.splitlines()[-1] if rc == 0 and out else 'ERR ' + err
    return {'t': 'true', 'f': 'false'}.get(o, o)




subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 43)]:
    path = find(f)
    if not path: continue
    rc, out, err = psql(file=path)
    if rc: raise SystemExit(f + ': ' + err)
q("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k in PEOPLE))
q("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, (r, n) in PEOPLE.items()))
q("insert into regions (id, name) values ('R1','Central'); insert into sectors (id, name) values ('S1','Buildings')")
q("insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status, pe_number) values ('P2','Old Line','OL','R1','S1','2024-01-01','2026-12-31',30,'Active','PE-555'), ('P3','Other','OT','R1','S1','2024-01-01','2026-12-31',30,'Active','PE-999')")
q("insert into project_access (user_id, project_id) values " + ",".join(f"('{U[k]}','{p}')" for k in ['ap', 'co', 'c2', 'c3', 'pm', 'pl', 'fo'] for p in ['P2', 'P3']))
q(f"insert into user_rights (user_id, right_key, allow) values ('{U['ap']}', 'bcm.approve', true), ('{U['ap']}', 'bcm.budget.approve', true), ('{U['c2']}', 'bcm.sap', true)")
check('Install: bcm_features gives version 42 with stage 4', one('co', "select bcm_features() ->> 'version'") == '42' and one('co', "select bcm_features() -> 'stages' @> '[4]'") == 'true')
check('Install: the SAP rights are listed; bcm.sap.import is a costing right by default, bcm.sap nobody\'s', one('co', "select 'bcm.sap.import' = any(pt_rights()) and 'bcm.sap' = any(pt_rights())") == 'true'
      and q("select pt_right_default('costing', 'bcm.sap.import') and not pt_right_default('costing', 'bcm.sap') and not pt_right_default('pm', 'bcm.sap.import')") == 'true')
for _ in range(5):
    ids = [i for i in q("select coalesce(string_agg(id, ','), '') from bcm_master where pend is not null and ent in ('wbs','rule')").split(',') if i]
    if not ids: break
    call('ap', 'bcm_master_act', {'action': 'approve_many', 'ids': ids})
REV0 = [('PE-555-01-001-01', 'SM1-01', 'Salaries - Project office team', 'SM', 'Overhead', '1250000'), ('PE-555-01-001-02', 'SM1-02', 'Salaries - Site office team', 'SM', 'Overhead', '820000'),
        ('PE-555-04-001', 'ELM-01', 'Cables material', 'MTRL.ELC', 'Material', '5100000'), ('PE-555-05-001', 'ELP-01', 'Cable laying manpower', 'MAN.ELC', 'Manpower', '910000'), ('PE-555-13', 'PC', 'Prime cost items', 'PC ITEMS', None, '300000')]
def version(kind, rows, pid='P2', approve=True):
    r = call('co', 'bcm_version_act', {'action': 'import', 'project_id': pid, 'kind': kind, 'currency': 'SAR', 'justification': kind + ' as loaded',
             'lines': [{'sap_wbs_id': a, 'wbs_code': b, 'descr': c, 'user_field': d, 'cost_type': e, 'amount': f, 'row': i + 2} for i, (a, b, c, d, e, f) in enumerate(rows)]})
    if r[0]: raise SystemExit('version: ' + r[2])
    vid = r[1]['id']
    if approve:
        call('co', 'bcm_version_act', {'action': 'submit', 'id': vid}); call('c3', 'bcm_version_act', {'action': 'review', 'id': vid}); call('ap', 'bcm_version_act', {'action': 'approve', 'id': vid})
    return vid
V0 = version('Rev 0', REV0)
check('Setup: Rev 0 of PE-555 approved in ProTrackAI', q(f"select status from bcm_versions where id='{V0}'") == 'Approved in ProTrackAI')

# ---------------- templates
no_('Templates: a planner cannot keep templates', call('pl', 'bcm_sap_tpl', {'name': 'S_ALR by WBS', 'kind': 'wbs', 'map': {'wbs': 'Object'}}), 'bcm.sap.import')
no_('Templates: a template needs the WBS element column', call('co', 'bcm_sap_tpl', {'name': 'S_ALR by WBS', 'kind': 'wbs', 'map': {'budget': 'Budget'}}), 'WBS element')
T1 = ok_('Templates: a costing engineer saves one', call('co', 'bcm_sap_tpl', {'name': 'S_ALR by WBS', 'kind': 'wbs', 'map': {'wbs': 'Object', 'budget': 'Budget', 'actual': 'Actual', 'commit': 'Commitment'}}), lambda r: r['id'].startswith('ST-'))
ok_('Templates: saving the same name again updates it', call('c2', 'bcm_sap_tpl', {'name': 'S_ALR by WBS', 'kind': 'wbs', 'map': {'wbs': 'Object', 'actual': 'Actual'}}), lambda r: r['id'] == T1['id'])
check('Templates: one template, by its last author, read by anyone with cost figures', one('pm', "select count(*) || '/' || min(by_name) from bcm_sap_tpls") == '1/Chris Costing' and one('fo', "select count(*) from bcm_sap_tpls") == '0')

# ---------------- importing reports
sha = lambda c: (c * 64)[:64]
def store(c, pid='P2', kind='xlsx'): q(f"insert into storage.objects (bucket_id, name) values ('bcm-tender', 'bcm/{pid}/sap/{sha(c)}.{kind}') on conflict do nothing")
def rep(c, period, kind, rows, who='co', pid='P2', **kw):
    p = {'project_id': pid, 'period': period, 'kind': kind, 'currency': 'SAR', 'file': {'name': f'{c}.xlsx', 'sha256': sha(c), 'size': 9000, 'kind': 'xlsx', 'path': f'bcm/{pid}/sap/{sha(c)}.xlsx'}, 'rows': rows}
    p.update(kw); return call(who, 'bcm_sap_import', p)
H = {'budget': True, 'actual': True, 'commit': True}
def W(rows): return [{'row': i + 5, 'wbs': w, 'desc': d, 'budget': b, 'actual': a, 'commit': c} for i, (w, d, b, a, c) in enumerate(rows)]
L08 = [('PE-555', 'Project', '8370000', '4735000', '2700000'), ('PE-555-01', 'Site Management', '2070000', '900000', '200000'), ('PE-555-01-001', 'Salaries', '2070000', '900000', '200000'),
       ('PE-555-01-001-01', 'Project office team', '1250000', '600000', '100000'), ('PE-555-01-001-02', 'Site office team', '820000', '300000', '100000'),
       ('PE-555-04', 'Electrical Material', '5100000', '3000000', '2500000'), ('PE-555-04-001', 'Cables material', '5100000', '3000000', '2500000'),
       ('PE-555-05', 'Electrical Manpower', '900000', '820000', '0'), ('PE-555-05-001', 'Cable laying manpower', '900000', '820000', '0'),
       ('PE-555-09', 'Earthing', '0', '15000', '0'), ('PE-555-09-001', 'Earthing material', '0', '15000', '0'), ('PE-555-13', 'Prime cost items', '300000', '0', '0')]
no_('Import: the file must be in storage first', rep('a', '2026-08', 'wbs', W(L08), has=H), 'Upload the file')
store('a')
no_('Import: a planner cannot import SAP reports', rep('a', '2026-08', 'wbs', W(L08), who='pl', has=H), 'bcm.sap.import')
no_('Import: a future period is refused', rep('a', '2099-01', 'wbs', W(L08), has=H), 'future')
no_('Import: an amount that is not a number is refused', rep('a', '2026-08', 'wbs', W([('PE-555-04-001', 'x', '5100000', 'n/a', '0')]), has=H), 'is not a number')
no_('Import: a repeated WBS element is refused', rep('a', '2026-08', 'wbs', W([('PE-555-04-001', 'x', '1', '1', '1'), ('pe-555-04-001', 'y', '1', '1', '1')]), has=H), 'repeated')
no_('Import: a row without a WBS element is refused', rep('a', '2026-08', 'wbs', W([('', 'x', '1', '1', '1')]), has=H), 'no WBS element')
no_('Import: a total row that does not match the elements is refused', rep('a', '2026-08', 'wbs', W(L08), has=H, ftot={'budget': '8380000', 'actual': '4735000'}), 'total row')
no_('Import: a report without amount columns is refused', rep('a', '2026-08', 'wbs', W(L08), has={}), 'no Budget')
check('Import: nothing is kept from refused imports', q("select count(*) from bcm_sap_reports") == '0' and q("select count(*) from bcm_sap_lines") == '0')
R08 = ok_('Import: the by-WBS report of 2026-08 is imported and frozen, with its totals checked against the total row', rep('a', '2026-08', 'wbs', W(L08), has=H, ftot={'budget': '8370000', 'actual': '4735000', 'commit': '2700000'}),
          lambda r: r['n'] == 12 and r['totals'] == {'budget': '8370000.000000', 'actual': '4735000.000000', 'commit': '2700000.000000'})
agg = json.loads(q(f"select agg from bcm_sap_reports where id='{R08['id']}'"))
check('Import: totals at each level are not counted twice: an element counts what is not in the elements below it', agg['pe-555-01']['actual'] == '0.000000' and agg['pe-555']['budget'] == '0.000000'
      and agg['pe-555-04-001']['commit'] == '2500000.000000' and agg['pe-555-01']['parent_row'] is True and agg['pe-555-01-001-01']['parent_row'] is False, agg.get('pe-555-01'))
no_('Import: the same file again is refused', rep('a', '2026-09', 'wbs', W(L08), has=H), 'already imported')
store('b')
R08b = ok_('Import: another report for the same period and kind is imported...', rep('b', '2026-08', 'wbs', W(L08[3:5]), has=H), lambda r: r['n'] == 2)
check('...and supersedes the first, which is kept', q(f"select status || '/' || superseded_by from bcm_sap_reports where id='{R08['id']}'") == f"Superseded/{R08b['id']}" and q(f"select count(*) from bcm_sap_lines where report_id='{R08['id']}'") == '12')
rc, out, err = run_as('co', f"update bcm_sap_lines set actual = 1 where report_id = '{R08b['id']}'")
check('Frozen: a costing engineer cannot change imported rows', rc != 0 or q(f"select sum(actual) from bcm_sap_lines where report_id='{R08b['id']}'") == '900000.000000', err)
rc, out, err = psql(f"update bcm_sap_lines set actual = 1 where report_id = '{R08b['id']}'")
check('Frozen: not even the database owner changes them', rc != 0 and 'never change' in err, err)
rc, out, err = psql(f"insert into bcm_sap_lines (report_id, n, wbs) values ('{R08b['id']}', 99, 'X')")
check('Frozen: rows are added only by the import', rc != 0 and 'never change' in err, err)
# line items
store('c')
I = lambda rows: [{'row': i + 4, 'wbs': w, 'date': d, 'actual': v, 'ce': '610000', 'doc': str(5100000 + i)} for i, (w, d, v) in enumerate(rows)]
no_('Line items: a posting after the period is refused', rep('c', '2026-09', 'actual', I([('PE-555-04-001', '2026-10-02', '10')])), 'after the period')
no_('Line items: a posting before the period is refused (postings of the period)', rep('c', '2026-09', 'actual', I([('PE-555-04-001', '2026-08-02', '10')])), 'before the period')
R09 = ok_('Line items: the actual postings of 2026-09 are summed by WBS element, the credit included', rep('c', '2026-09', 'actual', I([('PE-555-01-001-01', '2026-09-30', '50000'), ('PE-555-01-001-01', '2026-09-15', '25000'),
          ('PE-555-04-001', '2026-09-20', '120000'), ('PE-555-04-001', '2026-09-21', '-1500'), ('PE-555-05-001', '2026-09-28', '40000')]), ftot={'actual': '233500'}), lambda r: r['totals'] == {'actual': '233500.000000'})
agg = json.loads(q(f"select agg from bcm_sap_reports where id='{R09['id']}'"))
check('Line items: by WBS element, with the number of postings', agg['pe-555-04-001']['actual'] == '118500.000000' and agg['pe-555-04-001']['n'] == 2, agg)
store('d')
R09c = ok_('Line items: a report to the end of the period accepts earlier postings, and keeps the part of the period apart', rep('d', '2026-09', 'actual', I([('PE-555-04-001', '2026-01-02', '100'), ('PE-555-04-001', '2026-09-02', '10')]), cumulative=True), lambda r: True)
agg = json.loads(q(f"select agg from bcm_sap_reports where id='{R09c['id']}'"))
check('...its figures: 110 to date, 10 in the period', agg['pe-555-04-001']['actual'] == '110.000000' and agg['pe-555-04-001']['inP'] == '10.000000', agg)
store('e')
ok_('Line items: open commitments', rep('e', '2026-09', 'commit', [{'row': 2, 'wbs': 'PE-555-04-001', 'commit': '2380000', 'doc': '4500011'}]), lambda r: r['totals'] == {'commit': '2380000.000000'})
check('Read: a foreman reads no SAP report; someone outside the project neither', one('fo', 'select count(*) from bcm_sap_reports') == '0' and one('out', 'select count(*) from bcm_sap_reports') == '0' and one('out', 'select count(*) from bcm_sap_lines') == '0')
check('Read (fix of v41): someone with cost figures outside the project reads no budget version line', one('out', 'select count(*) from bcm_version_lines') == '0' and one('pm', 'select count(*) > 0 from bcm_version_lines') == 'true')
check('Read: a project manager with cost figures reads them', one('pm', 'select count(*) from bcm_sap_reports') == '5' and one('pm', 'select count(*) > 0 from bcm_sap_lines') == 'true')
check('Storage: the bucket rule lets a costing engineer add a report file under sap/, not a planner', one('co', "select pt_bcm_file_can(auth.uid(), 'bcm/P2/sap/" + sha('z') + ".xlsx', true)") == 'true' and one('pl', "select pt_bcm_file_can(auth.uid(), 'bcm/P2/sap/" + sha('z') + ".xlsx', true)") == 'false')
check('Audit: imports are logged', q("select count(*) from bcm_audit where action = 'SAP report imported'") == '5')

# ---------------- the SAP loading workbook
TE = version('Tender estimate', REV0)
no_('Workbook: a Tender estimate is not loaded in SAP', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': TE}), 'Tender estimate')
no_('Workbook: someone without bcm.sap cannot prepare it', call('co', 'bcm_sap_export', {'action': 'generate', 'version_id': V0}), 'bcm.sap')
VD = version('Revised Rev 0', REV0, approve=False)
no_('Workbook: a draft is not prepared for SAP', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': VD}), 'approved in ProTrackAI')
VB = version('Approved revision', REV0[:4] + [('XX-13', 'PC', 'Prime cost items', 'PC ITEMS', None, '300000')], pid='P2')
no_('Workbook: refused while an amount has no valid SAP WBS ID of the project, naming it', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': VB}), "XX-13 (does not start with the project's PE number PE-555)")
VC = version('Approved revision', REV0[:4] + [('PE-555-1', 'PC', 'Prime cost items', 'PC ITEMS', None, '300000')], pid='P2')
no_('Workbook: ...or a segment with the wrong digits', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': VC}), 'level 1 should be 2 digits')
call('ap', 'bcm_version_act', {'action': 'reject', 'id': VD, 'reason': 'not needed now'}) if False else None
X1 = ok_('Workbook: the SAP authorized user prepares the workbook of Rev 0: the original budget by SAP WBS ID', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': V0}),
         lambda r: r['seq'] == 1 and len(r['content']['items']) == 5 and r['content']['changes'] is None and r['content']['total'] == '8380000.000000' and r['content']['excluded'] == [] and len(r['check']) == 32)
check('Workbook: the version is Ready for SAP Loading, with its history', q(f"select status from bcm_versions where id='{V0}'") == 'Ready for SAP Loading' and q(f"select action from bcm_version_hist where version_id='{V0}' order by id desc limit 1") == 'SAP loading workbook 1')
no_('Workbook: another version waits while one is ready for loading', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': VB}), 'waiting for its SAP loading confirmation')
no_('Confirm: someone without bcm.sap cannot record the loading', call('co', 'bcm_sap_export', {'action': 'confirm', 'export_id': X1['id'], 'sap_ref': 'CJ30-4711', 'sap_date': '2026-10-01'}), 'bcm.sap')
no_('Confirm: the SAP reference is needed', call('c2', 'bcm_sap_export', {'action': 'confirm', 'export_id': X1['id'], 'sap_ref': 'x', 'sap_date': '2026-10-01'}), 'SAP reference')
no_('Confirm: a loading date in the future is refused', call('c2', 'bcm_sap_export', {'action': 'confirm', 'export_id': X1['id'], 'sap_ref': 'CJ30-4711', 'sap_date': '2099-01-01'}), 'future')
no_('Confirm: a loading date before the workbook is refused', call('c2', 'bcm_sap_export', {'action': 'confirm', 'export_id': X1['id'], 'sap_ref': 'CJ30-4711', 'sap_date': '2020-01-01'}), 'before the workbook')
q(f"update bcm_sap_exports set generated_at = now() - interval '3 days' where id = '{X1['id']}'")
ok_('Confirm: the SAP authorized user records the loading with the SAP reference', call('c2', 'bcm_sap_export', {'action': 'confirm', 'export_id': X1['id'], 'sap_ref': 'CJ30-4711', 'sap_date': str(q("select current_date - 1")), 'note': 'loaded by the SAP team'}), lambda r: r['status'] == 'SAP Loading Confirmed')
check('Confirm: the version is SAP Loading Confirmed with its reference', q(f"select status || '/' || sap_ref from bcm_versions where id='{V0}'") == 'SAP Loading Confirmed/CJ30-4711' and q(f"select status || '/' || closed_by_name from bcm_sap_exports where id='{X1['id']}'") == 'Confirmed/Chris Costing')
no_('Confirm: a confirmed workbook is not confirmed twice', call('c2', 'bcm_sap_export', {'action': 'confirm', 'export_id': X1['id'], 'sap_ref': 'CJ30-4712', 'sap_date': str(q("select current_date"))}), 'confirmed')
REV = [(a, b, c, d, e, f) for (a, b, c, d, e, _), f in zip(REV0, ['1300000', '840000', '4950000', '905000.5', '300000'])]
V1 = version('Revised Rev 0', REV)
X2 = ok_('Workbook: the revision is prepared as supplements and returns against the version loaded (Rev 0, CJ30-4711)', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': V1}),
         lambda r: r['content']['prev']['sap_ref'] == 'CJ30-4711' and r['content']['prev_total'] == '8380000.000000' and r['content']['total'] == '8295000.500000'
         and [(x['sap'], x['diff']) for x in r['content']['changes']] == [('PE-555-01-001-01', '50000.000000'), ('PE-555-01-001-02', '20000.000000'), ('PE-555-04-001', '-150000.000000'), ('PE-555-05-001', '-4999.500000')])
no_('Return: a reason is needed', call('c2', 'bcm_sap_export', {'action': 'return', 'export_id': X2['id']}), 'reason')
ok_('Return: the SAP team could not load it: returned with the reason, the version is approved again', call('c2', 'bcm_sap_export', {'action': 'return', 'export_id': X2['id'], 'reason': 'fiscal year closed in SAP'}), lambda r: r['status'] == 'Approved in ProTrackAI')
X3 = ok_('Workbook: prepared again: workbook 2 of the version', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': V1}), lambda r: r['seq'] == 2)
check('Workbook: the earlier workbooks keep their status', q(f"select string_agg(seq || ':' || status, ',' order by seq) from bcm_sap_exports where version_id='{V1}'") == '1:Returned,2:Generated')
q(f"update bcm_sap_exports set generated_at = now() - interval '1 day' where id = '{X3['id']}'")
ok_('Confirm: the revision loaded', call('c2', 'bcm_sap_export', {'action': 'confirm', 'export_id': X3['id'], 'sap_ref': 'CJ37-0815', 'sap_date': str(q("select current_date"))}), lambda r: True)
no_('Workbook: an older approved version is not loaded after a later one', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': VB}), 'later version')
V2 = version('Approved revision', REV)
no_('Workbook: a version with no change from the version loaded is refused', call('c2', 'bcm_sap_export', {'action': 'generate', 'version_id': V2}), 'Nothing changes')
check('Read: the workbooks are read with the project', one('pm', 'select count(*) from bcm_sap_exports') == '3' and one('out', 'select count(*) from bcm_sap_exports') == '0')
check('Audit: workbooks, confirmations and returns are logged', q("select string_agg(action, ',' order by id) from bcm_audit where action like 'SAP loading%'") ==
      'SAP loading workbook prepared,SAP loading confirmed,SAP loading workbook prepared,SAP loading workbook returned,SAP loading workbook prepared,SAP loading confirmed')

# ---------------- rollback and again
rc, out, err = psql(file=find('schema-rollback-v42.sql'))
check('Rollback: runs', rc == 0, err)
check('Rollback: the stage 4 functions are gone, the records are kept', q("select to_regprocedure('bcm_sap_import(jsonb)') is null and to_regprocedure('bcm_sap_export(jsonb)') is null") == 'true'
      and q("select count(*) from bcm_sap_reports") == '5' and q("select bcm_features() ->> 'version'") == '41')
for i in range(2):
    rc, out, err = psql(file=find('schema-update-v42.sql'))
    check(f'Again: v42 runs ({i + 1})', rc == 0, err)
check('Again: everything is back', q("select bcm_features() ->> 'version'") == '42' and q("select count(*) from bcm_sap_exports") == '3' and q("select count(*) from bcm_sap_tpls") == '1')

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'v42', 'passed': passed, 'total': len(results), 'checks': results}, open(os.path.join(HERE, 'test_v42_results.json'), 'w'), indent=1)
