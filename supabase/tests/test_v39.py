#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v39 (Budget & Cost Management, Automatic WBS Classification, stages 1-2):
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
DBN = 'pt_v39_test'
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
U = {k: f'00000000-0000-0000-0000-0000000039{i:02d}' for i, k in enumerate(PEOPLE, start=1)}
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
files = ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 40)]
for f in files:
    path = find(f)
    if not path: continue
    rc, out, err = psql(file=path)
    if rc: raise SystemExit(f + ': ' + err)
q("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k in PEOPLE))
q("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, (r, n) in PEOPLE.items()))
q("insert into regions (id, name) values ('R1','Central'); insert into sectors (id, name) values ('S1','Buildings')")
q("insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values ('P1','Test Tower','TT','R1','S1','2026-08-01','2027-12-31',50,'Active'), ('P2','Other','OT','R1','S1','2026-08-01','2027-12-31',10,'Active')")
q("insert into project_access (user_id, project_id) values " + ",".join(f"('{U[k]}','P1')" for k in ['ap', 'co', 'c2', 'pm', 'pl', 'fo']) + f",('{U['out']}','P2')")
q(f"insert into user_rights (user_id, right_key, allow) values ('{U['ap']}', 'bcm.approve', true), ('{U['pl']}', 'bcm.master', true), ('{U['co']}', 'bcm.master', true)")

# ---------------- install
check('Install: bcm_features gives version 39', one('co', "select bcm_features() ->> 'version'") == '39')
check('Install: the rights and the screen are listed', one('co', "select 'bcm.upload' = any(pt_rights()) and 'bcm.approve' = any(pt_rights()) and 'bcm' = any(pt_screens())") == 'true')
check('Install: the System seed arrives as proposals, nothing approved (50 WBS elements, 38 rules)', q("select count(*) filter (where ent='wbs' and cur is null and pend is not null) || '/' || count(*) filter (where ent='rule' and cur is null) from bcm_master") == '50/38')
check('Install: the settings are in force (95% automatic, 80% review)', q("select cur ->> 'auto' || '/' || (cur ->> 'review') from bcm_master where id='cfg'") == '0.95/0.8')

# ---------------- master data
no_('Master: a costing engineer without bcm.master cannot propose a WBS element', call('c2', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'X1', 'desc': 'Test'}}), 'bcm.master')
no_('Master: a rule cannot point at an element that is not approved yet', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'rule', 'data': {'name': 'x', 'wbs_id': 'W-SM4', 'any': ['villa']}}), 'approved, active, postable')
no_('Master: the proposer of the seed is System, but the approver must hold bcm.approve', call('co', 'bcm_master_act', {'action': 'approve', 'id': 'W-SM'}), 'bcm.approve')
no_('Master: a child is not approved before its parent', call('ap', 'bcm_master_act', {'action': 'approve', 'id': 'W-SM4'}), 'parent')
r = ok_('Master: an approver approves the seed in bulk (parents first)', call('ap', 'bcm_master_act', {'action': 'approve_many', 'ids': ['W-SM', 'W-SM4', 'W-CIV', 'W-CIV-06', 'W-CIV-08', 'W-OTH', 'W-FIN', 'W-ELM', 'W-ELM-02'], 'note': 'checked against the company WBS'}),
        lambda r: all(x['ok'] for x in r['results']))
