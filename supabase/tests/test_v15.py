#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v15 (internal weightage by phase, updated schedules, client reporting,
validation of differences from the updated schedule). Earlier: v14 (progress release dashboard fields, regional approval, project manager review step).
Original v9 description: (released reporting): progress releases and monthly cost reports
(prepare, submit, approve by the Head, no self-approval, return, revise, frozen once released, who can read what),
server-side cost formulas with approved budget supplements, and the change order / claim and budget supplement
log uploads (all-or-nothing, acknowledgement, duplicates, history). Usage: python3 test_v15.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v15_test'
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
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 15)]:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin(f"insert into pcc_designations (user_id, designation) values ('{U['hd']}','head')")
admin("insert into regions values ('R1','Western',null), ('R2','Central',null); insert into projects (id, name, short, region, value_m) values ('P1','One','P1','R1',100), ('P2','Two','P2','R2',50);")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['hd', 'pl', 'co', 'pm', 'fo', 'rp']) + f", ('{U['pl2']}','P2'), ('{U['hd']}','P2'), ('{U['rp2']}','P2')")
admin(f"insert into release_approvers (region_id, user_id) values ('R1','{U['rp']}')")
M0 = dict(project_id='P1', kind='planning', period_type='month', period='2026-07')
rel('pl', 'save', figures={'actual_pct': 30, 'planned_pct': 32}, **M0); rel('pl', 'submit', **M0); rel('rp', 'approve', **M0)
before = q("select figures::text from report_releases where period='2026-07'")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v15.sql'))
    check(f'v15 loads (run {i})', rc == 0, err)
SETUP = "select (select count(*) from pg_proc where proname in ('phase_setup_save','schedule_update_commit','pt_rel_sched','pt_sched_summary')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('project_phase_setup','schedule_updates','schedule_update_rows'))"
check('the setup check counts 7', q(SETUP) == '7', q(SETUP))
check('a report released before v15 is untouched', q("select figures::text from report_releases where period='2026-07'") == before)

# ------------------------------------------------------------------ internal weightage by phase
W = {'GEN': 5, 'DES': 15, 'MAT': 30, 'CON': 40, 'INS': 5, 'TC': 3, 'CLO': 2}
MAP = {'Design': 'DES', 'Materials': 'MAT', 'Construction': 'CON'}
no_('the weightage must add up to 100%', call('pl', 'phase_setup_save', {'project_id': 'P1', 'weights': dict(W, CLO=1)}), 'add up to 100')
no_('an unknown phase is refused', call('pl', 'phase_setup_save', {'project_id': 'P1', 'weights': dict(W, XYZ=0)}), 'unknown phase')
no_('a negative weightage is refused', call('pl', 'phase_setup_save', {'project_id': 'P1', 'weights': dict(W, GEN=-5, DES=25)}), 'between 0 and 100')
no_('a mapping to an unknown phase is refused', call('pl', 'phase_setup_save', {'project_id': 'P1', 'weights': W, 'wbs_map': {'Design': 'ZZ'}}), 'unknown phase')
no_('a costing engineer cannot set it', call('co', 'phase_setup_save', {'project_id': 'P1', 'weights': W}), 'only a planning engineer')
no_('a project manager cannot set it', call('pm', 'phase_setup_save', {'project_id': 'P1', 'weights': W}), 'only a planning engineer')
no_('a planning engineer of another project cannot', call('pl2', 'phase_setup_save', {'project_id': 'P1', 'weights': W}), 'access')
ok_('the planning engineer sets the weightage and maps the main WBS branches', call('pl', 'phase_setup_save', {'project_id': 'P1', 'weights': W, 'wbs_map': MAP}),
    lambda r: r['weights']['CON'] == 40 and r['wbs_map']['Design'] == 'DES')
check('the change is kept in the history', q("select count(*) from phase_setup_audit where project_id='P1'") == '1')
rc, out, err = psql("update phase_setup_audit set note='x'")
check('the history cannot be changed, even from the database console', rc != 0, err)

