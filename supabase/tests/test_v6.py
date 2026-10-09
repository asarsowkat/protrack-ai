#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v6 (governed lifecycle), on a local PostgreSQL 16 with a
Supabase stand-in: who may change, submit, approve, return, skip and reopen a stage; required deliverables;
no self-approval; history that cannot be edited; nothing deleted on rollback.
Usage: python3 test_v6.py [--keep]"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v6_test'
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
    if rc: raise SystemExit('setup failed: ' + err)
    return out

U = {k: f'00000000-0000-0000-0000-0000000000{i:02d}' for i, k in enumerate(['sa', 'pm', 'pm2', 'pl', 'c1', 'f1', 'ex', 'sa2', 'pmx'], start=1)}

def run_as(who, body):
    sub = U[who] if who else ''
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write(f"begin;\nset local role {'authenticated' if who else 'anon'};\nselect set_config('request.jwt.claim.sub', '{sub}', true) \\g /dev/null\n{body}\ncommit;\n"); path = f.name
    try: return psql(file=path)
    finally: os.unlink(path)

def check(name, ok, detail=''):
    results.append({'check': name, 'pass': bool(ok), 'detail': str(detail)[:300]})
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '  -> ' + str(detail)[:300]))

def lit(o): return "'" + json.dumps(o).replace("'", "''") + "'::jsonb"
def act(who, stage, action, project='P1', **kw):
    p = {'project_id': project, 'stage_no': stage, 'action': action}; p.update(kw)
    rc, out, err = run_as(who, f"select lifecycle_act({lit(p)});")
    return rc, (json.loads(out.splitlines()[-1]) if rc == 0 and out else None), err
def ok_(name, res, cond=lambda r: True):
    rc, r, err = res; check(name, rc == 0 and cond(r), r if rc == 0 else err); return r
def no_(name, res, msg=None):
    rc, r, err = res; check(name, rc != 0 and (msg is None or msg.lower() in err.lower()), err or r)
def st(stage, project='P1'): return admin(f"select status from lifecycle_stages where project_id='{project}' and stage_no={stage}")

subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql', 'schema-update-v4.sql', 'schema-update-v5.sql']:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
roles = {'sa': 'sa', 'pm': 'pm', 'pm2': 'pm', 'pl': 'plan', 'c1': 'costing', 'f1': 'foreman', 'ex': 'exec', 'sa2': 'sa', 'pmx': 'pm'}
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in roles.items()))
admin("insert into regions values ('R1','R',null); insert into projects (id, name, short, region) values ('P1','One','P1','R1'), ('P2','Two','P2','R1');")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['pm', 'pm2', 'pl', 'c1', 'f1']) + f", ('{U['pmx']}','P2')")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v6.sql'))
    check(f'v6 loads (run {i})', rc == 0, err)

# ------------------------------------------------------------------ reading and first touch
rc, out, err = run_as('f1', "select count(*) from lifecycle_stages;")
check('nothing exists until someone acts: stages start as Not started', rc == 0 and out.endswith('0'), out or err)
no_('a foreman cannot change a stage', act('f1', 6, 'update', fields={'next_action': 'x'}), 'only the stage owner')
no_('someone without access to the project cannot touch it', act('pmx', 6, 'update', fields={'next_action': 'x'}), 'do not have access')
no_('a signed-out visitor cannot touch it', run_as(None, f"select lifecycle_act({lit({'project_id': 'P1', 'stage_no': 6, 'action': 'start'})});"))
no_('an unknown stage is refused', act('pm', 13, 'start'), 'unknown lifecycle stage')
no_('an unknown action is refused', act('pm', 6, 'complete'), 'unknown action')
no_('the planner cannot assign themselves as owner', act('pl', 6, 'update', fields={'owner': U['pl']}), 'only the stage owner')
r = ok_('the project manager assigns an owner, due date and next action', act('pm', 6, 'update', fields={'owner': U['pl'], 'due_date': '2026-10-15', 'next_action': 'Submit baseline to client'}),
        lambda r: r['owner'] == U['pl'] and r['due_date'] == '2026-10-15' and r['department'] == 'Planning')
check('the stage starts with its required deliverables from the server template', admin("select jsonb_array_length(deliverables)||'/'||(select count(*) from jsonb_array_elements(deliverables) x where (x->>'req')::boolean) from lifecycle_stages where stage_no=6") == '5/4')
no_('the owner must be someone on the project', act('pm', 6, 'update', fields={'owner': U['pmx']}), 'access to this project')
no_('an invalid due date is refused', act('pm', 6, 'update', fields={'due_date': '2026-02-30'}), 'not a valid date')

# ------------------------------------------------------------------ owner works the stage
ok_('the owner ticks deliverables; the stage moves to In progress', act('pl', 6, 'update', ticks=[{'k': 'prepared', 'done': True}, {'k': 'costing', 'done': True}]),
    lambda r: r['status'] == 'In progress')