check('Master: approved elements are version 1, with their history kept', q("select string_agg(ver::text, ',' order by id) from bcm_master where id in ('W-SM','W-SM4')") == '1,1' and q("select count(*) from bcm_master_hist where ref='W-SM4' and action='Approved' and decided_by_name='Adam Approver'") == '1')
ok_('Master: approve the villa and rebar rules', call('ap', 'bcm_master_act', {'action': 'approve_many', 'ids': ['R-001', 'R-002', 'R-026', 'R-011']}), lambda r: all(x['ok'] for x in r['results']))
r = ok_('Master: a planner with bcm.master proposes a change of SM4 (the approved version stays in force)', call('pl', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'id': 'W-SM4', 'data': {**json.loads(q("select cur::text from bcm_master where id='W-SM4'")), 'desc': 'Villa / Staff accommodation'}, 'note': 'company name'}))
check('...the approved description stays until the change is approved', q("select cur ->> 'desc' from bcm_master where id='W-SM4'") == 'Villa / Accommodation' and q("select pend -> 'data' ->> 'desc' from bcm_master where id='W-SM4'") == 'Villa / Staff accommodation')
no_('Master: the proposer cannot approve his own change', call('sa', 'bcm_master_act', {'action': 'approve', 'id': 'W-SM4'}) if False else call('pl', 'bcm_master_act', {'action': 'approve', 'id': 'W-SM4'}), 'bcm.approve')
q(f"insert into user_rights (user_id, right_key, allow) values ('{U['pl']}', 'bcm.approve', true)")
no_('Master: ...even holding bcm.approve', call('pl', 'bcm_master_act', {'action': 'approve', 'id': 'W-SM4'}), 'someone else approves')
ok_('Master: another approver approves it: version 2', call('ap', 'bcm_master_act', {'action': 'approve', 'id': 'W-SM4'}), lambda r: r['ver'] == 2)
check('Master: both versions are kept for reproducing past classifications', q("select string_agg(data ->> 'desc', ' | ' order by ver) from bcm_master_hist where ref='W-SM4' and action='Approved'") == 'Villa / Accommodation | Villa / Staff accommodation')
no_('Master: a duplicate code is refused', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'sm4', 'desc': 'Dup', 'parent': 'W-SM'}}), 'already used')
no_('Master: an unknown parent is refused', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'NEW1', 'desc': 'New', 'parent': 'W-NOPE'}}), 'does not exist')
no_('Master: an element cannot be put under its own child', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'id': 'W-SM', 'data': {'code': 'SM', 'desc': 'Site', 'parent': 'W-SM4'}}), 'under itself')
no_('Master: a bad code is refused', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'bad code!', 'desc': 'x y'}}), 'WBS code')
no_('Master: a rule must match something', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'rule', 'data': {'name': 'empty', 'wbs_id': 'W-SM4', 'any': [], 'all': []}}), 'at least one phrase')
no_('Master: thresholds out of range are refused', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'cfg', 'data': {'auto': 0.4, 'review': 0.3, 'values': []}}), 'automatic threshold')
r = ok_('Master: a rejection needs a reason and leaves the element as it was', call('co', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'NEW1', 'desc': 'A new one', 'parent': 'W-CIV'}}))
no_('...no reason, no rejection', call('ap', 'bcm_master_act', {'action': 'reject', 'id': r['id']}), 'reason')
ok_('...with a reason', call('ap', 'bcm_master_act', {'action': 'reject', 'id': r['id'], 'note': 'not in the company WBS'}))
check('...a rejected new element has no version in force', q(f"select status || '/' || (cur is null) from bcm_master where id='{r['id']}'") == 'Rejected/true')
check('Master: nobody writes master data directly', one('sa', "update bcm_master set cur = '{}' where id = 'W-SM4' returning id").startswith('ERR'))