# ------------------------------------------------------------------ an updated schedule
DD = '2026-08-31'
def rows(extra=None):
    R = [dict(id='D1', name='Design part 1', wbs='Design', w=10, bs='2026-07-01', bf='2026-08-31', pct=100, af='2026-08-30'),
         dict(id='D2', name='Design part 2', wbs='Design', w=10, bs='2026-08-01', bf='2026-09-30', pct=40, ef='2026-10-05'),
         dict(id='M1', name='Cable supply', wbs='Materials', w=30, bs='2026-08-01', bf='2026-10-31', pct=20),
         dict(id='C1', name='Foundations', wbs='Construction', w=50, bs='2026-09-01', bf='2026-12-31', pct=0),
         dict(id='MS1', name='TCC - Taking over certificate', wbs='Construction', w=0, bs='2026-12-31', bf='2026-12-31', pct=0, ms=True, ef='2027-01-15'),
         dict(id='MS2', name='PAC issued', wbs='Construction', w=0, bs='2027-03-31', bf='2027-03-31', pct=0, ms=True)]
    return R + (extra or [])
from datetime import date
def frac(bs, bf, dd=date(2026, 8, 31)):
    bs, bf = date.fromisoformat(bs), date.fromisoformat(bf)
    return 1 if dd >= bf else 0 if dd <= bs else (dd - bs).days / (bf - bs).days
admin("insert into activities (id, project_id, name, bs, bf) values ('C1','P1','Foundations','2026-08-01','2026-12-31')")
cp = (10 * 1 + 10 * frac('2026-08-01', '2026-09-30') + 30 * frac('2026-08-01', '2026-10-31') + 50 * frac('2026-08-01', '2026-12-31')) / 100 * 100
ca = (10 * 1 + 10 * .4 + 30 * .2) / 100 * 100
ph = {'DES': ((1 + frac('2026-08-01', '2026-09-30')) / 2, .7), 'MAT': (frac('2026-08-01', '2026-10-31'), .2), 'CON': (frac('2026-08-01', '2026-12-31'), 0)}
ip = sum(W[k] * v[0] for k, v in ph.items()) / 85 * 100; ia = sum(W[k] * v[1] for k, v in ph.items()) / 85 * 100
UP = dict(project_id='P1', data_date=DD, weightage='client', file_name='P1_update_Aug.xer', file_hash='h1', weight_basis='Price weight')
no_('a costing engineer cannot upload a schedule', call('co', 'schedule_update_commit', dict(UP, rows=rows())), 'only a planning engineer')
no_('the tick box must say client or internal', call('pl', 'schedule_update_commit', dict(UP, weightage='other', rows=rows())), 'client or internal')
no_('a data date is needed', call('pl', 'schedule_update_commit', dict(UP, data_date=None, rows=rows())), 'data date')
no_('% complete over 100 is refused', call('pl', 'schedule_update_commit', dict(UP, rows=rows([dict(id='X1', wbs='Design', w=1, bs=DD, bf=DD, pct=120)]))), 'between 0 and 100')
no_('a weighted activity without dates is refused', call('pl', 'schedule_update_commit', dict(UP, rows=rows([dict(id='X2', wbs='Design', w=1, pct=0)]))), 'planned start and finish')
no_('a weighted activity outside the mapped WBS branches is refused', call('pl', 'schedule_update_commit', dict(UP, rows=rows([dict(id='X3', wbs='Testing', w=5, bs=DD, bf=DD, pct=0)]))), 'no phase')
check('...and nothing was kept from refused uploads', q("select count(*) from schedule_updates")+'/'+q("select count(*) from schedule_update_rows") == '0/0')
u1 = ok_('the planning engineer uploads the updated schedule (client weightage)', call('pl', 'schedule_update_commit', dict(UP, rows=rows())), lambda r: r['summary']['n'] == 6)
S = u1['summary'] if u1 else {}
check('client planned % = sum(weight x planned) / sum(weight), using the ProTrackAI baseline dates where the activity matches', abs(float(S.get('client_plan') or 0) - round(cp, 2)) < 0.006, (S.get('client_plan'), round(cp, 2)))
check('client actual % = sum(weight x % complete) / sum(weight)', abs(float(S.get('client_act') or 0) - round(ca, 2)) < 0.006, (S.get('client_act'), ca))
check('internal planned and actual % = phase weights x phase %, over the phases in the schedule', abs(float(S.get('int_plan') or 0) - round(ip, 2)) < 0.006 and abs(float(S.get('int_act') or 0) - round(ia, 2)) < 0.006, (S.get('int_plan'), round(ip, 2), S.get('int_act'), round(ia, 2)))
check('phases with weightage but no activities are listed', S.get('missing_phases') == ['GEN', 'INS', 'TC', 'CLO'], S.get('missing_phases'))
pd = {x['phase']: x for x in S.get('phases', [])}
check('per phase: design planned 75.4% (rounded) actual 70%', abs(float(pd['DES']['act_pct']) - 70) < 0.01 and abs(float(pd['DES']['plan_pct']) - round(ph['DES'][0] * 100, 2)) < 0.01, pd.get('DES'))
check('TCC and PAC dates come from the milestones (forecast where not achieved)', S.get('tcc_date') == '2027-01-15' and S.get('pac_date') == '2027-03-31' and S.get('tcc_actual') is False, (S.get('tcc_date'), S.get('pac_date')))
check('the look-ahead lists the open activities of the next 30 days', [x['id'] for x in S.get('lookahead', [])] == ['C1', 'D2', 'M1'], [x['id'] for x in S.get('lookahead', [])])
check('the planned dates of a matched activity are the ProTrackAI baseline', q("select bs from schedule_update_rows where act_id='C1'") == '2026-08-01')
r = call('pl', 'schedule_update_commit', dict(UP, rows=rows()))
check('the same file again changes nothing', r[0] == 0 and r[1].get('duplicate') is True and q("select count(*) from schedule_updates") == '1', r)
for sql, what in (("update schedule_updates set data_date='2026-01-01'", 'an update'), ("delete from schedule_update_rows", 'its activities'), ("truncate schedule_updates cascade", 'the register')):
    rc, out, err = psql(sql); check(f'{what} cannot be changed or deleted, even from the database console', rc != 0, err)
