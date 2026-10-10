#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v9 (released reporting): progress releases and monthly cost reports
(prepare, submit, approve by the Head, no self-approval, return, revise, frozen once released, who can read what),
server-side cost formulas with approved budget supplements, and the change order / claim and budget supplement
log uploads (all-or-nothing, acknowledgement, duplicates, history). Usage: python3 test_v9.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v9_test'
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
ROLES = {'sa': 'sa', 'sa2': 'sa', 'hd': 'plan', 'pl': 'plan', 'co': 'costing', 'cc': 'pm', 'pm': 'pm', 'ex': 'exec', 'fo': 'foreman', 'en': 'eng', 'sm': 'sm'}
U = {k: f'00000000-0000-0000-0000-0000000002{i:02d}' for i, k in enumerate(ROLES, start=1)}
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
          'schema-update-v6.sql', 'schema-update-v7.sql', 'schema-update-v8.sql']:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin(f"insert into pcc_designations (user_id, designation) values ('{U['hd']}','head'), ('{U['cc']}','coordinator')")
admin("insert into regions values ('R1','R',null); insert into projects (id, name, short, region) values ('P1','One','P1','R1'), ('P2','Two','P2','R1');")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['hd', 'pl', 'co', 'cc', 'pm', 'fo', 'en', 'sm']))
for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v9.sql'))
    check(f'v9 loads (run {i})', rc == 0, err)

PF = {'planned_pct': 55, 'actual_pct': 52, 'spi': 0.95, 'eng_pct': 84, 'prc_pct': 72, 'forecast_finish': '2027-03-31', 'next_ms_text': 'Energisation'}
NAR = {'summary': 'Civil works on track; cable pulling behind.', 'issues': 'Transformer delivery', 'next': 'Recover cable pulling'}
M = dict(project_id='P1', kind='planning', period_type='month', period='2026-09')
# ------------------------------------------------------------------ planning: who prepares
for who in ['fo', 'pm', 'co', 'ex']:
    no_(f'{ROLES[who]} cannot prepare a progress release', rel(who, 'save', figures=PF, **M), 'only a planning engineer')
no_('a period in the wrong form is refused', rel('pl', 'save', figures=PF, **dict(M, period='Sep 2026')), 'must look like')
no_('a week in the wrong form is refused', rel('pl', 'save', figures=PF, **dict(M, period_type='week', period='2026-38')), 'must look like')
no_('progress above 100% is refused', rel('pl', 'save', figures=dict(PF, actual_pct=120), **M), 'between 0 and 100')
no_('actual progress is required', rel('pl', 'save', figures={'planned_pct': 50}, **M), 'actual progress')
no_('a figure that is not a number is refused', rel('pl', 'save', figures=dict(PF, spi='good'), **M), 'must be a number')
no_('an override needs a reason', rel('pl', 'save', figures=PF, overrides=[{'field': 'actual_pct', 'computed': 50, 'value': 52, 'reason': ' '}], **M), 'give a reason')
r = ok_('the planning engineer saves a monthly draft with figures, an override and comments',
        rel('pl', 'save', figures=PF, overrides=[{'field': 'actual_pct', 'label': 'Actual progress', 'computed': 50.4, 'value': 52, 'reason': 'Cable pulling measured on site 30 Sep'}], narrative=NAR, data_date='2026-09-30', **M),
        lambda r: r['status'] == 'Draft' and r['rev'] == 0 and r['figures']['actual_pct'] == 52)