# ---------------- batches and files
no_('Intake: a planner (no bcm.upload) cannot create a batch', call('pl', 'bcm_batch_save', {'project_id': 'P1', 'tender_ref': 'T-1', 'currency': 'SAR'}), 'bcm.upload')
no_('Intake: someone outside the project cannot', call('out', 'bcm_batch_save', {'project_id': 'P1', 'tender_ref': 'T-1', 'currency': 'SAR'}), 'bcm.upload')
no_('Intake: the currency is required', call('co', 'bcm_batch_save', {'project_id': 'P1', 'tender_ref': 'T-1', 'currency': 'sar'}), 'currency')
B = ok_('Intake: a costing engineer creates a batch (project, tender, revision, currency, project type)', call('co', 'bcm_batch_save', {'project_id': 'P1', 'tender_ref': 'T-2026-118', 'tender_rev': '0', 'currency': 'SAR', 'ptype': '132 kV substation'}))['id']
SHA = 'a' * 64; PATH = f'bcm/P1/{B}/{SHA}.xlsx'
no_('Intake: a file is registered only once it is stored', call('co', 'bcm_file_add', {'batch_id': B, 'name': 'costing.xlsx', 'sha256': SHA, 'size': 1000, 'kind': 'xlsx', 'path': PATH}), 'storage first')
check('Storage: the costing engineer may store the file in the batch folder', one('co', f"insert into storage.objects (bucket_id, name, owner) values ('bcm-tender', '{PATH}', auth.uid()) returning name") == PATH)
check('Storage: ...a planner may not', one('pl', f"insert into storage.objects (bucket_id, name, owner) values ('bcm-tender', 'bcm/P1/{B}/{'b'*64}.xlsx', auth.uid()) returning name").startswith('ERR'))
check('Storage: ...nor anything that is not a workbook', one('co', f"insert into storage.objects (bucket_id, name, owner) values ('bcm-tender', 'bcm/P1/{B}/{'c'*64}.exe', auth.uid()) returning name").startswith('ERR'))
no_('Intake: the path must be the batch folder and the fingerprint', call('co', 'bcm_file_add', {'batch_id': B, 'name': 'costing.xlsx', 'sha256': SHA, 'size': 1000, 'kind': 'xlsx', 'path': 'bcm/P1/x.xlsx'}), 'path must be')
F = ok_('Intake: the file is registered with its name, SHA-256 and size', call('co', 'bcm_file_add', {'batch_id': B, 'name': 'costing.xlsx', 'sha256': SHA, 'size': 1000, 'kind': 'xlsx', 'path': PATH}))['id']
B2 = ok_('Intake: a second batch', call('co', 'bcm_batch_save', {'project_id': 'P1', 'tender_ref': 'T-2026-118', 'tender_rev': '1', 'currency': 'SAR'}))['id']
q(f"insert into storage.objects (bucket_id, name) values ('bcm-tender', 'bcm/P1/{B2}/{SHA}.xlsx')")
no_('Intake: the same file (same SHA-256) is refused a second time in the project, naming the first upload', call('co', 'bcm_file_add', {'batch_id': B2, 'name': 'copy.xlsx', 'sha256': SHA, 'size': 1000, 'kind': 'xlsx', 'path': f'bcm/P1/{B2}/{SHA}.xlsx'}), 'already uploaded: costing.xlsx')

# ---------------- a reading (run) and its lines
run = ok_('Lines: a reading starts (run 1)', call('co', 'bcm_file_run', {'file_id': F, 'step': 'start', 'engine': 'test'}), lambda r: r['run'] == 1)['run']
L = [{'n': 1, 'sheet': 'Costing', 'row': 2, 'kind': 'item', 'code': '1', 'desc': 'Supply of rebar Grade 60', 'qty': '120', 'unit': 'ton', 'unit_n': 't', 'rate': '3200', 'amount': '384000', 'amount_src': 'formula', 'f': '=C2*E2', 'refs': {'desc': 'B2', 'amount': 'F2'}, 'secs': [], 'flags': []},
     {'n': 2, 'sheet': 'Costing', 'row': 3, 'kind': 'item', 'desc': 'Rebar fixing crew', 'qty': '4', 'rate': '45000', 'amount': '180000', 'flags': []},
     {'n': 3, 'sheet': 'Costing', 'row': 4, 'kind': 'item', 'desc': 'Transformer supply 132/13.8kV 40MVA', 'qty': '2', 'rate': '2850000', 'amount': '5700000', 'flags': []},
     {'n': 4, 'sheet': 'Costing', 'row': 5, 'kind': 'item', 'desc': 'Site villa rent', 'amount': '216000', 'flags': []},
     {'n': 5, 'sheet': 'Costing', 'row': 6, 'kind': 'item', 'desc': 'Discount on villa', 'amount': '-10000', 'flags': ['Negative amount']},
     {'n': 6, 'sheet': 'Costing', 'row': 7, 'kind': 'item', 'desc': 'Bank guarantee charges', 'amount': '5000', 'flags': []},
     {'n': 7, 'sheet': 'Costing', 'row': 8, 'kind': 'total', 'desc': 'Total', 'amount': '6475000', 'flags': []}]