check('the foreman of the project can read it (no money in it)', cnt('fo', "select count(*) from schedule_updates") == '1')
check('a planning engineer of another project cannot', cnt('pl2', "select count(*) from schedule_updates") == '0' and cnt('pl2', "select count(*) from schedule_update_rows") == '0')
no_('changing the weightage after a reported update needs a reason', call('pl', 'phase_setup_save', {'project_id': 'P1', 'weights': dict(W, CON=35, GEN=10), 'wbs_map': MAP}), 'reason')
ok_('...with a reason it is saved', call('pl', 'phase_setup_save', {'project_id': 'P1', 'weights': dict(W, CON=35, GEN=10), 'wbs_map': MAP, 'note': 'Agreed with management, Sept'}))
check('...the history keeps before, after and the reason', q("select (before->'weights'->>'CON')||'/'||(after->'weights'->>'CON')||'/'||note from phase_setup_audit order by id desc limit 1") == '40/35/Agreed with management, Sept')
check('...and the update already loaded keeps the weights it was worked out with', q("select weights->>'CON' from schedule_updates") == '40')
call('pl', 'phase_setup_save', {'project_id': 'P1', 'weights': W, 'wbs_map': MAP, 'note': 'Back to the agreed weightage'})

# ------------------------------------------------------------------ internal report against the schedule
I1 = dict(project_id='P1', kind='planning', period_type='month', period='2026-08')
r = ok_('an internal report matching the schedule has no differences', rel('pl', 'save', figures={'planned_pct': round(ip, 2), 'actual_pct': round(ia, 2), 'tcc_ext_fc_date': '2027-01-15'}, **I1),
        lambda r: r['figures']['sched_diff_n'] == 0 and r['figures']['sched_update_text'] == u1['id'])
