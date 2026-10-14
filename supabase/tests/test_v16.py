#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v16 (roles, rights and access, controlled by the super admin):
nothing changes until a right is changed (every permission helper gives the v3.6 answer for every test person),
only a super admin changes rights, super admins cannot be limited, foremen never see cost figures, role rights,
person exceptions, positions, screens, custom roles made from a template, all projects, every action that reads the
rights, the history that cannot be changed, reads, and the rollback. Usage: python3 test_v16.py"""
import json, os, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v16_test'
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
    return {'t': 'true', 'f': 'false'}.get(out, out)
q = admin
ROLES = {'sa': 'sa', 'sa2': 'sa', 'ex': 'exec', 'rm': 'rm', 'pf': 'pf', 'hd': 'pm', 'cc': 'costing', 'pl': 'plan', 'pl2': 'plan',
         'co': 'costing', 'pm': 'pm', 'sm': 'sm', 'en': 'eng', 'fo': 'foreman', 'ro': 'ro', 'rp': 'plan', 'nx': 'plan'}
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
def call(who, fn, p):
    rc, out, err = run_as(who, f"select {fn}({lit(p)});")
    return rc, (json.loads(out.splitlines()[-1]) if rc == 0 and out else None), err
def rs(who, action, **kw): p = {'action': action}; p.update(kw); return call(who, 'rights_save', p)
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
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 16)]:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin(f"insert into pcc_designations (user_id, designation) values ('{U['hd']}','head'), ('{U['cc']}','coordinator')")
admin("insert into regions values ('R1','Western',null), ('R2','Central',null); insert into projects (id, name, short, region, value_m) values ('P1','One','P1','R1',100), ('P2','Two','P2','R2',50), ('P3','Three','P3','R2',20);")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['hd', 'cc', 'pl', 'co', 'pm', 'sm', 'en', 'fo', 'ro', 'rp']) + f", ('{U['pl2']}','P2')")
admin(f"insert into region_access values ('{U['rm']}','R1'), ('{U['pf']}','R2')")
admin(f"insert into release_approvers (region_id, user_id) values ('R1','{U['rp']}')")
admin(f"insert into approval_matrix (project_id, kind, from_user, to_user) values ('P1','fm','{U['fo']}','{U['en']}'), ('P1','eng','{U['en']}','{U['sm']}')")
admin("insert into activities (id, project_id, name, qty, budget_mh) values ('A1','P1','Concrete',1000,2000), ('A2','P1','Rebar',500,800)")

# ------------------------------------------------------------------ the answers of every permission helper, before v16
def matrix():
    out = {}
    for who in U:
        sub = f"select set_config('request.jwt.claim.sub', '{U[who]}', true) \\g /dev/null\n"
        exprs = []
        for p in ('P1', 'P2', 'P3'):
            exprs += [f"can_see('{p}')", f"user_sees('{U[who]}','{p}')", f"can_plan('{p}')", f"can_cost('{p}')", f"can_edit_dpr('{p}')", f"can_approve('{p}')",
                      f"pt_issue_editor('{U[who]}','{p}')", f"pt_lc_approver('{U[who]}','{p}')", f"pt_rel_approver('{U[who]}','{p}')", f"pt_rel_decider('{U[who]}','{p}')",
                      f"pt_sched_keeper('{U[who]}','{p}')", f"pt_lc_boss('{U[who]}','{p}',3)", f"pt_lc_boss('{U[who]}','{p}',8)"]
            exprs += [f"pt_doc_can('{U[who]}','{p}','{b}',{w})" for b in ('C01', 'P01', 'K01') for w in ('false', 'true')]
        exprs += ["pt_money_ok()", f"pt_can_register('{U[who]}')"] + [f"pt_release_preparer('{U[who]}','{k}')" for k in ('planning', 'client', 'cost')] \
                 + [f"pt_release_staff('{U[who]}','{k}')" for k in ('planning', 'client', 'cost')]
        with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
            f.write("begin;\n" + sub + "select concat_ws(',', " + ", ".join(f"coalesce(({e})::text,'null')" for e in exprs) + ");\ncommit;\n"); path = f.name
        rc, o, err = psql(file=path); os.unlink(path)
        out[who] = o if rc == 0 else 'ERR ' + err
    return out
before = matrix()
check('the v3.6 answers were collected for every test person', all(not v.startswith('ERR') for v in before.values()), [k for k, v in before.items() if v.startswith('ERR')])

for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v16.sql'))
    check(f'v16 loads (run {i})', rc == 0, err)
SETUP = "select (select count(*) from pg_proc where proname in ('rights_save','pt_right','people_access','pt_rights')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('app_roles','role_rights','user_rights','screen_rights'))"
check('the setup check counts 8', q(SETUP) == '8', q(SETUP))
after = matrix()
diff = [k for k in U if before[k] != after[k]]
check('nothing changes until a right is changed: every helper gives the v3.6 answer, for every test person (17 people x 89 answers)', not diff, diff)
check('seventeen rights and twenty-one screens are known', q("select array_length(pt_rights(),1) || '/' || array_length(pt_screens(),1)") == '17/21')

# ------------------------------------------------------------------ only a super admin
for who in ('pm', 'hd', 'ex', 'pl'):
    no_(f'{who}: only a super admin changes rights', rs(who, 'role_right', role_key='pm', right_key='money.view', allow=False), 'only a super admin')
no_('the anonymous visitor cannot call it', (lambda r: (r.returncode, None, r.stderr))(subprocess.run(PG + ['-d', DBN, '-c', f"begin; set local role anon; select rights_save({lit({'action': 'role_right'})}); commit;"], capture_output=True, text=True)), 'permission denied')
no_('a super admin cannot be limited (role)', rs('sa', 'role_right', role_key='sa', right_key='money.view', allow=False), 'super admin always')
no_('a super admin cannot be limited (person)', rs('sa', 'user_right', user_id=U['sa2'], right_key='money.view', allow=False), 'super admin always')
no_('foremen never see cost and billing figures (role)', rs('sa', 'role_right', role_key='foreman', right_key='money.view', allow=True), 'foremen never')
no_('foremen never see cost and billing figures (person)', rs('sa', 'user_right', user_id=U['fo'], right_key='money.view', allow=True), 'foremen never')
admin("insert into role_rights (role_key, right_key, allow) values ('foreman','money.view',true)")
check('...even a row written from the database console does not give it', one('fo', 'select pt_money_ok()') == 'false')
admin("delete from role_rights")
no_('an unknown right is refused', rs('sa', 'role_right', role_key='pm', right_key='money.steal', allow=True), 'unknown right')
no_('an unknown role is refused', rs('sa', 'role_right', role_key='boss', right_key='money.view', allow=True), 'unknown role')
no_('an unknown screen is refused', rs('sa', 'screen', role_key='pm', view_key='nope', visible=True), 'unknown screen')
no_('Administration cannot be given to other roles', rs('sa', 'screen', role_key='pm', view_key='admin', visible=True), 'unknown screen')
no_('allow must be true, false or empty', rs('sa', 'role_right', role_key='pm', right_key='money.view', allow='yes'), 'true, false or empty')
check('...and nothing was kept from refused changes', q("select (select count(*) from role_rights)+(select count(*) from user_rights)+(select count(*) from screen_rights)+(select count(*) from rights_audit)") == '0')
rc, out, err = run_as('sa', "insert into role_rights (role_key, right_key, allow) values ('pm','money.view',false);")
check('rights cannot be written around rights_save, even by a super admin', rc != 0, err)

# ------------------------------------------------------------------ role rights
M0 = dict(project_id='P1', kind='cost', period_type='month', period='2026-08')
CF = {'budget_rev0': 10000000, 'actual': 4200000, 'commitment': 1500000, 'ftc': 6100000}
ok_('a role right is removed: costing engineers no longer prepare cost reports', rs('sa', 'role_right', role_key='costing', right_key='report.cost.prepare', allow=False))
no_('...the costing engineer is refused by the server', call('co', 'release_act', dict(M0, action='save', figures=CF)), 'only a costing engineer')
check('...the costing coordinator keeps it through the position', q(f"select pt_release_preparer('{U['cc']}','cost')") == 'true')
ok_('a person exception gives it back to one costing engineer', rs('sa', 'user_right', user_id=U['co'], right_key='report.cost.prepare', allow=True))
ok_('...who can prepare again', call('co', 'release_act', dict(M0, action='save', figures=CF)), lambda r: r['status'] == 'Draft')
ok_('a role right is given: project managers may load baselines', rs('sa', 'role_right', role_key='pm', right_key='planning.manage', allow=True))
check('...can_plan is true for the project manager on his project only', one('pm', "select can_plan('P1')") == 'true' and one('pm', "select can_plan('P2')") == 'false')
check('...and he may set the internal weightage', call('pm', 'phase_setup_save', {'project_id': 'P1', 'weights': {'GEN': 10, 'DES': 10, 'MAT': 20, 'CON': 40, 'INS': 10, 'TC': 5, 'CLO': 5}})[0] == 0)
ok_('a person exception removes it from one person, and wins over the role', rs('sa', 'user_right', user_id=U['pm'], right_key='planning.manage', allow=False))
check('...can_plan is false again for him', one('pm', "select can_plan('P1')") == 'false')
ok_('setting the exception back to "as the role" removes it', rs('sa', 'user_right', user_id=U['pm'], right_key='planning.manage', allow=None))
check('...and the role right applies again', one('pm', "select can_plan('P1')") == 'true' and q("select count(*) from user_rights where user_id='%s'" % U['pm']) == '0')
ok_('a role right back to the default removes the setting', rs('sa', 'role_right', role_key='pm', right_key='planning.manage', allow=None))
check('...can_plan follows today\'s rule again', one('pm', "select can_plan('P1')") == 'false' and q("select count(*) from role_rights where role_key='pm'") == '0')

ok_('cost figures given to site engineers', rs('sa', 'role_right', role_key='eng', right_key='money.view', allow=True))
check('...a site engineer now reads invoices and the cost logs (the read rules follow the right)', one('en', 'select pt_money_ok()') == 'true')
check('...and the Contract row of the document rack', q(f"select pt_doc_can('{U['en']}','P1','C01',false)") == 'true')
check('...a site manager still does not', one('sm', 'select pt_money_ok()') == 'false' and q(f"select pt_doc_can('{U['sm']}','P1','C01',false)") == 'false')
ok_('cost figures removed from executive managers', rs('sa', 'role_right', role_key='exec', right_key='money.view', allow=False))
check('...an executive manager no longer sees them', one('ex', 'select pt_money_ok()') == 'false')
rs('sa', 'role_right', role_key='exec', right_key='money.view', allow=None); rs('sa', 'role_right', role_key='eng', right_key='money.view', allow=None)

# daily reports
LINE = [{'activity_id': 'A1', 'qty': 5, 'labour': [{'cat': 'Carpenter', 'count': 2, 'reg': 8, 'ot': 0}], 'subs': [], 'equip': []}]
ok_('daily reports removed from one foreman', rs('sa', 'user_right', user_id=U['fo'], right_key='dpr.create', allow=False))
no_('...he cannot write a report', call('fo', 'dpr_save', {'project_id': 'P1', 'report_date': '2026-09-10', 'lines': LINE}), 'cannot write daily reports')
rs('sa', 'user_right', user_id=U['fo'], right_key='dpr.create', allow=None)
D1 = ok_('...back to "as the role", he writes and submits it', call('fo', 'dpr_save', {'project_id': 'P1', 'report_date': '2026-09-10', 'lines': LINE, 'submit': True}), lambda r: r['status'] == 'Submitted')
ok_('daily reports given to site managers', rs('sa', 'role_right', role_key='sm', right_key='dpr.create', allow=True))
ok_('...a site manager writes a report for the foreman', call('sm', 'dpr_save', {'project_id': 'P1', 'report_date': '2026-09-11', 'lines': LINE, 'foreman_id': U['fo']}), lambda r: r['status'] == 'Draft')
ok_('approving any daily report removed from project managers', rs('sa', 'role_right', role_key='pm', right_key='dpr.approve', allow=False))
rc, out, err = run_as('pm', f"select dpr_act('{D1['id']}', 'review', null, 0, null);")
check('...the project manager can no longer review a report assigned to a site engineer', rc != 0 and 'not the reviewer' in err, err)
rc, out, err = run_as('en', f"select dpr_act('{D1['id']}', 'review', null, 0, null);")
check('...the assigned site engineer still can', rc == 0, err)
rs('sa', 'role_right', role_key='pm', right_key='dpr.approve', allow=None)
rc, out, err = run_as('pm', f"select dpr_act('{D1['id']}', 'approve', null, 0, null);")
check('...back to the default, the project manager approves it', rc == 0, err)

# positions
ok_('internal report approval removed from a person who is the regional approver', rs('sa', 'user_right', user_id=U['rp'], right_key='report.internal.approve', allow=False))
check('...the regional planning section manager no longer approves', q(f"select pt_rel_approver('{U['rp']}','P1')") == 'false')
rs('sa', 'user_right', user_id=U['rp'], right_key='report.internal.approve', allow=None)
check('...back to "as the role", the position applies again', q(f"select pt_rel_approver('{U['rp']}','P1')") == 'true')
ok_('a role setting does not remove a position: project managers without cost report approval', rs('sa', 'role_right', role_key='pm', right_key='report.cost.approve', allow=False))
check('...the Head (a project manager) keeps it', q(f"select pt_cost_approver('{U['hd']}')") == 'true')
rs('sa', 'role_right', role_key='pm', right_key='report.cost.approve', allow=None)
ok_('internal report approval given to planning engineers', rs('sa', 'role_right', role_key='plan', right_key='report.internal.approve', allow=True))
check('...for the projects in their access only', q(f"select pt_rel_approver('{U['pl']}','P1')") == 'true' and q(f"select pt_rel_approver('{U['pl']}','P2')") == 'false')
rs('sa', 'role_right', role_key='plan', right_key='report.internal.approve', allow=None)
ok_('the issue review given to one costing engineer', rs('sa', 'user_right', user_id=U['co'], right_key='issues.review', allow=True))
ok_('tender registration given to the planning role', rs('sa', 'role_right', role_key='plan', right_key='tender.register', allow=True))
check('...pt_can_register follows', q(f"select pt_can_register('{U['pl']}')") == 'true' and q(f"select pt_can_register('{U['co']}')") == 'false')
rs('sa', 'role_right', role_key='plan', right_key='tender.register', allow=None)
ok_('the Planning row of the document rack given to site managers', rs('sa', 'role_right', role_key='sm', right_key='docs.planning', allow=True))
check('...a site manager keeps that row, not the others', q(f"select pt_doc_can('{U['sm']}','P1','P01',true)") == 'true' and q(f"select pt_doc_can('{U['sm']}','P1','K01',true)") == 'false')
rs('sa', 'role_right', role_key='sm', right_key='docs.planning', allow=None)
ok_('the change order log upload removed from the costing coordinator, by person', rs('sa', 'user_right', user_id=U['cc'], right_key='logs.upload', allow=False))
no_('...the server refuses the upload', call('cc', 'log_import', {'project_id': 'P1', 'kind': 'volog', 'period': '2026-08', 'rows': []}), 'only a costing engineer')
ok_('lifecycle approval removed from project managers', rs('sa', 'role_right', role_key='pm', right_key='lifecycle.approve', allow=False))
check('...stages 6 to 12 are no longer theirs; stages 1 to 5 stay with the Head', q(f"select pt_lc_boss('{U['pm']}','P1',8)") == 'false' and q(f"select pt_lc_boss('{U['hd']}','P1',3)") == 'true')
rs('sa', 'role_right', role_key='pm', right_key='lifecycle.approve', allow=None)

# ------------------------------------------------------------------ screens
ok_('a screen is hidden for a role', rs('sa', 'screen', role_key='sm', view_key='cdash', visible=False))
ok_('...and shown again', rs('sa', 'screen', role_key='sm', view_key='cdash', visible=None))
check('...the setting is gone', q("select count(*) from screen_rights") == '0')
rs('sa', 'screen', role_key='plan', view_key='eva', visible=False)

# ------------------------------------------------------------------ custom roles
no_('a custom role needs a name of 2 to 60 characters', rs('sa', 'role_create', name='x', base_role='plan'), '2 to 60')
no_('a custom role is not made from the super admin', rs('sa', 'role_create', name='Deputy admin', base_role='sa'), 'any role except super admin')
rs('sa', 'role_right', role_key='plan', right_key='issues.review', allow=True)
cr = ok_('a custom role is made from Planning Engineer', rs('sa', 'role_create', name='Planning Section Manager', base_role='plan'), lambda r: r['key'] == 'c_planning_section_manager' and r['base_role'] == 'plan')
check('...it starts with the current settings of Planning Engineer (rights and screens)', q("select allow from role_rights where role_key='c_planning_section_manager' and right_key='issues.review'") == 'true'
      and q("select visible from screen_rights where role_key='c_planning_section_manager' and view_key='eva'") == 'false')
rs('sa', 'role_right', role_key='plan', right_key='issues.review', allow=None)
no_('names are unique, whatever the capitals', rs('sa', 'role_create', name='planning section MANAGER', base_role='pm'), 'already exists')
ok_('it gets its own right: approve internal and client reports', rs('sa', 'role_right', role_key='c_planning_section_manager', right_key='report.internal.approve', allow=True))
no_('a person cannot be given a custom role made from another role', call('sa', 'admin_save_person', {'email': 'nx@t.local', 'name': 'User NX', 'role': 'pm', 'custom_role': 'c_planning_section_manager', 'projects': ['P2']}), 'made from the chosen role')
no_('...nor an unknown one', call('sa', 'admin_save_person', {'email': 'nx@t.local', 'name': 'User NX', 'role': 'plan', 'custom_role': 'c_nobody', 'projects': ['P2']}), 'switched on')
ok_('a planning engineer is given the custom role, on P2', call('sa', 'admin_save_person', {'email': 'nx@t.local', 'name': 'User NX', 'role': 'plan', 'custom_role': 'c_planning_section_manager', 'projects': ['P2']}))
check('...he approves internal reports of P2, not of P1', q(f"select pt_rel_approver('{U['nx']}','P2')") == 'true' and q(f"select pt_rel_approver('{U['nx']}','P1')") == 'false')
check('...he keeps every built-in rule of a planning engineer (prepares internal reports, loads baselines on P2)', q(f"select pt_release_preparer('{U['nx']}','planning')") == 'true' and one('nx', "select can_plan('P2')") == 'true')
check('...and the planning engineer role itself is unchanged', q(f"select pt_rel_approver('{U['pl2']}','P2')") == 'false')
no_('a role still given to someone cannot be switched off', rs('sa', 'role_update', key='c_planning_section_manager', active=False), 'still have this role')
ok_('it can be renamed', rs('sa', 'role_update', key='c_planning_section_manager', name='Planning Section Mgr'), lambda r: r['name'] == 'Planning Section Mgr')
ok_('once nobody has it...', call('sa', 'admin_save_person', {'email': 'nx@t.local', 'name': 'User NX', 'role': 'plan', 'projects': ['P2']}))
ok_('...it can be switched off', rs('sa', 'role_update', key='c_planning_section_manager', active=False), lambda r: r['active'] is False)
no_('a switched-off role cannot be given', call('sa', 'admin_save_person', {'email': 'nx@t.local', 'name': 'User NX', 'role': 'plan', 'custom_role': 'c_planning_section_manager', 'projects': ['P2']}), 'switched on')
admin(f"update profiles set custom_role='c_planning_section_manager' where id='{U['nx']}'")
check('a switched-off role gives nothing: the person falls back to the role he was made from', q(f"select pt_rel_approver('{U['nx']}','P2')") == 'false')
admin(f"update profiles set custom_role=null where id='{U['nx']}'")

# ------------------------------------------------------------------ access: all projects, any role
ok_('a planning engineer is given All projects', call('sa', 'admin_save_person', {'email': 'pl2@t.local', 'name': 'User PL2', 'role': 'plan', 'all_projects': True}))
check('...he sees every project, including one added later', one('pl2', "select count(*) from projects") == '3' and (admin("insert into projects (id, name, short, region) values ('P4','Four','P4','R1')") or True) and one('pl2', "select can_see('P4')") == 'true')
check('...and the people directory shows it', one('sa', f"select all_projects from people_access() where id='{U['pl2']}'") == 'true')
ok_('a project manager can be given a whole region', call('sa', 'admin_save_person', {'email': 'pm@t.local', 'name': 'User PM', 'role': 'pm', 'regions': ['R2'], 'projects': ['P1']}))
check('...he sees P1 and both Central projects', one('pm', "select string_agg(id, ',' order by id) from projects") == 'P1,P2,P3')
ok_('All projects is not kept for an executive manager, who already sees everything', call('sa', 'admin_save_person', {'email': 'ex@t.local', 'name': 'User EX', 'role': 'exec', 'all_projects': True}))
check('...the flag stays off', q(f"select all_projects from profiles where id='{U['ex']}'") == 'false')
no_('a site role needs at least one region, one project or All projects', call('sa', 'admin_save_person', {'email': 'en@t.local', 'name': 'User EN', 'role': 'eng'}), 'at least one region')
check('people_access: a super admin sees everyone, others only themselves', one('sa', "select count(*) from people_access()") == str(len(U)) and one('pl', "select count(*) from people_access()") == '1')

# ------------------------------------------------------------------ reads and the history
check('everyone signed in reads custom roles, role rights and screens', one('fo', "select count(*) from app_roles") == '1' and one('fo', "select count(*) from screen_rights") != '0')
check('a person reads their own exceptions only', one('co', "select count(*) from user_rights") == '2' and one('pl', "select count(*) from user_rights") == '0')
check('only super admins read the history', one('pm', "select count(*) from rights_audit") == '0' and int(one('sa', "select count(*) from rights_audit")) > 20)
check('every change is in the history with who made it', q("select count(*) from rights_audit where by_name='User SA'") == q("select count(*) from rights_audit"))
check('the history says what changed', q("select action||'|'||target||'|'||right_key||'|'||value from rights_audit where action='Person exception' order by id limit 1") == 'Person exception|User CO|report.cost.prepare|true')
for sql, what in (("update rights_audit set value='x'", 'changed'), ("delete from rights_audit", 'deleted'), ("truncate rights_audit", 'emptied')):
    rc, out, err = psql(sql); check(f'the history cannot be {what}, even from the database console', rc != 0, err)

# ------------------------------------------------------------------ rollback
admin("delete from user_rights; delete from role_rights; delete from screen_rights")
admin(f"update profiles set all_projects=false where id='{U['pl2']}'; update profiles set custom_role=null")
admin(f"delete from project_access where user_id in ('{U['nx']}','{U['pl2']}'); insert into project_access values ('{U['pl2']}','P2')")
admin(f"delete from project_access where user_id='{U['pm']}'; delete from region_access where user_id='{U['pm']}'; insert into project_access values ('{U['pm']}','P1'); delete from projects where id='P4'")
rs('sa', 'role_right', role_key='pm', right_key='planning.manage', allow=True)
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v16.sql'))
    check(f'the rollback runs (run {i})', rc == 0, err)
check('...back to the v3.6 rules: a role right is no longer read', one('pm', "select can_plan('P1')") == 'false')
check('...the tables and the history are kept', q("select count(*) from role_rights") == '1' and int(q("select count(*) from rights_audit")) > 20)
check('...and rights_save is gone', q("select count(*) from pg_proc where proname in ('rights_save','pt_right','people_access')") == '0')
back = matrix()
d2 = [k for k in U if before[k] != back[k]]
check('...every helper gives the v3.6 answer again', not d2, d2)
rc, out, err = psql(file=find('schema-update-v16.sql'))
check('v16 can be applied again after the rollback', rc == 0 and q(SETUP) == '8', err)
check('...and the kept settings apply again', one('pm', "select can_plan('P1')") == 'true')

json.dump(results, open(os.path.join(HERE, 'test_v16_results.json'), 'w'), indent=1)
print(f"\n{sum(r['pass'] for r in results)}/{len(results)} passed")
