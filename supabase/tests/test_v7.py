#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v7 (Tender register, PE numbers, stages 1 to 5), on a local
PostgreSQL 16 with a Supabase stand-in. Covers: the one-time checklist update keeps ticks and touches only open
stages; designations; PE proposal, duplicates, release and reallocation; who registers, updates, cancels and
reinstates; stage 1 to 5 approval by the Head of Planning and Cost Control; stage 4 due 7 days after signing;
browsers cannot bypass the register; history cannot be edited; rollback keeps every record.
Usage: python3 test_v7.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v7_test'
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

NAMES = ['sa', 'sa2', 'hd', 'c1', 'c2', 'pm', 'ce', 'f1', 'ex', 'hx']
U = {k: f'00000000-0000-0000-0000-0000000000{i:02d}' for i, k in enumerate(NAMES, start=1)}
ROLES = {'sa': 'sa', 'sa2': 'sa', 'hd': 'plan', 'c1': 'costing', 'c2': 'costing', 'pm': 'pm', 'ce': 'costing', 'f1': 'foreman', 'ex': 'exec', 'hx': 'plan'}

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
def call(who, fn, p):
    rc, out, err = run_as(who, f"select {fn}({lit(p) if p is not None else ''});")
    return rc, (json.loads(out.splitlines()[-1]) if rc == 0 and out else None), err
def lc(who, stage, action, project, **kw):
    p = {'project_id': project, 'stage_no': stage, 'action': action}; p.update(kw); return call(who, 'lifecycle_act', p)
def ta(who, action, project=None, note=None, **fields):
    p = {'action': action, 'fields': fields}
    if project: p['project_id'] = project
    if note: p['note'] = note
    return call(who, 'tender_act', p)
def prop(who): return call(who, 'pe_proposal', None)
def ok_(name, res, cond=lambda r: True):
    rc, r, err = res
    try: good = rc == 0 and cond(r)
    except Exception as e: good, err = False, repr(e)
    check(name, good, r if rc == 0 else err); return r
def no_(name, res, msg=None):
    rc, r, err = res; check(name, rc != 0 and (msg is None or msg.lower() in err.lower()), err or r)
def q(sql): return admin(sql)

subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql', 'schema-update-v4.sql',
          'schema-update-v5.sql', 'schema-update-v6.sql']:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin("insert into regions values ('R1','R',null); insert into sectors values ('S1','Sector');"
      "insert into projects (id, name, short, region, status) values ('PE-329','Legacy one','L1','R1','Active'), ('PE-330','Legacy two','L2','R1','Active'), ('EL-001','Other code','EL','R1','Active');")
admin("insert into project_access values " + ",".join(f"('{U[k]}','PE-329')" for k in ['pm', 'ce', 'f1']))

# ---- v6 data that the one-time checklist update must respect
for a in [lc('pm', 1, 'update', 'PE-329', fields={'owner': U['pm']}, ticks=[{'k': 'notice', 'done': True}]),
          lc('pm', 2, 'update', 'PE-329', fields={'owner': U['pm']}, ticks=[{'k': 'number', 'done': True}]),
          lc('pm', 3, 'update', 'PE-329', fields={'owner': U['ce']}, ticks=[{'k': x, 'done': True} for x in ('loa', 'contract', 'terms')]),
          lc('ce', 3, 'submit', 'PE-329'), lc('pm', 3, 'approve', 'PE-329'),
          lc('pm', 4, 'update', 'PE-329', fields={'owner': U['ce']}, ticks=[{'k': x, 'done': True} for x in ('docs', 'scope', 'team')]),
          lc('ce', 4, 'submit', 'PE-329'), lc('pm', 5, 'update', 'PE-329', fields={'due_date': '2026-11-01'})]:
    if a[0]: raise SystemExit('v6 setup failed: ' + a[2])
