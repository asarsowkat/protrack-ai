#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v11 (ProTrackAI v3.2): quantities beyond the activity scope in daily
reports. A report may record more than the scope; the reviewer must justify each such activity while reviewing; the
justification is kept and cannot be changed; the approver cannot approve an unjustified quantity (for example one raised
by an edit after review). Builds schema.sql + v2 ... v10, loads v11 twice, tests, rolls back, re-applies.
Usage: python3 test_v11.py   (PostgreSQL 16 on /tmp:5499)"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v11_test'
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
ROLES = {'sa': 'sa', 'pm': 'pm', 'e1': 'eng', 's1': 'sm', 'f1': 'foreman', 'f2': 'foreman', 'nx': 'pm'}
U = {k: f'00000000-0000-0000-0000-0000000004{i:02d}' for i, k in enumerate(ROLES, start=1)}
def run_as(who, body):
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write(f"begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub', '{U[who]}', true) \\g /dev/null\n{body}\ncommit;\n"); path = f.name
    try: return psql(file=path)
    finally: os.unlink(path)
def check(name, ok, detail=''):
    results.append({'check': name, 'pass': bool(ok), 'detail': str(detail)[:300]})
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '  -> ' + str(detail)[:300]))
def lit(o): return "'" + json.dumps(o).replace("'", "''") + "'::jsonb"
def one(who, sql):
    rc, out, err = run_as(who, sql)
    return rc, (out.splitlines()[-1] if rc == 0 and out else ''), err
def ok_(name, res, want=None):
    rc, out, err = res; check(name, rc == 0 and (want is None or out == want), err or out); return out
def no_(name, res, msg=None):
    rc, out, err = res; check(name, rc != 0 and (msg is None or msg.lower() in err.lower()), err or out)
def save(who, p): return one(who, f"select dpr_save({lit(p)})->>'id';")
def act(who, did, a, note=None, just=None):
    n = 'null' if note is None else "'" + note.replace("'", "''") + "'"
    j = '' if just is None else f", 0, {lit(just)}"
    return one(who, f"select dpr_act('{did}', '{a}', {n}{j if just is not None else ''})->>'status';")
def line(act_id, qty): return {'activity_id': act_id, 'qty': qty, 'labour': [{'cat': 'Mason', 'count': 2, 'reg': 8, 'ot': 0}]}
q = admin

subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql', 'schema-update-v4.sql', 'schema-update-v5.sql',
          'schema-update-v6.sql', 'schema-update-v7.sql', 'schema-update-v8.sql', 'schema-update-v9.sql', 'schema-update-v10.sql']:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin("insert into regions values ('R1','Western',null); insert into projects (id, name, short, region) values ('P1','One','P1','R1');")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['pm', 'e1', 's1', 'f1', 'f2']))
admin("insert into activities (id, project_id, name, uom, qty, prior_qty, budget_mh) values ('A1','P1','Raft concrete','m3',100,60,200), ('A2','P1','Rebar','t',50,0,100);")
admin(f"insert into approval_matrix (project_id, kind, from_user, to_user) values ('P1','fm','{U['f1']}','{U['e1']}'), ('P1','fm','{U['f2']}','{U['e1']}'), ('P1','eng','{U['e1']}','{U['s1']}')")
# a report reviewed before v11 that already went beyond the scope: v11 must not touch it
D0 = save('f1', {'project_id': 'P1', 'report_date': '2026-09-01', 'lines': [line('A2', 5)], 'submit': True})[1]
act('e1', D0, 'review')
for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v11.sql'))
    check(f'v11 loads (run {i})', rc == 0, err)
check('the setup check counts the new function signature and helper', q("select count(*) from pg_proc where proname in ('dpr_act','pt_dpr_over') and (proname <> 'dpr_act' or pronargs = 5)") == '2')
check('the old four-argument function is gone, so calls cannot be ambiguous', q("select count(*) from pg_proc where proname='dpr_act'") == '1')
check('a report reviewed before v11 is untouched', q(f"select status from dprs where id='{D0}'") == 'Reviewed')
ok_('...and it can still be approved (its quantity is within the scope)', act('s1', D0, 'approve'), 'Approved')

