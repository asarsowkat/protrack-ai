#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v10 (issue register, release snapshot); based on the v9 harness.
Original v9 description: (released reporting): progress releases and monthly cost reports
(prepare, submit, approve by the Head, no self-approval, return, revise, frozen once released, who can read what),
server-side cost formulas with approved budget supplements, and the change order / claim and budget supplement
log uploads (all-or-nothing, acknowledgement, duplicates, history). Usage: python3 test_v9.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v10_test'
results = []
def find(name):
    for d in (HERE, os.path.dirname(HERE), os.path.join(HERE, 'tests')):
        if os.path.exists(os.path.join(d, name)): return os.path.join(d, name)
    raise SystemExit('missing ' + name)
def psql(sql=None, file=None):
    p = subprocess.run(PG + ['-d', DBN] + (['-f', file] if file else ['-c', sql]), capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()
def admin(sql):
    rc, out, err = psql(sql)
    if rc: raise SystemExit('setup failed: ' + err + '\n' + sql)
    return out
ROLES = {'sa': 'sa', 'hd': 'pm', 'pl': 'plan', 'pl2': 'plan', 'co': 'costing', 'pm': 'pm', 'ex': 'exec', 'fo': 'foreman', 'nx': 'plan'}
U = {k: f'00000000-0000-0000-0000-0000000003{i:02d}' for i, k in enumerate(ROLES, start=1)}
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
def rel(who, action, **kw): p = {'action': action}; p.update(kw); return call(who, 'release_act', p)
def ok_(name, res, cond=lambda r: True):
    rc, r, err = res
    try: good = rc == 0 and cond(r)
    except Exception as e: good, err = False, repr(e)
    check(name, good, r if rc == 0 else err); return r
def no_(name, res, msg=None):
    rc, r, err = res; check(name, rc != 0 and (msg is None or msg.lower() in err.lower()), err or r)
def cnt(who, sql):
    rc, out, err = run_as(who, sql.rstrip().rstrip(';') + ';')
    if rc: print('CNT ERR', who, err[:300])
    return out.splitlines()[-1] if rc == 0 and out else 'ERR ' + err
q = admin

subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql', 'schema-update-v4.sql', 'schema-update-v5.sql',
          'schema-update-v6.sql', 'schema-update-v7.sql', 'schema-update-v8.sql', 'schema-update-v9.sql']:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin(f"insert into pcc_designations (user_id, designation) values ('{U['hd']}','head')")
admin("insert into regions values ('R1','Western',null); insert into projects (id, name, short, region) values ('P1','One','P1','R1'), ('P2','Two','P2','R1');")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['hd', 'pl', 'co', 'pm', 'fo']) + f", ('{U['pl2']}','P2'), ('{U['hd']}','P2')")
# a released planning version from before v10 must stay untouched
rel('pl', 'save', project_id='P1', kind='planning', period_type='month', period='2026-08', figures={'actual_pct': 40}); rel('pl', 'submit', project_id='P1', kind='planning', period_type='month', period='2026-08')
rel('hd', 'approve', project_id='P1', kind='planning', period_type='month', period='2026-08')
for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v10.sql'))
    check(f'v10 loads (run {i})', rc == 0, err)
check('existing releases keep an empty issue snapshot', q("select issues_snapshot::text from report_releases where period='2026-08'") == '[]')
def iss(who, action, **kw): p = {'action': action}; p.update(kw); return call(who, 'issue_act', p)
F1 = {'description': 'Power transformer delivery delayed at factory', 'impact': 'extremely high', 'owner': 'Vendor', 'sub_owner': 'SPTC', 'issue_type': 'Delivery',
      'started_on': '2026-07-01', 'action_required': 'Expedite FAT', 'priority_client': 'a', 'priority_internal': 'A', 'action_by': 'PM', 'planned_target': '2026-10-15',
      'schedule_impact': '2 months', 'cost_impact': 'No impact', 'data_date': '2026-09-24'}
for who in ['fo', 'pm', 'ex']:
    no_(f'{ROLES[who]} cannot add an issue', iss(who, 'save', project_id='P1', fields=F1), 'only the planning and costing engineers')
no_('a planning engineer of another project cannot add one here', iss('pl2', 'save', project_id='P1', fields=F1), 'do not have access')
no_('an issue needs a description', iss('pl', 'save', project_id='P1', fields=dict(F1, description=' ')), 'describe the issue')
no_('impact must be one of the four levels', iss('pl', 'save', project_id='P1', fields=dict(F1, impact='Huge')), 'impact must be')
no_('priority must be A, B or C', iss('pl', 'save', project_id='P1', fields=dict(F1, priority_client='Z')), 'priority must be')
no_('dates must be real', iss('pl', 'save', project_id='P1', fields=dict(F1, planned_target='2026-02-30')), 'not a valid date')
r1 = ok_('the planning engineer adds an issue; impact and priority are written the standard way', iss('pl', 'save', project_id='P1', fields=F1),
         lambda r: r['issue_no'] == 'ISS-001' and r['impact'] == 'Extremely High' and r['priority_client'] == 'A' and r['status'] == 'Open' and r['planned_target'] == '2026-10-15')
