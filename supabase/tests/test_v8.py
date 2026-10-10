#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v8 (Phase 5): invoice rows, invoice and costing import batches
and costing/invoice upload history reach only roles that may see cost; everyone else's access is unchanged;
writes are unaffected; rollback restores the previous rules. Usage: python3 test_v8.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v8_test'
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
ROLES = {'sa': 'sa', 'ex': 'exec', 'rm': 'rm', 'pf': 'pf', 'pl': 'plan', 'co': 'costing', 'pm': 'pm', 'sm': 'sm', 'en': 'eng', 'fo': 'foreman', 'ro': 'ro', 'px': 'pm'}
U = {k: f'00000000-0000-0000-0000-0000000001{i:02d}' for i, k in enumerate(ROLES, start=1)}
def run_as(who, body):
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write(f"begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub', '{U[who]}', true) \\g /dev/null\n{body}\ncommit;\n"); path = f.name
    try: return psql(file=path)
    finally: os.unlink(path)
def check(name, ok, detail=''):
    results.append({'check': name, 'pass': bool(ok), 'detail': str(detail)[:300]})
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '  -> ' + str(detail)[:300]))
def seen(who):
    rc, out, err = run_as(who, "select (select count(*) from invoices)||'/'||(select count(*) from import_batches where kind in ('invoices','costing'))||'/'||(select count(*) from import_batches where kind in ('baseline','update'))||'/'||(select count(*) from upload_history where kind in ('invoices','costing'));")
    return out.splitlines()[-1] if rc == 0 else 'ERR ' + err

subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql', 'schema-update-v4.sql',
          'schema-update-v5.sql', 'schema-update-v6.sql', 'schema-update-v7.sql']:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in ROLES.items()))
admin("insert into regions values ('R1','R',null); insert into projects (id, name, short, region) values ('P1','One','P1','R1'), ('P2','Two','P2','R1');")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['pl', 'co', 'pm', 'sm', 'en', 'fo', 'ro']) + f", ('{U['px']}','P2')")
admin(f"insert into region_access values ('{U['rm']}','R1'), ('{U['pf']}','R1')")
admin("insert into invoices (project_id, invoice_no, amount, submitted) values ('P1','INV-1',100,100), ('P1','INV-2',200,200), ('P2','INV-3',50,50)")
admin("insert into import_batches (project_id, kind, file_name, total_source, total_accepted) values ('P1','invoices','inv.xlsx',300,300), ('P1','costing','cost.xlsx',9000,9000), ('P1','baseline','base.xer',null,null), (null,'update','upd.xlsx',null,null)")
admin("insert into upload_history (project_id, kind, file_name) values ('P1','invoices','inv.xlsx'), ('P1','costing','cost.xlsx')")

before = {k: seen(k) for k in ROLES}
for i in (1, 2):
    rc, out, err = psql(file=find('schema-update-v8.sql'))
    check(f'v8 loads (run {i})', rc == 0, err)
after = {k: seen(k) for k in ROLES}
for k in ['fo', 'en', 'sm']:
    check(f'{ROLES[k]}: no invoice rows, invoice or costing batches, or costing/invoice upload history', after[k].startswith('0/0/') and after[k].endswith('/0'), after[k])
    check(f'{ROLES[k]}: still sees the baseline batch for the project', after[k].split('/')[2] == before[k].split('/')[2], (before[k], after[k]))
for k in ['sa', 'ex', 'rm', 'pf', 'pl', 'co', 'pm', 'ro', 'px']:
    check(f'{ROLES[k]} ({k}): sees exactly what it saw before', after[k] == before[k], (before[k], after[k]))
check('before v8 a foreman could read invoice rows (the gap this closes)', before['fo'].startswith('2/2/'), before['fo'])
rc, out, err = run_as('fo', "select coalesce(sum(amount),0) from invoices;")
check('a foreman summing invoices gets nothing back', rc == 0 and out.splitlines()[-1] in ('0', '0.0'), out or err)
rc, out, err = run_as('co', "insert into invoices (project_id, invoice_no, amount) values ('P1','INV-9',10);")
check('costing can still add invoices', rc == 0, err)
rc, out, err = run_as('fo', "insert into invoices (project_id, invoice_no, amount) values ('P1','INV-10',10);")
check('a foreman still cannot add invoices', rc != 0, out)
rc, out, err = run_as('fo', "select import_progress('{}'::jsonb);")
check('functions the app calls still run (permission errors come from the function, not the policy)', rc != 0 and 'policy' not in err.lower(), err)
admin(f"update profiles set active=false where id='{U['pm']}'")
check('a switched-off account sees no cost rows', seen('pm').startswith('0/0/'), seen('pm'))
admin(f"update profiles set active=true where id='{U['pm']}'")
for i in (1, 2):
    rc, out, err = psql(file=find('schema-rollback-v8.sql'))
    check(f'rollback runs (run {i})', rc == 0, err)
back = {k: seen(k) for k in ['fo', 'co']}
check('after rollback the previous rules apply again (foreman reads invoices)', back['fo'].startswith('3/2/'), back)
check('rollback removes the helper and touches no data', admin("select count(*) from pg_proc where proname='pt_money_ok'") == '0' and admin("select count(*) from invoices") == '4')
rc, out, err = psql(file=find('schema-update-v8.sql'))
check('v8 can be applied again after a rollback', rc == 0 and seen('fo').startswith('0/0/'), err)

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'schema-update-v8', 'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v8_results.json'), 'w'), indent=1)
sys.exit(0 if passed == len(results) else 1)