before3 = q("select deliverables::text from lifecycle_stages where project_id='PE-329' and stage_no=3")
before4 = q("select deliverables::text from lifecycle_stages where project_id='PE-329' and stage_no=4")
before_audit = int(q("select count(*) from lifecycle_audit"))

for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v7.sql'))
    check(f'v7 loads (run {i})', rc == 0, err)

# ------------------------------------------------------------------ one-time checklist update
d1 = json.loads(q("select deliverables from lifecycle_stages where project_id='PE-329' and stage_no=1"))
check('stage 1 in progress takes the new required items', [x['k'] for x in d1 if x.get('req')] == ['te', 'value'], d1)
check('stage 1 keeps the old ticked item, as optional and marked from the old checklist',
      any(x['k'] == 'notice' and x['done'] and not x['req'] and x.get('legacy') for x in d1), d1)
d2 = json.loads(q("select deliverables from lifecycle_stages where project_id='PE-329' and stage_no=2"))
check('stage 2 keeps the tick on the same item (PE number) under its new label',
      any(x['k'] == 'number' and x['done'] and x['label'].startswith('PE number allocated') for x in d2), d2)
check('a complete stage is not touched', q("select deliverables::text from lifecycle_stages where project_id='PE-329' and stage_no=3") == before3)
check('a stage awaiting approval is not touched', q("select deliverables::text from lifecycle_stages where project_id='PE-329' and stage_no=4") == before4)
d5 = json.loads(q("select deliverables from lifecycle_stages where project_id='PE-329' and stage_no=5"))
check('a not-started stage gets exactly the new checklist (9 items, nothing old kept)', len(d5) == 9 and not any(x.get('legacy') for x in d5), d5)
check('its due date is kept', q("select due_date from lifecycle_stages where project_id='PE-329' and stage_no=5") == '2026-11-01')
check('each update is written once to the stage history, even after a second run',
      q("select count(*) from lifecycle_audit where action='Checklist updated'") == '3' and int(q("select count(*) from lifecycle_audit")) == before_audit + 3)
check('no project or stage was removed', q("select count(*) from projects") == '3' and q("select count(*) from lifecycle_stages") == '5')

# ------------------------------------------------------------------ designations
no_('only a super admin gives designations', call('hd', 'pcc_designate', {'user_id': U['hd'], 'designation': 'head', 'on': True}), 'only a super admin')
ok_('the super admin names the Head of Planning and Cost Control', call('sa', 'pcc_designate', {'user_id': U['hd'], 'designation': 'head', 'on': True}), lambda r: r == ['head'])
for k in ('c1', 'c2'): ok_(f'the super admin names costing coordinator {k}', call('sa', 'pcc_designate', {'user_id': U[k], 'designation': 'coordinator', 'on': True}), lambda r: r == ['coordinator'])
call('sa', 'pcc_designate', {'user_id': U['hx'], 'designation': 'head', 'on': True})
no_('an unknown designation is refused', call('sa', 'pcc_designate', {'user_id': U['hd'], 'designation': 'boss', 'on': True}), 'unknown designation')
check('the change log records who was named', q("select count(*) from change_log where text like '%designation given to%'") == '4')
rc, out, err = run_as('f1', "select count(*) from pcc_designations;")
check('signed-in people can see who holds a designation', rc == 0 and out.endswith('4'), out or err)
rc, out, err = run_as(None, "select count(*) from pcc_designations;")
check('a signed-out visitor cannot', rc != 0 or out.endswith('0'), out or err)
no_('nobody writes designations directly', run_as('sa', f"insert into pcc_designations (user_id, designation) values ('{U['ce']}','head');"))

# ------------------------------------------------------------------ PE proposal
no_('a foreman cannot ask for a PE number', prop('f1'), 'only the costing coordinator')
ok_('the proposal follows the highest PE number already used (PE-330 -> PE-331)', prop('c1'), lambda r: r['proposed'] == 'PE-331' and r['released'] == [])

