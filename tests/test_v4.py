#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v4, run against a local PostgreSQL 16 with a Supabase stand-in.

Builds a fresh database from schema.sql + v2 + v3, adds pre-v4 data (written the old way), loads v4,
then signs in as different people and checks what the server allows and refuses.
Usage: python3 test_v4.py [--keep]     (needs psql on PATH and a server on /tmp:5499)
"""
import json, subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v4_test'
results = []

def find(name):
    for d in (HERE, os.path.dirname(HERE), os.path.join(HERE, 'tests')):
        if os.path.exists(os.path.join(d, name)): return os.path.join(d, name)
    raise SystemExit('missing ' + name)

def psql(sql, db=DBN, file=None):
    cmd = PG + ['-d', db] + (['-f', file] if file else ['-c', sql])
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()

U = {k: f'00000000-0000-0000-0000-0000000000{i:02d}' for i, k in enumerate(
    ['sa', 'pm', 'e1', 'e2', 's1', 's2', 'f1', 'f2', 'c1', 'pl', 'ex', 'pm2', 'f3'], start=1)}

def as_user(who, sql):
    """Runs sql in one transaction as the signed-in app user `who` (role authenticated), like a browser request."""
    sub = U[who] if who else ''
    role = 'authenticated' if who else 'anon'
    return psql(f"begin; set local role {role}; select set_config('request.jwt.claim.sub', '{sub}', true) \\g /dev/null\n{sql}\ncommit;")

def as_user_script(who, sql):
    sub = U[who] if who else ''
    role = 'authenticated' if who else 'anon'
    path = os.path.join(HERE, '.t.sql')
    open(path, 'w').write(f"begin;\nset local role {role};\nselect set_config('request.jwt.claim.sub', '{sub}', true) \\g /dev/null\n{sql}\ncommit;\n")
    return psql(None, file=path)

def check(name, ok, detail=''):
    results.append({'check': name, 'pass': bool(ok), 'detail': detail[:300]})
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '  -> ' + detail[:300]))

def expect_ok(name, who, sql, contains=None):
    rc, out, err = as_user_script(who, sql)
    ok = rc == 0 and (contains is None or contains in out)
    check(name, ok, out if rc == 0 else err)
    return out

def expect_refused(name, who, sql, msg=None):
    rc, out, err = as_user_script(who, sql)
    ok = rc != 0 and (msg is None or msg.lower() in err.lower())
    check(name, ok, err or out)

def expect_no_effect(name, who, sql, probe):
    """Row level security refuses some writes silently (nothing matches); what counts is that nothing changed."""
    before = admin(probe)
    rc, out, err = as_user_script(who, sql)
    after = admin(probe)
    check(name, before == after, f'rc={rc} before={before} after={after} {err}')

def j(o): return "'" + json.dumps(o).replace("'", "''") + "'::jsonb"

def admin(sql):
    rc, out, err = psql(sql)
    if rc: raise SystemExit('setup failed: ' + err)
    return out

# ------------------------------------------------------------------ build
subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql']:
    rc, out, err = psql(None, file=find(f))
    if rc: raise SystemExit(f'{f} failed: {err}')

roles = {'sa': 'sa', 'pm': 'pm', 'e1': 'eng', 'e2': 'eng', 's1': 'sm', 's2': 'sm', 'f1': 'foreman', 'f2': 'foreman',
         'c1': 'costing', 'pl': 'plan', 'ex': 'exec', 'pm2': 'pm', 'f3': 'foreman'}
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in roles.items()))
admin("""insert into regions values ('R1','Region 1',null);
insert into projects (id, name, short, region) values ('P1','Project One','P1','R1'), ('P2','Project Two','P2','R1');
insert into project_access (user_id, project_id) select id, 'P1' from profiles where role::text not in ('sa','exec') and name not in ('User F2','User PM2');
insert into project_access values ('%s','P2'), ('%s','P2'), ('%s','P2');
insert into activities (id, project_id, name, qty, budget_mh) values ('A1','P1','Concrete',1000,2000), ('A2','P1','Rebar',500,800), ('B1','P2','Piling',100,300);
insert into approval_matrix (project_id, kind, from_user, to_user) values ('P1','fm','%s','%s'), ('P1','eng','%s','%s');
""" % (U['f2'], U['pm2'], U['e1'], U['f1'], U['e1'], U['e1'], U['s1']))
# a report and audit entries written the old (pre-v4) way, directly into the tables
admin("""insert into dprs (id, project_id, report_date, foreman, status) values ('DPR-OLD1','P1','2026-09-01','User F1','Approved');
insert into dpr_lines (dpr_id, activity_id, qty) values ('DPR-OLD1','A1',40);
insert into dpr_audit (dpr_id, action, by_user, at_time) values ('DPR-OLD1','Submitted','%s','2026-09-01 17:00+03'),
  ('DPR-OLD1','Approved','%s','2026-09-02 09:00+03');""" % (U['f1'], U['pm']))

rc, out, err = psql(None, file=find('schema-update-v4.sql'))
check('v4 loads on a database that already has reports', rc == 0, err)
rc2, out, err = psql(None, file=find('schema-update-v4.sql'))
check('v4 can be run a second time', rc2 == 0, err)
if rc: raise SystemExit(1)

check('old audit entries are sealed into the chain', admin("select dpr_audit_verify('DPR-OLD1')") == 't')
check('old data untouched by v4', admin("select status||'/'||(select count(*) from dpr_lines where dpr_id='DPR-OLD1')||'/'||(select count(*) from dpr_audit where dpr_id='DPR-OLD1') from dprs where id='DPR-OLD1'") == 'Approved/1/2')

LINE = [{'activity_id': 'A1', 'qty': 50, 'labour': [{'cat': 'Carpenter', 'count': 10, 'reg': 8, 'ot': 2}], 'subs': [], 'equip': []}]

# ------------------------------------------------------------------ direct writes (as a browser would)
expect_refused('direct insert of a report is refused', 'f1',
    "insert into dprs (id, project_id, report_date, foreman, status) values ('X1','P1','2026-09-10','User F1','Approved');")
expect_no_effect('direct status change is refused', 'pm', "update dprs set status='Rejected' where id='DPR-OLD1';",
    "select status from dprs where id='DPR-OLD1'")
expect_no_effect('direct delete of a report is refused', 'sa', "delete from dprs where id='DPR-OLD1';", "select count(*) from dprs")
expect_no_effect('direct edit of report lines is refused', 'f1', "update dpr_lines set qty=999 where dpr_id='DPR-OLD1';",
    "select string_agg(qty::text, ',') from dpr_lines")
expect_refused('writing an audit entry directly is refused', 'pm',
    f"insert into dpr_audit (dpr_id, action, by_user) values ('DPR-OLD1','Approved','{U['s1']}');")
expect_no_effect('changing an audit entry is refused', 'sa', "update dpr_audit set note='x' where dpr_id='DPR-OLD1';",
    "select string_agg(coalesce(note,'-'), ',') from dpr_audit")
expect_no_effect('deleting an audit entry is refused', 'sa', "delete from dpr_audit where dpr_id='DPR-OLD1';", "select count(*) from dpr_audit")
admin("insert into change_log (text) values ('seed entry')")
expect_no_effect('changing the change log is refused', 'sa', "update change_log set text='x';", "select string_agg(text, ',') from change_log")
expect_refused('change log entry in someone else\'s name is refused', 'f1',
    f"insert into change_log (text, by_user) values ('fake', '{U['sa']}');")
expect_ok('change log entry in own name is allowed', 'f1', "insert into change_log (text) values ('mine') returning by_user;", U['f1'])
expect_refused('signed-out visitor cannot call report functions', None, f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-10','lines':LINE})});")
expect_refused('internal helper functions are not callable', 'f1', "select pt_audit('DPR-OLD1','Approved','x');")
expect_refused('approval routing helper is not callable', 'f1', f"select role_of('{U['sa']}');")

# ------------------------------------------------------------------ the normal path
out = expect_ok('foreman saves a draft', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-10','lines':LINE,'secs':120})})->>'id';")
D1 = out.strip()
check('new report number continues the sequence', D1.startswith('DPR-'), D1)
expect_ok('foreman submits own draft', 'f1', f"select dpr_save({j({'id':D1,'project_id':'P1','report_date':'2026-09-10','lines':LINE,'submit':True})})->>'status';", 'Submitted')
expect_refused('foreman cannot edit after submitting', 'f1', f"select dpr_save({j({'id':D1,'project_id':'P1','report_date':'2026-09-10','lines':LINE})});", 'assigned site engineer')
expect_refused('foreman cannot review', 'f1', f"select dpr_act('{D1}','review');", 'not the reviewer')
expect_refused('unassigned site engineer cannot review', 'e2', f"select dpr_act('{D1}','review');", 'not the reviewer')
expect_refused('site manager cannot approve before review', 's1', f"select dpr_act('{D1}','approve');")
expect_refused('return without a comment is refused', 'e1', f"select dpr_act('{D1}','return','  ');", 'comment is required')
expect_refused('engineer cannot reject (only return)', 'e1', f"select dpr_act('{D1}','reject','bad');")
expect_ok('assigned site engineer reviews', 'e1', f"select dpr_act('{D1}','review',null,30)->>'status';", 'Reviewed')
expect_refused('unassigned site manager cannot approve', 's2', f"select dpr_act('{D1}','approve');", 'not the reviewer or approver')
expect_refused('engineer cannot approve', 'e1', f"select dpr_act('{D1}','approve');")
expect_ok('assigned site manager approves', 's1', f"select dpr_act('{D1}','approve',null,45)->>'status';", 'Approved')
expect_refused('approved report cannot be edited', 'pm', f"select dpr_save({j({'id':D1,'project_id':'P1','report_date':'2026-09-10','lines':LINE})});", 'cannot be edited')
expect_refused('approved report cannot be acted on again', 'sa', f"select dpr_act('{D1}','reject','late');")
check('audit trail has 4 entries with names and roles',
      admin(f"select string_agg(action||':'||by_role, ',' order by seq) from dpr_audit where dpr_id='{D1}'") ==
      'Draft created:foreman,Submitted:foreman,Reviewed:eng,Approved:sm',
      admin(f"select string_agg(action||':'||coalesce(by_role,'-'), ',' order by seq) from dpr_audit where dpr_id='{D1}'"))
check('timers recorded for create, review and approve',
      admin(f"select (timing->'create'->>'secs')||'/'||(timing->'review'->>'secs')||'/'||(timing->'approve'->>'secs') from dprs where id='{D1}'") == '120/30/45')
expect_ok('audit chain verifies', 'pm', f"select dpr_audit_verify('{D1}');", 't')
expect_refused('cannot verify a report on a project you cannot see', 'f2', f"select dpr_audit_verify('{D1}');")

rc, out, err = psql(f"update dpr_audit set note='edited' where dpr_id='{D1}'")
check('even the database owner cannot edit an audit entry', rc != 0 and 'cannot be changed' in err, err)
rc, out, err = psql("delete from change_log")
check('even the database owner cannot delete the change log', rc != 0 and 'append-only' in err, err)
rc, out, err = psql(f"update dprs set status='Draft' where id='{D1}'")
check('even the database owner cannot reopen an approved report', rc != 0 and 'approved report' in err, err)
# tamper (as the database owner, with the guard switched off) and detect it
admin(f"alter table dpr_audit disable trigger trg_audit_chain; update dpr_audit set by_name='Someone else' where dpr_id='{D1}' and action='Approved'; alter table dpr_audit enable trigger trg_audit_chain;")
check('tampering with an audit entry is detected', admin(f"select dpr_audit_verify('{D1}')") == 'f')

# ------------------------------------------------------------------ returns, rejections, fallbacks
out = expect_ok('engineer creates a report for a foreman', 'e1',
    f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-11','foreman_id':U['f1'],'lines':LINE,'submit':True})})->>'id';")
D2 = out.strip()
expect_ok('assigned engineer returns with a comment', 'e1', f"select dpr_act('{D2}','return','Check quantities')->>'status';", 'Draft')
check('returned flag set', admin(f"select returned from dprs where id='{D2}'") == 't')
expect_ok('foreman edits the returned draft', 'f1', f"select dpr_save({j({'id':D2,'project_id':'P1','report_date':'2026-09-11','lines':[dict(LINE[0], qty=45)],'submit':True})})->>'status';", 'Submitted')
check('resubmission is recorded as such', admin(f"select action from dpr_audit where dpr_id='{D2}' order by seq desc limit 1") == 'Resubmitted')
check('returned flag cleared on resubmit', admin(f"select returned from dprs where id='{D2}'") == 'f')
expect_ok('project manager rejects with a comment', 'pm', f"select dpr_act('{D2}','reject','Duplicate')->>'status';", 'Rejected')
expect_refused('rejected report cannot be edited', 'e1', f"select dpr_save({j({'id':D2,'project_id':'P1','report_date':'2026-09-11','lines':LINE})});")

out = expect_ok('foreman with no engineer assigned saves and submits', 'f3',
    f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-12','lines':LINE,'submit':True})})->>'id';")
D3 = out.strip()
expect_refused('...an engineer cannot review it', 'e1', f"select dpr_act('{D3}','review');")
expect_ok('...the project manager reviews it', 'pm', f"select dpr_act('{D3}','review')->>'status';", 'Reviewed')
expect_refused('...a site manager cannot approve it', 's1', f"select dpr_act('{D3}','approve');")
expect_ok('...the project manager approves it', 'pm', f"select dpr_act('{D3}','approve')->>'status';", 'Approved')

# ------------------------------------------------------------------ input checks and project access
expect_refused('foreman cannot write on a project outside their access', 'f1', f"select dpr_save({j({'project_id':'P2','report_date':'2026-09-10','lines':[dict(LINE[0], activity_id='B1')]})});", 'access')
expect_refused('activity from another project is refused', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-13','lines':[dict(LINE[0], activity_id='B1')]})});", 'unknown activity')
expect_refused('negative quantity is refused', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-13','lines':[dict(LINE[0], qty=-5)]})});", 'negative')
expect_refused('more than 24 hours a day is refused', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-13','lines':[dict(LINE[0], labour=[{'cat':'Carpenter','count':2,'reg':20,'ot':6}])]})});", '24 hours')
expect_refused('empty report is refused', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-13','lines':[]})});", 'at least one')
expect_refused('cost engineer cannot write reports', 'c1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-13','lines':LINE})});", 'cannot write')
expect_refused('engineer cannot name a foreman from another project', 'e1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-13','foreman_id':U['f2'],'lines':LINE})});", 'not on this project')
rc, out, err = as_user_script('f2', "select count(*) from dprs;")
check('row level security still hides other projects', rc == 0 and out.strip().endswith('0'), out or err)

expect_refused('report dated in the future is refused', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2030-01-01','lines':LINE})});", 'future')
expect_refused('same activity twice is refused', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-13','lines':LINE+LINE})});", 'twice')
expect_refused('second report for the same foreman and day is refused', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-10','lines':LINE})});", 'already has a report')

out = expect_ok('a foreman always reports under their own name', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-13','foreman':'User F3','lines':LINE})})->>'id';")
check('...stored as the signed-in foreman', admin(f"select foreman from dprs where id='{out.strip()}'") == 'User F1', out)

# ------------------------------------------------------------------ team directory
out = expect_ok('foreman sees the team directory', 'f1', "select string_agg(name||':'||role||':'||coalesce(email,''), ',' order by name) from team_directory();")
check('directory holds colleagues on shared projects and leadership', all(x in out for x in ['User E1:eng', 'User S1:sm', 'User PM:pm', 'User SA:sa', 'User EX:exec']), out)
check('directory leaves out people on other projects only', 'User F2' not in out and 'User PM2' not in out, out)
out = expect_ok('super admin sees everyone', 'sa', "select count(*) from team_directory();")
check('...all 13 people', out.strip().endswith('13'), out)
out = expect_ok('colleague project lists are limited to projects the caller sees', 'f2', "select string_agg(name||'='||array_to_string(projects,'+'), ',' order by name) from team_directory();")
check('...P2 foreman sees P2 team, and E1 only as a P2 member', 'User E1=P2,' in out and 'User PM2=P2' in out and 'User S1' not in out, out)
expect_refused('signed-out visitor gets no directory', None, "select * from team_directory();")

# ------------------------------------------------------------------ people
admin("insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000099', 'new@test.local')")
expect_refused('only the super admin manages people', 'pm', f"select admin_save_person({j({'email':'new@test.local','name':'New','role':'eng','projects':['P1']})});", 'super admin')
expect_refused('a person needs a sign-in account first', 'sa', f"select admin_save_person({j({'email':'nobody@test.local','name':'X','role':'eng'})});", 'no sign-in account')
expect_ok('super admin adds a person with role and access', 'sa', f"select admin_save_person({j({'email':'NEW@test.local','name':'New Engineer','role':'eng','projects':['P1','NOPE']})});")
check('...profile and access created, unknown project ignored', admin("select p.name||'/'||p.role||'/'||(select string_agg(project_id, ',') from project_access where user_id=p.id) from profiles p where id='00000000-0000-0000-0000-000000000099'") == 'New Engineer/eng/P1')
expect_ok('super admin changes role and moves the person', 'sa', f"select admin_save_person({j({'email':'new@test.local','name':'New Engineer','role':'sm','projects':['P2'],'active':True})});")
check('...access replaced, not added to', admin("select role||'/'||(select string_agg(project_id, ',') from project_access where user_id=p.id) from profiles p where id='00000000-0000-0000-0000-000000000099'") == 'sm/P2')
expect_refused('super admin cannot remove their own access', 'sa', f"select admin_save_person({j({'email':'sa@test.local','name':'User SA','role':'pm'})});", 'own super admin')
expect_refused('unknown role is refused', 'sa', f"select admin_save_person({j({'email':'new@test.local','name':'N','role':'boss'})});", 'unknown role')

# ------------------------------------------------------------------ imports
INV = [{'no': 'INV-1', 'date': '2026-08-31', 'sub': 100000, 'appr': 90000, 'coll': 50000},
       {'no': 'INV-2', 'date': '2026-09-30', 'sub': 80000, 'appr': 0, 'coll': 0},
       {'no': 'INV-3', 'sub': 1000, 'appr': 2000, 'coll': 0},
       {'no': '', 'sub': 5}]
H1 = 'a' * 64
out = expect_ok('cost engineer loads an invoice register', 'c1', f"select import_invoices('P1','reg.xlsx','{H1}',{j(INV)});")
r = json.loads(out.splitlines()[-1]) if out else {}
check('valid rows accepted, invalid rows refused with reasons', r.get('accepted') == 2 and len(r.get('rejected', [])) == 2, out)
check('accepted total reconciles', float(r.get('total_accepted', 0)) == 180000, out)
out = expect_ok('same file again changes nothing', 'c1', f"select import_invoices('P1','reg.xlsx','{H1}',{j(INV[:1])});", '"duplicate": true')
check('...register still has 2 invoices', admin("select count(*) from invoices where project_id='P1'") == '2')
INV_B = [{'no': 'INV-9', 'sub': 5000}]
expect_ok('a different register replaces the first', 'c1', f"select import_invoices('P1','reg-b.xlsx','{'9'*64}',{j(INV_B)});", '"accepted": 1')
out = expect_ok('loading the first register again applies it again', 'c1', f"select import_invoices('P1','reg.xlsx','{H1}',{j(INV)});", '"duplicate": false')
check('...register is back to the first file', admin("select string_agg(invoice_no, ',' order by invoice_no) from invoices where project_id='P1'") == 'INV-1,INV-2')
expect_refused('foreman cannot load invoices', 'f1', f"select import_invoices('P1','reg.xlsx','{'b'*64}',{j(INV)});", 'only costing')
expect_refused('cost engineer cannot load invoices into a project outside access', 'c1', f"select import_invoices('P2','reg.xlsx','{'c'*64}',{j(INV)});")
expect_refused('a load without a file fingerprint is refused', 'c1', f"select import_invoices('P1','reg.xlsx','short',{j(INV)});", 'hash')
expect_refused('cost engineer cannot write invoices into another project directly', 'c1', "insert into invoices (project_id, invoice_no) values ('P2','X');")

COST = [{'id': 'A1', 'qty': 1000, 'uom': 'm3', 'rate': 50, 'cost': 50000, 'mh': 2100},
        {'id': 'a2', 'qty': 500, 'uom': 't', 'rate': 200, 'cost': 100000, 'mh': 0},
        {'id': 'ZZ', 'qty': 1, 'cost': 1}, {'id': 'A1', 'qty': 0}]
out = expect_ok('cost engineer applies a costing file', 'c1', f"select apply_costing('P1','cost.xlsx','{'d'*64}',{j(COST)});")
r = json.loads(out.splitlines()[-1]) if out else {}
check('matched activities updated, unknown and zero-quantity rows refused', r.get('applied') == 2 and len(r.get('rejected', [])) == 2, out)
check('costing manhours used as budget', admin("select budget_mh||'/'||p6_mh from activities where project_id='P1' and id='A1'") == '2100/2000')
check('snapshot kept for undo', admin("select count(*) from baseline_history where project_id='P1'") == '1')
expect_ok('same costing file again changes nothing', 'c1', f"select apply_costing('P1','cost.xlsx','{'d'*64}',{j(COST)});", '"duplicate": true')
expect_refused('planner cannot apply costing', 'pl', f"select apply_costing('P1','cost.xlsx','{'e'*64}',{j(COST)});")

BASE = [{'id': 'A3', 'name': 'Blockwork', 'cls': 'CON', 'uom': 'm2', 'qty': 300, 'budget_mh': 600, 'bs': '2026-10-01', 'bf': '2026-10-31'},
        {'id': 'A1', 'name': 'Concrete (renamed)'}]
expect_ok('planner loads a baseline', 'pl', f"select import_baseline('P1','p6.xlsx','{'f'*64}',{j(BASE)});", '"upserted": 2')
check('project dates follow the imported activities', admin("select start_date||'/'||finish_date from projects where id='P1'") == '2026-10-01/2026-10-31')
check('baseline upserts keep existing quantities', admin("select name||'/'||qty from activities where project_id='P1' and id='A1'") == 'Concrete (renamed)/1000')
expect_refused('baseline with a missing name is refused as a whole', 'pl', f"select import_baseline('P1','p6.xlsx','{'g'*64}',{j([{'id':'A9','name':''},{'id':'A10','name':'ok'}])});", 'nothing was imported')
check('...and nothing was imported', admin("select count(*) from activities where project_id='P1' and id in ('A9','A10')") == '0')
expect_refused('cost engineer cannot load a baseline', 'c1', f"select import_baseline('P1','p6.xlsx','{'h'*64}',{j(BASE)});", 'only planning')
expect_refused('nobody can write import batches directly', 'sa', "insert into import_batches (project_id, kind) values ('P1','invoices');")

# ------------------------------------------------------------------ backup and migration
out = expect_ok('project manager exports a project backup', 'pm', "select export_project('P1');")
r = json.loads(out.splitlines()[-1]) if out else {}
check('backup holds reports, lines, audit, invoices, batches',
      len(r.get('dprs', [])) == 5 and len(r.get('dpr_lines', [])) == 5 and len(r.get('invoices', [])) == 2 and len(r.get('import_batches', [])) == 5 and len(r.get('dpr_audit', [])) > 8,
      json.dumps({k: len(v) for k, v in r.items() if isinstance(v, list)}))
expect_refused('cannot export a project outside access', 'f1', "select export_project('P2');")

MIG = {'project_id': 'P1', 'file': 'browser-backup.json', 'hash': 'm' * 64, 'dprs': [
    {'id': 'DPR-0007', 'report_date': '2026-08-20', 'foreman': 'User F1', 'foreman_email': 'F1@test.local', 'status': 'Approved',
     'lines': [{'activity_id': 'A1', 'qty': 30, 'labour': [{'cat': 'Carpenter', 'count': 6, 'reg': 8, 'ot': 0}]}],
     'audit': [{'action': 'Submitted', 'who': 'User F1', 'at': '2026-08-20T17:00:00+03:00'}, {'action': 'Approved', 'who': 'User PM', 'at': '2026-08-21T09:00:00+03:00'}]},
    {'id': 'DPR-OLD1', 'report_date': '2026-09-01', 'foreman': 'User F1', 'status': 'Draft', 'lines': [{'activity_id': 'A1', 'qty': 1}]},
    {'id': 'DPR-0008', 'report_date': '2026-08-21', 'foreman': 'User F1', 'status': 'Submitted', 'lines': [{'activity_id': 'NOPE', 'qty': 1}]},
    {'id': 'DPR-0009', 'report_date': '2026-09-10', 'foreman': 'User F1', 'status': 'Approved', 'lines': [{'activity_id': 'A1', 'qty': 1}]},
    {'id': 'DPR-0010', 'report_date': '2026-08-22', 'foreman': 'User F1', 'status': 'Done', 'lines': [{'activity_id': 'A1', 'qty': 1}]}]}
expect_refused('only the super admin can migrate', 'pm', f"select migrate_dprs({j(MIG)});", 'super admin')
out = expect_ok('super admin migrates browser reports', 'sa', f"select migrate_dprs({j(MIG)});")
r = json.loads(out.splitlines()[-1]) if out else {}
check('new report created, existing one skipped, bad one refused', r.get('created') == 1 and r.get('skipped_existing') == 1 and len(r.get('refused', [])) == 3, out)
check('existing server report not overwritten', admin("select status from dprs where id='DPR-OLD1'") == 'Approved')
check('migrated report keeps status, foreman link and history',
      admin(f"select status||'/'||(foreman_id='{U['f1']}')||'/'||(select count(*) from dpr_audit where dpr_id='DPR-0007') from dprs where id='DPR-0007'") == 'Approved/true/3')
check('migrated audit chain verifies', admin("select dpr_audit_verify('DPR-0007') and exists (select 1 from dpr_audit where dpr_id='DPR-0007')") == 't')
expect_ok('running the same migration again changes nothing', 'sa', f"select migrate_dprs({j(MIG)});", '"duplicate": true')
out = expect_ok('new reports continue after migrated numbers', 'f1', f"select dpr_save({j({'project_id':'P1','report_date':'2026-09-14','lines':LINE})})->>'id';")
check('...no clash with migrated IDs', out.strip() not in ('DPR-00007', 'DPR-0007') and out.strip() > 'DPR-00007', out)

# ------------------------------------------------------------------ deleting a project with reports
expect_refused('a project with an approved report cannot be deleted', 'sa', "delete from projects where id='P1';")
check('...project still there', admin("select count(*) from projects where id='P1'") == '1')

# ------------------------------------------------------------------ undo and redo
counts = admin("select (select count(*) from dprs)||'/'||(select count(*) from dpr_lines)||'/'||(select count(*) from dpr_audit)||'/'||(select count(*) from invoices)")
rc, out, err = psql(None, file=find('schema-rollback-v4.sql'))
check('rollback script runs', rc == 0, err)
check('rollback keeps every report, line, audit entry and invoice', admin("select (select count(*) from dprs)||'/'||(select count(*) from dpr_lines)||'/'||(select count(*) from dpr_audit)||'/'||(select count(*) from invoices)") == counts, counts)
rc, out, err = psql(None, file=find('schema-update-v4.sql'))
check('v4 can be applied again after a rollback', rc == 0, err)
check('untampered chains still verify after rollback and re-apply', admin("select bool_and(dpr_audit_verify(id)) from dprs where id<>'" + D1 + "'") == 't')

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} checks passed')
json.dump({'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v4_results.json'), 'w'), indent=1)
try: os.remove(os.path.join(HERE, '.t.sql'))
except OSError: pass
if '--keep' not in sys.argv:
    subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database {DBN}'], capture_output=True)
sys.exit(0 if passed == len(results) else 1)