r2 = ok_('the costing engineer adds one too', iss('co', 'save', project_id='P1', fields={'description': 'Budget supplement for TSC panel pending approval', 'impact': 'High', 'issue_type': 'Funding', 'owner': 'Internal'}),
         lambda r: r['issue_no'] == 'ISS-002')
r3 = ok_('a third, medium impact', iss('pl', 'save', project_id='P1', fields={'description': 'Shutdown permit pending', 'impact': 'Medium', 'owner': 'Client', 'sub_owner': 'SEC'}), lambda r: r['issue_no'] == 'ISS-003')
ok_('an update records which fields changed', iss('pl', 'save', id=r1['id'], fields={'forecast_target': '2026-11-05', 'action_taken': 'Letter sent to vendor'}), lambda r: r['forecast_target'] == '2026-11-05')
check('the history holds the creation and the change', q(f"select string_agg(action||':'||coalesce(detail->>'changes',''), ' | ' order by id) from issue_audit where issue_id='{r1['id']}'") == 'Created: | Updated:["action_taken", "forecast_target"]')
ok_('the Head (a project manager with the designation) can keep issues on any of their projects', iss('hd', 'save', id=r3['id'], fields={'action_by': 'SEC/PM'}), lambda r: r['action_by'] == 'SEC/PM')
no_('only the Head or a super admin marks an issue reviewed', iss('pl', 'review', id=r1['id'], note='ok'), 'only the head')
ok_('the Head marks it reviewed', iss('hd', 'review', id=r1['id'], note='Escalate to VP'), lambda r: r['reviewed_by'] == U['hd'] and r['review_note'] == 'Escalate to VP')
ok_('the costing engineer closes an issue', iss('co', 'close', id=r2['id'], closed_on='2026-09-20'), lambda r: r['status'] == 'Closed' and r['closed_on'] == '2026-09-20')
no_('a closed issue cannot be edited', iss('co', 'save', id=r2['id'], fields={'remarks': 'x'}), 'reopen it first')
no_('reopening needs a comment', iss('co', 'reopen', id=r2['id']), 'add a comment')
ok_('it can be reopened with a comment', iss('co', 'reopen', id=r2['id'], note='Approval withdrawn'), lambda r: r['status'] == 'Open' and r['closed_on'] is None)
iss('co', 'close', id=r2['id'])
check('office staff with access to the project read its issues; others do not', cnt('pm', "select count(*) from issues") == '3' and cnt('nx', "select count(*) from issues") == '0' and cnt('pl2', "select count(*) from issues") == '0')
check('site staff (foreman) read no issues and no issue history, even on their project', cnt('fo', "select count(*) from issues") == '0' and cnt('fo', "select count(*) from issue_audit") == '0')
no_('the issue history cannot be edited', psql("update issue_audit set note='x'"), 'append-only')
run_as('pl', "update issues set impact='Low';")
check('a direct write from the browser changes nothing', q("select count(*) from issues where impact='Low'") == '0')

# ------------------------------------------------------------------ upload
ROWS = [{'project_id': 'P1', 'description': '  power TRANSFORMER delivery delayed   at factory ', 'impact': 'High', 'remarks': 'Shipped 20 Sep', 'status': 'Open'},
        {'project_id': 'P1', 'description': 'GIS HV test flashover', 'impact': 'High', 'owner': 'Internal', 'issue_type': 'Test & Comm.', 'status': 'open', 'data_date': '2026-09-24'},
        {'project_id': 'P1', 'description': 'Old punch list', 'impact': 'Low', 'status': 'Closed', 'closed_on': '2026-08-01'},
        {'project_id': 'P2', 'description': 'Not my project', 'impact': 'High'},
        {'project_id': 'P1', 'description': 'Bad impact row', 'impact': 'Catastrophic'},
        {'project_id': 'PX', 'description': 'Unknown project', 'impact': 'High'},
        {'project_id': 'P1', 'description': 'Bad priority row', 'impact': 'High', 'priority_client': 'Medium', 'row': 42},
        {'project_id': '', 'description': '', 'action_taken': 'continuation text'}]
IM = dict(file_name='issue_log.xlsx', hash='h' * 64, rows=ROWS)
for who in ['fo', 'pm']:
    no_(f'{ROLES[who]} cannot upload the issue log', call(who, 'issue_import', IM), 'only planning and costing engineers')