ok_('Lines: the lines are stored with the numbers exact', call('co', 'bcm_file_run', {'file_id': F, 'step': 'lines', 'run': run, 'lines': L}), lambda r: r['n'] == 7)
check('...amounts are decimals, not floats', q(f"select amount::text from bcm_lines where id = '{F}:1:1'") == '384000.000000')
no_('Lines: the reading closes only with the right count', call('co', 'bcm_file_run', {'file_id': F, 'step': 'done', 'run': run, 'n': 8, 'sheets': []}), 'holds 7 lines')
ok_('Lines: the reading closes (Extracted)', call('co', 'bcm_file_run', {'file_id': F, 'step': 'done', 'run': run, 'n': 7, 'sheets': [{'sheet': 'Costing', 'status': 'Extracted'}], 'control': {'amount': '6475000'}, 'fingerprint': 'f1'}), lambda r: r['status'] == 'Extracted')
check('Lines: a source line can never be changed...', one('sa', f"update bcm_lines set amount = 1 where id = '{F}:1:1' returning id").startswith('ERR'))
rc, out, err = psql(f"update bcm_lines set amount = 1 where id = '{F}:1:1'")
check('...not even by the database owner (trigger)', rc != 0 and 'never changed' in err, err)
rc, out, err = psql(f"delete from bcm_lines where id = '{F}:1:1'")
check('...nor deleted', rc != 0 and 'never changed' in err, err)

# ---------------- the engine's results, checked on the server
def res(n, **k): return dict({'id': f'{F}:1:{n}', 'engine': 'test', 'flags': [], 'refs': {}}, **k)
ok_('Classify: an auto-classification from the approved rebar rule is accepted', call('co', 'bcm_classify', {'lines': [res(1, status='Auto-Classified', wbs_id='W-CIV-06', cost_type='Material', conf=0.96, layer='rule', refs={'rule': 'R-001'})]}))
no_('Classify: automatic from a similarity match is refused', call('co', 'bcm_classify', {'lines': [res(2, status='Auto-Classified', wbs_id='W-CIV-08', cost_type='Manpower', conf=0.99, layer='similar')]}), 'only an approved mapping or rule')
no_('Classify: automatic naming a rule that leads elsewhere is refused', call('co', 'bcm_classify', {'lines': [res(2, status='Auto-Classified', wbs_id='W-CIV-08', cost_type='Manpower', conf=0.99, layer='rule', refs={'rule': 'R-001'})]}), 'does not lead to')
no_('Classify: automatic below the threshold is refused', call('co', 'bcm_classify', {'lines': [res(2, status='Auto-Classified', wbs_id='W-CIV-08', cost_type='Manpower', conf=0.9, layer='rule', refs={'rule': 'R-002'})]}), 'below the automatic threshold')
no_('Classify: a destination that is not approved is refused', call('co', 'bcm_classify', {'lines': [res(2, status='Proposed', wbs_id='W-SM5', cost_type='Overhead', conf=0.9, layer='similar')]}), 'not an approved')
no_('Classify: a parent (not postable) destination is refused', call('co', 'bcm_classify', {'lines': [res(2, status='Proposed', wbs_id='W-CIV', cost_type='Overhead', conf=0.9, layer='similar')]}), 'not an approved')
no_('Classify: the engine cannot confirm', call('co', 'bcm_classify', {'lines': [res(2, status='Confirmed', wbs_id='W-CIV-08', cost_type='Manpower')]}), 'cannot set the status')
no_('Classify: high value cannot be automatic (SAR 5.7 million, the server reads the amount itself)', call('co', 'bcm_classify', {'lines': [res(3, status='Auto-Classified', wbs_id='W-ELM-02', cost_type='Material', conf=0.96, layer='rule', refs={'rule': 'R-011'})]}), 'high value')
no_('Classify: a line with a data problem (negative amount) cannot be automatic, even if the app sends no flag', call('co', 'bcm_classify', {'lines': [res(5, status='Auto-Classified', wbs_id='W-SM4', cost_type='Overhead', conf=0.96, layer='rule', refs={'rule': 'R-026'})]}), 'data problem')
q("update bcm_master set cur = jsonb_set(cur, '{active}', 'true') where id = 'W-FIN'")
q("insert into bcm_master (id, ent, ver, cur, status) values ('R-T01', 'rule', 1, '{\"name\":\"t\",\"wbs_id\":\"W-FIN\",\"any\":[\"bank guarantee\"],\"active\":true}', 'Approved')")
no_('Classify: a mandatory-review element (Financing) cannot be automatic', call('co', 'bcm_classify', {'lines': [res(6, status='Auto-Classified', wbs_id='W-FIN', cost_type='Financing', conf=0.96, layer='rule', refs={'rule': 'R-T01'})]}), 'always needs individual review')
no_('Classify: a total row is not a cost line', call('co', 'bcm_classify', {'lines': [res(7, status='Proposed', wbs_id='W-SM4', cost_type='Overhead', conf=0.9)]}), 'not a cost line')
no_('Classify: someone outside the project cannot classify its lines', call('out', 'bcm_classify', {'lines': [res(2, status='Unclassified')]}), 'cannot classify')
ok_('Classify: proposals and review states are stored', call('co', 'bcm_classify', {'lines': [res(2, status='Proposed', wbs_id='W-CIV-08', cost_type='Manpower', conf=0.88, layer='similar'),
    res(3, status='Pending Review', wbs_id='W-ELM-02', cost_type='Material', conf=0.96, layer='rule', refs={'rule': 'R-011'}, flags=['High value: at or above 1,000,000.00 SAR']),
    res(4, status='Auto-Classified', wbs_id='W-SM4', cost_type='Overhead', conf=0.96, layer='rule', refs={'rule': 'R-026'}),
    res(5, status='Pending Review', wbs_id='W-SM4', cost_type='Overhead', conf=0.96, layer='rule', flags=['Negative amount']),
    res(6, status='Pending Review', wbs_id='W-FIN', cost_type='Financing', conf=0.96, layer='rule', flags=['Mandatory review: FIN Financing']),
    res(7, status='Not a cost line')]}), lambda r: r['n'] == 6)

