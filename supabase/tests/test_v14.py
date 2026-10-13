#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v14 (progress release dashboard fields, regional approval, project manager review step).
Original v9 description: (released reporting): progress releases and monthly cost reports
(prepare, submit, approve by the Head, no self-approval, return, revise, frozen once released, who can read what),
server-side cost formulas with approved budget supplements, and the change order / claim and budget supplement
log uploads (all-or-nothing, acknowledgement, duplicates, history). Usage: python3 test_v14.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v14_test'
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
ROLES = {'sa': 'sa', 'hd': 'pm', 'pl': 'plan', 'pl2': 'plan', 'co': 'costing', 'pm': 'pm', 'ex': 'exec', 'fo': 'foreman', 'nx': 'plan', 'rp': 'plan', 'rp2': 'plan', 'pm2': 'pm'}
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
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 14)]:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin(f"insert into pcc_designations (user_id, designation) values ('{U['hd']}','head')")
admin("insert into regions values ('R1','Western',null), ('R2','Central',null); insert into projects (id, name, short, region, value_m) values ('P1','One','P1','R1',100), ('P2','Two','P2','R2',50);")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['hd', 'pl', 'co', 'pm', 'fo', 'rp']) + f", ('{U['pl2']}','P2'), ('{U['hd']}','P2'), ('{U['rp2']}','P2')")
M0 = dict(project_id='P1', kind='planning', period_type='month', period='2026-07')
rel('pl', 'save', figures={'actual_pct': 30, 'planned_pct': 32}, **M0); rel('pl', 'submit', **M0); rel('hd', 'approve', **M0)
before = q("select figures::text from report_releases where period='2026-07'")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v14.sql'))
    check(f'v14 loads (run {i})', rc == 0, err)
check('the setup check counts 5', q("select (select count(*) from pg_proc where proname in ('release_setup','pt_rel_approver','pt_rel_plan_calc','pt_rel_decider')) + (select count(*) from release_settings)") == '5')
check('a release approved before v14 is untouched', q("select figures::text from report_releases where period='2026-07'") == before)
check('the project manager review step starts switched off', q("select v::text from release_settings where k='pm_review'") == 'false')

# ------------------------------------------------------------------ dashboard fields, checked and worked out
DASH = {'actual_pct': 40, 'planned_pct': 45, 'sub_project_text': 'PE-336-A', 'commence_date': '2025-01-01', 'site_handover_date': '2025-02-01',
        'tcc_orig_date': '2026-05-16', 'pac_orig_date': '2026-08-16', 'fac_orig_date': '2027-08-16', 'tcc_int_target_date': '2026-04-30',
        'tcc_rev_date': '2026-06-30', 'tcc_int_fc_date': '2026-06-15', 'tcc_ext_fc_date': '2026-07-20', 'pac_ext_fc_date': '2026-08-10', 'fac_ext_fc_date': '2027-09-15',
        'ext_plan_amt': 50000000, 'ext_act_amt': 42000000, 'ext_plan_pct': 50, 'ext_act_pct': 42,
        'mp_dir_plan': 100, 'mp_dir_act': 90, 'mp_ind_plan': 20, 'mp_ind_act': 25, 'mp_sub_plan': 80, 'mp_sub_act': 60,
        'energ_status_text': 'Under Testing', 'energ_date': '2026-07-01', 'energ_remarks_text': 'Awaiting SEC witness', 'tcc_delay_days': 999}