RID = r['id'] if r else None
check('management does not see a draft', cnt('ex', "select count(*) from report_releases") == '0')
check('the planning engineer and the Head do', cnt('pl', "select count(*) from report_releases") == '1' and cnt('hd', "select count(*) from report_releases") == '1')
ok_('the draft can be changed', rel('pl', 'save', figures=dict(PF, actual_pct=53), narrative=NAR, data_date='2026-09-30', **M), lambda r: r['figures']['actual_pct'] == 53 and r['id'] == RID)
ok_('the planning engineer submits it', rel('pl', 'submit', id=RID), lambda r: r['status'] == 'Submitted')
no_('a submitted version cannot be edited', rel('pl', 'save', figures=PF, **M), 'cannot be edited')
no_('the planning engineer cannot approve', rel('pl', 'approve', id=RID), 'only the head')
no_('a project manager cannot approve', rel('pm', 'approve', id=RID), 'only the head')
no_('returning needs a comment', rel('hd', 'return', id=RID), 'add a comment')
ok_('the Head returns it with a comment', rel('hd', 'return', id=RID, note='Explain the SPI'), lambda r: r['status'] == 'Draft')
rel('pl', 'submit', id=RID)
ok_('the Head approves; it is released', rel('hd', 'approve', id=RID), lambda r: r['status'] == 'Released' and r['approved_by'] == U['hd'])
check('management now sees it', cnt('ex', "select count(*) from report_releases where status='Released'") == '1')
check('so do site staff (progress, not cost)', cnt('fo', "select count(*) from report_releases") == '1')
no_('a released period cannot be saved over', rel('pl', 'save', figures=PF, **M), 'use revise')
no_('a released version cannot be changed, even from the database console', psql(f"update report_releases set figures='{{}}' where id='{RID}'"), 'cannot be changed')
no_('nor deleted', psql(f"delete from report_releases where id='{RID}'"), 'cannot be deleted')
no_('a revision needs a reason', rel('pl', 'revise', **M), 'add a comment')
r2 = ok_('the planning engineer starts revision 1 with a reason', rel('pl', 'revise', note='Late site measurement', **M), lambda r: r['rev'] == 1 and r['status'] == 'Draft' and r['figures']['actual_pct'] == 53)
no_('only one revision at a time', rel('pl', 'revise', note='again', **M), 'already being prepared')
check('while it is prepared, management still sees revision 0', cnt('ex', "select string_agg(rev||status, ',') from report_releases") == '0Released')
rel('pl', 'save', id=r2['id'], figures=dict(PF, actual_pct=54), narrative=NAR, data_date='2026-09-30'); rel('pl', 'submit', id=r2['id']); rel('sa', 'approve', id=r2['id'])
check('approving revision 1 supersedes revision 0; both are kept', cnt('ex', "select string_agg(rev||status, ',' order by rev) from report_releases") == '0Superseded,1Released')
check('the history records every step', q(f"select string_agg(action, ',' order by id) from release_audit where release_id='{RID}'") == 'Prepared,Updated,Submitted for approval,Returned,Submitted for approval,Approved and released')
W = dict(project_id='P1', kind='planning', period_type='week', period='2026-W39')
no_('a project manager cannot submit a progress release', rel('pm', 'submit', **W), 'nothing is being prepared')
rel('pl', 'save', figures=PF, data_date='2026-09-27', **W)
no_('a project manager cannot submit someone else\'s draft either', rel('pm', 'submit', **W), 'only the people who prepare')
rel('pl', 'submit', **W)
ok_('a weekly release works the same way', rel('hd', 'approve', **W), lambda r: r['status'] == 'Released' and r['period_type'] == 'week')
rel('sa', 'save', figures=PF, data_date='2026-10-04', **dict(W, period='2026-W40')); rel('sa', 'submit', **dict(W, period='2026-W40'))
no_('a super admin who submitted cannot approve their own', rel('sa', 'approve', **dict(W, period='2026-W40')), 'someone else')
ok_('a second super admin can', rel('sa2', 'approve', **dict(W, period='2026-W40')), lambda r: r['status'] == 'Released')
no_('someone without access to the project cannot prepare', rel('pl', 'save', figures=PF, **dict(M, project_id='P2')), 'do not have access')