r = ok_('a manual change of progress and the TCC forecast is recorded as a difference', rel('pl', 'save', figures={'planned_pct': round(ip, 2), 'actual_pct': 25, 'tcc_ext_fc_date': '2027-02-01', 'sched_diff_n': 0}, **I1),
        lambda r: r['figures']['sched_diff_n'] == 2 and 'actual 25' in r['figures']['sched_diff_text'] and 'TCC forecast 2027-02-01' in r['figures']['sched_diff_text'])
check('the app cannot hide a difference (the server writes the schedule figures)', r and r['figures']['sched_diff_n'] == 2)
rel('pl', 'submit', **I1)
check('the submission history notes the difference', q("select count(*) from release_audit where action='Submitted for approval' and detail ? 'differs_from_schedule'") == '1')
check('the regional planning section manager can read the submitted report', cnt('rp', "select count(*) from report_releases where period='2026-08' and status='Submitted'") == '1')
no_('approval without validating the differences is refused', rel('rp', 'approve', **I1), 'validate the differences')
no_('validation needs a note', rel('rp', 'approve', validated=True, **I1), 'validate the differences')
ok_('the section manager validates with a note and approves', rel('rp', 'approve', validated=True, validation_note='Site measurement agreed; P6 to be updated next week', **I1),
    lambda r: r['status'] == 'Released' and r['sched_validated_by'] == U['rp'] and r['sched_validation_note'].startswith('Site measurement'))
check('the validation is in the history', q("select count(*) from release_audit where action='Differences from the updated schedule validated'") == '1')
rc, out, err = psql("update report_releases set sched_validation_note='changed' where period='2026-08' and kind='planning'")
check('the validation of a released report cannot be changed', rc != 0, err)
I2 = dict(project_id='P1', kind='planning', period_type='week', period='2026-W36')
rel('pl', 'save', figures={'planned_pct': round(ip, 2), 'actual_pct': round(ia, 2)}, **I2); rel('pl', 'submit', **I2)
ok_('a report matching the schedule is approved without validation', rel('rp', 'approve', **I2), lambda r: r['status'] == 'Released' and r['sched_validated_by'] is None)
I0 = dict(project_id='P1', kind='planning', period_type='week', period='2026-W30')
ok_('a report for a period before any updated schedule has no schedule figures', rel('pl', 'save', figures={'actual_pct': 10}, **I0), lambda r: 'sched_diff_n' not in r['figures'])

# ------------------------------------------------------------------ client reports
C1 = dict(project_id='P1', kind='client', period_type='month', period='2026-08')
no_('a costing engineer cannot prepare a client report', rel('co', 'save', figures={'act_pct': 20}, **C1), 'only a planning engineer')
no_('client actual % over 100 is refused', rel('pl', 'save', figures={'act_pct': 120}, **C1), 'between 0 and 100')
no_('client actual progress is required', rel('pl', 'save', figures={'plan_pct': 20}, **C1), 'actual progress')
r = ok_('the planning engineer prepares the client report from the schedule (client weightage)', rel('pl', 'save', figures={'plan_pct': round(cp, 2), 'act_pct': round(ca, 2), 'tcc_fc_date': '2027-01-15', 'phases': [{'phase': 'X'}]},
        narrative={'summary': 'Design progressing'}, **C1),
        lambda r: r['figures']['sched_diff_n'] == 0 and len(r['figures']['phases']) == 3 and r['figures']['phases'][0]['phase'] == 'DES' and len(r['figures']['milestones']) == 2)
