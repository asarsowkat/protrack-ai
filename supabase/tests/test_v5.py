#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v5 (controlled imports), on a local PostgreSQL 16 with a
Supabase stand-in. Covers the master prompt's import tests: valid files, missing data, wrong formats,
wrong project, duplicate batches and transactions, bad dates and currencies, partial errors, reconciliation
differences, interrupted commits, retry after failure, concurrent uploads and unauthorized uploads.
Usage: python3 test_v5.py [--keep]"""
import hashlib, json, os, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v5_test'
results = []

def find(name):
    for d in (HERE, os.path.dirname(HERE), os.path.join(HERE, 'tests')):
        if os.path.exists(os.path.join(d, name)): return os.path.join(d, name)
    raise SystemExit('missing ' + name)

def psql(sql=None, file=None, db=DBN):
    p = subprocess.run(PG + ['-d', db] + (['-f', file] if file else ['-c', sql]), capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()

def admin(sql):
    rc, out, err = psql(sql)
    if rc: raise SystemExit('setup failed: ' + err)
    return out

U = {k: f'00000000-0000-0000-0000-0000000000{i:02d}' for i, k in enumerate(['sa', 'pm', 'c1', 'pl', 'f1', 'pl1', 'ex'], start=1)}

def script(who, body):
    sub = U[who] if who else ''
    role = 'authenticated' if who else 'anon'
    return f"begin;\nset local role {role};\nselect set_config('request.jwt.claim.sub', '{sub}', true) \\g /dev/null\n{body}\ncommit;\n"

def run_as(who, body):
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write(script(who, body)); path = f.name
    try: return psql(file=path)
    finally: os.unlink(path)

def check(name, ok, detail=''):
    results.append({'check': name, 'pass': bool(ok), 'detail': str(detail)[:300]})
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '  -> ' + str(detail)[:300]))

def lit(o): return "'" + json.dumps(o).replace("'", "''") + "'::jsonb"
def h(o): return hashlib.sha256(json.dumps(o, sort_keys=True).encode()).hexdigest()

def commit(who, kind, rows, project='P1', accept=False, fname=None, **extra):
    p = {'kind': kind, 'project_id': project, 'file_name': fname or f'{kind}.xlsx', 'file_sha256': h(['file', rows]), 'file_size': 2048,
         'hash': h([kind, project, rows]), 'rows': rows, 'accept_difference': accept, 'warnings': extra.pop('warnings', [])}
    p.update(extra)
    rc, out, err = run_as(who, f"select import_commit({lit(p)});")
    return rc, (json.loads(out.splitlines()[-1]) if rc == 0 and out else None), err

def ok_(name, res, cond=lambda r: True):
    rc, r, err = res
    check(name, rc == 0 and r is not None and cond(r), r if rc == 0 else err)
    return r

def refused(name, res, msg=None):
    rc, r, err = res
    check(name, rc != 0 and (msg is None or msg.lower() in err.lower()), err or r)

# ------------------------------------------------------------------ build
subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql', 'schema-update-v4.sql']:
    rc, out, err = psql(file=find(f))
    if rc: raise SystemExit(f + ': ' + err)
roles = {'sa': 'sa', 'pm': 'pm', 'c1': 'costing', 'pl': 'plan', 'f1': 'foreman', 'pl1': 'plan', 'ex': 'exec'}
admin("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@t.local')" for k in U))
admin("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', 'User {k.upper()}', '{r}')" for k, r in roles.items()))
admin("""insert into regions values ('R1','R',null);
insert into projects (id, name, short, region) values ('P1','One','P1','R1'), ('P2','Two','P2','R1'), ('P3','Three','P3','R1');""")
admin("insert into project_access values " + ",".join(f"('{U[k]}','P1')" for k in ['pm', 'c1', 'pl', 'f1', 'pl1']) + f", ('{U['pl']}','P2'), ('{U['c1']}','P3')")
admin("""insert into activities (id, project_id, name, cls, qty, budget_mh, bs, bf, cur) values
 ('A1','P1','Concrete','CON',1000,2000,'2026-09-01','2026-09-30','{}'), ('A2','P1','Rebar','CON',500,800,'2026-09-01','2026-10-31','{}'),
 ('E1','P1','Drawings','ENG',100,300,'2026-08-01','2026-09-30','{"ms":"IDC","pct":0.4,"as":"2026-08-05"}'),
 ('R1','P1','Pumps','PRC',100,50,'2026-08-01','2026-12-31','{}'),
 ('E2','P2','Drawings P2','ENG',100,300,'2026-08-01','2026-09-30','{}');""")
# a v4-era import batch, to prove v5 keeps it
admin(f"""begin; set local role authenticated; select set_config('request.jwt.claim.sub','{U['c1']}',true);
select import_invoices('P1','old.xlsx','{'0'*64}','[{{"no":"OLD-1","sub":500}}]'::jsonb); commit;""")
rc, out, err = psql(file=find('schema-update-v5.sql'))
check('v5 loads on a database with v4 import batches', rc == 0, err)
rc, out, err = psql(file=find('schema-update-v5.sql'))
check('v5 can be run a second time', rc == 0, err)
if rc: raise SystemExit(1)
check('earlier batches kept, numbered', admin("select count(*)||'/'||min(seq) from import_batches") == '1/1')

# ------------------------------------------------------------------ invoices
INV = [{'no': 'INV-1', 'date': '2026-08-31', 'sub': 100000, 'appr': 90000, 'coll': 50000, 'currency': 'SAR', 'project': 'P1'},
       {'no': 'INV-2', 'date': '2026-09-30', 'sub': 80000}]
r = ok_('valid register loads and reconciles', commit('c1', 'invoices', INV, period='2026-09'),
        lambda r: r['recon_status'] == 'Matched' and float(r['total_source']) == 180000 and float(r['total_accepted']) == 180000)
row = admin("select seq||'|'||recon_status||'|'||recon_diff||'|'||length(file_sha256)||'|'||file_size||'|'||currency||'|'||source_period||'|'||status from import_batches order by seq desc limit 1")
check('batch records number, fingerprint, size, currency, period, reconciliation', row.split('|')[1:] == ['Matched', '0', '64', '2048', 'SAR', '2026-09', 'committed'], row)
ok_('same file again is recognised and changes nothing', commit('c1', 'invoices', INV), lambda r: r['duplicate'] is True)
check('...no second batch', admin("select count(*) from import_batches where kind='invoices' and status='committed'") == '2')

BAD = INV + [{'no': 'INV-2', 'sub': 10}, {'no': 'INV-3', 'date': '31/09/2026', 'sub': 5000}, {'no': 'INV-4', 'sub': 7000, 'currency': 'USD'},
             {'no': 'INV-5', 'sub': 3000, 'project': 'P9'}, {'no': 'INV-6', 'sub': 'abc'}, {'no': 'INV-7', 'sub': -5}]
refused('refused rows without confirmation: nothing saved', commit('c1', 'invoices', BAD), 'reconciliation difference')
check('...register unchanged', admin("select string_agg(invoice_no, ',' order by invoice_no) from invoices where project_id='P1'") == 'INV-1,INV-2')
r = ok_('confirmed difference loads the valid rows', commit('c1', 'invoices', BAD, accept=True, note='checked with finance'),
        lambda r: r['recon_status'] == 'Accepted with difference' and r['accepted'] == 1)
rej = {x['no']: x['error'] for x in (r or {}).get('rejected', [])}
check('every refused row has its reason', all(k in rej for k in ['INV-2', 'INV-3', 'INV-4', 'INV-5', 'INV-6', 'INV-7'])
      and 'more than once' in rej.get('INV-2', '') and 'date' in rej.get('INV-3', '') and 'USD' in rej.get('INV-4', '')
      and 'P9' in rej.get('INV-5', '') and 'not a number' in rej.get('INV-6', '') and 'Negative' in rej.get('INV-7', ''), rej)
row = admin("select recon_diff||'|'||(recon_accepted_by is not null)||'|'||recon_note from import_batches order by seq desc limit 1")
check('difference amount, who accepted it and the note are recorded', row.split('|')[0] in ('95005', '95005.00') and row.endswith('|true|checked with finance'), row)
refused('a file with no valid row never empties the register', commit('c1', 'invoices', [{'no': 'X', 'sub': 'n/a'}], accept=True), 'kept unchanged')
check('...register still holds the last good load', admin("select count(*) from invoices where project_id='P1'") == '1')

# interrupted commit: the database fails half way through writing
admin("""create function test_boom() returns trigger language plpgsql as $$ begin if new.invoice_no = 'BOOM' then raise exception 'disk full (simulated)'; end if; return new; end $$;
create trigger test_boom before insert on invoices for each row execute function test_boom();""")
GOOD = [{'no': 'G-1', 'sub': 1000}, {'no': 'G-2', 'sub': 2000}, {'no': 'BOOM', 'sub': 3000}]
before = admin("select string_agg(invoice_no, ',') from invoices where project_id='P1'")
refused('a commit interrupted half way fails', commit('c1', 'invoices', GOOD), 'disk full')
check('...nothing half-saved: the previous register is intact, no batch recorded',
      admin("select string_agg(invoice_no, ',') from invoices where project_id='P1'") == before and admin("select count(*) from import_batches where file_hash = '" + h(['invoices', 'P1', GOOD]) + "'") == '0')
p = {'kind': 'invoices', 'project_id': 'P1', 'file_name': 'invoices.xlsx', 'hash': h(['invoices', 'P1', GOOD]), 'rows_total': 3, 'error': 'disk full (simulated)'}
rc, out, err = run_as('c1', f"select log_import_failure({lit(p)});")
check('the failure is logged in the import centre', rc == 0 and admin("select status||'|'||error_message from import_batches order by seq desc limit 1") == 'failed|disk full (simulated)', err or out)
admin("drop trigger test_boom on invoices")
ok_('retry after the failure succeeds', commit('c1', 'invoices', GOOD), lambda r: r['accepted'] == 3)
check('...and is linked to the failed attempt', admin("select (b.retry_of = f.id) from import_batches b, import_batches f where b.status='committed' and f.status='failed' order by b.seq desc limit 1") == 't')
refused('a foreman cannot log a failure', run_as('f1', f"select log_import_failure({lit(p)});"), 'cannot load')

ok_("a row the app already refused stays refused, with the app's reason", commit('c1', 'invoices', [{'no': 'K-1', 'sub': 10}, {'no': 'K-2', 'sub': 20, 'client_error': 'Belongs to project X'}], accept=True),
    lambda r: r['accepted'] == 1 and r['rejected'][0]['error'] == 'Belongs to project X')

# ------------------------------------------------------------------ concurrent uploads
A = [{'no': 'CA-1', 'sub': 1}, {'no': 'CA-2', 'sub': 2}]; B = [{'no': 'CB-1', 'sub': 3}]
def bg(who, rows, sleep):
    pa = {'kind': 'invoices', 'project_id': 'P1', 'file_name': 'c.xlsx', 'hash': h(['invoices', 'P1', rows]), 'rows': rows, 'warnings': []}
    f = tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False)
    f.write(script(who, f"select import_commit({lit(pa)}) \\g /dev/null\nselect pg_sleep({sleep}) \\g /dev/null")); f.close()
    return subprocess.Popen(PG + ['-d', DBN, '-f', f.name], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
p1 = bg('c1', A, 2); time.sleep(0.6); p2 = bg('pm', B, 0); t0 = time.time()
o2 = p2.communicate(); waited = time.time() - t0; o1 = p1.communicate()
check('two uploads at once: the second waits for the first', p1.returncode == 0 and p2.returncode == 0 and waited > 0.8, (o1, o2, waited))
check('...the register is exactly one file, never a mix', admin("select string_agg(invoice_no, ',' order by invoice_no) from invoices where project_id='P1'") == 'CB-1')
nA = int(admin("select count(*) from import_batches where file_hash='" + h(['invoices', 'P1', A]) + "' and status='committed'"))
p1 = bg('c1', A, 1); time.sleep(0.4); p2 = bg('pm', A, 0); p2.communicate(); p1.communicate()
check('the same file sent twice at once is saved once', int(admin("select count(*) from import_batches where file_hash='" + h(['invoices', 'P1', A]) + "' and status='committed'")) == nA + 1)

# ------------------------------------------------------------------ file checks and authorization
refused('macro workbooks are refused', commit('c1', 'invoices', INV, fname='register.xlsm'), 'only excel')
refused('files over 10 MB are refused', commit('c1', 'invoices', INV, file_size=11 * 1024 * 1024), '10 mb')
refused('more than 20,000 rows are refused', commit('c1', 'invoices', [{'no': f'N{i}', 'sub': 1} for i in range(20001)]), '20,000')
refused('an empty file is refused', commit('c1', 'invoices', []), 'no data rows')
refused('an unknown import type is refused', commit('c1', 'payroll', INV), 'unknown import type')
refused('a foreman cannot load invoices', commit('f1', 'invoices', INV), 'only costing')
refused('a planner cannot apply costing', commit('pl', 'costing', [{'id': 'A1', 'qty': 1}]), 'only costing')
refused('a cost engineer cannot load progress', commit('c1', 'update', [{'project_id': 'P1', 'id': 'E1', 'ms': 'CMT'}], data_date='2026-09-20'), 'only planning')
refused('a cost engineer cannot load into a project outside access', commit('c1', 'invoices', INV, project='P2'), 'only costing')
refused('a signed-out visitor cannot import', run_as(None, f"select import_commit({lit({'kind': 'invoices', 'project_id': 'P1', 'rows': INV})});"))
refused('import batches cannot be written directly', run_as('sa', "insert into import_batches (project_id, kind) values ('P1','invoices');"))

# ------------------------------------------------------------------ costing
COST = [{'id': 'A1', 'qty': 1000, 'uom': 'm3', 'rate': 300, 'cost': 300000, 'mh': 2100}, {'id': 'A2', 'qty': 'lots', 'cost': 5},
        {'id': 'ZZ', 'qty': 1, 'cost': 9}, {'id': 'A2', 'qty': 10, 'cost': 1, 'currency': 'EUR'}]
refused('costing with refused rows needs confirmation', commit('c1', 'costing', COST), 'reconciliation difference')
check('...activities unchanged', admin("select coalesce(budget_cost,0) from activities where id='A1'") == '0')
r = ok_('confirmed costing applies the valid row', commit('c1', 'costing', COST, accept=True), lambda r: r['applied'] == 1)
check('...budget and reconciliation recorded', admin("select budget_cost from activities where id='A1'") == '300000'
      and admin("select total_source||'/'||total_accepted||'/'||recon_diff from import_batches where kind='costing' order by seq desc limit 1") == '300015/300000/15', admin("select total_source||'/'||total_accepted||'/'||recon_diff from import_batches where kind='costing' order by seq desc limit 1"))
r = ok_('costing rows for another project are refused', commit('c1', 'costing', [{'id': 'A2', 'qty': 5, 'cost': 1, 'project': 'P3'}, {'id': 'A1', 'qty': 1000, 'cost': 300000, 'mh': 2100}], accept=True),
        lambda r: any('P3' in x['error'] for x in r['rejected']))
refused('costing with no valid row changes nothing', commit('c1', 'costing', [{'id': 'ZZ', 'qty': 1}], accept=True), 'nothing was changed')
# the same session, two loads in a row (the server keeps working tables between calls)
c2a = {'kind': 'costing', 'project_id': 'P1', 'file_name': 'a.xlsx', 'hash': h('s1'), 'rows': [{'id': 'A2', 'qty': 500, 'cost': 100}], 'warnings': []}
c2b = {'kind': 'costing', 'project_id': 'P1', 'file_name': 'b.xlsx', 'hash': h('s2'), 'rows': [{'id': 'A2', 'qty': 500, 'cost': 200}], 'warnings': []}
rc, out, err = run_as('c1', f"select import_commit({lit(c2a)}) \\g /dev/null\ncommit;\nbegin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub','{U['c1']}',true) \\g /dev/null\nselect import_commit({lit(c2b)}) \\g /dev/null")
check('two costing loads in one connection both work', rc == 0 and admin("select budget_cost from activities where id='A2'") == '200', err)

# ------------------------------------------------------------------ baseline
refused('baseline with duplicate activity IDs is refused whole', commit('pl', 'baseline', [{'id': 'B1', 'name': 'x'}, {'id': 'B1', 'name': 'y'}]), 'more than once')
refused('baseline with finish before start is refused whole', commit('pl', 'baseline', [{'id': 'B2', 'name': 'x', 'bs': '2026-10-10', 'bf': '2026-10-01'}]), 'nothing was imported')
refused('baseline with text in a number column is refused whole', commit('pl', 'baseline', [{'id': 'B3', 'name': 'x', 'qty': 'ten'}]), 'nothing was imported')
check('...no activity created', admin("select count(*) from activities where id in ('B1','B2','B3')") == '0')
ok_('valid baseline imports', commit('pl', 'baseline', [{'id': 'B4', 'name': 'Blockwork', 'qty': 300, 'budget_mh': 600, 'bs': '2026-10-01', 'bf': '2026-10-31'}]), lambda r: r['upserted'] == 1)

# ------------------------------------------------------------------ weekly progress
PROG = [{'project_id': 'P1', 'id': 'E1', 'ms': 'CMT', 'ff': '2026-10-15', 'rem': 'comments back'},
        {'project_id': 'P1', 'id': 'r1', 'ms': 'PO', 'as': '2026-09-01'},
        {'project_id': 'P2', 'id': 'E2', 'ms': 'ST', 'as': '2026-09-10'},
        {'project_id': 'P1', 'id': 'A1', 'ms': 'ST'},
        {'project_id': 'P1', 'id': 'NOPE', 'ms': 'ST'},
        {'project_id': 'P1', 'id': 'E1', 'ms': 'IFC'}]
refused('progress with refused rows needs confirmation', commit('pl', 'update', PROG, project=None, data_date='2026-09-21'), 'reconciliation difference')
check('...no progress changed', admin("select cur->>'ms' from activities where id='E1'") == 'IDC')
r = ok_('confirmed progress applies valid rows in every project, in one go', commit('pl', 'update', PROG[1:5], project=None, data_date='2026-09-21', accept=True),
        lambda r: r['applied'] == 2)
check('...milestone and percent set by the server, not the file', admin("select (cur->>'ms')||'/'||(cur->>'pct')||'/'||(cur->>'dataDate') from activities where id='R1'") == 'PO/0.15/2026-09-21'
      and admin("select cur->>'ms' from activities where id='E2'") == 'ST')
check('...history written per project', admin("select count(*) from weekly_updates") == '2')
check('...batch covers several projects', admin("select (project_id is null)||'/'||(detail->'projects')::text from import_batches where kind='update' order by seq desc limit 1") == 'true/["P1", "P2"]')
BACK = [{'project_id': 'P1', 'id': 'E1', 'ms': 'ST'}]
refused('progress going backwards without a remark is refused', commit('pl', 'update', BACK, project=None, data_date='2026-09-22', accept=True), 'no valid progress row')
ok_('...accepted with a remark', commit('pl', 'update', [dict(BACK[0], rem='re-issued for comments')], project=None, data_date='2026-09-22'), lambda r: r['applied'] == 1)
LATE = [{'project_id': 'P1', 'id': 'R1', 'ms': 'DEL', 'af': '2026-09-30'}]
refused('actual finish after the data date is refused', commit('pl', 'update', LATE, project=None, data_date='2026-09-22', accept=True), 'no valid progress row')
refused('a planner without access to one project cannot load the file', commit('pl1', 'update', PROG[1:3], project=None, data_date='2026-09-21'), 'only planning')
refused('a future data date is refused', commit('pl', 'update', BACK, project=None, data_date='2031-01-01'), 'future')
rc, out, err = run_as('f1', "select count(*) from import_batches where project_id is null;")
check('a foreman does not see batches that span other projects', rc == 0 and out.strip().endswith('0'), out or err)
rc, out, err = run_as('pl', "select count(*) > 0 from import_batches where project_id is null;")
check('the planner sees them', rc == 0 and out.strip().endswith('t'), out or err)

# ------------------------------------------------------------------ undo and redo
counts = admin("select (select count(*) from import_batches)||'/'||(select count(*) from invoices)||'/'||(select count(*) from weekly_updates)")
rc, out, err = psql(file=find('schema-rollback-v5.sql'))
check('rollback script runs', rc == 0, err)
check('rollback keeps every batch, invoice and progress record', admin("select (select count(*) from import_batches)||'/'||(select count(*) from invoices)||'/'||(select count(*) from weekly_updates)") == counts)
rc, out, err = run_as('c1', "select import_invoices('P1','v4.xlsx','" + 'b' * 64 + "','[{\"no\":\"V4-1\",\"sub\":1}]'::jsonb);")
check('after rollback, the v2.5 import still works', rc == 0, err)
rc, out, err = psql(file=find('schema-update-v5.sql'))
check('v5 can be applied again after a rollback', rc == 0, err)

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} checks passed')
json.dump({'passed': passed, 'total': len(results), 'results': results}, open(os.path.join(HERE, 'test_v5_results.json'), 'w'), indent=1)
if '--keep' not in sys.argv:
    subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database {DBN}'], capture_output=True)
sys.exit(0 if passed == len(results) else 1)