# ------------------------------------------------------------------ cost reports
C = dict(project_id='P1', kind='cost', period_type='month', period='2026-09')
CF = {'budget_rev0': 10000000, 'actual': 4200000, 'commitment': 1500000, 'ftc': 6100000, 'eac': 1}
no_('a planning engineer cannot prepare a cost report', rel('pl', 'save', figures=CF, **C), 'only a costing engineer')
no_('cost reports are monthly only', rel('co', 'save', figures=CF, **dict(C, period_type='week', period='2026-W39')), 'monthly')
no_('every input is required', rel('co', 'save', figures={'budget_rev0': 1, 'actual': 2, 'ftc': 3}, **C), 'commitments')
no_('negative amounts are refused', rel('co', 'save', figures=dict(CF, actual=-5), **C), 'cannot be negative')
r = ok_('the costing engineer saves the September cost report; the server works out budget, EAC and VAC (ignoring an EAC sent by the browser)',
        rel('co', 'save', figures=CF, data_date='2026-09-30', **C),
        lambda r: float(r['figures']['budget_current']) == 10000000 and float(r['figures']['eac']) == 10300000 and float(r['figures']['vac']) == -300000 and float(r['figures']['supplements_approved']) == 0)
CID = r['id']
ok_('the costing coordinator (a project manager with the designation) can prepare it too', rel('cc', 'save', id=CID, figures=CF, data_date='2026-09-30'), lambda r: r['prepared_by'] == U['cc'])
check('a project manager without the designation does not see the cost draft', cnt('pm', "select count(*) from report_releases where kind='cost'") == '0')
rel('co', 'submit', id=CID)
ok_('the Head approves the cost report', rel('hd', 'approve', id=CID), lambda r: r['status'] == 'Released')
check('management and project managers see the released cost report', cnt('ex', "select count(*) from report_releases where kind='cost'") == '1' and cnt('pm', "select count(*) from report_releases where kind='cost'") == '1')
for who in ['fo', 'en', 'sm']:
    check(f'{ROLES[who]} never sees cost reports, released or not', cnt(who, "select count(*) from report_releases where kind='cost'") == '0')

# ------------------------------------------------------------------ logs
VO = [{'ref_no': 'VO-001', 'kind': 'VO', 'description': 'Additional cable trench', 'submission_status': 'Submitted', 'submitted_on': '2026-08-10', 'client_status': 'Approved',
       'est_price': 450000, 'est_cost': 300000, 'expected_price': 420000, 'price_internal': 'Yes', 'cost_internal': 'Yes', 'rev0_change': 300000, 'internal_wf': 'Internally approved', 'overall_status': 'Approved'},
      {'ref_no': 'CL-001', 'kind': 'Claim', 'description': 'Prolongation, 45 days', 'submission_status': 'Submitted', 'client_status': 'Pending', 'est_price': 900000, 'expected_price': 500000},
      {'ref_no': 'X-1', 'kind': 'Change', 'description': 'bad type'}]
L = dict(kind='volog', project_id='P1', period='2026-09', file_name='vo_log_sep.xlsx', hash='a' * 64)
for who in ['fo', 'pl', 'pm']:
    no_(f'{ROLES[who]} cannot upload the change order and claim log', call(who, 'log_import', dict(L, rows=VO)), 'only a costing engineer')
no_('refused rows must be acknowledged; nothing is saved until then', call('co', 'log_import', dict(L, rows=VO)), 'acknowledge')
check('...and nothing was saved', q("select count(*) from co_log") == '0' and q("select count(*) from import_batches where kind='volog'") == '0')
r = ok_('with the refused row acknowledged, the other two are saved as one batch', call('co', 'log_import', dict(L, rows=VO, ack=True)),
        lambda r: r['accepted'] == 2 and r['rejected'][0]['ref'] == 'X-1' and float(r['total']) == 920000)