# ------------------------------------------------------------------ register
reg = dict(te_number='te-2231', name='Riyadh substation 132 kV', region='R1', client='SEC', location='Riyadh', expected_value_m='42.5', notified_on='2026-10-01')
no_('a foreman cannot register a project', ta('f1', 'register', **reg), 'only the costing coordinator')
no_('a project manager without the designation cannot either', ta('pm', 'register', **reg), 'only the costing coordinator')
r = ok_('the costing coordinator registers TE-2231 and gets the proposed PE-331, whatever number they send',
        ta('c1', 'register', pe_number='PE-500', **reg),
        lambda r: r['id'] == 'PE-331' and r['pe_number'] == 'PE-331' and r['te_number'] == 'TE-2231' and r['status'] == 'Pre-award' and float(r['expected_value_m']) == 42.5)
check('the coordinator owns stages 1 to 4 from the start', q(f"select string_agg(stage_no::text, ',' order by stage_no) from lifecycle_stages where project_id='PE-331' and owner='{U['c1']}'") == '1,2,3,4')
check('the coordinators and the Head get access; super admins already see everything',
      q("select string_agg(p.name, ',' order by p.name) from project_access a join profiles p on p.id=a.user_id where a.project_id='PE-331'") == 'User C1,User C2,User HD,User HX')
check('the register history shows the registration and the PE allocation', q("select string_agg(action, ',' order by id) from register_audit where project_id='PE-331'") == 'Registered,PE allocated')
no_('the same TE number cannot be registered twice (any case)', ta('c2', 'register', **dict(reg, te_number=' TE-2231 ')), 'already registered')
no_('a TE number is required', ta('c1', 'register', **dict(reg, te_number=' ')), 'enter the te number')
no_('a project name is required', ta('c1', 'register', **dict(reg, te_number='TE-1', name='')), 'enter the project name')
no_('the expected value must be a number', ta('c1', 'register', **dict(reg, te_number='TE-1', expected_value_m='lots')), 'expected value')
no_('a negative expected value is refused', ta('c1', 'register', **dict(reg, te_number='TE-1', expected_value_m='-1')), 'expected value')
no_('an impossible date is refused', ta('c1', 'register', **dict(reg, te_number='TE-1', notified_on='2026-02-30')), 'not a valid date')
no_('an unknown region is refused', ta('c1', 'register', **dict(reg, te_number='TE-1', region='ZZ')), 'unknown region')
ok_('a super admin can choose another PE number', ta('sa', 'register', **dict(reg, te_number='TE-2240', name='Jeddah depot', pe_number='PE-400')), lambda r: r['id'] == 'PE-400')
ok_('the next proposal continues after it (PE-401)', prop('c1'), lambda r: r['proposed'] == 'PE-401')
no_('a PE number already held by a live project is refused, even an old one', ta('sa', 'register', **dict(reg, te_number='TE-2241', pe_number='PE-329')), 'already given')
no_('PE-0400 is the same number as PE-400', ta('sa', 'register', **dict(reg, te_number='TE-2241', pe_number='pe-0400')), 'already given')
no_('a number that is not a PE number is refused', ta('sa', 'register', **dict(reg, te_number='TE-2241', pe_number='XY-12')), 'looks like pe-123')
ok_('pe 77 is written as PE-077', ta('sa', 'register', **dict(reg, te_number='TE-2242', name='Small job', pe_number='pe 77')), lambda r: r['id'] == 'PE-077')

