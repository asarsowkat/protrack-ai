#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v40 (order, SAP WBS segment, user field; the starting master in the company layout), on top of v39 (Budget & Cost Management, Automatic WBS Classification, stages 1-2):
rights and project access; master data proposed and approved by different people, versioned, validated (codes, parents,
cycles, destinations); the System seed waiting for approval; batches, files (same file refused), extracted lines that
never change and runs; the engine's results checked on the server (approved destinations only, automatic only from an
approved mapping or rule leading there, above the threshold, below the value limit, not for mandatory elements, not with
data problems); people's decisions never overwritten; review actions with reasons, bulk confirmation skipping what needs
individual review, bulk reassignment proposing only; undo; read access by project and cost right; rollback and again.
Loads schema.sql and every update v2 to v39. Usage: python3 test_v39.py"""
import json, os, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v40_test'
results = []
def find(name):
    for d in (HERE, os.path.dirname(HERE)):
        if os.path.exists(os.path.join(d, name)): return os.path.join(d, name)
    return None
def psql(sql=None, file=None):
    p = subprocess.run(PG + ['-d', DBN] + (['-f', file] if file else ['-c', sql]), capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()
def q(sql):
    rc, out, err = psql(sql)
    if rc: raise SystemExit('setup failed: ' + err + '\n' + sql)
    return {'t': 'true', 'f': 'false'}.get(out, out)
PEOPLE = {'sa': ('sa', 'Sara Admin'), 'ap': ('pm', 'Adam Approver'), 'co': ('costing', 'Carla Costing'), 'c2': ('costing', 'Chris Costing'),
          'pm': ('pm', 'Paul Manager'), 'pl': ('plan', 'Peter Planner'), 'fo': ('foreman', 'Faisal Foreman'), 'out': ('costing', 'Olga Outside'), 'ex': ('exec', 'Eva Executive')}
U = {k: f'00000000-0000-0000-0000-0000000040{i:02d}' for i, k in enumerate(PEOPLE, start=1)}
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
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 40)]:
    path = find(f)
    if not path: continue
    rc, out, err = psql(file=path)
    if rc: raise SystemExit(f + ': ' + err)
q("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k in PEOPLE))
q("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, (r, n) in PEOPLE.items()))
q(f"insert into user_rights (user_id, right_key, allow) values ('{U['ap']}', 'bcm.approve', true), ('{U['co']}', 'bcm.master', true)")
# before v40: some of the starting master approved, and a person's change waiting on DES
ok_('Before: the approver approves SM, SM1 and DES under v39', call('ap', 'bcm_master_act', {'action': 'approve_many', 'ids': ['W-SM', 'W-SM1', 'W-DES']}), lambda r: all(x['ok'] for x in r['results']))
ok_('Before: a costing engineer proposes a change of DES', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'id': 'W-DES', 'data': {**json.loads(q("select cur::text from bcm_master where id='W-DES'")), 'desc': 'Design and engineering'}, 'note': 'company name'}))
rc, out, err = psql(file=find('schema-update-v40.sql'))
check('Install: v40 runs', rc == 0, err)
check('Install: bcm_features gives version 40', one('co', "select bcm_features() ->> 'version'") == '40')
check('Seed: seven new elements arrive as proposals (SM1-01, SM1-02, Mechanical x3, Prime Cost, Provisional Sum)', q("select count(*) from bcm_master where ent='wbs'") == '57' and q("select string_agg(id, ',' order by id) from bcm_master where id in ('W-SM1-01','W-SM1-02','W-MEM','W-MEP','W-MEI','W-PC','W-PS') and cur is null and pend ->> 'by' = 'system'") == 'W-MEI,W-MEM,W-MEP,W-PC,W-PS,W-SM1-01,W-SM1-02')
check('Seed: SM1-02 is "Salaries - Site office team" under SM1, SAP segment 02, user field SM', q("select pend -> 'data' ->> 'desc' || '|' || (pend -> 'data' ->> 'parent') || '|' || (pend -> 'data' ->> 'sap_seg') || '|' || (pend -> 'data' ->> 'user_field') from bcm_master where id='W-SM1-02'") == 'Salaries - Site office team|W-SM1|02|SM')
check('Seed: an approved element (SM) keeps its approved version and gets a System proposal with segment 01 and user field SM', q("select (cur ->> 'sap_seg') is null and pend ->> 'by' = 'system' and pend -> 'data' ->> 'sap_seg' = '01' and pend -> 'data' ->> 'user_field' = 'SM' and ver = 1 from bcm_master where id='W-SM'") == 'true')
check('Seed: an element still waiting (SM4) gets the change in its proposal: segment 004', q("select cur is null and pend -> 'data' ->> 'sap_seg' = '004' and pend -> 'data' ->> 'order' = '40' from bcm_master where id='W-SM4'") == 'true')
check("Seed: an element with a person's change waiting (DES) is left alone, and the audit log says so", q("select pend ->> 'by' = %s and pend -> 'data' ->> 'sap_seg' is null from bcm_master where id='W-DES'" % ("'" + U['co'] + "'")) == 'true' and q("select count(*) from bcm_audit where ref='W-DES' and action like 'Seed update not applied%'") == '1')
check('Seed: Saudization, Financing, Contingency and Management Reserve move to the top level; Other approved categories is switched off', q("select string_agg(id || ':' || coalesce(pend -> 'data' ->> 'parent', 'top') || ':' || (pend -> 'data' ->> 'sap_seg'), ',' order by id) from bcm_master where id in ('W-SAU','W-FIN','W-CON','W-MR')") == 'W-CON:top:15,W-FIN:top:12,W-MR:top:16,W-SAU:top:11' and q("select pend -> 'data' ->> 'active' from bcm_master where id='W-OTH'") == 'false')
check('Seed: nothing is approved by the update', q("select count(*) from bcm_master where ent='wbs' and cur is not null") == '3')
ok_('Approve: the approver approves the System proposal of SM: version 2 with segment 01', call('ap', 'bcm_master_act', {'action': 'approve', 'id': 'W-SM'}), lambda r: r['ver'] == 2)
ok_('Approve: SM1 (segment 001) and SM1-01 (segment 01) in bulk, parents first', call('ap', 'bcm_master_act', {'action': 'approve_many', 'ids': ['W-SM1', 'W-SM1-01']}), lambda r: all(x['ok'] for x in r['results']))
check('...the SAP WBS of Salaries - Project office team is built from 01-001-01', q("select string_agg(cur ->> 'sap_seg', '-' order by array_position(array['W-SM','W-SM1','W-SM1-01'], id)) from bcm_master where id in ('W-SM','W-SM1','W-SM1-01')") == '01-001-01')
base = json.loads(q("select pend -> 'data' from bcm_master where id='W-SM2'"))
no_('Check: a top-level segment of 1 digit is refused (2 digits at level 1)', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'NEW1', 'desc': 'New', 'sap_seg': '1'}}), 'level 1 the SAP WBS segment has 2 digits')
no_('Check: a level-2 segment needs 3 digits', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'id': 'W-SM2', 'data': {**base, 'sap_seg': '02'}}), 'level 2 the SAP WBS segment has 3 digits')
no_('Check: a segment is digits', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'NEW1', 'desc': 'New', 'sap_seg': 'AB'}}), '1 to 6 digits')
no_('Check: a user field must be in the user field list', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'NEW1', 'desc': 'New', 'user_field': 'XYZ'}}), 'not in the user field list')
ok_('Check: a user field of the list is taken whatever its case (instl.mech)', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'NEW2', 'desc': 'New mech', 'user_field': 'instl.mech', 'sap_seg': '41'}}))
no_('Check: the order is a whole number', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'NEW3', 'desc': 'New', 'order': 'first'}}), 'whole number')
r = ok_('Unique: a new top-level element proposed with segment 01', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'NEW4', 'desc': 'Clash', 'sap_seg': '01'}}))
no_('Unique: ...its approval is refused: 01 is used by Site Management', call('ap', 'bcm_master_act', {'action': 'approve', 'id': r['id']}), 'already used under the same parent')
ok_('Order: a costing engineer with bcm.master proposes a new order for SM2 (a proposal like any change)', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'id': 'W-SM2', 'data': {**base, 'order': 5}, 'note': 'reorder'}))
cnt = q('select count(*) from bcm_master_hist')
rc, out, err = psql(file=find('schema-update-v40.sql'))
check('Again: v40 runs a second time without new proposals or history', rc == 0 and q('select count(*) from bcm_master_hist') == cnt and q("select count(*) from bcm_master where ent='wbs'") == str(57 + 2), err)
rc, out, err = psql(file=find('schema-rollback-v40.sql'))
check('Rollback: runs and goes back to the v39 checks (version 39), keeping the records', rc == 0 and one('co', "select bcm_features() ->> 'version'") == '39' and q("select cur ->> 'sap_seg' from bcm_master where id='W-SM1-01'") == '01', err)
ok_('Rollback: the v39 checks do not look at segments any more', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'NEW5', 'desc': 'After rollback', 'sap_seg': '1'}}))
rc, out, err = psql(file=find('schema-update-v40.sql'))
check('Again: v40 after the rollback', rc == 0 and one('co', "select bcm_features() ->> 'version'") == '40', err)

p = sum(r['pass'] for r in results)
print(f'\n{p}/{len(results)} passed')
json.dump({'suite': 'test_v40', 'passed': p, 'total': len(results), 'checks': results}, open(os.path.join(HERE, 'test_v40_results.json'), 'w'), indent=1)
