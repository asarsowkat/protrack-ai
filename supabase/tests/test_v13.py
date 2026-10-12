#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v13 (ProTrackAI v3.4): the three-row project document rack.
Storage rules on the private "project-docs" bucket, who may add and read documents in each row, registering files,
revisions that never overwrite, status and details changes with history, box files (add, rename, hide, reorder),
and rollback. Supabase Storage is imitated by two tables in TEST-ONLY-supabase-stub.sql. Usage: python3 test_v13.py"""
import json, os, subprocess, sys, tempfile, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v13_test'
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
ROLES = {'sa': 'sa', 'hd': 'pm', 'pl': 'plan', 'co': 'costing', 'pm': 'pm', 'ex': 'exec', 'en': 'eng', 'sm': 'sm', 'fo': 'foreman', 'nx': 'costing'}
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
def act(who, p):
    rc, out, err = run_as(who, f"select doc_act({lit(p)});")
    return rc, (json.loads(out.splitlines()[-1]) if rc == 0 and out else None), err
def ok_(name, res, cond=lambda r: True):
    rc, r, err = res
    try: good = rc == 0 and cond(r)
    except Exception as e: good, err = False, repr(e)
    check(name, good, r if rc == 0 else err); return r
def no_(name, res, msg=None):
    rc, r, err = res; check(name, rc != 0 and (msg is None or msg.lower() in err.lower()), err or r)
def cnt(who, sql):
    rc, out, err = run_as(who, sql.rstrip().rstrip(';') + ';')
    return out.splitlines()[-1] if rc == 0 and out else 'ERR ' + err
def put(who, path, size=1234, mime='application/pdf'):
    meta = json.dumps({'size': size, 'mimetype': mime})
    return run_as(who, f"insert into storage.objects (bucket_id, name, owner, metadata) values ('project-docs', '{path}', auth.uid(), '{meta}'::jsonb);")
def path(pid, box, name): return f"{pid}/{box}/{uuid.uuid4()}/{name}"
q = admin

subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 13)]:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin(f"insert into pcc_designations (user_id, designation) values ('{U['hd']}','head')")
admin("insert into regions values ('R1','Western',null); insert into projects (id, name, short, region) values ('P1','One','P1','R1'), ('P2','Two','P2','R1');")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['hd', 'pl', 'co', 'pm', 'en', 'sm', 'fo']) + f", ('{U['nx']}','P2')")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v13.sql'))
    check(f'v13 loads (run {i})', rc == 0, err)
check('the setup check counts 3', q("select count(*) from pg_proc where proname in ('doc_act','pt_doc_can','pt_doc_row')") == '3')
check('the bucket is private with a 50 MB limit per file', q("select public::text||'/'||file_size_limit from storage.buckets where id='project-docs'") == 'false/52428800')

# ------------------------------------------------------------------ storage: who may add files where
rules = [('co', 'K02', True, 'the costing engineer adds to the Cost row'), ('co', 'C05', True, 'the costing engineer adds to the Contract row'),
         ('co', 'P01', False, 'the costing engineer cannot add to the Planning row'), ('pl', 'P01', True, 'the planning engineer adds to the Planning row'),
         ('pl', 'K02', False, 'the planning engineer cannot add to the Cost row'), ('pl', 'C01', False, 'the planning engineer cannot add to the Contract row'),
         ('hd', 'C01', True, 'the Head adds to any row'), ('pm', 'P03', False, 'a project manager cannot add files'), ('en', 'P03', False, 'a site engineer cannot add files'),
         ('fo', 'P03', False, 'a foreman cannot add files'), ('ex', 'K01', False, 'an executive cannot add files'), ('nx', 'K02', False, 'a costing engineer without access to the project cannot add files'),
         ('co', 'Z99', False, 'nobody adds to a box that does not exist')]
for who, box, allowed, name in rules:
    rc, out, err = put(who, path('P1', box, 'file.pdf'))
    check(('allowed: ' if allowed else 'refused: ') + name, (rc == 0) == allowed, err)
rc, out, err = put('co', path('P1', 'K02', 'virus.exe')); check('refused: a file type that is not a document (.exe)', rc != 0, err)
rc, out, err = put('co', 'P1/K02/flat.pdf'); check('refused: a file outside the <project>/<box>/<id>/<name> folders', rc != 0, err)
rc, out, err = put('sa', path('P1', 'P01', 'baseline.xer')); check('allowed: the super admin adds anywhere, P6 XER files too', rc == 0, err)

# ------------------------------------------------------------------ register documents
R0 = path('P1', 'K02', 'Rev0 budget.pdf'); put('co', R0, size=45678)
no_('registering needs the file in storage first', act('co', {'action': 'add', 'project_id': 'P1', 'box_key': 'K02', 'title': 'x', 'storage_path': path('P1', 'K02', 'missing.pdf')}), 'not found in storage')
no_('the file must be in this box\'s folder', act('co', {'action': 'add', 'project_id': 'P1', 'box_key': 'K03', 'title': 'x', 'storage_path': R0}), 'folder')
no_('a title is needed', act('co', {'action': 'add', 'project_id': 'P1', 'box_key': 'K02', 'title': ' ', 'storage_path': R0}), 'title')
no_('the period must be a month or a week', act('co', {'action': 'add', 'project_id': 'P1', 'box_key': 'K02', 'title': 'x', 'period': 'Sept', 'storage_path': R0}), 'period')
no_('a planning engineer cannot register in the Cost row', act('pl', {'action': 'add', 'project_id': 'P1', 'box_key': 'K02', 'title': 'x', 'storage_path': R0}), 'only the people who keep this row')
d0 = ok_('the costing engineer registers the Rev 0 budget', act('co', {'action': 'add', 'project_id': 'P1', 'box_key': 'k02', 'title': 'Rev 0 approved project budget', 'revision': 'Rev 0', 'status': 'Approved',
         'period': '2025-05', 'doc_date': '2025-05-20', 'category': 'Rev 0 cost baseline', 'storage_path': R0, 'file_name': 'Rev0 budget.pdf', 'sha256': 'a' * 64}),
         lambda r: r['box_key'] == 'K02' and r['file_size'] == 45678 and r['mime'] == 'application/pdf' and r['status'] == 'Approved')
no_('the same file cannot be registered twice', act('co', {'action': 'add', 'project_id': 'P1', 'box_key': 'K02', 'title': 'x', 'storage_path': R0}), 'already registered')
check('the upload is in the history', q(f"select action||'/'||(by_user::text='{U['co']}') from doc_audit where doc_id='{d0['id']}'") == 'Uploaded/true')
R1 = path('P1', 'K02', 'Rev1 budget.pdf'); put('co', R1)
d1 = ok_('a new revision (Rev 1) is a new document pointing to Rev 0', act('co', {'action': 'add', 'project_id': 'P1', 'box_key': 'K02', 'title': 'Rev 1 budget', 'revision': 'Rev 1', 'status': 'Submitted', 'supersedes': d0['id'], 'storage_path': R1}),
         lambda r: r['supersedes'] == d0['id'])
check('Rev 0 stays as it was: same file, same status', q(f"select status||'/'||storage_path from documents where id='{d0['id']}'") == 'Approved/' + R0)
R2 = path('P1', 'K03', 'Monthly.xlsx'); put('co', R2)
no_('a new revision must be in the same box', act('co', {'action': 'add', 'project_id': 'P1', 'box_key': 'K03', 'title': 'x', 'supersedes': d0['id'], 'storage_path': R2}), 'same box')
B0 = path('P1', 'P01', 'Baseline Rev01.xer'); put('pl', B0)
b0 = ok_('the planning engineer registers the approved baseline', act('pl', {'action': 'add', 'project_id': 'P1', 'box_key': 'P01', 'title': 'Approved baseline', 'revision': 'Rev 01', 'status': 'Approved', 'storage_path': B0}))
C0 = path('P1', 'P02', 'Update W41.xer'); put('pl', C0)
ok_('a current P6 schedule goes in its own box, with its week', act('pl', {'action': 'add', 'project_id': 'P1', 'box_key': 'P02', 'title': 'Current schedule', 'period': '2026-W41', 'storage_path': C0}), lambda r: r['period'] == '2026-W41')
check('...and the approved baseline is untouched', q(f"select count(*) from documents where box_key='P01'") == '1' and q(f"select status from documents where id='{b0['id']}'") == 'Approved')

# ------------------------------------------------------------------ who reads what
check('the project manager reads the Cost and Planning rows', cnt('pm', "select count(*) from documents where box_key in ('K02','P01')") == '3')
check('a site engineer reads the Planning row only', cnt('en', "select count(*) from documents where box_key like 'P%'") == '2' and cnt('en', "select count(*) from documents where box_key like 'K%'") == '0')
check('a site manager reads the Planning row only', cnt('sm', "select count(*) from documents") == '2')
check('a foreman reads none', cnt('fo', "select count(*) from documents") == '0' and cnt('fo', "select count(*) from storage.objects") == '0')
check('someone without access to the project reads none', cnt('nx', "select count(*) from documents") == '0' and cnt('nx', "select count(*) from storage.objects where name like 'P1/%'") == '0')
check('an executive reads all rows', cnt('ex', "select count(*) from documents") == '4')
check('file downloads follow the same rules (site engineer: planning files only)', cnt('en', "select count(*) from storage.objects where name like 'P1/K%'") == '0' and cnt('en', f"select count(*) from storage.objects where name = '{B0}'") == '1')
check('the history follows the same rules', cnt('en', "select count(*) from doc_audit where box_key like 'K%'") == '0' and cnt('pm', "select count(*) from doc_audit where box_key like 'K%'") == '2')

# ------------------------------------------------------------------ status and details
ok_('the costing engineer marks Rev 1 approved', act('co', {'action': 'status', 'id': d1['id'], 'status': 'Approved'}), lambda r: r['status'] == 'Approved')
check('the change is in the history, from and to', q(f"select detail->>'from'||'>'||(detail->>'to') from doc_audit where doc_id='{d1['id']}' and action like 'Status%'") == 'Submitted>Approved')
no_('rejecting needs a comment', act('co', {'action': 'status', 'id': d1['id'], 'status': 'Rejected'}), 'comment')
no_('an unknown status is refused', act('co', {'action': 'status', 'id': d1['id'], 'status': 'Lost'}), 'unknown status')
no_('a project manager cannot change a status', act('pm', {'action': 'status', 'id': d1['id'], 'status': 'Paid'}), 'not change it')
no_('a site engineer cannot even see a Cost document', act('en', {'action': 'status', 'id': d1['id'], 'status': 'Paid'}), 'unknown document')
ok_('details can be corrected; the changes are listed', act('co', {'action': 'edit', 'id': d1['id'], 'fields': {'ref_no': 'BUD-01', 'doc_date': '2026-01-15'}}), lambda r: r['ref_no'] == 'BUD-01')
check('...in the history', q(f"select detail->'changes' from doc_audit where doc_id='{d1['id']}' and action='Details changed'") == '["ref_no", "doc_date"]')
no_('the file of a document cannot be changed, even from the database console', psql(f"update documents set storage_path='x' where id='{d0['id']}'"), 'cannot be changed')
no_('a document cannot be deleted, even from the database console', psql(f"delete from documents where id='{d0['id']}'"), 'kept')
no_('the history cannot be edited', psql("update doc_audit set note='x'"), 'append-only')
run_as('co', f"update documents set title='changed' where id='{d0['id']}';")
check('a direct write from the browser changes nothing', q(f"select title from documents where id='{d0['id']}'") == 'Rev 0 approved project budget')
rc, out, err = run_as('co', f"insert into documents (project_id, box_key, title, storage_path, file_name) values ('P1','K02','x','P1/K02/a/b.pdf','b.pdf');")
check('nobody registers a document directly from the browser', rc != 0, out)
run_as('co', f"delete from storage.objects where name = '{R0}';"); run_as('co', f"update storage.objects set name = 'P1/K02/x/y.pdf' where name = '{R0}';")
check('stored files cannot be deleted or renamed from the browser', q(f"select count(*) from storage.objects where name = '{R0}'") == '1')

# ------------------------------------------------------------------ box files
nb = ok_('the costing engineer adds a box to the Cost row', act('co', {'action': 'box_save', 'project_id': 'P1', 'row_key': 'cost', 'title': 'Insurance claims'}), lambda r: r['box_key'].startswith('X'))
no_('a planning engineer cannot add a box to the Cost row', act('pl', {'action': 'box_save', 'project_id': 'P1', 'row_key': 'cost', 'title': 'x'}), 'only the people who keep this row')
NB = nb['box_key'] if nb else 'X'
rc, out, err = put('co', path('P1', NB, 'claim.pdf')); check('files can be added to the new box', rc == 0, err)
rc, out, err = put('pl', path('P1', NB, 'claim.pdf')); check('...by the people who keep its row only', rc != 0)
ok_('the planning engineer renames a planning box', act('pl', {'action': 'box_save', 'project_id': 'P1', 'box_key': 'P03', 'title': 'Weekly reports and updates'}))
check('the default box now carries the new name and stays in its row', q("select row_key||'/'||title from doc_boxes where box_key='P03'") == 'planning/Weekly reports and updates')
ok_('a box can be hidden', act('pl', {'action': 'box_save', 'project_id': 'P1', 'box_key': 'P12', 'hidden': True}))
ok_('the planning row is reordered', act('pl', {'action': 'box_order', 'project_id': 'P1', 'row_key': 'planning', 'keys': ['P02', 'P01', 'P03']}))
check('...in the new order', q("select string_agg(box_key, ',' order by sort) from doc_boxes where box_key in ('P01','P02','P03')") == 'P02,P01,P03')
no_('a box cannot be put into another row by reordering', act('pl', {'action': 'box_order', 'project_id': 'P1', 'row_key': 'planning', 'keys': ['K01']}), 'not in this row')
no_('a project manager cannot change boxes', act('pm', {'action': 'box_save', 'project_id': 'P1', 'box_key': 'P03', 'title': 'x'}), 'only the people')
check('box changes are in the history', q("select count(*) from doc_audit where action in ('Box added','Box changed','Boxes reordered')") == '4')
check('no budget, schedule or release was touched by any of this', q("select (select count(*) from report_releases)||'/'||(select count(*) from activities)") == '0/0')

# ------------------------------------------------------------------ rollback keeps everything
n = q("select (select count(*) from documents)||'/'||(select count(*) from doc_audit)||'/'||(select count(*) from storage.objects)")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v13.sql'))
    check(f'rollback runs (run {i})', rc == 0, err)
check('rollback stops new files and documents', put('co', path('P1', 'K02', 'after.pdf'))[0] != 0 and q("select count(*) from pg_proc where proname='doc_act'") == '0')
check('rollback keeps every document, history entry and file', q("select (select count(*) from documents)||'/'||(select count(*) from doc_audit)||'/'||(select count(*) from storage.objects)") == n, n)
check('...still readable by the same people', cnt('pm', "select count(*) from documents") == '4' and cnt('fo', "select count(*) from documents") == '0')
rc, out, err = psql(file=find('schema-update-v13.sql'))
check('v13 can be applied again after a rollback', rc == 0, err)

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'schema-update-v13', 'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v13_results.json'), 'w'), indent=1)
sys.exit(0 if passed == len(results) else 1)