check('the batch records the acknowledged difference and who accepted it', q("select recon_status||'/'||(recon_accepted_by::text='" + U['co'] + "')||'/'||rows_rejected from import_batches where kind='volog'") == 'Accepted with difference/true/1')
ok_('loading the same file for the same month again changes nothing', call('co', 'log_import', dict(L, rows=VO, ack=True)), lambda r: r['duplicate'] is True)
no_('a file with no valid rows saves nothing', call('co', 'log_import', dict(L, hash='b' * 64, rows=[VO[2]])), 'no valid rows')
no_('a reference that appears twice is refused', call('co', 'log_import', dict(L, hash='c' * 64, rows=[VO[0], VO[0]])), 'appears twice')
check('the cost team and management read the log; site staff do not', cnt('ex', "select count(*) from co_log") == '2' and cnt('fo', "select count(*) from co_log") == '0' and cnt('sm', "select count(*) from co_log") == '0')
check('site staff do not even see the log batches', cnt('fo', "select count(*) from import_batches where kind in ('volog','supplements')") == '0')
SU = [{'supp_no': 'BS-01', 'supp_date': '2026-09-05', 'description': 'Saudization levy', 'amount': 100000, 'category': 'Saudization', 'approval_status': 'Approved'},
      {'supp_no': 'BS-02', 'description': 'VO-001 cost', 'amount': 50000, 'category': 'Change order', 'linked_ref': 'VO-001', 'approval_status': 'Approved'},
      {'supp_no': 'BS-03', 'description': 'Under-estimated cabling', 'amount': 30000, 'category': 'Under estimate', 'approval_status': 'Pending'},
      {'supp_no': 'BS-04', 'description': 'bad', 'amount': 1, 'category': 'Weather'}]
no_('a supplement with a category outside the seven is refused', call('cc', 'log_import', dict(kind='supplements', project_id='P1', period='2026-10', file_name='bs.xlsx', hash='d' * 64, rows=[SU[3]])), 'category must be one of')
ok_('the costing coordinator uploads the October supplement log (BS-04 acknowledged)', call('cc', 'log_import', dict(kind='supplements', project_id='P1', period='2026-10', file_name='bs.xlsx', hash='d' * 64, rows=SU, ack=True)), lambda r: r['accepted'] == 3)
O = dict(C, period='2026-10')
r = ok_('the October cost report adds the approved supplements (150,000) to the Rev-0 budget; the pending one is left out',
        rel('co', 'save', figures=CF, data_date='2026-10-31', **O), lambda r: float(r['figures']['supplements_approved']) == 150000 and float(r['figures']['budget_current']) == 10150000 and float(r['figures']['vac']) == -150000)
r = ok_('an August cost report is not affected by the log uploaded in October', rel('co', 'save', figures=CF, data_date='2026-08-31', **dict(C, period='2026-08')), lambda r: float(r['figures']['supplements_approved']) == 0)
ok_('the November log replaces the current log but October\'s stays', call('co', 'log_import', dict(kind='supplements', project_id='P1', period='2026-11', file_name='bs_nov.xlsx', hash='e' * 64, rows=SU[:1])), lambda r: r['accepted'] == 1)
check('both months are kept', q("select string_agg(period||':'||n, ',' order by period) from (select period, count(*) n from budget_supplements group by period) x") == '2026-10:3,2026-11:1')
no_('the logs cannot be edited', psql("update co_log set description='x'"), 'append-only')
no_('or deleted', psql("delete from budget_supplements"), 'append-only')
no_('a log for a month in the wrong form is refused', call('co', 'log_import', dict(L, period='September', hash='f' * 64, rows=VO[:1])), 'must look like')

# ------------------------------------------------------------------ rollback keeps everything
counts = q("select (select count(*) from report_releases)||'/'||(select count(*) from release_audit)||'/'||(select count(*) from co_log)||'/'||(select count(*) from budget_supplements)")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v9.sql'))
    check(f'rollback runs (run {i})', rc == 0, err)
check('rollback removes the functions that write', q("select count(*) from pg_proc where proname in ('release_act','log_import')") == '0')
check('rollback keeps every release, history entry and log row', q("select (select count(*) from report_releases)||'/'||(select count(*) from release_audit)||'/'||(select count(*) from co_log)||'/'||(select count(*) from budget_supplements)") == counts, counts)
check('released versions can still be read by management after rollback', cnt('ex', "select count(*) from report_releases where status='Released'") != '0')
rc, out, err = psql(file=find('schema-update-v9.sql'))
check('v9 can be applied again after a rollback', rc == 0, err)

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'schema-update-v9', 'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v9_results.json'), 'w'), indent=1)
sys.exit(0 if passed == len(results) else 1)