# ------------------------------------------------------------------ the register cannot be bypassed
no_('a browser cannot set a PE number directly, even as super admin', run_as('sa', "update projects set pe_number='PE-999' where id='PE-331';"), 'tender register')
no_('or a TE number', run_as('sa', "update projects set te_number='TE-9' where id='PE-329';"), 'tender register')
no_('or cancel a project by changing its status', run_as('sa', "update projects set status='Cancelled' where id='PE-330';"), 'tender register')
no_('or create a project that carries a TE number', run_as('sa', "insert into projects (id, name, short, te_number) values ('X1','x','x','TE-77');"), 'tender register')
rc, out, err = run_as('sa', "update projects set name='Legacy one (renamed)' where id='PE-329';")
check('ordinary edits by the super admin still work', rc == 0 and q("select name from projects where id='PE-329'") == 'Legacy one (renamed)', err)
rc, out, err = psql("insert into projects (id, name, short, pe_number) values ('PE-331-X','x','x','PE-331');")
check('the database itself refuses a second live project with the same PE number', rc != 0 and 'projects_pe_live_uq' in err, err)
rc, out, err = run_as('sa', "insert into projects (id, name, short) values ('pe-330','x','x');")
check('...including a project typed in by hand as pe-330', rc != 0 and 'projects_pe_live_uq' in err, err)

# ------------------------------------------------------------------ stages 1 to 5: Head of Planning and Cost Control approves
admin(f"insert into project_access values ('{U['pm']}','PE-331'), ('{U['ce']}','PE-331'), ('{U['f1']}','PE-331')")
ok_('the coordinator ticks stage 1 and submits it', lc('c1', 1, 'update', 'PE-331', ticks=[{'k': 'te', 'done': True}, {'k': 'value', 'done': True}]))
ok_('...', lc('c1', 1, 'submit', 'PE-331'), lambda r: r['status'] == 'Awaiting approval')
no_('the project manager cannot approve stage 1', lc('pm', 1, 'approve', 'PE-331'), 'head of planning and cost control')
no_('the coordinator cannot approve their own stage', lc('c1', 1, 'approve', 'PE-331'), 'only the head')
ok_('the Head of Planning and Cost Control approves stage 1', lc('hd', 1, 'approve', 'PE-331'), lambda r: r['status'] == 'Complete' and r['approved_by'] == U['hd'])
no_('the project manager cannot assign owners on stages 1 to 5 any more', lc('pm', 5, 'update', 'PE-331', fields={'owner': U['ce']}), 'only the stage owner, the head')
ok_('the Head assigns the costing engineer to stage 5', lc('hd', 5, 'update', 'PE-331', fields={'owner': U['ce']}), lambda r: r['owner'] == U['ce'])
no_('the Head does not approve or skip stages 6 to 12', lc('hd', 6, 'na', 'PE-331', note='x'), 'project manager or a super admin')
ok_('the project manager still runs stage 6', lc('pm', 6, 'update', 'PE-331', fields={'owner': U['pm']}), lambda r: r['owner'] == U['pm'])
ok_('a super admin can also approve stages 1 to 5', (lc('c1', 2, 'update', 'PE-331', ticks=[{'k': 'number', 'done': True}]), lc('c1', 2, 'submit', 'PE-331'), lc('sa', 2, 'approve', 'PE-331'))[-1], lambda r: r['status'] == 'Complete')
no_('a Head whose account is switched off cannot approve', (admin(f"update profiles set active=false where id='{U['hx']}'"), lc('c1', 3, 'update', 'PE-331', ticks=[{'k': k, 'done': True} for k in ('loa', 'wbs', 'fwbs', 'sapact', 'contract')]), lc('c1', 3, 'submit', 'PE-331'), lc('hx', 3, 'approve', 'PE-331'))[-1])
check('new stages get the new checklists (stage 3 has the SAP steps)', q("select string_agg(x->>'k', ',') from lifecycle_stages, jsonb_array_elements(deliverables) x where project_id='PE-331' and stage_no=3") == 'loa,wbs,fwbs,sapact,contract')

