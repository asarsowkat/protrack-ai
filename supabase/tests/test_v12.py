#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v12 (cost report by WBS head, company format); based on the v10 harness.
Original v9 description: (released reporting): progress releases and monthly cost reports
(prepare, submit, approve by the Head, no self-approval, return, revise, frozen once released, who can read what),
server-side cost formulas with approved budget supplements, and the change order / claim and budget supplement
log uploads (all-or-nothing, acknowledgement, duplicates, history). Usage: python3 test_v12.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v12_test'
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
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 12)]:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin(f"insert into pcc_designations (user_id, designation) values ('{U['hd']}','head')")
admin("insert into regions values ('R1','Western',null); insert into projects (id, name, short, region) values ('P1','One','P1','R1'), ('P2','Two','P2','R1');")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['hd', 'pl', 'co', 'pm', 'fo']) + f", ('{U['pl2']}','P2'), ('{U['hd']}','P2')")
# a totals-only cost report released before v12 must stay as it is
M0 = dict(project_id='P1', kind='cost', period_type='month', period='2026-06')
rel('co', 'save', figures={'budget_rev0': 1000, 'actual': 300, 'commitment': 100, 'ftc': 650}, **M0); rel('co', 'submit', **M0); rel('hd', 'approve', **M0)
before = q("select figures::text from report_releases where period='2026-06'")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v12.sql'))
    check(f'v12 loads (run {i})', rc == 0, err)
check('the setup check counts 2', q("select count(*) from pg_proc where proname in ('release_act','pt_cost_wbs')") == '2')
check('a cost report released before v12 is untouched', q("select figures::text from report_releases where period='2026-06'") == before)

# ------------------------------------------------------------------ totals-only still works
M1 = dict(project_id='P1', kind='cost', period_type='month', period='2026-07')
ok_('a cost report by totals only still works, with the same formulas', rel('co', 'save', figures={'budget_rev0': 1000, 'actual': 400, 'commitment': 100, 'ftc': 580}, **M1),
    lambda r: float(r['figures']['eac']) == 980 and float(r['figures']['vac']) == 20 and 'wbs' not in r['figures'])
rel('co', 'submit', **M1); rel('hd', 'approve', **M1)

# ------------------------------------------------------------------ by WBS head
def L(code, name, tender, rev0, rrev, prev, bud, act, com, etc, just=None):
    return {'code': code, 'name': name, 'tender': tender, 'rev0': rev0, 'rev0_rev': rrev, 'prev': prev, 'budget': bud, 'actual': act, 'commitment': com, 'etc': etc, 'justification': just}
W1 = [L('sm', 'Site Management', 2000, 2000, 2000, 2100, 2500, 2100, 20, 420, 'More site staff during demobilisation'),
      L('MTRL.ELC', 'Electrical Material', 18000, 18000, 18000, 16000, 15000, 13000, 1500, 300, 'Savings on cable'),
      L('CONT', 'Contingency', 6000, 6000, 6000, 500, 400, 0, 0, 100)]
W1[0]['eac'] = 1; W1[0]['var'] = 999   # sent by a browser; must be ignored
HDR = {'planned_poc': 29.3, 'actual_poc': 16.87, 'planned_tcc_date': '2026-05-16', 'forecast_tcc_date': '2026-05-16', 'contract_value': 30000,
       'tender_month_text': '2024-12', 'rev0_month_text': '2025-05', 'rev0_rev_month_text': '2025-05', 'overall_note_text': 'Expected potential savings'}
M2 = dict(project_id='P1', kind='cost', period_type='month', period='2026-08')
r = ok_('the costing engineer saves a cost report by WBS head', rel('co', 'save', figures=dict(HDR, wbs=W1), **M2), lambda r: len(r['figures']['wbs']) == 3)
w = {x['code']: x for x in r['figures']['wbs']} if r else {}
F = r['figures'] if r else {}
check('codes are kept in capitals', set(w) == {'SM', 'MTRL.ELC', 'CONT'}, list(w))
check('per line: balance G = D − E − F', w and float(w['SM']['balance']) == 380 and float(w['MTRL.ELC']['balance']) == 500)
check('per line: EAC I = E + F + H (what the browser sent is ignored)', w and float(w['SM']['eac']) == 2540 and float(w['MTRL.ELC']['eac']) == 14800)
check('per line: supplement (−) / saving (+) J = D − I', w and float(w['SM']['var']) == -40 and float(w['MTRL.ELC']['var']) == 200 and float(w['CONT']['var']) == 300)
check('the previous version of a project\'s first WBS report is what was entered (the earlier reports had no WBS lines)', w and float(w['SM']['prev']) == 2100 and 'prev_period_text' not in F)
check('totals: current budget = Σ D, actual, commitment, ETC, EAC, VAC',
      F and float(F['budget_current']) == 17900 and float(F['actual']) == 15100 and float(F['commitment']) == 1520 and float(F['etc']) == 820 and float(F['eac']) == 17440 and float(F['vac']) == 460)
