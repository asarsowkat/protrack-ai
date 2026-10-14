#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v17 (Material Tracking): who may set it up and keep it, the baseline
load and its checks, the milestone mapping, choosing the monitored materials, PO number, supplier and remarks with
their history, manual fields never overwritten by a new baseline or an updated schedule, the updated schedule keeping
the material codes, reads, the new right in Roles and rights, and the rollback. Usage: python3 test_v17.py
Earlier: v16 (roles, rights and access, controlled by the super admin):
nothing changes until a right is changed (every permission helper gives the v3.6 answer for every test person),
only a super admin changes rights, super admins cannot be limited, foremen never see cost figures, role rights,
person exceptions, positions, screens, custom roles made from a template, all projects, every action that reads the
rights, the history that cannot be changed, reads, and the rollback. Usage: python3 test_v16.py"""
import json, os, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v17_test'
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
U = {k: f'00000000-0000-0000-0000-0000000005{i:02d}' for i, k in enumerate(ROLES, start=1)}
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
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 17)]:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin(f"insert into pcc_designations (user_id, designation) values ('{U['hd']}','head'), ('{U['cc']}','coordinator')")
admin("insert into regions values ('R1','Western',null), ('R2','Central',null); insert into projects (id, name, short, region, value_m) values ('P1','One','P1','R1',100), ('P2','Two','P2','R2',50);")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['hd', 'cc', 'pl', 'co', 'pm', 'sm', 'en', 'fo', 'ro', 'rp']) + f", ('{U['pl2']}','P2')")
admin("insert into activities (id, project_id, name, bs, bf) values ('C1','P1','Foundations','2026-08-01','2026-12-31')")

for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v17.sql'))
    check(f'v17 loads (run {i})', rc == 0, err)
SETUP = "select (select count(*) from pg_proc where proname in ('material_setup_save','material_item_save','pt_mat_keeper')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('material_setup','material_acts','material_items','material_audit'))"
check('the setup check counts 7', q(SETUP) == '7', q(SETUP))
check('eighteen rights (the new one: keep material tracking) and twenty-two screens (the new one: Material tracking)',
      q("select array_length(pt_rights(),1) || '/' || array_length(pt_screens(),1) || '/' || ('materials.keep' = any(pt_rights())) || '/' || ('mat' = any(pt_screens()))") == '18/22/true/true')
check('the right goes to planning engineers and, by position, the Head; not to costing engineers or project managers',
      q(f"select pt_mat_keeper('{U['pl']}','P1')") == 'true' and q(f"select pt_mat_keeper('{U['hd']}','P1')") == 'true' and q(f"select pt_mat_keeper('{U['co']}','P1')") == 'false' and q(f"select pt_mat_keeper('{U['pm']}','P1')") == 'false')

# ------------------------------------------------------------------ the baseline load
STAGES = [('PR', 'PR Creation'), ('PO', 'PO Creation'), ('BD', 'Base Design'), ('GAFM', 'GAFM Approval'), ('MFG', 'Manufacturing'), ('FAT', 'FAT'), ('RFS', 'Shipment'), ('DEL', 'Delivery'), ('CIV', 'Installation Readiness')]
MAP = {u: k for k, u in STAGES}
def acts(materials=('GIS Equipment', 'Power Transformer', 'Cable Drum'), extra=None):
    R = []
    for mi, m in enumerate(materials):
        for si, (k, u) in enumerate(STAGES):
            R.append(dict(id=f'M{mi}-{k}', name=f'{m} - {u}', wbs='Procurement', wbs_leaf=f'{m} package', material=m, uact=u,
                          bs=f'2026-{(si % 9) + 1:02d}-01', bf=f'2026-{(si % 9) + 1:02d}-20', pct=0))
    return R + (extra or [])
B = dict(project_id='P1', action='baseline', mat_code='Material Name', uact_code='Unified Activity Name', wbs_filter=['Procurement'], stage_map=MAP,
         file_name='PE-001 baseline.xer', file_hash='b1', data_date='2026-01-01')
no_('a costing engineer cannot set it up', call('co', 'material_setup_save', dict(B, rows=acts())), 'only the people who keep material tracking')
no_('a project manager cannot', call('pm', 'material_setup_save', dict(B, rows=acts())), 'only the people who keep')
no_('a foreman cannot', call('fo', 'material_setup_save', dict(B, rows=acts())), 'only the people who keep')
no_('a planning engineer of another project cannot', call('pl2', 'material_setup_save', dict(B, rows=acts())), 'access')
no_('settings before a baseline are refused', call('pl', 'material_setup_save', dict(project_id='P1', action='settings', stage_map=MAP)), 'load the baseline')
no_('the two activity codes must differ', call('pl', 'material_setup_save', dict(B, uact_code='material name', rows=acts())), 'two different activity codes')
no_('at least one WBS branch', call('pl', 'material_setup_save', dict(B, wbs_filter=[], rows=acts())), 'at least one wbs branch')
no_('an unknown milestone is refused', call('pl', 'material_setup_save', dict(B, stage_map={'FAT': 'XYZ'}, rows=acts())), 'unknown milestone')
no_('an activity without a Material Name is refused', call('pl', 'material_setup_save', dict(B, rows=acts(extra=[dict(id='X1', material='', uact='FAT')]))), 'activities refused')
no_('a wrong date is refused', call('pl', 'material_setup_save', dict(B, rows=acts(extra=[dict(id='X2', material='Bolts', bs='2026-13-45')]))), 'activities refused')
no_('% complete over 100 is refused', call('pl', 'material_setup_save', dict(B, rows=acts(extra=[dict(id='X3', material='Bolts', pct=120)]))), 'activities refused')
no_('a baseline with no material activities is refused', call('pl', 'material_setup_save', dict(B, rows=[])), 'no activity')
check('...and nothing was kept from refused loads', q("select (select count(*) from material_setup)+(select count(*) from material_acts)+(select count(*) from material_items)+(select count(*) from material_audit)") == '0')
r = ok_('the planning engineer loads the baseline: 3 materials x 9 milestone activities', call('pl', 'material_setup_save', dict(B, rows=acts())),
        lambda r: r['activities'] == 27 and r['new_materials'] == 3 and r['monitored'] == 3)
check('one monitoring row per material, monitored by default', q("select string_agg(material||':'||selected, ',' order by material) from material_items") == 'Cable Drum:true,GIS Equipment:true,Power Transformer:true')
check('the set-up is kept: codes, WBS and the mapping', q("select mat_code||'/'||uact_code||'/'||(wbs_filter->>0)||'/'||(stage_map->>'Shipment')||'/'||file_name from material_setup") == 'Material Name/Unified Activity Name/Procurement/RFS/PE-001 baseline.xer')
ok_('the planning engineer chooses which materials are monitored', call('pl', 'material_setup_save', dict(project_id='P1', action='settings', select=['GIS Equipment', 'Power Transformer'])), lambda r: r['monitored'] == 2)
check('...Cable Drum is no longer monitored, and the history says so', q("select selected from material_items where material='Cable Drum'") == 'false' and q("select field||':'||before||'>'||after from material_audit where material='Cable Drum'") == 'Monitored:true>false')
ok_('the mapping can be changed later without loading again', call('pl', 'material_setup_save', dict(project_id='P1', action='settings', stage_map=dict(MAP, **{'Installation Readiness': ''}))))
check('...kept, with the set-up change in the history', q("select stage_map->>'Installation Readiness' from material_setup") == '' and q("select count(*) from material_audit where field='Set-up'") == '1')

# ------------------------------------------------------------------ manual fields
M = dict(project_id='P1', material='GIS Equipment')
ok_('the planning engineer enters the PO number, supplier and remarks', call('pl', 'material_item_save', dict(M, po_number='4500012345', supplier='Siemens Energy', remarks='FAT witnessed by client\nShipment by sea')),
    lambda r: r['changed'] == 3 and r['po_number'] == '4500012345')
check('each field change is in the history with user, date and field', q("select string_agg(field||'='||coalesce(after,''), '|' order by id) from material_audit where material='GIS Equipment'") == 'PO Number=4500012345|Supplier Name=Siemens Energy|Remarks=FAT witnessed by client\nShipment by sea'
      and q("select bool_and(by_name='User PL' and at_time is not null) from material_audit where material='GIS Equipment'") == 'true')
r = ok_('saving the same values again changes nothing', call('pl', 'material_item_save', dict(M, po_number='4500012345')), lambda r: r['changed'] == 0)
ok_('the supplier is changed', call('pl', 'material_item_save', dict(M, supplier='Hitachi Energy')))
check('...the history keeps before and after', q("select before||'>'||after from material_audit where field='Supplier Name' order by id desc limit 1") == 'Siemens Energy>Hitachi Energy')
ok_('only the fields sent are changed', call('pl', 'material_item_save', dict(M, remarks='Shipment by sea')), lambda r: r['po_number'] == '4500012345' and r['supplier'] == 'Hitachi Energy')
no_('a PO number over 60 characters is refused', call('pl', 'material_item_save', dict(M, po_number='9' * 61)), '60 characters')
no_('remarks over 4,000 characters are refused', call('pl', 'material_item_save', dict(M, remarks='x' * 4001)), '4,000')
no_('an unknown material is refused', call('pl', 'material_item_save', dict(M, material='Nothing')), 'unknown material')
no_('a costing engineer cannot edit them', call('co', 'material_item_save', dict(M, po_number='1')), 'only the people who keep')
ok_('the Head of Planning and Cost Control can (position)', call('hd', 'material_item_save', dict(M, remarks='Checked by the Head')))
ok_('a super admin gives the right to one costing engineer', call('sa', 'rights_save', dict(action='user_right', user_id=U['co'], right_key='materials.keep', allow=True)))
ok_('...who can now edit them', call('co', 'material_item_save', dict(M, po_number='4500012346')))
ok_('a super admin removes it from planning engineers (role)', call('sa', 'rights_save', dict(action='role_right', role_key='plan', right_key='materials.keep', allow=False)))
no_('...a planning engineer is refused', call('pl', 'material_item_save', dict(M, po_number='1')), 'only the people who keep')
call('sa', 'rights_save', dict(action='role_right', role_key='plan', right_key='materials.keep', allow=None))
no_('foremen never get it either way: a foreman cannot edit', call('fo', 'material_item_save', dict(M, po_number='1')), 'only the people who keep')
rc, out, err = run_as('pl', "update material_items set po_number='hack';")
check('the fields cannot be written around the functions', rc != 0 or q("select po_number from material_items where material='GIS Equipment'") == '4500012346', err)

# ------------------------------------------------------------------ a new baseline and an updated schedule never overwrite manual data
ok_('a revised baseline is loaded: a new material, one activity less', call('pl', 'material_setup_save', dict(B, file_name='rev1.xer', file_hash='b2', rows=[a for a in acts(('GIS Equipment', 'Power Transformer', 'Cable Drum', 'Shunt Reactor')) if a['id'] != 'M0-CIV'])),
    lambda r: r['activities'] == 35 and r['new_materials'] == 1)
check('...PO number, supplier and remarks are kept', q("select po_number||'/'||supplier||'/'||remarks from material_items where material='GIS Equipment'") == '4500012346/Hitachi Energy/Checked by the Head')
check('...Cable Drum stays unmonitored; the new Shunt Reactor is monitored', q("select string_agg(material||':'||selected, ',' order by material) from material_items") == 'Cable Drum:false,GIS Equipment:true,Power Transformer:true,Shunt Reactor:true')
check('...the removed activity is gone from the material activities', q("select count(*) from material_acts where act_id='M0-CIV'") == '0')
UP = dict(project_id='P1', data_date='2026-06-30', weightage='client', file_name='update Jun.xer', file_hash='u1', weight_basis='Price weight',
          rows=[dict(id='C1', name='Foundations', wbs='Construction', w=100, bs='2026-08-01', bf='2026-12-31', pct=0),
                dict(id='M0-MFG', name='GIS - Manufacturing', wbs='Procurement', wbs_leaf='GIS Equipment package', w=0, bs='2026-05-01', bf='2026-05-20', pct=60, **{'as': '2026-05-03'}, es='2026-05-03', ef='2026-07-10', mat='GIS Equipment', uact='Manufacturing')])
ok_('an updated schedule is loaded (v15 upload)', call('pl', 'schedule_update_commit', UP))
check('...it keeps the early start, Material Name, Unified Activity Name and own WBS of each activity', q("select es||'/'||mat||'/'||uact||'/'||wbs_leaf||'/'||pct from schedule_update_rows where act_id='M0-MFG'") == '2026-05-03/GIS Equipment/Manufacturing/GIS Equipment package/60')
check('...and never touches the manual fields', q("select po_number||'/'||supplier from material_items where material='GIS Equipment'") == '4500012346/Hitachi Energy')

# ------------------------------------------------------------------ reads and the history
check('everyone with access to the project reads the tracking (a foreman too)', one('fo', "select count(*) from material_items") == '4' and one('fo', "select count(*) from material_acts") == '35')
check('people without access to the project read nothing', one('pl2', "select (select count(*) from material_items)+(select count(*) from material_acts)+(select count(*) from material_audit)") == '0')
for sql, what in (("update material_audit set after='x'", 'changed'), ("delete from material_audit", 'deleted'), ("truncate material_audit", 'emptied')):
    rc, out, err = psql(sql); check(f'the history cannot be {what}, even from the database console', rc != 0, err)
check('Roles and rights accepts the new right and screen', call('sa', 'rights_save', dict(action='screen', role_key='sm', view_key='mat', visible=True))[0] == 0)
no_('foremen still never see cost figures (unchanged)', call('sa', 'rights_save', dict(action='role_right', role_key='foreman', right_key='money.view', allow=True)), 'foremen never')

# ------------------------------------------------------------------ rollback
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v17.sql'))
    check(f'the rollback runs (run {i})', rc == 0, err)
check('...the functions are gone, the tables and history are kept', q("select count(*) from pg_proc where proname in ('material_setup_save','material_item_save')") == '0' and q("select count(*) from material_items") == '4' and int(q("select count(*) from material_audit")) > 10)
check('...the v3.7 rights and screens are back (17 and 21)', q("select array_length(pt_rights(),1) || '/' || array_length(pt_screens(),1)") == '17/21')
ok_('...an updated schedule still loads (the v3.7 upload)', call('pl', 'schedule_update_commit', dict(UP, file_hash='u2', data_date='2026-07-31')))
rc, out, err = psql(file=find('schema-update-v17.sql'))
check('v17 can be applied again after the rollback', rc == 0 and q(SETUP) == '7', err)
check('...and the kept data is there', q("select po_number from material_items where material='GIS Equipment'") == '4500012346')

json.dump(results, open(os.path.join(HERE, 'test_v17_results.json'), 'w'), indent=1)
print(f"\n{sum(r['pass'] for r in results)}/{len(results)} passed")