# ------------------------------------------------------------------ within the scope: nothing changes
D1 = save('f1', {'project_id': 'P1', 'report_date': '2026-09-10', 'lines': [line('A1', 30)], 'submit': True})[1]
ok_('within the scope (60 before + 30 of 100), the engineer reviews without any justification, as before', act('e1', D1, 'review'), 'Reviewed')
ok_('...and the site manager approves', act('s1', D1, 'approve'), 'Approved')
check('no justification is recorded for it', q("select count(*) from dpr_qty_just") == '0')

# ------------------------------------------------------------------ beyond the scope
D2 = save('f1', {'project_id': 'P1', 'report_date': '2026-09-11', 'lines': [line('A1', 20), line('A2', 10)], 'submit': True})
check('a report beyond the scope (60 + 30 + 20 = 110 of 100) is accepted when submitted', D2[0] == 0 and q(f"select status from dprs where id='{D2[1]}'") == 'Submitted', D2[2]); D2 = D2[1]
check('the helper finds only the activity beyond its scope, with this report, the total to date and the scope', q(f"select string_agg(activity_id||':'||qty::int||':'||cum_qty::int||':'||scope_qty::int, ',') from pt_dpr_over('{D2}')") == 'A1:20:110:100')
no_('reviewing it without a justification is refused, naming the activity', act('e1', D2, 'review'), 'A1')
no_('a justification of a word or two is refused', act('e1', D2, 'review', just={'A1': 'ok'}), 'Justify')
no_('a justification for another activity does not count', act('e1', D2, 'review', just={'A2': 'Surveyed quantity is higher than the BOQ'}), 'A1')
no_('justifications must be given per activity', act('e1', D2, 'review', just=['x']), 'per activity')
check('...nothing was recorded by the refused attempts', q("select count(*) from dpr_qty_just") == '0' and q(f"select status from dprs where id='{D2}'") == 'Submitted')
ok_('with a justification the engineer reviews it', act('e1', D2, 'review', just={'A1': 'Raft thickened at the lift pit per RFI-12; re-measured 110 m3'}), 'Reviewed')
check('the justification is kept with the quantities, who and when', q(f"select activity_id||'/'||qty::int||'/'||cum_qty::int||'/'||scope_qty::int||'/'||(by_user::text='{U['e1']}') from dpr_qty_just where dpr_id='{D2}'") == 'A1/20/110/100/true')
check('it is also in the report audit trail', q(f"select count(*) from dpr_audit where dpr_id='{D2}' and action='Quantity variation justified' and note like 'A1: Raft thickened%'") == '1')
no_('the justification cannot be changed', psql("update dpr_qty_just set note='changed later on'"), 'append-only')
no_('...or deleted', psql("delete from dpr_qty_just"), 'append-only')
no_('...or emptied', psql("truncate dpr_qty_just"), 'cannot be emptied')
rc, out, err = run_as('e1', f"insert into dpr_qty_just (dpr_id, activity_id, qty, cum_qty, scope_qty, note) values ('{D2}','A2',1,1,1,'written directly');")
check('nobody can write a justification directly from the browser', rc != 0, out)