M1 = dict(project_id='P1', kind='planning', period_type='month', period='2026-09')
r = ok_('the planning engineer saves a progress release with the dashboard fields', rel('pl', 'save', figures=DASH, narrative={'summary': 's', 'issues': 'i', 'recovery': 'r', 'next': 'n'}, **M1), lambda r: True)
F = r['figures'] if r else {}
check('TCC delay = external forecast − approved revised TCC (20 days; what the browser sent is ignored)', F.get('tcc_delay_days') == 20, F.get('tcc_delay_days'))
check('PAC delay uses the original contractual date when there is no revised one (−6 days)', F.get('pac_delay_days') == -6, F.get('pac_delay_days'))
check('FAC delay (30 days) and the internal TCC delay against the internal target (46 days)', F.get('fac_delay_days') == 30 and F.get('tcc_int_delay_days') == 46, (F.get('fac_delay_days'), F.get('tcc_int_delay_days')))
check('external variance = actual − planned (−8) and external SPI = actual ÷ planned (0.84)', float(F.get('ext_var_pct')) == -8 and float(F.get('ext_spi')) == 0.84, (F.get('ext_var_pct'), F.get('ext_spi')))
check('internal amounts = contract value × internal % (45M planned, 40M actual), internal variance −5', float(F.get('int_plan_amt')) == 45000000 and float(F.get('int_act_amt')) == 40000000 and float(F.get('int_var_pct')) == -5)
check('manpower totals 200 / 175, variance −25, utilization 87.5%', float(F.get('mp_tot_plan')) == 200 and float(F.get('mp_tot_act')) == 175 and float(F.get('mp_var')) == -25 and float(F.get('mp_util_pct')) == 87.5)
check('text and dates are kept as given', F.get('sub_project_text') == 'PE-336-A' and F.get('energ_status_text') == 'Under Testing' and F.get('tcc_rev_date') == '2026-06-30')
for name, extra, msg in [('external % over 100', {'ext_act_pct': 120}, 'between 0 and 100'), ('negative manpower', {'mp_sub_act': -1}, 'cannot be negative'),
                         ('an unknown energization status', {'energ_status_text': 'Live'}, 'energization status'), ('Energized without its date', {'energ_status_text': 'Energized', 'energ_date': None}, 'energization date'),
                         ('a date that is not a date', {'tcc_ext_fc_date': '2026-13-01'}, 'not a valid date'), ('remarks over 300 characters', {'energ_remarks_text': 'x' * 301}, 'too long')]:
    no_(f'refused: {name}', rel('pl', 'save', figures=dict(DASH, **extra), **M1), msg)

# ------------------------------------------------------------------ regional approvers
no_('only a super admin names the regional planning section managers', call('hd', 'release_setup', {'action': 'approver_add', 'region_id': 'R1', 'user_id': U['rp']}), 'only a super admin')
ok_('the super admin names RP for the Western region and RP2 for Central', call('sa', 'release_setup', {'action': 'approver_add', 'region_id': 'R1', 'user_id': U['rp']}))
call('sa', 'release_setup', {'action': 'approver_add', 'region_id': 'R2', 'user_id': U['rp2']})
no_('a foreman cannot be named', call('sa', 'release_setup', {'action': 'approver_add', 'region_id': 'R1', 'user_id': U['fo']}), 'planning section manager must be')
check('everyone signed in can see who approves where', cnt('pl', "select count(*) from release_approvers") == '2')
rel('pl', 'submit', **M1)
check('the regional planning section manager sees the submitted release', cnt('rp', "select count(*) from report_releases where period='2026-09' and status='Submitted'") == '1')
check('...the manager of another region does not', cnt('rp2', "select count(*) from report_releases where period='2026-09'") == '0')
no_('the project manager cannot review while the step is off', rel('pm', 'review', **M1), 'not switched on')
no_('a project manager cannot approve', rel('pm', 'approve', **M1), 'regional planning section manager')
no_('the manager of another region cannot approve (no access to the project)', rel('rp2', 'approve', **M1), 'access')
ok_('the regional planning section manager approves, with management remarks', rel('rp', 'approve', mgmt='Recover the cable laying in October', **M1), lambda r: r['status'] == 'Released')
check('approval fills reviewed and approved (by the same manager, no PM step) and keeps the remarks',
      q(f"select (approved_by::text='{U['rp']}')::text||'/'||(reviewed_by::text='{U['rp']}')::text||'/'||(narrative->>'mgmt') from report_releases where period='2026-09' and status='Released'") == 'true/true/Recover the cable laying in October')
no_('released, the review details cannot be changed even from the database console', psql("update report_releases set reviewed_by=null where period='2026-09'"), 'cannot be changed')