# ---------------- people's decisions
no_('Review: a planner without bcm.review cannot confirm', call('pl', 'bcm_review', {'ids': [f'{F}:1:1'], 'action': 'confirm'}), 'bcm.review')
r = ok_('Review: a bulk confirmation confirms the clean lines and skips the high-value, negative and financing ones, saying why',
        call('co', 'bcm_review', {'ids': [f'{F}:1:{n}' for n in (1, 2, 3, 4, 5, 6)], 'action': 'confirm'}), lambda r: r['done'] == 3 and len(r['skipped']) == 3)
check('...the skipped reasons', sorted(x['why'].split(' ')[0] for x in r['skipped']) == ['Pending', 'Pending', 'Pending'], r['skipped'])
check('...the clean lines are Confirmed, with who and when', q(f"select string_agg(status, ',' order by line_id) from bcm_class where line_id in ('{F}:1:1','{F}:1:2','{F}:1:4')") == 'Confirmed,Confirmed,Confirmed' and q(f"select decided_by_name from bcm_class where line_id='{F}:1:1'") == 'Carla Costing')
ok_('Review: a high-value line is confirmed on its own', call('co', 'bcm_review', {'ids': [f'{F}:1:3'], 'action': 'confirm'}), lambda r: r['done'] == 1)
ok_('Classify: a new engine run never overwrites a person\'s decision', call('co', 'bcm_classify', {'lines': [res(1, status='Unclassified')]}), lambda r: r['n'] == 0 and r['kept'] == 1)
check('...still Confirmed', q(f"select status from bcm_class where line_id='{F}:1:1'") == 'Confirmed')
no_('Review: an override needs a reason', call('co', 'bcm_review', {'ids': [f'{F}:1:2'], 'action': 'override', 'wbs_id': 'W-CIV-06', 'cost_type': 'Material'}), 'reason')
no_('Review: an override to an element that is not approved is refused', call('co', 'bcm_review', {'ids': [f'{F}:1:2'], 'action': 'override', 'wbs_id': 'W-SM5', 'cost_type': 'Overhead', 'reason': 'recruitment agency crew'}), 'not an approved')
ok_('Review: an override with a reason confirms the new destination, marked as overridden', call('co', 'bcm_review', {'ids': [f'{F}:1:2'], 'action': 'override', 'wbs_id': 'W-CIV-06', 'cost_type': 'Manpower', 'reason': 'rebar crew is in the rebar package'}))
check('...', q(f"select status||'/'||wbs_id||'/'||cost_type||'/'||override||'/'||layer from bcm_class where line_id='{F}:1:2'") == 'Confirmed/W-CIV-06/Manpower/true/person')
r = ok_('Review: a bulk reassignment of a line that needs individual review only proposes it', call('co', 'bcm_review', {'ids': [f'{F}:1:5', f'{F}:1:6'], 'action': 'override', 'wbs_id': 'W-SM4', 'cost_type': 'Overhead', 'reason': 'both are accommodation'}))
check('...the negative line waits for individual confirmation; the other (no longer a mandatory element, normal value) is confirmed with the reason', q(f"select string_agg(status, ',' order by line_id) from bcm_class where line_id in ('{F}:1:5','{F}:1:6')") == 'Pending Review,Confirmed' and 'data problem' in r['skipped'][0]['why'], r)
ok_('Review: undo restores the state before the last decision, as a new action', call('co', 'bcm_review', {'ids': [f'{F}:1:2'], 'action': 'undo', 'reason': 'override was a mistake'}))
check('...back to the proposal, and both actions are in the history', q(f"select status||'/'||wbs_id from bcm_class where line_id='{F}:1:2'") == 'Confirmed/W-CIV-08' and q(f"select string_agg(action, ',' order by seq) from bcm_class_hist where line_id='{F}:1:2'") == 'Engine,Confirmed (bulk),Overridden,Undo')
no_('Review: excluding needs a reason', call('co', 'bcm_review', {'ids': [f'{F}:1:6'], 'action': 'exclude'}), 'reason')
ok_('Review: exclude with a reason', call('co', 'bcm_review', {'ids': [f'{F}:1:6'], 'action': 'exclude', 'reason': 'bank charges are in the finance WBS of the NOA'}))
ok_('Review: correct a row kind (the source row stays as read)', call('co', 'bcm_review', {'ids': [f'{F}:1:7'], 'action': 'correct', 'kind': 'subtotal', 'reason': 'it is a page total'}))
check('...the source line is unchanged, the correction is beside it', q(f"select kind from bcm_lines where id='{F}:1:7'") == 'total' and q(f"select corr ->> 'kind' from bcm_class where line_id='{F}:1:7'") == 'subtotal')
check('Review: the history of a line cannot be changed', one('sa', f"delete from bcm_class_hist where line_id='{F}:1:1' returning id").startswith('ERR'))