# ------------------------------------------------------------------ Tender details, award and the 7-day handover
ok_('the coordinator records the contract signing date', ta('c1', 'update', 'PE-331', contract_signed_on='2026-10-01'), lambda r: r['contract_signed_on'] == '2026-10-01')
check('stage 4 becomes due 7 days later', q("select due_date from lifecycle_stages where project_id='PE-331' and stage_no=4") == '2026-10-08')
check('the history says why', q("select count(*) from lifecycle_audit where project_id='PE-331' and stage_no=4 and note='Due 7 days after contract signing'") == '1')
ta('c1', 'update', 'PE-331', contract_signed_on='2026-10-03')
check('a corrected signing date moves that due date', q("select due_date from lifecycle_stages where project_id='PE-331' and stage_no=4") == '2026-10-10')
lc('c1', 4, 'update', 'PE-331', fields={'due_date': '2026-10-20'}); ta('c1', 'update', 'PE-331', contract_signed_on='2026-10-04')
check('a due date someone set by hand is left alone', q("select due_date from lifecycle_stages where project_id='PE-331' and stage_no=4") == '2026-10-20')
ok_('recording the award makes the project active', ta('c1', 'update', 'PE-331', award_on='2026-09-28', client='Saudi Electricity Co.'), lambda r: r['status'] == 'Active' and r['client'] == 'Saudi Electricity Co.')
no_('a signing date in the future is refused', ta('c1', 'update', 'PE-331', contract_signed_on='2099-01-01'), 'future')
no_('the coordinator cannot change a TE number once recorded', ta('c1', 'update', 'PE-331', te_number='TE-2232'), 'only a super admin')
no_('a foreman cannot change Tender details', ta('f1', 'update', 'PE-331', client='x'), 'only the costing coordinator')
ok_('the coordinator adds a TE number to an older project that had none', (admin(f"insert into project_access values ('{U['c1']}','PE-330')"), ta('c1', 'update', 'PE-330', te_number='te-1001'))[-1], lambda r: r['te_number'] == 'TE-1001')
check('every change is in the register history', q("select count(*) from register_audit where action='Details updated'") == '5')

# ------------------------------------------------------------------ cancel, release and reallocate
no_('the coordinator cannot cancel a project', ta('c1', 'cancel', 'PE-331', note='Client cancelled'), 'only the head')
no_('a cancellation needs a comment', ta('hd', 'cancel', 'PE-331'), 'add a comment')
ok_('the Head cancels PE-331 (client cancelled after L1)', ta('hd', 'cancel', 'PE-331', note='Client cancelled after L1'), lambda r: r['status'] == 'Cancelled' and r['cancelled_on'])
check('the project and its stages are all still there', q("select count(*) from lifecycle_stages where project_id='PE-331'") == '6')
no_('a cancelled project\'s stages cannot change', lc('c1', 4, 'update', 'PE-331', fields={'next_action': 'x'}), 'cancelled')
no_('nor its Tender details', ta('c1', 'update', 'PE-331', client='x'), 'cancelled')
ok_('PE-331 is now proposed first, as a released number', prop('c2'), lambda r: r['proposed'] == 'PE-331' and r['released'][0]['te'] == 'TE-2231' and r['next'] == 'PE-401')
r = ok_('the next L1 project gets PE-331 again', ta('c2', 'register', **dict(reg, te_number='TE-2250', name='Dammam pumping station')),
        lambda r: r['pe_number'] == 'PE-331' and r['id'] == 'PE-331-R2')
check('the history says it was reallocated', q("select note from register_audit where project_id='PE-331-R2' and action='PE allocated'").startswith('Reallocated'))
check('PE-331\'s history shows both TE numbers', q("select string_agg(distinct te_number, ',') from register_audit where pe_number='PE-331'") == 'TE-2231,TE-2250')
ok_('with no released number left, the proposal is the next in sequence again', prop('c2'), lambda r: r['proposed'] == 'PE-401' and r['released'] == [])
no_('only a super admin reinstates', ta('hd', 'reinstate', 'PE-331', note='Client revived it'), 'only a super admin')
no_('reinstating with its old number is refused while another project holds it', ta('sa', 'reinstate', 'PE-331', note='Client revived it'), 'now belongs to another live project')
ok_('the super admin reinstates it with a new PE number and its earlier status comes back',
    ta('sa', 'reinstate', 'PE-331', note='Client revived it', pe_number='PE-402'), lambda r: r['status'] == 'Active' and r['pe_number'] == 'PE-402' and r['cancelled_on'] is None)

