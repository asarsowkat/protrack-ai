#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v41 (Budget & Cost Management stage 3: sheet roles, duplicates and backups, split allocations, reconciliation, budget versions) (Budget & Cost Management, Automatic WBS Classification, stages 1-2):
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
DBN = 'pt_v41_test'
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
PEOPLE = {'c3': ('costing', 'Cora Costing'), 'sa': ('sa', 'Sara Admin'), 'ap': ('pm', 'Adam Approver'), 'co': ('costing', 'Carla Costing'), 'c2': ('costing', 'Chris Costing'),
          'pm': ('pm', 'Paul Manager'), 'pl': ('plan', 'Peter Planner'), 'fo': ('foreman', 'Faisal Foreman'), 'out': ('costing', 'Olga Outside'), 'ex': ('exec', 'Eva Executive')}
U = {k: f'00000000-0000-0000-0000-0000000041{i:02d}' for i, k in enumerate(PEOPLE, start=1)}
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
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 42)]:
    path = find(f)
    if not path: continue
    rc, out, err = psql(file=path)
    if rc: raise SystemExit(f + ': ' + err)
q("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k in PEOPLE))
q("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, (r, n) in PEOPLE.items()))
q("insert into regions (id, name) values ('R1','Central'); insert into sectors (id, name) values ('S1','Buildings')")
q("insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status, pe_number) values ('P1','Test Tower','TT','R1','S1','2026-08-01','2027-12-31',50,'Active','PE-777'), ('P2','Old Line','OL','R1','S1','2024-01-01','2026-12-31',30,'Active','PE-555')")
q("insert into project_access (user_id, project_id) values " + ",".join(f"('{U[k]}','{p}')" for k in ['ap', 'co', 'c2', 'c3', 'pm', 'pl', 'fo'] for p in ['P1', 'P2']))
q(f"insert into user_rights (user_id, right_key, allow) values ('{U['ap']}', 'bcm.approve', true), ('{U['ap']}', 'bcm.budget.approve', true)")
check('Install: bcm_features gives version 41 with stage 3', one('co', "select bcm_features() ->> 'version'") == '41' and one('co', "select bcm_features() -> 'stages' @> '[3]'") == 'true')
check('Install: the budget rights are listed', one('co', "select 'bcm.budget' = any(pt_rights()) and 'bcm.budget.approve' = any(pt_rights())") == 'true')
# the whole starting master approved (parents first)
for _ in range(5):
    ids = q("select coalesce(string_agg(id, ','), '') from bcm_master where pend is not null and ent in ('wbs','rule')").split(',')
    ids = [i for i in ids if i]
    if not ids: break
    call('ap', 'bcm_master_act', {'action': 'approve_many', 'ids': ids})
check('Setup: the starting master is approved', q("select count(*) from bcm_master where pend is not null and ent in ('wbs','rule')") == '0' and q("select count(*) from bcm_master where cur is not null") == '96', q("select count(*) from bcm_master where cur is not null"))
B = call('co', 'bcm_batch_save', {'project_id': 'P1', 'tender_ref': 'T-118', 'tender_rev': '0', 'currency': 'SAR', 'ptype': '132 kV substation'})[1]['id']
def addfile(name, sha, lines, control):
    q(f"insert into storage.objects (bucket_id, name) values ('bcm-tender', 'bcm/P1/{B}/{sha}.xlsx')")
    fid = call('co', 'bcm_file_add', {'batch_id': B, 'name': name, 'sha256': sha, 'size': 100, 'kind': 'xlsx', 'path': f'bcm/P1/{B}/{sha}.xlsx'})[1]['id']
    run = call('co', 'bcm_file_run', {'file_id': fid, 'step': 'start'})[1]['run']
    call('co', 'bcm_file_run', {'file_id': fid, 'step': 'lines', 'run': run, 'lines': lines})
    call('co', 'bcm_file_run', {'file_id': fid, 'step': 'done', 'run': run, 'n': len(lines), 'sheets': [], 'control': control})
    return fid
it = lambda n, sh, row, d, a, **k: dict({'n': n, 'sheet': sh, 'row': row, 'kind': 'item', 'desc': d, 'amount': a, 'flags': []}, **k)
F1 = addfile('summary.xlsx', 'a' * 64, [it(1, 'Summary', 2, 'Site staff salaries', '1656000', flags=['Amount linked to sheet Salaries backup cell F5']), it(2, 'Summary', 3, 'Insurance (CAR policy)', '75000'),
    {'n': 3, 'sheet': 'Summary', 'row': 4, 'kind': 'total', 'desc': 'Grand Total', 'amount': '1731000', 'flags': []},
    it(4, 'Salaries backup', 2, 'Project manager', '756000'), it(5, 'Salaries backup', 3, 'Site engineer', '648000'), it(6, 'Salaries backup', 4, 'Safety officer', '252000')], {'sheet': 'Summary', 'amount': '1731000'})
F2 = addfile('electrical.xlsx', 'b' * 64, [it(1, 'Electrical', 2, 'Supply and install cable 132kV', '250000', extra=[{'name': 'Material amount', 'amount': '190000'}, {'name': 'Labour amount', 'amount': '60000'}]),
    it(2, 'Electrical', 3, 'XLPE cable 630mm2 132kV', '520000'), it(3, 'Electrical', 4, 'XLPE cable 630mm2 132kV', '520000')], {'sheet': 'Electrical', 'amount': '1290000'})
L = lambda f, n: f'{f}:1:{n}'
def cls(lid, st, w, ct, **k): return dict({'id': lid, 'status': st, 'wbs_id': w, 'cost_type': ct, 'conf': 0.9, 'layer': 'similar', 'flags': [], 'refs': {}, 'engine': 't'}, **k)
call('co', 'bcm_classify', {'lines': [cls(L(F1, 1), 'Proposed', 'W-SM1', 'Overhead'), cls(L(F1, 2), 'Proposed', 'W-SM8', 'Overhead'), cls(L(F1, 4), 'Proposed', 'W-SM1-01', 'Overhead'), cls(L(F1, 5), 'Proposed', 'W-SM1-02', 'Overhead'),
    cls(L(F1, 6), 'Proposed', 'W-SM1-02', 'Overhead'), cls(L(F2, 1), 'Split Required', 'W-ELM-01', 'Material', flags=['Combined cost: supply and installation (or material and labour) in one line']),
    cls(L(F2, 2), 'Proposed', 'W-ELM-01', 'Material'), cls(L(F2, 3), 'Proposed', 'W-ELM-01', 'Material'), cls(L(F1, 3), 'Not a cost line', None, None)]})
call('co', 'bcm_review', {'ids': [L(F1, n) for n in (1, 2, 4, 5, 6)] + [L(F2, 2), L(F2, 3)], 'action': 'confirm'})
t = json.loads(one('co', f"select bcm_totals('{B}')::text"))
check('Totals: before stage 3 decisions the batch is not ready: sheets without a confirmed role and a split pending', t['ready'] is False and {p['key'] for p in t['problems']} >= {'roles', 'unresolved'}, t['problems'])
check('Totals: without decisions the backup lines and the repeated line all count (double counting is visible)', t['counted'] == '4677000.000000', t['counted'])
# ---------------- sheet roles
no_('Roles: a planner cannot propose sheet roles', call('pl', 'bcm_stage3', {'action': 'roles_propose', 'file_id': F1, 'run': 1, 'roles': [{'sheet': 'Summary', 'role': 'summary'}]}), 'cannot propose')
ok_('Roles: ProTrack proposes the roles (summary, backup)', call('co', 'bcm_stage3', {'action': 'roles_propose', 'file_id': F1, 'run': 1, 'roles': [{'sheet': 'Summary', 'role': 'summary', 'basis': ['control total']}, {'sheet': 'Salaries backup', 'role': 'backup', 'basis': ['linked']}]}))
no_('Roles: an unknown role is refused', call('co', 'bcm_stage3', {'action': 'roles_propose', 'file_id': F1, 'run': 1, 'roles': [{'sheet': 'Summary', 'role': 'main'}]}), 'Unknown sheet role')
check('Roles: a proposed backup role already stops its lines counting (shown, never added)', json.loads(one('co', f"select bcm_totals('{B}')::text"))['counted'] == '3021000.000000')
no_('Roles: a planner cannot confirm roles', call('pl', 'bcm_stage3', {'action': 'roles_confirm', 'file_id': F1, 'run': 1, 'roles': [{'sheet': 'Summary', 'role': 'summary'}]}), 'bcm.review')
ok_('Roles: a reviewer confirms the roles of both files', call('c2', 'bcm_stage3', {'action': 'roles_confirm', 'file_id': F1, 'run': 1, 'roles': [{'sheet': 'Summary', 'role': 'summary'}, {'sheet': 'Salaries backup', 'role': 'backup'}]}))
call('c2', 'bcm_stage3', {'action': 'roles_confirm', 'file_id': F2, 'run': 1, 'roles': [{'sheet': 'Electrical', 'role': 'summary'}]})
ok_('Roles: a later proposal never replaces a confirmed role', call('co', 'bcm_stage3', {'action': 'roles_propose', 'file_id': F1, 'run': 1, 'roles': [{'sheet': 'Salaries backup', 'role': 'summary'}]}))
check('...', q(f"select role || '/' || status from bcm_roles where file_id='{F1}' and sheet='Salaries backup'") == 'backup/Confirmed')
# ---------------- candidates
CB = {'id': 'backup-x1', 'kind': 'backup', 'lines': [L(F1, 1)], 'backup_lines': [L(F1, 4), L(F1, 5), L(F1, 6)], 'evidence': ['linked'], 'score': 1}
CE = {'id': 'exact-x2', 'kind': 'exact', 'lines': [L(F2, 2), L(F2, 3)], 'evidence': ['same figures'], 'score': 1}
CS = {'id': 'spec-x3', 'kind': 'spec', 'lines': [L(F2, 2), L(F2, 1)], 'evidence': ['differ'], 'score': 0.5}
no_('Candidates: a planner cannot run the analysis', call('pl', 'bcm_stage3', {'action': 'dups_save', 'batch_id': B, 'cands': [CB]}), 'cannot run')
no_('Candidates: a candidate naming a line of another batch is refused', call('co', 'bcm_stage3', {'action': 'dups_save', 'batch_id': B, 'cands': [{**CE, 'lines': ['nope:1:1']}]}), 'not in the current reading')
ok_('Candidates: the analysis saves its candidates', call('co', 'bcm_stage3', {'action': 'dups_save', 'batch_id': B, 'cands': [CB, CE, CS]}), lambda r: r['n'] == 3)
check('Candidates: exact and backup ones block a budget version, the specification one does not', q(f"select string_agg(kind || ':' || blocking, ',' order by kind) from bcm_dups where batch_id='{B}'") == 'backup:true,exact:true,spec:false')
check('Totals: open blocking candidates stop the version', 'dups' in {p['key'] for p in json.loads(one('co', f"select bcm_totals('{B}')::text"))['problems']})
no_('Decide: a planner cannot decide', call('pl', 'bcm_stage3', {'action': 'dup_decide', 'id': 'exact-x2', 'decision': 'duplicate', 'keep': [L(F2, 2)], 'reason': 'same line twice'}), 'bcm.review')
no_('Decide: a duplicate decision needs a reason', call('co', 'bcm_stage3', {'action': 'dup_decide', 'id': 'exact-x2', 'decision': 'duplicate', 'keep': [L(F2, 2)]}), 'reason')
no_('Decide: ...and the line that counts', call('co', 'bcm_stage3', {'action': 'dup_decide', 'id': 'exact-x2', 'decision': 'duplicate', 'keep': [], 'reason': 'same line twice'}), 'Choose the line')
no_('Decide: keeping every line is not a duplicate decision', call('co', 'bcm_stage3', {'action': 'dup_decide', 'id': 'exact-x2', 'decision': 'duplicate', 'keep': [L(F2, 2), L(F2, 3)], 'reason': 'same line twice'}), 'At least one line')
ok_('Decide: duplicate of another line: the server stops the second line counting', call('co', 'bcm_stage3', {'action': 'dup_decide', 'id': 'exact-x2', 'decision': 'duplicate', 'keep': [L(F2, 2)], 'reason': 'the same line copied twice'}), lambda r: r['targets'] == [L(F2, 3)])
ok_('Decide: supporting backup only, counting the summary line: the backup lines do not count', call('co', 'bcm_stage3', {'action': 'dup_decide', 'id': 'backup-x1', 'decision': 'backup', 'reason': 'the summary carries the salaries'}), lambda r: sorted(r['targets']) == sorted([L(F1, 4), L(F1, 5), L(F1, 6)]))
ok_('Decide: reopen needs a reason, then count the backup lines instead (Project office and Site office teams)', call('co', 'bcm_stage3', {'action': 'dup_reopen', 'id': 'backup-x1', 'reason': 'details are more useful'}))
ok_('...', call('co', 'bcm_stage3', {'action': 'dup_decide', 'id': 'backup-x1', 'decision': 'backup', 'details': True, 'reason': 'count the detailed salaries'}), lambda r: r['targets'] == [L(F1, 1)])
ok_('Decide: the specification candidate is a valid independent cost (no reason needed)', call('co', 'bcm_stage3', {'action': 'dup_decide', 'id': 'spec-x3', 'decision': 'valid'}), lambda r: r['targets'] == [])
ok_('Candidates: a new analysis without a candidate makes the open ones obsolete and keeps decided ones', call('co', 'bcm_stage3', {'action': 'dups_save', 'batch_id': B, 'cands': []}))
check('...', q(f"select string_agg(kind || ':' || status, ',' order by kind) from bcm_dups where batch_id='{B}'") == 'backup:Decided,exact:Decided,spec:Decided')
# ---------------- split
rows = [{'wbs_id': 'W-ELM-01', 'cost_type': 'Material', 'amount': '190000'}, {'wbs_id': 'W-ELP-01', 'cost_type': 'Manpower', 'amount': '60000'}]
no_('Split: a planner cannot propose a split', call('pl', 'bcm_stage3', {'action': 'alloc_propose', 'line_id': L(F2, 1), 'rows': rows, 'method': 'Source breakdown'}), 'bcm.review')
no_('Split: allocations that do not add up to the line are refused', call('co', 'bcm_stage3', {'action': 'alloc_propose', 'line_id': L(F2, 1), 'rows': [rows[0], {**rows[1], 'amount': '50000'}], 'method': 'Source breakdown'}), 'add up to')
no_('Split: one allocation is not a split', call('co', 'bcm_stage3', {'action': 'alloc_propose', 'line_id': L(F2, 1), 'rows': rows[:1], 'method': 'Source breakdown'}), 'at least two')
no_('Split: a destination that is not approved is refused', call('co', 'bcm_stage3', {'action': 'alloc_propose', 'line_id': L(F2, 1), 'rows': [rows[0], {**rows[1], 'wbs_id': 'W-ELP'}], 'method': 'Source breakdown'}), 'not an approved')
no_('Split: a manual split needs its basis', call('co', 'bcm_stage3', {'action': 'alloc_propose', 'line_id': L(F2, 1), 'rows': rows, 'method': 'Manual'}), 'basis')
A = ok_('Split: the costing engineer proposes the split from the source breakdown', call('co', 'bcm_stage3', {'action': 'alloc_propose', 'line_id': L(F2, 1), 'rows': rows, 'method': 'Source breakdown', 'evidence': 'Breakdown sheet E2 and F2'}))['id']
no_('Split: its proposer cannot approve it', call('co', 'bcm_stage3', {'action': 'alloc_approve', 'id': A}), 'someone else approves')
check('Totals: a split waiting for approval stops the version', 'allocs' in {p['key'] for p in json.loads(one('co', f"select bcm_totals('{B}')::text"))['problems']})
ok_('Split: another reviewer approves it: the line is confirmed as split', call('c2', 'bcm_stage3', {'action': 'alloc_approve', 'id': A}))
check('...', q(f"select status || '/' || layer from bcm_class where line_id='{L(F2, 1)}'") == 'Confirmed/split')
# ---------------- reconciliation
t = json.loads(one('co', f"select bcm_totals('{B}')::text"))
wbs = {(w['wbs_id'], w['cost_type']): w['amount'] for w in t['wbs']}
check('Totals: by WBS and cost type on the server: salaries in the two teams, insurance, the cable once (with its split share), the manpower share', wbs == {('W-SM1-01', 'Overhead'): '756000.000000', ('W-SM1-02', 'Overhead'): '900000.000000', ('W-SM8', 'Overhead'): '75000.000000', ('W-ELM-01', 'Material'): '710000.000000', ('W-ELP-01', 'Manpower'): '60000.000000'}, wbs)
check('Totals: counted 2,501,000, not counted 2,176,000 (the summary salaries line and the repeated cable)', t['counted'] == '2501000.000000' and t['not_counted'] == '2176000.000000', (t['counted'], t['not_counted']))
probs = {p['key']: p['msg'] for p in t['problems']}
check('Reconciliation: the electrical file\'s control total (1,290,000) differs from the lines counted (770,000): not ready until explained', f'src:{F2}' in probs and len(probs) == 1, probs)
no_('Reconciliation: an explanation needs at least 10 characters', call('c2', 'bcm_stage3', {'action': 'recon_note', 'batch_id': B, 'check_key': f'src:{F2}', 'reason': 'ok'}), '10 characters')
no_('Reconciliation: a planner cannot explain', call('pl', 'bcm_stage3', {'action': 'recon_note', 'batch_id': B, 'check_key': f'src:{F2}', 'reason': 'the control total counts the cable twice'}), 'bcm.review')
ok_('Reconciliation: a reviewer explains it (the figures are not adjusted)', call('c2', 'bcm_stage3', {'action': 'recon_note', 'batch_id': B, 'check_key': f'src:{F2}', 'reason': 'the file total adds the repeated cable line twice'}))
t = json.loads(one('co', f"select bcm_totals('{B}')::text"))
check('Reconciliation: now the batch is ready, and the figures are unchanged', t['ready'] is True and t['counted'] == '2501000.000000', t['problems'])
check('Reconciliation: the explanation cannot be changed', one('sa', "delete from bcm_recon_notes returning id").startswith('ERR'))
# ---------------- budget versions
no_('Version: a planner cannot prepare a budget version', call('pl', 'bcm_version_act', {'action': 'from_batch', 'batch_id': B, 'kind': 'Rev 0', 'justification': 'tender awarded'}), 'bcm.budget')
no_('Version: a justification is needed', call('co', 'bcm_version_act', {'action': 'from_batch', 'batch_id': B, 'kind': 'Rev 0'}), 'justification')
V = ok_('Version: the costing engineer prepares Rev 0 from the batch: the server computes the lines', call('co', 'bcm_version_act', {'action': 'from_batch', 'batch_id': B, 'kind': 'Rev 0', 'title': 'Rev 0 at award', 'justification': 'tender awarded, budget at award'}), lambda r: r['total'] == '2501000.000000' and r['n'] == 5)['id']
check('Version: each line has its SAP WBS ID on the project (PE-777-01-001-01 for the Project office team) and its user field', q(f"select string_agg(sap_wbs_id || ':' || coalesce(user_field, '') || ':' || amount::text, ',' order by sap_wbs_id) from bcm_version_lines where version_id='{V}' and wbs_id in ('W-SM1-01','W-SM8')") == 'PE-777-01-001-01:SM:756000.000000,PE-777-01-008:SM:75000.000000')
check('Version: a draft is version 0 of its kind', q(f"select kind || ' ' || rev_no || ' ' || status from bcm_versions where id='{V}'") == 'Rev 0 0 Draft')
ok_('Version: submitted by its preparer', call('co', 'bcm_version_act', {'action': 'submit', 'id': V}))
rc, out, err = psql(f"insert into bcm_version_lines (version_id, n, amount) values ('{V}', 99, 1)")
check('Version: no line can be added after submission, not even by the database owner', rc != 0 and 'never change' in err, err)
rc, out, err = psql(f"update bcm_version_lines set amount = 1 where version_id = '{V}'")
check('...nor changed', rc != 0 and 'never change' in err, err)
no_('Version: the preparer cannot review it', call('co', 'bcm_version_act', {'action': 'review', 'id': V}), 'someone else reviews')
ok_('Version: another reviewer takes it under review', call('c2', 'bcm_version_act', {'action': 'review', 'id': V}))
no_('Version: a reviewer without bcm.budget.approve cannot approve', call('c2', 'bcm_version_act', {'action': 'approve', 'id': V}), 'budget approver')
ok_('Version: the budget approver approves: "Approved in ProTrackAI" (not loaded in SAP)', call('ap', 'bcm_version_act', {'action': 'approve', 'id': V}), lambda r: r['status'] == 'Approved in ProTrackAI')
check('Version: its history keeps every step with who', q(f"select string_agg(action || ':' || by_name, ',' order by id) from bcm_version_hist where version_id='{V}'") == 'Prepared from batch ' + B + ':Carla Costing,Submit:Carla Costing,Review:Chris Costing,Approve:Adam Approver')
no_('Version: an approved version cannot be cancelled', call('ap', 'bcm_version_act', {'action': 'cancel', 'id': V, 'reason': 'changed my mind'}), 'Only a draft')
# ---------------- an existing project: the budget imported with its actual SAP WBS
IL = [{'sap_wbs_id': 'PE-555-01', 'descr': 'Site Management', 'user_field': 'SM', 'amount': '1200000.50', 'row': 3}, {'sap_wbs_id': 'PE-555-04-002', 'descr': 'Transformers', 'user_field': 'MTRL.ELC', 'cost_type': 'Material', 'amount': '8000000', 'wbs_id': 'W-ELM-02', 'row': 4},
      {'sap_wbs_id': 'PE-555-15', 'descr': 'Contingency', 'user_field': 'cont', 'amount': '300000', 'row': 5}]
imp = lambda **k: call('co', 'bcm_version_act', dict({'action': 'import', 'project_id': 'P2', 'kind': 'Rev 0', 'currency': 'SAR', 'justification': 'Rev 0 as loaded in SAP in 2024', 'lines': IL, 'file': {'name': 'P2 budget.xlsx'}}, **k))
no_('Import: the same SAP WBS twice is refused', imp(lines=IL + [IL[0]]), 'twice in the file')
no_('Import: an amount that is not a number is refused', imp(lines=[{**IL[0], 'amount': '1,200'}]), 'not a number')
no_('Import: a user field outside the list is refused', imp(lines=[{**IL[0], 'user_field': 'XYZ'}]), 'not in the user field list')
no_('Import: lines that do not add up to the file total are refused', imp(file_total='9000000'), 'not the total')
no_('Import: a planner cannot import', call('pl', 'bcm_version_act', {'action': 'import', 'project_id': 'P2', 'kind': 'Rev 0', 'currency': 'SAR', 'justification': 'x x x x x', 'lines': IL}), 'bcm.budget')
V2 = ok_('Import: the existing project\'s Rev 0 is imported with its actual SAP WBS IDs, exact', imp(file_total='9500000.50'), lambda r: r['total'] == '9500000.500000' and r['n'] == 3)['id']
check('Import: lines kept as in SAP; a line may be linked to a master element', q(f"select string_agg(sap_wbs_id || ':' || coalesce(wbs_id, '-'), ',' order by n) from bcm_version_lines where version_id='{V2}'") == 'PE-555-01:-,PE-555-04-002:W-ELM-02,PE-555-15:-')
ok_('Import: submitted', call('co', 'bcm_version_act', {'action': 'submit', 'id': V2}))
no_('Import: the submitter cannot reject his own version (he cancels it)', call('co', 'bcm_version_act', {'action': 'reject', 'id': V2, 'reason': 'wrong figures'}), 'cancel it instead')
ok_('Import: the approver rejects it with a reason', call('ap', 'bcm_version_act', {'action': 'reject', 'id': V2, 'reason': 'use the 2025 revision'}), lambda r: r['status'] == 'Rejected')
V3 = ok_('Import: a corrected import is the next version number (rev 1) of the same kind', imp(), lambda r: r['rev_no'] == 1)['id']
ok_('Import: its preparer cancels the draft with a reason', call('co', 'bcm_version_act', {'action': 'cancel', 'id': V3, 'reason': 'not needed now'}), lambda r: r['status'] == 'Cancelled')
V4 = call('co', 'bcm_version_act', {'action': 'from_batch', 'batch_id': B, 'kind': 'Revised Rev 0', 'justification': 'scope change'})[1]['id']
call('co', 'bcm_version_act', {'action': 'submit', 'id': V4}); call('c2', 'bcm_version_act', {'action': 'review', 'id': V4}); call('ap', 'bcm_version_act', {'action': 'approve', 'id': V4})
check('Version: a later approved version records the previous approved one (for the comparison)', q(f"select prev_id from bcm_versions where id='{V4}'") == V)
check('Read: a foreman sees no version; the costing engineer sees them and their lines', one('fo', 'select count(*) from bcm_versions') == '0' and one('co', 'select count(*) from bcm_version_lines') == '16')
# ---------------- rollback and again
rc, out, err = psql(file=find('schema-rollback-v41.sql'))
check('Rollback: runs; nothing of stage 3 can be written; everything is kept', rc == 0 and q("select count(*) from pg_proc where proname in ('bcm_stage3','bcm_version_act','bcm_totals')") == '0' and q('select count(*) from bcm_versions') == '4' and one('co', "select bcm_features() ->> 'version'") == '40', err)
rc, out, err = psql(file=find('schema-update-v41.sql'))
check('Again: v41 runs a second time and the figures are the same', rc == 0 and json.loads(one('co', f"select bcm_totals('{B}')::text"))['counted'] == '2501000.000000', err)
p = sum(r['pass'] for r in results)
print(f'\n{p}/{len(results)} passed')
json.dump({'suite': 'test_v41', 'passed': p, 'total': len(results), 'checks': results}, open(os.path.join(HERE, 'test_v41_results.json'), 'w'), indent=1)