check('client variance and SPI are worked out', r and abs(float(r['figures']['var_pct']) - round(round(ca, 2) - round(cp, 2), 2)) < 0.006 and abs(float(r['figures']['spi']) - round(round(ca, 2) / round(cp, 2), 3)) < 0.0006, r and (r['figures']['var_pct'], r['figures']['spi']))
check('the client report carries no internal weightage figures', r and not any(k in r['figures'] for k in ('int_plan', 'planned_pct', 'actual_pct')) and r['figures']['sched_basis_text'] == 'client weightage')
rel('pl', 'submit', **C1)
check('the section manager can read the submitted client report', cnt('rp', "select count(*) from report_releases where kind='client' and status='Submitted'") == '1')
no_('a project manager cannot approve a client report', rel('pm', 'approve', **C1), 'regional planning section manager')
no_('the preparer cannot approve it', rel('pl', 'approve', **C1), 'only the head')
ok_('the regional planning section manager approves the client report', rel('rp', 'approve', **C1), lambda r: r['status'] == 'Released')
check('the released client report is visible to the project team', cnt('pm', "select count(*) from report_releases where kind='client' and status='Released'") == '1')
UPI = dict(project_id='P1', data_date='2026-09-07', weightage='internal', file_name='P1_internal.xer', file_hash='h2')
u2 = ok_('a schedule loaded with internal weightage: internal % is the schedule\'s own; no client %', call('pl', 'schedule_update_commit', dict(UPI, rows=rows())),
         lambda r: r['summary']['int_basis'].startswith('schedule loaded with internal') and r['summary']['client_plan'] is None and abs(float(r['summary']['int_act']) - round(ca, 2)) < 0.006)
C2 = dict(project_id='P1', kind='client', period_type='month', period='2026-09')
ok_('the next client report still uses the latest client-weighted schedule', rel('pl', 'save', figures={'plan_pct': round(cp, 2), 'act_pct': round(ca, 2)}, **C2), lambda r: r['figures']['sched_update_text'] == u1['id'])
ok_('the next internal report uses the newer internal-weighted schedule', rel('pl', 'save', figures={'actual_pct': round(ca, 2)}, project_id='P1', kind='planning', period_type='month', period='2026-09'),
    lambda r: r['figures']['sched_update_text'] == u2['id'] and r['figures']['sched_diff_n'] == 0)
CC = dict(project_id='P1', kind='cost', period_type='month', period='2026-09')
ok_('cost reports are unchanged', rel('co', 'save', figures={'budget_rev0': 10, 'actual': 4, 'commitment': 1, 'ftc': 5}, **CC), lambda r: r['figures']['vac'] == 1 and r['figures']['eac'] == 9 and 'sched_diff_n' not in r['figures'])

# ------------------------------------------------------------------ rollback keeps everything
n = q("select (select count(*) from schedule_updates)||'/'||(select count(*) from schedule_update_rows)||'/'||(select count(*) from report_releases where kind='client')||'/'||(select count(sched_validated_by) from report_releases)")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v15.sql'))
    check(f'rollback runs (run {i})', rc == 0, err)
check('rollback stops weightage changes and schedule uploads', q("select count(*) from pg_proc where proname in ('phase_setup_save','schedule_update_commit','pt_rel_sched','pt_rel_client_calc')") == '0')
check('rollback keeps every updated schedule, client report and validation', q("select (select count(*) from schedule_updates)||'/'||(select count(*) from schedule_update_rows)||'/'||(select count(*) from report_releases where kind='client')||'/'||(select count(sched_validated_by) from report_releases)") == n, n)
no_('after rollback, client reports are no longer prepared', rel('pl', 'save', figures={'act_pct': 20}, project_id='P1', kind='client', period_type='month', period='2026-10'), 'unknown release kind')
M9 = dict(project_id='P1', kind='planning', period_type='month', period='2026-10')
rel('pl', 'save', figures={'actual_pct': 50}, **M9); rel('pl', 'submit', **M9)
ok_('after rollback the section manager approves as in v3.5', rel('rp', 'approve', **M9), lambda r: r['status'] == 'Released')
check('the released client report stays readable', cnt('pm', "select count(*) from report_releases where kind='client'") == '1')
rc, out, err = psql(file=find('schema-update-v15.sql'))
check('v15 can be applied again after a rollback', rc == 0, err)
check('...the weightage and updates were kept', q("select weights->>'CON' from project_phase_setup") == '40' and q("select count(*) from schedule_updates") == '2')

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'schema-update-v15', 'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v15_results.json'), 'w'), indent=1)
