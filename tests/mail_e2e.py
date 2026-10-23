#!/usr/bin/env python3
"""ProTrackAI v3.34 in server mode: approval and report emails queued on the server and handed to the send-mail function.
The real app in Chromium, talking to a local PostgreSQL built from schema.sql and every update v2 to v38 through
fake_supabase.py (the Edge Function is replaced by the stand-in, which records each call). Every allow/refuse decision is
the database's. Usage: python3 mail_e2e.py APP_HTML SUPABASE_DIR > results_mail_e2e.json"""
import json, os, subprocess, sys, time, urllib.request
from playwright.sync_api import sync_playwright

APP = os.path.abspath(sys.argv[1]); DBDIR = os.path.abspath(sys.argv[2])
HERE = os.path.dirname(os.path.abspath(__file__))
DBN, PORT, PW = 'pt_mail_e2e', 8766, 'Test-Pass-2026'
URL = f'http://127.0.0.1:{PORT}/'
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
R = []
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:300]})
    print(('PASS ' if cond else 'FAIL ') + area + ': ' + name + ('' if cond else '  -> ' + str(detail)[:300]), file=sys.stderr)
def sql(q):
    p = subprocess.run(PG + ['-d', DBN, '-c', q], capture_output=True, text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()
def sqlfile(f):
    return subprocess.run(PG + ['-d', DBN, '-f', f], capture_output=True, text=True)
def calls(): return json.loads(urllib.request.urlopen(URL + '__sb/calls').read())

subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 39)]:
    path = os.path.join(DBDIR, f)
    if not os.path.exists(path): continue
    p = sqlfile(path)
    if p.returncode: raise SystemExit(f + ': ' + p.stderr)
people = [('sa', 'Sara Admin', 'sa'), ('pm', 'Paul Manager', 'pm'), ('e1', 'Eng. Omar Engineer', 'eng'), ('e2', 'Eng. Hadi Other', 'eng'),
          ('s1', 'Samir SiteManager', 'sm'), ('f1', 'Faisal Foreman', 'foreman'), ('c1', 'Carla Costing', 'costing'), ('pl', 'Peter Planner', 'plan'), ('rp', 'Rana RegionalPlanning', 'plan')]