# ------------------------------------------------------------------ changing a PE number
no_('only a super admin changes a PE number', ta('hd', 'change_pe', 'PE-400', note='typo', pe_number='PE-410'), 'only a super admin')
no_('a change needs a comment', ta('sa', 'change_pe', 'PE-400', pe_number='PE-410'), 'add a comment')
no_('a number another live project holds is refused', ta('sa', 'change_pe', 'PE-400', note='x', pe_number='PE-331'), 'already given')
ok_('the super admin changes PE-400 to PE-410', ta('sa', 'change_pe', 'PE-400', note='Allocated in error', pe_number='PE-410'), lambda r: r['pe_number'] == 'PE-410' and r['id'] == 'PE-400')
ok_('PE-400 is released and proposed next', prop('c1'), lambda r: r['proposed'] == 'PE-400')
ok_('an older project without a stored PE number can be given one', ta('sa', 'change_pe', 'EL-001', note='Numbering convention', pe_number='PE-200'), lambda r: r['pe_number'] == 'PE-200')
check('EL-001 is not offered as a released PE number', 'EL-001' not in json.dumps(prop('c1')[1]))

# ------------------------------------------------------------------ history and visibility
no_('the register history cannot be edited', psql("update register_audit set note='x' where id=1;"), 'append-only')
no_('or deleted, even from the database console', psql("delete from register_audit;"), 'append-only')
rc, out, err = run_as('f1', "select count(*) from register_audit where project_id='PE-331-R2';")
check('someone without access to a project does not see its register history', rc == 0 and out.endswith('0'), out or err)
rc, out, err = run_as('c2', "select count(*) from register_audit where project_id='PE-331-R2';")
check('the coordinators do', rc == 0 and int(out.splitlines()[-1]) >= 2, out or err)
call('sa', 'pcc_designate', {'user_id': U['c1'], 'designation': 'coordinator', 'on': False})
no_('a person whose coordinator designation is removed can no longer register', ta('c1', 'register', **dict(reg, te_number='TE-3000')), 'only the costing coordinator')

# ------------------------------------------------------------------ rollback keeps everything
counts = q("select (select count(*) from projects where te_number is not null)||'/'||(select count(*) from register_audit)||'/'||(select count(*) from pcc_designations)||'/'||(select count(*) from lifecycle_audit)")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v7.sql'))
    check(f'rollback runs (run {i})', rc == 0, err)
check('rollback removes the register functions', q("select count(*) from pg_proc where proname in ('tender_act','pe_proposal','pcc_designate','pt_pe_canon','pt_lc_boss')") == '0')
check('rollback keeps every project, register entry, designation and stage history entry',
      q("select (select count(*) from projects where te_number is not null)||'/'||(select count(*) from register_audit)||'/'||(select count(*) from pcc_designations)||'/'||(select count(*) from lifecycle_audit)") == counts, counts)
ok_('after rollback the v6 rules apply again (the project manager approves stage 1)',
    (lc('pm', 1, 'update', 'PE-329', ticks=[{'k': 'te', 'done': True}, {'k': 'value', 'done': True}, {'k': 'notice', 'done': True}]), lc('pm', 1, 'submit', 'PE-329'), lc('sa', 1, 'approve', 'PE-329'))[-1], lambda r: r['status'] == 'Complete')
rc, out, err = psql(file=find('schema-update-v7.sql'))
check('v7 can be applied again after a rollback', rc == 0, err)
check('re-applying does not repeat the checklist update', q("select count(*) from lifecycle_audit where action='Checklist updated'") == '3')

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'schema-update-v7', 'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v7_results.json'), 'w'), indent=1)
sys.exit(0 if passed == len(results) else 1)