# an edit after review that raises the quantity needs a new justification
ok_('the engineer edits the reviewed report and raises the quantity', save('e1', {'id': D2, 'project_id': 'P1', 'report_date': '2026-09-11', 'lines': [line('A1', 25), line('A2', 10)]}), D2)
no_('the site manager cannot approve a quantity that was not justified', act('s1', D2, 'approve'), 'not been justified')
ok_('the site manager returns it with a comment (no justification needed to return)', act('s1', D2, 'return', 'Engineer to justify the new quantity'), 'Draft')
ok_('the foreman resubmits', save('f1', {'id': D2, 'project_id': 'P1', 'report_date': '2026-09-11', 'lines': [line('A1', 25), line('A2', 10)], 'submit': True}), D2)
ok_('the engineer reviews with a new justification', act('e1', D2, 'review', just={'A1': 'Re-measured after the pump line flush: 115 m3 placed'}), 'Reviewed')
ok_('the site manager approves', act('s1', D2, 'approve'), 'Approved')
check('both justifications are kept', q(f"select string_agg(qty::int::text, ',' order by id) from dpr_qty_just where dpr_id='{D2}'") == '20,25')

# other reports of the same day count
D3 = save('f2', {'project_id': 'P1', 'report_date': '2026-09-11', 'lines': [line('A2', 45)], 'submit': True})[1]
check('another foreman\'s report of the same day counts towards the scope (5 + 10 + 45 = 60 of 50)', q(f"select string_agg(activity_id||':'||cum_qty::int, ',') from pt_dpr_over('{D3}')") == 'A2:60')
save('f1', {'project_id': 'P1', 'report_date': '2026-09-12', 'lines': [line('A1', 40)]})   # a draft, never submitted
no_('the project manager reviewing must justify too', act('pm', D3, 'review'), 'A2')
ok_('the project manager reviews with a justification', act('pm', D3, 'review', just={'A2': 'Additional dowels instructed by the consultant'}), 'Reviewed')
D4 = save('f1', {'project_id': 'P1', 'report_date': '2026-09-13', 'lines': [line('A1', 5)], 'submit': True})[1]
ok_('a report beyond the scope can still be returned without a justification', act('e1', D4, 'return', 'Check the quantity'), 'Draft')
ok_('...or rejected by the project manager', (lambda r: r)(save('f1', {'id': D4, 'project_id': 'P1', 'report_date': '2026-09-13', 'lines': [line('A1', 5)], 'submit': True})), D4)
ok_('rejected', act('pm', D4, 'reject', 'Duplicate of an earlier report'), 'Rejected')
D6 = save('f2', {'project_id': 'P1', 'report_date': '2026-09-13', 'lines': [line('A1', 1)], 'submit': True})[1]
check('drafts and rejected reports do not count (60 + 30 + 25 + 1 = 116, without the 40 in a draft and the 5 rejected)', q(f"select string_agg(activity_id||':'||cum_qty::int, ',') from pt_dpr_over('{D6}')") == 'A1:116')

# who reads the justifications
check('people on the project read the justifications', one('pm', "select count(*) from dpr_qty_just")[1] == '3' and one('f1', "select count(*) from dpr_qty_just")[1] == '3')
check('people without access to the project read none', one('nx', "select count(*) from dpr_qty_just")[1] == '0')
no_('the helper is not callable from the browser', one('e1', f"select * from pt_dpr_over('{D2}');"), 'permission denied')

# ------------------------------------------------------------------ rollback keeps everything
n = q("select count(*) from dpr_qty_just")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v11.sql'))
    check(f'rollback runs (run {i})', rc == 0, err)
check('rollback restores the four-argument function', q("select string_agg(pronargs::text, ',') from pg_proc where proname='dpr_act'") == '4' and q("select count(*) from pg_proc where proname='pt_dpr_over'") == '0')
check('rollback keeps every justification', q("select count(*) from dpr_qty_just") == n, n)
D5 = save('f1', {'project_id': 'P1', 'report_date': '2026-09-14', 'lines': [line('A1', 10)], 'submit': True})[1]
ok_('after rollback reviews work as before (no justification asked)', act('e1', D5, 'review'), 'Reviewed')
rc, out, err = psql(file=find('schema-update-v11.sql'))
check('v11 can be applied again after a rollback', rc == 0, err)

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'schema-update-v11', 'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v11_results.json'), 'w'), indent=1)
sys.exit(0 if passed == len(results) else 1)
