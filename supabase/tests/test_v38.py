#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v38 (emails really sent, only to the right people): the mail queue
checks that the event is real and that the caller made it, works out the recipients itself (approval email settings,
the approval chain, the report email lists with their regions, weekly flag, named people and other addresses, the
people a reminder named who still have access), queues each event once, keeps the outbox out of reach of direct
writes, shows each person their own emails and the super admin all of them, lets a super admin re-queue a failed
email, and rolls back. Loads schema.sql and every update v2 to v38. Usage: python3 test_v38.py"""
import json, os, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v38_test'
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
PEOPLE = {'sa': ('sa', 'Sara Admin'), 'pm': ('pm', 'Paul Manager'), 'e1': ('eng', 'Omar Engineer'), 'e2': ('eng', 'Hadi Engineer'),
          's1': ('sm', 'Samir SiteManager'), 'pl': ('plan', 'Peter Planner'), 'rp': ('plan', 'Rana RegionalPlanning'), 'co': ('costing', 'Carla Costing'),
          'fo': ('foreman', 'Faisal Foreman'), 'ex': ('exec', 'Eva Executive'), 'out': ('pm', 'Olga Outside'), 'ne': ('pm', 'Nadia NoEmail'), 'nm': ('ro', 'Nora Named')}
U = {k: f'00000000-0000-0000-0000-0000000038{i:02d}' for i, k in enumerate(PEOPLE, start=1)}
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
names = lambda r: sorted(x['name'] for x in (r or {}).get('to', []))
def mq(who, kind, ref, subject='Subject', html='<p>Body</p>', label=None):
    p = {'kind': kind, 'ref': ref, 'subject': subject, 'html': html}
    if label: p['label'] = label
    return call(who, 'mail_queue', p)

subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
files = ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 39)]
for f in files:
    path = find(f)
    if not path: continue            # v19 was never issued
    rc, out, err = psql(file=path)
    if rc: raise SystemExit(f + ': ' + err)

q("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', {'null' if k == 'ne' else repr(k + '@test.local')})" for k in PEOPLE))
q("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, (r, n) in PEOPLE.items()))
q("insert into regions (id, name) values ('C','Central'), ('W','Western') on conflict do nothing")
q("insert into projects (id, name, short, region) values ('P1','Test Project One','TP1','C'), ('P2','Test Project Two','TP2','W')")
q("insert into project_access (user_id, project_id) values " + ",".join(f"('{U[k]}','P1')" for k in ['pm', 'e1', 'e2', 's1', 'pl', 'rp', 'co', 'fo', 'ne']))
# a daily report approved through the chain: foreman → e1 reviewed → s1 approved
q(f"insert into dprs (id, project_id, report_date, foreman, status, created_by) values ('DPR-1','P1','2026-10-20','Faisal','Approved','{U['fo']}'), ('DPR-2','P1','2026-10-21','Faisal','Approved','{U['fo']}'), ('DPR-3','P1','2026-10-22','Faisal','Submitted','{U['fo']}')")
q(f"insert into dpr_audit (dpr_id, action, by_user) values ('DPR-1','Submitted','{U['fo']}'), ('DPR-1','Reviewed','{U['e1']}'), ('DPR-1','Approved','{U['s1']}'), ('DPR-2','Approved','{U['sa']}')")

check('v38 is installed: mail_features', one('pm', 'select mail_features()') == '{"queue": true, "version": 38}')

# ---- daily report emails
r = ok_('the approver queues the approval email of the daily report he approved', mq('s1', 'dpr', 'DPR-1', 'Daily report approved: TP1'), lambda r: r['id'] and r['status'] == 'queued')
check('recipients worked out by the server: roles of the settings with access to the project; site roles only from the chain; no foreman, no outsider, nobody without an address',
      names(r) == sorted(['Sara Admin', 'Paul Manager', 'Omar Engineer', 'Samir SiteManager', 'Peter Planner', 'Rana RegionalPlanning', 'Carla Costing', 'Eva Executive']), names(r))
check('each recipient carries the address from the sign-in account and the role', all(x['email'] == [k for k in U if U[k] == x['id']][0] + '@test.local' and x['role'] for x in r['to']), r['to'][:2])
ok_('asking again returns the same email (queued once)', mq('s1', 'dpr', 'DPR-1'), lambda x: x['id'] == r['id'] and x.get('duplicate') is True)
check('one row in the outbox for that report', q("select count(*) from mail_outbox where kind='dpr' and ref='DPR-1'") == '1')
no_('someone who did not approve it cannot send its email', mq('pm', 'dpr', 'DPR-2'), 'only the person who approved')
no_('a report that is not approved is refused', mq('sa', 'dpr', 'DPR-3'), 'not approved')
no_('an unknown report is refused', mq('sa', 'dpr', 'DPR-404'), 'unknown daily report')
q("update mail_config set chain_only = false")
r2 = ok_('a super admin can send the email of a report he approved', mq('sa', 'dpr', 'DPR-2'), lambda r: r['id'])
check('with "site roles only for their reports" off, every site engineer with access receives it', 'Hadi Engineer' in names(r2), names(r2))
q("update mail_config set enabled = false")
q("insert into dprs (id, project_id, report_date, foreman, status) values ('DPR-4','P1','2026-10-23','Faisal','Approved')")
q(f"insert into dpr_audit (dpr_id, action, by_user) values ('DPR-4','Approved','{U['s1']}')")
ok_('with the approval email switched off, nothing is queued', mq('s1', 'dpr', 'DPR-4'), lambda r: r['id'] is None and r['n'] == 0 and 'switched off' in r['skipped'])
q("update mail_config set enabled = true, chain_only = true, roles = '{pm}'")
ok_('the roles of the settings decide who receives it', mq('s1', 'dpr', 'DPR-4'), lambda r: names(r) == ['Paul Manager'])
q("update mail_config set roles = '{eng,sm,pm,pf,plan,costing,exec,sa}'")

# ---- report emails (internal and cost reports)
q(f"insert into report_releases (id, project_id, kind, period_type, period, rev, status, approved_by, approved_at) values "
  f"('00000000-0000-0000-0000-00000000a001','P1','planning','month','2026-09',0,'Released','{U['rp']}',now()),"
  f"('00000000-0000-0000-0000-00000000a002','P1','planning','week','2026-W40',0,'Released','{U['rp']}',now()),"
  f"('00000000-0000-0000-0000-00000000a003','P1','cost','month','2026-09',0,'Released','{U['sa']}',now()),"
  f"('00000000-0000-0000-0000-00000000a004','P1','planning','month','2026-10',0,'Submitted',null,null)")
R1, R2, R3, R4 = ('00000000-0000-0000-0000-00000000a00' + c for c in '1234')
r = ok_('the approver queues the internal report email', mq('rp', 'release', R1, 'Monthly internal report released'), lambda r: r['id'])
check('default internal report list: project managers, portfolio, regional managers, executives and planners with access',
      names(r) == sorted(['Paul Manager', 'Peter Planner', 'Rana RegionalPlanning', 'Eva Executive']), names(r))
no_('only the person who approved the report sends its email', mq('pl', 'release', R3), 'only the person who approved')
no_('a report that is not released is refused', mq('sa', 'release', R4), 'not released')
no_('an unknown or malformed report id is refused', mq('sa', 'release', 'not-a-uuid'), 'unknown report')
q(f"update report_mail_lists set extra = array['finance@company.com','bad address','PM@test.local'], people = array['{U['nm']}'::uuid] where kind = 'cost' and region_id is null")
r = ok_('the cost report email goes to the cost list', mq('sa', 'release', R3, 'Monthly cost report released'), lambda r: r['id'])
check('cost list: its roles with access, its named people, valid other addresses only, no address twice',
      names(r) == sorted(['Paul Manager', 'Carla Costing', 'Eva Executive', 'Nora Named', 'finance@company.com']) and not any(x['email'] == 'bad address' for x in r['to']), names(r))
q("insert into report_mail_lists (kind, region_id, enabled, weekly, roles) values ('planning','C',true,false,'{pm}')")
ok_('a weekly internal report is not emailed when the region list says monthly only', mq('rp', 'release', R2), lambda r: r['id'] is None and 'weekly' in r['skipped'].lower())
q("update report_mail_lists set weekly = true where kind = 'planning' and region_id = 'C'")
ok_('...and goes to the region list, not the default, when weekly is on', mq('rp', 'release', R2), lambda r: names(r) == ['Paul Manager'])

# ---- Reporting status reminders
q(f"insert into rs_reminders (id, project_id, period_type, period, keys, \"to\", by_user, at) values "
  f"('RR1','P1','month','2026-09','{{int}}','[{{\"id\":\"{U['pl']}\"}},{{\"id\":\"{U['co']}\"}},{{\"id\":\"{U['out']}\"}},{{\"id\":\"junk\"}}]','{U['pm']}',now()),"
  f"('RR2','P1','month','2026-08','{{int}}','[{{\"id\":\"{U['pl']}\"}}]','{U['pm']}',now() - interval '2 hours')")
ok_('a reminder email goes to the people it named who still have access', mq('pm', 'remind', 'RR1', 'Reminder: TP1'), lambda r: names(r) == ['Carla Costing', 'Peter Planner'])
no_('someone else cannot email that reminder', mq('pl', 'remind', 'RR1'), 'only the person who sent')
no_('an old reminder is refused', mq('pm', 'remind', 'RR2'), 'more than an hour old')

# ---- test email, checks on the content
ok_('a super admin sends a test email to himself', mq('sa', 'test', '', 'ProTrack test email'), lambda r: names(r) == ['Sara Admin'])
ok_('...as many as he likes (each test is its own email)', mq('sa', 'test', '', 'ProTrack test email'), lambda r: r['id'] and not r.get('duplicate'))
no_('only a super admin sends a test email', mq('pm', 'test', '', 'x'), 'only a super admin')
no_('a subject over 300 characters is refused', mq('sa', 'test', '', 'x' * 301), 'subject')
no_('an empty body is refused', mq('sa', 'test', '', 'x', ''), 'body')
no_('an unknown type is refused', call('sa', 'mail_queue', {'kind': 'spam', 'ref': 'x', 'subject': 's', 'html': 'h'}), 'unknown email type')
no_('nobody signed in is refused', (lambda p: (lambda r: (r.returncode, None, r.stderr))(subprocess.run(PG + ['-d', DBN, '-c', f"set role authenticated; select mail_queue({lit(p)})"], capture_output=True, text=True)))({'kind': 'test', 'ref': '', 'subject': 's', 'html': 'h'}), 'sign in')

# ---- the outbox: no direct writes, each person sees their own
no_('nobody writes the outbox directly', run_as('sa', "insert into mail_outbox (kind, ref, subject, html) values ('test','x','s','h')"))
no_('...or changes an email in it', run_as('sa', "update mail_outbox set recipients = '[]'"))
check('a person sees only the emails he queued', one('pm', 'select count(*) from mail_outbox') == q(f"select count(*) from mail_outbox where queued_by = '{U['pm']}'") and int(one('pm', 'select count(*) from mail_outbox')) >= 1)
check('the super admin sees every email', one('sa', 'select count(*) from mail_outbox') == q('select count(*) from mail_outbox'))
check('a foreman sees none', one('fo', 'select count(*) from mail_outbox') == '0')

# ---- sending again
mid = q("select id from mail_outbox where kind='dpr' and ref='DPR-1'")
q(f"update mail_outbox set status='failed', attempts=1, error='mailbox unavailable' where id='{mid}'")
ok_('a super admin puts a failed email back in the queue', call('sa', 'mail_retry', {'id': mid}), lambda r: r['status'] == 'queued')
check('...its error is cleared and its attempts kept', q(f"select coalesce(error,'')||'/'||attempts from mail_outbox where id='{mid}'") == '/1')
no_('only a super admin does', call('pm', 'mail_retry', {'id': mid}), 'only a super admin')
q(f"update mail_outbox set status='sent' where id='{mid}'")
no_('an email already sent is not sent again', call('sa', 'mail_retry', {'id': mid}), 'sent already')

# ---- rollback and again
rc, out, err = psql(file=find('schema-rollback-v38.sql'))
check('the rollback runs', rc == 0, err)
check('...the queue functions are gone and the outbox is kept', q("select to_regprocedure('mail_queue(jsonb)') is null") == 'true' and int(q('select count(*) from mail_outbox')) > 5)
rc, out, err = psql(file=find('schema-rollback-v38.sql'))
check('the rollback runs twice', rc == 0, err)
rc, out, err = psql(file=find('schema-update-v38.sql'))
check('v38 runs again after the rollback, keeping every email', rc == 0 and int(q('select count(*) from mail_outbox')) > 5, err)
ok_('...and the queue works again', mq('sa', 'test', '', 'again'), lambda r: r['id'])

passed = sum(r['pass'] for r in results)
print(f"\n{passed}/{len(results)} passed")
json.dump({'suite': 'test_v38', 'passed': passed, 'total': len(results), 'checks': results}, open(os.path.join(HERE, 'test_v38_results.json'), 'w'), indent=1)