check('totals keep their meaning for the rest of the app: forecast to complete = F + H, EAC = actual + forecast to complete', F and float(F['ftc']) == 2340 and float(F['eac']) == float(F['actual']) + float(F['ftc']))
check('totals of tender, Rev-0, revised Rev-0 and previous version', F and float(F['tender_total']) == 26000 and float(F['budget_rev0']) == 26000 and float(F['rev0_rev_total']) == 26000 and float(F['prev_total']) == 18600)
check('header figures are kept: POC, TCC dates, contract value, overall note', F and float(F['planned_poc']) == 29.3 and F['forecast_tcc_date'] == '2026-05-16' and float(F['contract_value']) == 30000 and F['overall_note_text'] == 'Expected potential savings')
check('justifications are kept per line (an empty one is stored as none)', w and w['SM']['justification'] == 'More site staff during demobilisation' and w['CONT']['justification'] is None)
for name, bad, msg in [('a WBS code twice', [L('SM', 'a', 0, 0, 0, 0, 1, 0, 0, 0), L('sm', 'b', 0, 0, 0, 0, 1, 0, 0, 0)], 'twice'),
                       ('a negative amount', [L('SM', 'a', 0, 0, 0, 0, 1, -5, 0, 0)], 'cannot be negative'),
                       ('an amount that is not a number', [L('SM', 'a', 0, 0, 0, 0, 'lots', 0, 0, 0)], 'must be a number'),
                       ('a line without a code', [L('', 'a', 0, 0, 0, 0, 1, 0, 0, 0)], 'needs a code'),
                       ('no lines at all', [], 'at least one WBS line'),
                       ('a justification over 600 characters', [L('SM', 'a', 0, 0, 0, 0, 1, 0, 0, 0, 'x' * 601)], 'too long')]:
    no_(f'refused: {name}', rel('co', 'save', figures=dict(HDR, wbs=bad), **M2), msg)
no_('refused: POC over 100%', rel('co', 'save', figures=dict(HDR, actual_poc=120, wbs=W1), **M2), 'between 0 and 100')
no_('refused: a negative contract value', rel('co', 'save', figures=dict(HDR, contract_value=-1, wbs=W1), **M2), 'cannot be negative')
no_('refused: wbs that is not a list', rel('co', 'save', figures=dict(HDR, wbs={'SM': 1}), **M2), 'at least one WBS line')
no_('a planning engineer cannot prepare it', rel('pl', 'save', figures=dict(HDR, wbs=W1), **M2), 'costing engineer')
no_('submitting is refused while a line with a supplement or saving has no justification', rel('co', 'submit', **M2), 'CONT')
W1[2]['justification'] = 'Balance contingency retained'
ok_('with the justification it saves', rel('co', 'save', figures=dict(HDR, wbs=W1), **M2), lambda r: True)
ok_('...and submits', rel('co', 'submit', **M2), lambda r: r['status'] == 'Submitted')
ok_('the Head approves it', rel('hd', 'approve', **M2), lambda r: r['status'] == 'Released')
no_('released, it cannot be changed, even from the database console', psql("update report_releases set figures = figures || '{\"budget_current\":1}' where period='2026-08' and kind='cost'"), 'cannot be changed')
check('a foreman receives none of it', cnt('fo', "select count(*) from report_releases where kind='cost'") == '0')

# the next month takes the previous version from the released report
W2 = [L('SM', 'Site Management', 2000, 2000, 2000, 1, 2600, 2300, 20, 300), L('MTRL.ELC', 'Electrical Material', 18000, 18000, 18000, 1, 14800, 13500, 1000, 300),
      L('NEW', 'New head', 0, 0, 0, 77, 100, 0, 0, 100)]
M3 = dict(project_id='P1', kind='cost', period_type='month', period='2026-09')
r = ok_('the next month by WBS head', rel('co', 'save', figures=dict(HDR, wbs=W2), **M3), lambda r: True)
w = {x['code']: x for x in r['figures']['wbs']} if r else {}
check('previous version C = the current budget of the last released cost report, line by line (what was entered is ignored)', w and float(w['SM']['prev']) == 2500 and float(w['MTRL.ELC']['prev']) == 15000)
check('a head that was not in the previous report has no previous version', w and float(w['NEW']['prev']) == 0)
check('the previous version\'s month is recorded', r and r['figures'].get('prev_period_text') == '2026-08')
# revise keeps the WBS lines; saving the revision recomputes them
for x in W2: x['justification'] = 'Re-forecast'
rel('co', 'save', figures=dict(HDR, wbs=W2), **M3); rel('co', 'submit', **M3); rel('hd', 'approve', **M3)
ok_('a revision starts from the released lines', rel('co', 'revise', note='Late SAP posting', **M3), lambda r: len(r['figures']['wbs']) == 3 and r['rev'] == 1)
ok_('saving the revision recomputes everything (EAC 17,520) and keeps the previous version from August', rel('co', 'save', figures=dict(HDR, wbs=W2, prev_period_text='2026-08', eac=5), **M3), lambda r: float(r['figures']['eac']) == 17520 and [float(x['prev']) for x in r['figures']['wbs'] if x['code'] == 'SM'] == [2500])

# ------------------------------------------------------------------ rollback keeps everything
n = q("select count(*) from report_releases where figures ? 'wbs'")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v12.sql'))
    check(f'rollback runs (run {i})', rc == 0, err)
check('rollback removes the helper', q("select count(*) from pg_proc where proname='pt_cost_wbs'") == '0')
check('rollback keeps every cost report with WBS lines, still readable', q("select count(*) from report_releases where figures ? 'wbs'") == n and cnt('pm', "select count(*) from report_releases where figures ? 'wbs' and status in ('Released','Superseded')") == q("select count(*) from report_releases where figures ? 'wbs' and status in ('Released','Superseded')"), n)
M4 = dict(project_id='P1', kind='cost', period_type='month', period='2026-10')
ok_('after rollback cost reports by totals work as in v3.2', rel('co', 'save', figures={'budget_rev0': 10, 'actual': 4, 'commitment': 1, 'ftc': 5}, **M4), lambda r: float(r['figures']['eac']) == 9)
rc, out, err = psql(file=find('schema-update-v12.sql'))
check('v12 can be applied again after a rollback', rc == 0, err)

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'schema-update-v12', 'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v12_results.json'), 'w'), indent=1)
sys.exit(0 if passed == len(results) else 1)