ok_('Learning: a reviewer (bcm.review, no bcm.master) proposes a project mapping from his decision', call('c2', 'bcm_master_act', {'action': 'propose', 'ent': 'map', 'data': {'scope': 'project', 'project_id': 'P1', 'key': 'Rebar fixing crew', 'wbs_id': 'W-CIV-08', 'cost_type': 'Manpower', 'source': {'line': f'{F}:1:2'}}, 'note': 'confirmed in T-2026-118'}))
no_('Learning: ...but not a WBS element', call('c2', 'bcm_master_act', {'action': 'propose', 'ent': 'wbs', 'data': {'code': 'X2', 'desc': 'Test'}}), 'bcm.master')
no_('Learning: ...nor a mapping for a project he cannot see', call('out', 'bcm_master_act', {'action': 'propose', 'ent': 'map', 'data': {'scope': 'project', 'project_id': 'P1', 'key': 'x', 'wbs_id': 'W-CIV-08'}}), 'bcm.master')

# ---------------- re-reading a file
no_('Runs: reading a file again when people have decided lines needs a confirmation', call('co', 'bcm_file_run', {'file_id': F, 'step': 'start'}), 'Confirm to go on')
ok_('Runs: with the confirmation, a new run starts beside the old lines', call('co', 'bcm_file_run', {'file_id': F, 'step': 'start', 'confirm_rerun': True}), lambda r: r['run'] == 2)
no_('Runs: the old run cannot receive lines any more', call('co', 'bcm_file_run', {'file_id': F, 'step': 'lines', 'run': 1, 'lines': L[:1]}), 'no longer the current')
no_('Runs: lines of the old run cannot be classified any more', call('co', 'bcm_classify', {'lines': [res(3, status='Unclassified')]}), 'earlier reading')
check('Runs: the old lines and their decisions are all kept', q(f"select count(*) from bcm_lines where file_id='{F}' and run=1") == '7' and q(f"select count(*) from bcm_class where line_id like '{F}:1:%' and status='Confirmed'") == '4')