U = {k: f'20000000-0000-0000-0000-0000000000{i:02d}' for i, (k, _, _) in enumerate(people, 1)}
sql("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k, _, _ in people))
sql("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, n, r in people))
sql("""insert into regions (id, name) values ('R1','Central'); insert into sectors (id, name) values ('S1','Buildings');
insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values ('P1','Test Tower','TT','R1','S1','2026-08-01','2026-12-31',50,'Active');""")
sql("insert into project_access (user_id, project_id) values " + ",".join(f"('{U[k]}','P1')" for k in ['pm', 'e1', 'e2', 's1', 'f1', 'c1', 'pl', 'rp']))
sql(f"insert into approval_matrix (project_id, kind, from_user, to_user) values ('P1','fm','{U['f1']}','{U['e1']}'), ('P1','eng','{U['e1']}','{U['s1']}')")
sql("""insert into activities (id, project_id, name, cls, disc, area, wbs, uom, qty, budget_mh, p6_mh, price_weight, bs, bf) values
 ('TT-100','P1','Raft concrete','CON','Civil','Zone A','Structure Works','m3',1000,2000,2000,100000,'2026-09-01','2026-09-30')""")
for i, d in [(1, '2026-09-20'), (2, '2026-09-21')]:
    sql(f"insert into dprs (id, project_id, report_date, foreman, status, created_by) values ('DPR-000{i}','P1','{d}','Faisal Foreman','Approved','{U['f1']}')")
    sql(f"insert into dpr_lines (dpr_id, activity_id, qty, labour) values ('DPR-000{i}','TT-100',40,'[{{\"cat\":\"Carpenter\",\"count\":5,\"reg\":8,\"ot\":0}}]')")
    sql(f"insert into dpr_audit (dpr_id, action, by_user) values ('DPR-000{i}','Submitted','{U['f1']}'), ('DPR-000{i}','Reviewed','{U['e1']}'), ('DPR-000{i}','Approved','{U['s1']}')")
sql(f"insert into report_releases (id, project_id, kind, period_type, period, rev, status, approved_by, approved_at, figures) values ('30000000-0000-0000-0000-000000000001','P1','planning','month','2026-09',0,'Released','{U['rp']}',now(),'{{\"planned_pct\":40,\"actual_pct\":38}}')")

srv = subprocess.Popen([sys.executable, os.path.join(HERE, 'fake_supabase.py'), APP, DBN, str(PORT)])
import atexit; atexit.register(srv.terminate)
for _ in range(50):
    try: urllib.request.urlopen(URL + 'config.js', timeout=1); break
    except Exception: time.sleep(0.2)
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
FAKE = urllib.request.urlopen(URL + '__sb/client.js').read().decode()
def route(r):
    u = r.request.url
    if u.startswith(URL): return r.continue_()
    if 'supabase' in u: return r.fulfill(body=FAKE, content_type='application/javascript')
    if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
    return r.abort()

with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    ctx = b.new_context(viewport={'width': 1440, 'height': 900}); ctx.route('**/*', route); errs = []
    pg = ctx.new_page(); pg.on('pageerror', lambda e: errs.append(str(e))); pg.goto(URL); pg.wait_for_timeout(900)
    def login(who):
        if pg.locator('#app').is_visible(): pg.evaluate("signOut()"); pg.wait_for_timeout(700)
        pg.fill('#lgId', f'{who}@test.local'); pg.fill('#lgPw', PW); pg.click('#lgBtn')
        pg.wait_for_selector('#app', state='visible', timeout=15000); pg.wait_for_timeout(2500)
        pg.evaluate("window.aiHint=()=>{};window.rasaBubble=()=>{}")
    J = pg.evaluate

    # ---- the approver's daily report email
    login('s1')
    ck('Server', 'the app sees the v38 mail queue', J("mailSrv().queue") is True)
    n0 = len(calls())
    r = J("sendApprovalMail(DB.dprs.find(d=>d.id==='DPR-0001')).then(n=>({n,st:DB.outbox[0].status,kind:DB.outbox[0].kind,srv:!!DB.outbox[0].srv,to:DB.outbox[0].to.length}))"); pg.wait_for_timeout(500)
    row = sql("select status||'|'||(select string_agg(x->>'name', ',' order by x->>'name') from jsonb_array_elements(recipients) x) from mail_outbox where kind='dpr' and ref='DPR-0001'")
    ck('Daily report', "the approver's email is queued on the server with the recipients the server worked out (roles with access; site roles only from the chain; no foreman)",
       row == 'queued|Carla Costing,Eng. Omar Engineer,Paul Manager,Peter Planner,Rana RegionalPlanning,Samir SiteManager,Sara Admin', row)
    mid = sql("select id from mail_outbox where kind='dpr' and ref='DPR-0001'")
    C = calls()[n0:]
    ck('Daily report', 'the app then asks the send-mail function to send that email, by its id only', any(c.get('name') == 'send-mail' and (c.get('body') or {}) == {'id': mid} for c in C), C)
    ck('Daily report', "the outbox shows the server's email; the approver is not told it was emailed while it is not sent", r and r['srv'] and r['kind'] == 'dpr' and r['st'].startswith('Queued') and r['n'] == 0 and r['to'] == 7, r)
    ck('Daily report', 'the approver sees why it is not sent yet', 'not sent yet' in (J("document.querySelector('#toast')&&document.querySelector('#toast').textContent") or ''), J("document.querySelector('#toast')&&document.querySelector('#toast').textContent"))
    r = J("sendApprovalMail(DB.dprs.find(d=>d.id==='DPR-0001')).then(()=>DB.outbox.filter(m=>m.ref==='DPR-0001').length)")
    ck('Daily report', 'approving twice does not queue a second email', r == 1 and sql("select count(*) from mail_outbox where ref='DPR-0001'") == '1', r)

    # ---- others
    login('pm')
    r = J("rpc('mail_queue',{p:{kind:'dpr',ref:'DPR-0002',subject:'x',html:'<p>x</p>'}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Refusals', 'someone who did not approve the report cannot queue its email', r.startswith('refused') and 'only the person who approved' in r.lower(), r)
    r = J("rpc('mail_queue',{p:{kind:'dpr',ref:'DPR-0001',subject:'x',html:'<p>x</p>'}}).then(x=>'ran '+JSON.stringify(x),e=>'refused: '+e.message)")
    ck('Refusals', '...nor read the recipients of one already queued', r.startswith('refused'), r)
    r = J("SB.from('mail_outbox').select('id').then(x=>x.error?'err':String((x.data||[]).length))")
    ck('Refusals', 'a person sees only the emails he queued', r == '0', r)
    r = J("SB.from('mail_outbox').insert({kind:'test',ref:'x',subject:'s',html:'h'}).then(x=>x.error?'refused':'ran')")
    ck('Refusals', 'nobody writes the outbox directly', r == 'refused', r)
    r = J("SB.from('mail_config').update({enabled:false}).eq('id',1).select('id').then(x=>x.error?'err':String((x.data||[]).length))")
    ck('Refusals', 'only the super admin changes the approval email settings', r in ('err', '0') and sql("select enabled from mail_config where id=1") == 't', r)

    # ---- the report email
    login('rp')
    n0 = len(calls())
    r = J("(()=>{const x=relRows().find(r=>r.kind==='planning'&&r.status==='Released');return x?sendReleaseMail(x).then(n=>({n,kind:DB.outbox[0].kind})):null})()"); pg.wait_for_timeout(500)
    row = sql("select (select string_agg(x->>'name', ',' order by x->>'name') from jsonb_array_elements(recipients) x) from mail_outbox where kind='release'")
    ck('Report email', 'the approved internal report email goes to the default internal report list (roles with access)', r and r['kind'] == 'release' and row == 'Paul Manager,Peter Planner,Rana RegionalPlanning', (r, row))
    ck('Report email', '...and is handed to the function by its id', any(c.get('name') == 'send-mail' and list((c.get('body') or {}).keys()) == ['id'] for c in calls()[n0:]))

    # ---- Settings -> Email as super admin
    login('sa')
    J("state.scope='ALL';go('admin');state.adminTab='mail';render()"); pg.wait_for_timeout(1500)
    v = pg.inner_text('#view')
    ck('Settings', 'Settings → Email shows the mail service and every email, with Send again for the ones not sent', 'Mail service' in v and pg.locator('[data-mailretry]').count() == 2, v[:300])
    ck('Settings', 'the mail service check asks the function, and says when it is not ready', any(c.get('name') == 'send-mail' and (c.get('body') or {}).get('ping') for c in calls()) and 'Not ready' in pg.inner_text('#mailSrvState'), pg.inner_text('#mailSrvState'))
    n0 = len(calls())
    pg.click('[data-mailtest]'); pg.wait_for_timeout(1500)
    ck('Settings', "a super admin's test email is queued to himself and handed to the function", sql("select count(*) from mail_outbox where kind='test' and recipients->0->>'email'='sa@test.local'") == '1' and any(c.get('name') == 'send-mail' and (c.get('body') or {}).get('id') for c in calls()[n0:]))
    sql(f"update mail_outbox set status='failed', error='mailbox unavailable', attempts=1 where id='{mid}'")
    J("cloudLoadMail().then(()=>render())"); pg.wait_for_timeout(1000)
    ck('Settings', 'a failed email shows its reason', 'Failed: mailbox unavailable' in pg.inner_text('#view'))
    pg.click(f'[data-mailopen="{mid}"]'); pg.wait_for_timeout(1200)
    ck('Settings', 'opening an email shows its recipients and fetches its body for the preview', 'Carla Costing' in pg.inner_text('#view') and pg.locator('iframe[title="Email preview"]').count() == 1 and 'Daily report approved' in (pg.locator('iframe[title="Email preview"]').get_attribute('srcdoc') or ''))
    n0 = len(calls())
    pg.click(f'[data-mailretry="{mid}"]'); pg.wait_for_timeout(1500)
    ck('Settings', 'Send again puts it back in the queue on the server and hands it to the function', sql(f"select status||'/'||coalesce(error,'') from mail_outbox where id='{mid}'") == 'queued/' and any((c.get('body') or {}) == {'id': mid} for c in calls()[n0:]))
    n0 = len(calls())
    pg.click('[data-mailpending]'); pg.wait_for_timeout(1200)
    ck('Settings', 'Send queued emails now asks the function to send the queue', any((c.get('body') or {}).get('pending') is True for c in calls()[n0:]))
    pg.uncheck('[data-mailrole="costing"]'); pg.wait_for_timeout(1200)
    ck('Settings', 'the approval email settings are saved on the server by the super admin', sql("select not ('costing' = any(roles)) from mail_config where id=1") == 't')
    pg.uncheck('[data-mailcfg="on"]'); pg.wait_for_timeout(1200)
    ck('Settings', '...including switching it off', sql("select enabled from mail_config where id=1") == 'f')
    sql("update mail_config set enabled = true, roles = array['eng','sm','pm','pf','plan','costing','exec','sa'] where id=1")

    # ---- without the v38 update
    p2 = sqlfile(os.path.join(DBDIR, 'schema-rollback-v38.sql'))
    ck('Without v38', 'the rollback runs', p2.returncode == 0, p2.stderr[:200])
    login('s1'); n0 = len(calls())
    r = J("sendApprovalMail(DB.dprs.find(d=>d.id==='DPR-0002')).then(n=>({n,st:DB.outbox[0].status}))")
    ck('Without v38', 'the email is listed as not sent with the reason, and nothing is handed to a function', r['n'] == 0 and 'needs the v38 update' in r['st'] and not any(c.get('name') in ('send-mail', 'send-daily-report') for c in calls()[n0:]), r)
    login('sa'); J("state.scope='ALL';go('admin');state.adminTab='mail';render()"); pg.wait_for_timeout(800)
    ck('Without v38', 'Settings → Email says emails are not sent until the v38 update and the function are installed', 'Emails are not sent yet' in pg.inner_text('#view'))
    p3 = sqlfile(os.path.join(DBDIR, 'schema-update-v38.sql'))
    ck('Without v38', 'v38 runs again and keeps every email', p3.returncode == 0 and int(sql('select count(*) from mail_outbox')) >= 3, p3.stderr[:200])
    ck('Page', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'suite': 'mail_e2e', 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