no_('refused rows must be acknowledged; nothing is saved until then', call('pl', 'issue_import', IM), 'acknowledge')
check('...and nothing changed', q("select count(*) from issues") == '3')
r = ok_('acknowledged, the upload updates the matching issue, adds two and refuses five', call('pl', 'issue_import', dict(IM, ack=True)),
        lambda r: r['created'] == 2 and r['updated'] == 1 and sorted(x['error'] for x in r['rejected']) == ['impact must be Extremely High, High, Medium or Low', 'no project or description (a continuation row?)', 'not one of your projects', 'priority must be A, B or C', 'unknown project'])
check('refused rows keep the row number of the file when it is sent', any(x['row'] == 42 for x in r['rejected']) and any(x['row'] == 6 and x['project'] == 'PX' for x in r['rejected']), r['rejected'])
check('the matched issue keeps its number and history, with the new impact and remarks', q(f"select issue_no||'/'||impact||'/'||remarks||'/'||(select count(*) from issue_audit where issue_id=i.id) from issues i where id='{r1['id']}'") == 'ISS-001/High/Shipped 20 Sep/4')
check('a closed row comes in closed with its date', q("select status||'/'||closed_on from issues where description='Old punch list'") == 'Closed/2026-08-01')
check('the upload is a numbered batch with the acknowledged difference', q("select kind||'/'||project_id||'/'||rows_rejected||'/'||recon_status from import_batches where kind='issues'") == 'issues/P1/5/Accepted with difference')
ok_('the same file again changes nothing', call('pl', 'issue_import', dict(IM, ack=True)), lambda r: r['duplicate'] is True)
no_('a file with no valid rows saves nothing', call('pl', 'issue_import', dict(IM, hash='k' * 64, rows=ROWS[3:])), 'no valid rows')

# ------------------------------------------------------------------ released versions carry the open issues
M = dict(project_id='P1', kind='planning', period_type='month', period='2026-09')
rel('pl', 'save', figures={'actual_pct': 52}, **M); rel('pl', 'submit', **M)
r = ok_('approving a progress release saves the project\'s open issues with it, worst first', rel('hd', 'approve', **M),
        lambda r: [x['no'] for x in r['issues_snapshot']] == ['ISS-001', 'ISS-004', 'ISS-003'] and r['issues_snapshot'][0]['impact'] == 'High')
check('the saved issues carry no cost impact (site staff can read progress releases)', q("select count(*) from report_releases, jsonb_array_elements(issues_snapshot) x where x ? 'cost_impact'") == '0')
iss('pl', 'close', id=r1['id'])
check('closing an issue later does not change what was released', q("select jsonb_array_length(issues_snapshot) from report_releases where period='2026-09' and kind='planning'") == '3')
no_('the saved issues cannot be changed, even from the database console', psql("update report_releases set issues_snapshot='[]' where period='2026-09' and kind='planning'"), 'cannot be changed')
CM = dict(project_id='P1', kind='cost', period_type='month', period='2026-09')
ok_('a cost report can carry billing figures from the invoice register', rel('co', 'save', figures={'budget_rev0': 100, 'actual': 40, 'commitment': 10, 'ftc': 70, 'inv_invoiceable': 55, 'inv_submitted': 50, 'inv_approved': 45, 'inv_collected': 30}, **CM),
    lambda r: float(r['figures']['inv_collected']) == 30 and r['issues_snapshot'] == [])
no_('billing amounts cannot be negative', rel('co', 'save', figures={'budget_rev0': 100, 'actual': 40, 'commitment': 10, 'ftc': 70, 'inv_collected': -5}, **CM), 'cannot be negative')
no_('billing figures must be numbers', rel('co', 'save', figures={'budget_rev0': 100, 'actual': 40, 'commitment': 10, 'ftc': 70, 'inv_submitted': 'lots'}, **CM), 'must be a number')

# ------------------------------------------------------------------ rollback keeps everything
counts = q("select (select count(*) from issues)||'/'||(select count(*) from issue_audit)||'/'||(select count(*) from report_releases where issues_snapshot <> '[]')")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v10.sql'))
    check(f'rollback runs (run {i})', rc == 0, err)
check('rollback removes the issue functions', q("select count(*) from pg_proc where proname in ('issue_act','issue_import','pt_issue_snapshot')") == '0')
check('rollback keeps every issue, history entry and saved snapshot', q("select (select count(*) from issues)||'/'||(select count(*) from issue_audit)||'/'||(select count(*) from report_releases where issues_snapshot <> '[]')") == counts, counts)
W = dict(project_id='P1', kind='planning', period_type='week', period='2026-W40')
rel('pl', 'save', figures={'actual_pct': 53}, **W); rel('pl', 'submit', **W)
ok_('after rollback releases work as in v9', rel('hd', 'approve', **W), lambda r: r['status'] == 'Released')
rc, out, err = psql(file=find('schema-update-v10.sql'))
check('v10 can be applied again after a rollback', rc == 0, err)

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'schema-update-v10', 'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v10_results.json'), 'w'), indent=1)
sys.exit(0 if passed == len(results) else 1)