# ---------------- reading
check('Read: the costing engineer sees the lines of his project', one('co', 'select count(*) from bcm_lines') == '7')
check('Read: bcm_lines_read gives exact amounts as text, current run only (none yet in run 2), or every run', one('co', f"select jsonb_array_length(bcm_lines_read('{B}', 0, true))") == '0' and one('co', f"select bcm_lines_read('{B}', 0, false) -> 0 ->> 'amount'") == '384000.000000')
check('Read: ...and nothing for someone outside the project', one('out', f"select jsonb_array_length(bcm_lines_read('{B}', 0, false))") == '0')
check('Read: a foreman (no cost figures) sees none', one('fo', 'select count(*) from bcm_lines') == '0')
check('Read: someone outside the project sees none of its batches or lines', one('out', 'select count(*) from bcm_batches') == '0' and one('out', 'select count(*) from bcm_lines') == '0')
check('Read: the executive sees them (cost figures, all projects)', one('ex', 'select count(*) from bcm_lines') == '7')
check('Read: master data is readable by people with cost figures, not by a foreman', one('co', 'select count(*) > 80 from bcm_master') == 'true' and one('fo', 'select count(*) from bcm_master') == '0')
check('Read: the audit log records who did what', int(q("select count(distinct action) from bcm_audit")) >= 8 and q("select count(*) from bcm_audit where action = 'File uploaded' and by_name = 'Carla Costing'") == '1')
check('Storage: a foreman cannot read a stored tender file', one('fo', f"select count(*) from storage.objects where bucket_id='bcm-tender'") == '0' and one('co', f"select count(*) from storage.objects where bucket_id='bcm-tender'") == '2')

# ---------------- withdraw
no_('Withdraw: needs a reason', call('co', 'bcm_batch_save', {'action': 'withdraw', 'id': B2}), 'reason')
ok_('Withdraw: the uploader withdraws a batch; its data stays', call('co', 'bcm_batch_save', {'action': 'withdraw', 'id': B2, 'reason': 'uploaded by mistake'}))
no_('Withdraw: a withdrawn batch takes no file', call('co', 'bcm_file_add', {'batch_id': B2, 'name': 'x.xlsx', 'sha256': 'd' * 64, 'size': 10, 'kind': 'xlsx', 'path': f'bcm/P1/{B2}/{"d"*64}.xlsx'}), 'withdrawn')

# ---------------- rollback and again
rc, out, err = psql(file=find('schema-rollback-v39.sql'))
check('Rollback: runs', rc == 0, err)
check('Rollback: nothing can be written, everything is kept', q("select count(*) from pg_proc where proname in ('bcm_master_act','bcm_review','bcm_classify')") == '0' and q('select count(*) from bcm_lines') == '7' and int(q('select count(*) from bcm_class_hist')) > 10)
rc, out, err = psql(file=find('schema-update-v39.sql'))
check('Again: v39 runs a second time and keeps every record (no second seed)', rc == 0 and q("select count(*) from bcm_master where ent='rule'") == '39' and q("select cur ->> 'desc' from bcm_master where id='W-SM4'") == 'Villa / Staff accommodation', err)
check('Again: the check query', q("select bcm_features() ->> 'version', (select count(*) from pg_proc where proname in ('bcm_master_act','bcm_batch_save','bcm_file_add','bcm_file_run','bcm_classify','bcm_review')), to_regclass('public.bcm_lines') is not null") == '39|6|t')

p = sum(r['pass'] for r in results)
print(f'\n{p}/{len(results)} passed')
json.dump({'suite': 'test_v39', 'passed': p, 'total': len(results), 'checks': results}, open(os.path.join(HERE, 'test_v39_results.json'), 'w'), indent=1)