check('each tick records who and when', admin("select (x->>'by') from lifecycle_stages, jsonb_array_elements(deliverables) x where stage_no=6 and x->>'k'='prepared'") == 'User PL')
no_('an unknown deliverable is refused', act('pl', 6, 'update', ticks=[{'k': 'hack', 'done': True}]), 'unknown deliverable')
no_('submitting with required deliverables open is refused', act('pl', 6, 'submit'), 'required deliverables are not done')
check('...status unchanged', st(6) == 'In progress')
ok_('owner completes the rest and submits', act('pl', 6, 'update', ticks=[{'k': 'submitted', 'done': True}, {'k': 'approved', 'done': True}]))
ok_('...submit succeeds', act('pl', 6, 'submit'), lambda r: r['status'] == 'Awaiting approval' and r['submitted_by'] == U['pl'])
no_('the owner cannot approve', act('pl', 6, 'approve'), 'only the project manager')
no_('an executive cannot approve', act('ex', 6, 'approve'), 'only the project manager')
no_('return needs a comment', act('pm', 6, 'return'), 'add a comment')
ok_('the project manager returns it with a comment', act('pm', 6, 'return', note='Attach the client transmittal'), lambda r: r['status'] == 'In progress')
ok_('the owner resubmits', act('pl', 6, 'submit'))
ok_('the project manager approves', act('pm', 6, 'approve'), lambda r: r['status'] == 'Complete' and r['approved_by'] == U['pm'])
no_('a complete stage cannot be edited', act('pm', 6, 'update', fields={'next_action': 'x'}), 'reopen')
no_('a complete stage cannot be approved again', act('sa', 6, 'approve'))

# ------------------------------------------------------------------ no self-approval
ok_('a project manager can own and submit a stage', act('pm', 4, 'update', fields={'owner': U['pm']}, ticks=[{'k': 'docs', 'done': True}, {'k': 'scope', 'done': True}, {'k': 'team', 'done': True}]))
ok_('...submits it', act('pm', 4, 'submit'))
no_('...but cannot approve their own submission', act('pm', 4, 'approve'), 'someone else must approve')
ok_('another project manager on the project approves it', act('pm2', 4, 'approve'), lambda r: r['status'] == 'Complete')
ok_('a super admin can submit', act('sa', 1, 'update', fields={'owner': U['sa']}, ticks=[{'k': 'notice', 'done': True}, {'k': 'bid', 'done': True}]))
ok_('...', act('sa', 1, 'submit'))
no_('...and cannot approve their own submission either', act('sa', 1, 'approve'), 'someone else must approve')
ok_('a second super admin can', act('sa2', 1, 'approve'))

# ------------------------------------------------------------------ not applicable, reopen
no_('not applicable needs a comment', act('pm', 10, 'na'), 'add a comment')
no_('the owner cannot mark a stage not applicable', act('pl', 8, 'na', note='x'), 'only the project manager')
ok_('the project manager marks a stage not applicable with a reason', act('pm', 10, 'na', note='Lump-sum contract, no variations clause'), lambda r: r['status'] == 'Not applicable')
no_('a project manager cannot reopen', act('pm', 6, 'reopen', note='client re-baseline'), 'only a super admin')
no_('reopen needs a comment', act('sa', 6, 'reopen'), 'add a comment')
ok_('a super admin reopens with a reason; approval is cleared', act('sa', 6, 'reopen', note='Client asked for a revised baseline'),
    lambda r: r['status'] == 'In progress' and r['approved_by'] is None)

# ------------------------------------------------------------------ history
h = admin("select string_agg(action||':'||by_role, ',' order by id) from lifecycle_audit where stage_no=6")
check('every step is in the history with who and role', h == 'Updated:pm,Updated:plan,Updated:plan,Submitted for approval:plan,Returned:pm,Submitted for approval:plan,Approved:pm,Reopened:sa', h)
check('the return comment is kept', admin("select note from lifecycle_audit where action='Returned'") == 'Attach the client transmittal')
rc, out, err = psql("update lifecycle_audit set note='changed'")
check('history cannot be edited, even by the database owner', rc != 0 and 'append-only' in err, err)
rc, out, err = psql("delete from lifecycle_audit")
check('history cannot be deleted, even by the database owner', rc != 0, err)
rc, out, err = run_as('sa', "update lifecycle_stages set status='Complete' where stage_no=7 returning 1;")
check('stages cannot be written directly from the app', admin("select count(*) from lifecycle_stages where stage_no=7") == '0', out or err)
rc, out, err = run_as('sa', "insert into lifecycle_stages (project_id, stage_no, status) values ('P1', 9, 'Complete');")
check('...nor created directly', rc != 0, err)
rc, out, err = run_as('pmx', "select count(*) from lifecycle_stages;")
check('people on other projects cannot read these stages', rc == 0 and out.endswith('0'), out or err)
rc, out, err = run_as('f1', "select count(*) from lifecycle_audit;")
check('people on the project can read the history', rc == 0 and int(out.splitlines()[-1]) > 5, out or err)

# ------------------------------------------------------------------ rollback keeps data
counts = admin("select (select count(*) from lifecycle_stages)||'/'||(select count(*) from lifecycle_audit)")
rc, out, err = psql(file=find('schema-rollback-v6.sql'))
check('rollback runs', rc == 0, err)
check('rollback keeps every stage and history entry', admin("select (select count(*) from lifecycle_stages)||'/'||(select count(*) from lifecycle_audit)") == counts)
rc, out, err = psql(file=find('schema-update-v6.sql'))
check('v6 can be applied again after a rollback', rc == 0, err)

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} checks passed')
json.dump({'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v6_results.json'), 'w'), indent=1)
if '--keep' not in sys.argv:
    subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database {DBN}'], capture_output=True)
sys.exit(0 if passed == len(results) else 1)