# ------------------------------------------------------------------ the project manager review step
no_('only a super admin switches the review step', call('hd', 'release_setup', {'action': 'pm_review', 'on': True}), 'only a super admin')
ok_('the super admin switches the project manager review on', call('sa', 'release_setup', {'action': 'pm_review', 'on': True}), lambda r: r['pm_review'] is True)
W = dict(project_id='P1', kind='planning', period_type='week', period='2026-W40')
rel('pl', 'save', figures={'actual_pct': 41}, **W); rel('pl', 'submit', **W)
no_('the regional manager cannot approve before the project manager reviews', rel('rp', 'approve', **W), 'must review')
check('the project manager sees the submitted release', cnt('pm', "select count(*) from report_releases where period='2026-W40'") == '1')
no_('a project manager without access to the project cannot review', rel('pm2', 'review', **W), 'access')
ok_('the project manager reviews', rel('pm', 'review', note='Checked against site', **W), lambda r: r['reviewed_by'] == U['pm'])
no_('...only once', rel('pm', 'review', **W), 'already reviewed')
no_('a reviewed release cannot be returned by the project manager any more', rel('pm', 'return', note='x', **W), 'regional planning section manager')
ok_('the regional manager approves; the review stays the project manager\'s', rel('rp', 'approve', **W), lambda r: r['status'] == 'Released' and r['reviewed_by'] == U['pm'])
W2 = dict(project_id='P1', kind='planning', period_type='week', period='2026-W41')
rel('pl', 'save', figures={'actual_pct': 42}, **W2); rel('pl', 'submit', **W2)
no_('rejecting needs a comment', rel('pm', 'return', **W2), 'comment')
ok_('the project manager rejects (returns) it with a comment', rel('pm', 'return', note='Recheck the manpower', **W2), lambda r: r['status'] == 'Draft' and r['reviewed_by'] is None)
check('history records the review and the rejection', q("select count(*) from release_audit where action in ('Reviewed by the project manager','Returned')") == '2')
ok_('the Head still approves progress releases', (rel('pl', 'submit', **W2), rel('pm', 'review', **W2), rel('hd', 'approve', **W2))[2], lambda r: r['status'] == 'Released')
C = dict(project_id='P1', kind='cost', period_type='month', period='2026-09')
rel('co', 'save', figures={'budget_rev0': 10, 'actual': 4, 'commitment': 1, 'ftc': 5}, **C); rel('co', 'submit', **C)
no_('cost reports are unchanged: the regional planning manager cannot approve them', rel('rp', 'approve', **C), 'only the head')
ok_('...the Head approves them without any review step', rel('hd', 'approve', **C), lambda r: r['status'] == 'Released')
call('sa', 'release_setup', {'action': 'pm_review', 'on': False})
ok_('switched off again, the regional manager approves directly', (rel('pl', 'save', figures={'actual_pct': 43}, project_id='P1', kind='planning', period_type='week', period='2026-W42'), rel('pl', 'submit', project_id='P1', kind='planning', period_type='week', period='2026-W42'), rel('rp', 'approve', project_id='P1', kind='planning', period_type='week', period='2026-W42'))[2], lambda r: r['status'] == 'Released')
ok_('approvers can be removed', call('sa', 'release_setup', {'action': 'approver_remove', 'region_id': 'R1', 'user_id': U['rp']}))
check('...and then no longer approve', q(f"select pt_rel_approver('{U['rp']}','P1')") == 'f')

# ------------------------------------------------------------------ rollback keeps everything
n = q("select count(*)||'/'||count(reviewed_by)||'/'||count(*) filter (where figures ? 'tcc_delay_days') from report_releases")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v14.sql'))
    check(f'rollback runs (run {i})', rc == 0, err)
check('rollback removes the new functions', q("select count(*) from pg_proc where proname in ('release_setup','pt_rel_approver','pt_rel_plan_calc','pt_rel_decider')") == '0')
check('rollback keeps every release with its dashboard fields and review details', q("select count(*)||'/'||count(reviewed_by)||'/'||count(*) filter (where figures ? 'tcc_delay_days') from report_releases") == n, n)
M9 = dict(project_id='P1', kind='planning', period_type='month', period='2026-10')
rel('pl', 'save', figures={'actual_pct': 50}, **M9); rel('pl', 'submit', **M9)
ok_('after rollback the Head approves as in v3.4', rel('hd', 'approve', **M9), lambda r: r['status'] == 'Released')
rc, out, err = psql(file=find('schema-update-v14.sql'))
check('v14 can be applied again after a rollback', rc == 0, err)
check('...the approvers and settings were kept', q("select count(*) from release_approvers") == '1' and q("select v::text from release_settings") == 'false')

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'schema-update-v14', 'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v14_results.json'), 'w'), indent=1)
sys.exit(0 if passed == len(results) else 1)
