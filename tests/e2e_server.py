#!/usr/bin/env python3
"""ProTrackAI v2.5+ (extended to v3.6) in server mode, end to end: the real app in Chromium, talking to a local PostgreSQL built
from the real ProTrack schema (schema.sql + v2 ... v9, then v10 to v17 applied mid-run as on a live database) through fake_supabase.py.
Every allow/refuse decision in these tests is made by the database (row level security and the v4
functions), exactly as on Supabase. What is NOT covered: Supabase's own sign-in service, its REST layer
and the email function; those are replaced by the stand-in.
Usage: python3 e2e_server.py APP_HTML DB_DIR  > results_server.json"""
import json, os, subprocess, sys, time, urllib.request
from playwright.sync_api import sync_playwright

APP = os.path.abspath(sys.argv[1]); DBDIR = os.path.abspath(sys.argv[2])
HERE = os.path.dirname(os.path.abspath(__file__))
DBN, PORT, PW = 'pt_e2e', 8765, 'Test-Pass-2026'
URL = f'http://127.0.0.1:{PORT}/'
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
R = []

def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:300]})
    print(('PASS ' if cond else 'FAIL ') + area + ': ' + name + ('' if cond else '  -> ' + str(detail)[:300]), file=sys.stderr)

def sql(q, db=DBN):
    p = subprocess.run(PG + ['-d', db, '-c', q], capture_output=True, text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()

# ------------------------------------------------------------------ database
subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql', 'schema-update-v4.sql', 'schema-update-v5.sql', 'schema-update-v6.sql', 'schema-update-v7.sql', 'schema-update-v8.sql', 'schema-update-v9.sql']:
    p = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, f)], capture_output=True, text=True)
    if p.returncode: raise SystemExit(f + ': ' + p.stderr)
people = [('sa', 'Sara Admin', 'sa'), ('pm', 'Paul Manager', 'pm'), ('e1', 'Eng. Omar Engineer', 'eng'), ('e2', 'Eng. Hadi Other', 'eng'),
          ('s1', 'Samir SiteManager', 'sm'), ('f1', 'Faisal Foreman', 'foreman'), ('f2', 'Fahad Foreman', 'foreman'),
          ('c1', 'Carla Costing', 'costing'), ('pl', 'Peter Planner', 'plan'), ('cc', 'Cora Coordinator', 'costing'), ('hd', 'Hana Head', 'plan'), ('rp', 'Rana RegionalPlanning', 'plan')]
U = {k: f'10000000-0000-0000-0000-0000000000{i:02d}' for i, (k, _, _) in enumerate(people, 1)}
sql("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k, _, _ in people))
sql("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, n, r in people))
sql("""insert into regions values ('R1','Central',null); insert into sectors values ('S1','Buildings');
insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values
 ('P1','Test Tower','TT','R1','S1','2026-08-01','2026-12-31',50,'Active');""")
sql("insert into project_access (user_id, project_id) values " + ",".join(f"('{U[k]}','P1')" for k in ['pm', 'e1', 'e2', 's1', 'f1', 'f2', 'c1', 'pl']))
sql("""insert into activities (id, project_id, name, cls, disc, area, wbs, uom, qty, budget_mh, p6_mh, price_weight, bs, bf) values
 ('TT-100','P1','Raft concrete','CON','Civil','Zone A','Structure Works','m3',1000,2000,2000,100000,'2026-09-01','2026-09-30'),
 ('TT-110','P1','Column rebar','CON','Civil','Zone A','Structure Works','t',200,1600,1600,50000,'2026-09-01','2026-10-31'),
 ('TT-E01','P1','Shop drawings','ENG','Civil','Design','Engineering','%',100,300,300,20000,'2026-08-01','2026-09-30');""")
sql(f"insert into approval_matrix (project_id, kind, from_user, to_user) values ('P1','fm','{U['f1']}','{U['e1']}'), ('P1','eng','{U['e1']}','{U['s1']}')")

srv = subprocess.Popen([sys.executable, os.path.join(HERE, 'fake_supabase.py'), APP, DBN, str(PORT)])
import atexit; atexit.register(srv.terminate)
for _ in range(50):
    try: urllib.request.urlopen(URL + 'config.js', timeout=1); break
    except Exception: time.sleep(0.2)

CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
XLSX_STUB = """window.XLSX={read:function(ab){var j=JSON.parse(new TextDecoder().decode(new Uint8Array(ab)));var n=j.sheet||'Sheet1';var o={SheetNames:[n],Sheets:{}};o.Sheets[n]={aoa:j.aoa};return o},
utils:{sheet_to_json:function(ws){return ws.aoa||[]},aoa_to_sheet:function(a){return{aoa:a}},json_to_sheet:function(){return{}},book_new:function(){return{SheetNames:[],Sheets:{}}},book_append_sheet:function(wb,ws,n){wb.SheetNames.push(n);wb.Sheets[n]=ws},encode_range:function(){return'A1'},decode_range:function(){return{s:{r:0,c:0},e:{r:0,c:0}}},encode_cell:function(){return'A1'}},
write:function(){return new Uint8Array([80,75,3,4])},writeFile:function(){}};"""
FAKE = urllib.request.urlopen(URL + '__sb/client.js').read().decode()

def route(r):
    u = r.request.url
    if u.startswith(URL): return r.continue_()
    if 'supabase' in u: return r.fulfill(body=FAKE, content_type='application/javascript')
    if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
    if 'xlsx' in u.lower(): return r.fulfill(body=XLSX_STUB, content_type='application/javascript')
    return r.abort()

def book(aoa, sheet, name):
    return {'name': name, 'mimeType': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'buffer': json.dumps({'sheet': sheet, 'aoa': aoa}).encode()}

with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    ctx = b.new_context(viewport={'width': 1440, 'height': 900}, accept_downloads=True)
    ctx.route('**/*', route)
    errs = []

    def new_page(seed_local=None):
        pg = ctx.new_page(); pg.on('pageerror', lambda e: errs.append(str(e)))
        if seed_local: pg.add_init_script(seed_local)
        pg.goto(URL); pg.wait_for_timeout(900); return pg

    def login(pg, who, expect_ok=True):
        try: pg.wait_for_function("(()=>{const a=document.querySelector('#app'),l=document.querySelector('#lgPw');return (a&&a.offsetParent!==null)||(l&&l.offsetParent!==null)})()", timeout=15000)
        except Exception: pass  # after a reload the app may still be restoring the session
        if pg.locator('#app').is_visible():
            pg.evaluate("signOut()"); pg.wait_for_timeout(700)
        pg.fill('#lgId', f'{who}@test.local'); pg.fill('#lgPw', PW); pg.click('#lgBtn'); pg.wait_for_timeout(1200)
        if expect_ok:
            try: pg.wait_for_selector('#app', state='visible', timeout=12000)
            except Exception: pass
        pg.wait_for_timeout(1400)
        pg.evaluate("window.aiHint=()=>{};window.rasaBubble=()=>{}")
        if expect_ok and not pg.locator('#app').is_visible(): raise RuntimeError('sign-in failed for ' + who + ': ' + pg.inner_text('#lgErr'))

    def cfm(pg):
        pg.wait_for_timeout(300)
        if pg.locator('[data-cfm="1"]').count(): pg.click('[data-cfm="1"]'); pg.wait_for_timeout(500)

    # ---------------------------------------------------------------- sign-in screen
    pg = new_page()
    txt = pg.inner_text('#authCard')
    ck('Sign-in', 'demo accounts are not offered on a server site', pg.locator('details.demo').count() == 0 and 'demo accounts are switched off' in txt.lower(), txt[:200])
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1500)
    ck('Sign-in', 'a demo account and password do not open the app', not pg.locator('#app').is_visible(), pg.inner_text('#lgErr'))
    pg.fill('#lgId', 'U28'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(800)
    ck('Sign-in', 'a username (not an email) is refused with a clear message', not pg.locator('#app').is_visible() and 'work email' in pg.inner_text('#lgIdErr'), pg.inner_text('#lgIdErr'))
    pg.close()

    # ---------------------------------------------------------------- foreman: create and submit
    pg = new_page(); login(pg, 'f1')
    st = pg.evaluate("({users:DB.master.users.map(u=>u.name).sort(),acts:ACTS.map(a=>a.id),dprs:DB.dprs.length,role:state.role,demoUser:!!DB.master.users.find(u=>u.email==='asarudeen@company.com')})")
    ck('Load', 'people come from the server directory, no demo accounts', not st['demoUser'] and 'Eng. Omar Engineer' in st['users'] and 'Faisal Foreman' in st['users'], st)
    ck('Load', 'activities come from the server only', sorted(st['acts']) == ['TT-100', 'TT-110', 'TT-E01'], st['acts'])
    ck('Load', 'no reports yet', st['dprs'] == 0, st)
    ck('Load', 'side note says data is on the server', 'checked by the server' in pg.inner_text('#sideNote'), pg.inner_text('#sideNote'))
    pg.evaluate("go('new')"); pg.wait_for_timeout(1200)
    pg.fill('[data-lk="qty"][data-l="0"]', '40'); pg.wait_for_timeout(600)
    pg.click('[data-save="submit"]'); pg.wait_for_timeout(2500)
    row = sql("select id||'|'||status||'|'||foreman||'|'||coalesce(foreman_id::text,'')||'|'||(select count(*) from dpr_lines l where l.dpr_id=d.id)||'|'||coalesce((timing->'create'->>'secs'),'0') from dprs d order by id desc limit 1")
    rid = row.split('|')[0] if row else ''
    ck('Reports', 'foreman submits through the server', row and row.split('|')[1] == 'Submitted' and row.split('|')[2] == 'Faisal Foreman' and row.split('|')[3] == U['f1'], row)
    ck('Reports', 'preparation time stored on the server', row and int(row.split('|')[5]) >= 1, row)
    ck('Reports', 'app shows the server copy', pg.evaluate(f"(DB.dprs.find(d=>d.id==='{rid}')||{{}}).status") == 'Submitted')
    ck('Reports', 'audit chain on the server verifies', sql(f"select dpr_audit_verify('{rid}')") == 't')
    # same foreman, same day: server refuses, form stays with the message
    pg.evaluate("go('new')"); pg.wait_for_timeout(1000); pg.fill('[data-lk="qty"][data-l="0"]', '5'); pg.wait_for_timeout(400)
    pg.click('[data-save="submit"]'); pg.wait_for_timeout(1800)
    msg = pg.inner_text('#formErr') if pg.locator('#formErr').count() else ''
    ck('Reports', 'server refusal shown on the form, nothing saved locally', 'already has a report' in msg and pg.evaluate("DB.dprs.length") == 1 and sql("select count(*) from dprs") == '1', msg)
    # tampered client: foreman tries to approve through the server
    pg.evaluate(f"openDpr('{rid}')"); pg.wait_for_timeout(900)
    pg.evaluate(f"cloudAct(DB.dprs.find(d=>d.id==='{rid}'),'approve','')"); pg.wait_for_timeout(1500)
    ck('Reports', 'forced approval by a foreman is refused by the server', sql(f"select status from dprs where id='{rid}'") == 'Submitted' and 'refused' in pg.inner_text('#toast').lower(), pg.inner_text('#toast'))
    pg.keyboard.press('Escape')

    # ---------------------------------------------------------------- unassigned engineer
    login(pg, 'e2')
    ck('Approval', 'unassigned engineer is not offered Review', 'review' not in pg.evaluate(f"actionsFor(DB.dprs.find(d=>d.id==='{rid}'))"))
    pg.evaluate(f"openDpr('{rid}')"); pg.wait_for_timeout(800)
    pg.evaluate(f"cloudAct(DB.dprs.find(d=>d.id==='{rid}'),'review','')"); pg.wait_for_timeout(1500)
    ck('Approval', 'forced review by an unassigned engineer is refused', sql(f"select status from dprs where id='{rid}'") == 'Submitted' and 'not the reviewer' in pg.inner_text('#toast'), pg.inner_text('#toast'))
    pg.keyboard.press('Escape')

    # ---------------------------------------------------------------- assigned engineer reviews, site manager approves
    login(pg, 'e1')
    pg.evaluate(f"openDpr('{rid}')"); pg.wait_for_timeout(2200)
    pg.click('#sheet [data-do="review"]'); pg.wait_for_timeout(2000)
    ck('Approval', 'assigned engineer reviews through the server', sql(f"select status from dprs where id='{rid}'") == 'Reviewed')
    pg.keyboard.press('Escape')
    login(pg, 's1')
    ck('Approval', 'assigned site manager is offered Approve', 'approve' in pg.evaluate(f"actionsFor(DB.dprs.find(d=>d.id==='{rid}'))"))
    pg.evaluate(f"openDpr('{rid}')"); pg.wait_for_timeout(2200)
    pg.click('#sheet [data-do="approve"]'); pg.wait_for_timeout(3000)
    ck('Approval', 'assigned site manager approves through the server', sql(f"select status from dprs where id='{rid}'") == 'Approved')
    ck('Approval', 'review and approval time stored', sql(f"select (timing ? 'review') and (timing ? 'approve') from dprs where id='{rid}'") == 't')
    trail = pg.evaluate(f"DB.dprs.find(d=>d.id==='{rid}').audit.map(a=>a.action+':'+a.who)")
    ck('Approval', 'history in the app comes from the server with names', trail == ['Draft created:Faisal Foreman', 'Submitted:Faisal Foreman', 'Reviewed:Eng. Omar Engineer', 'Approved:Samir SiteManager'], trail)
    calls = json.loads(urllib.request.urlopen(URL + '__sb/calls').read())
    ck('Email', 'approval email handed to the server function with recipients', any(c.get('name') == 'send-daily-report' and (c.get('body') or {}).get('to') for c in calls), calls[-1:] if calls else calls)
    pg.keyboard.press('Escape')
    login(pg, 'pm')
    pg.evaluate(f"state.editing='{rid}';cloudSaveDpr({{p:'P1',date:'2026-09-20',foreman:'Faisal Foreman',remarks:'x',attachments:[]}},[{{act:'TT-100',qty:999,labour:[],subs:[],equip:[]}}],'draft',{{set textContent(v){{window.__err=v}}}})"); pg.wait_for_timeout(1500)
    ck('Approval', 'approved report cannot be edited, even by the project manager', 'cannot be edited' in (pg.evaluate("window.__err") or '') and sql(f"select sum(qty) from dpr_lines where dpr_id='{rid}'") == '40', pg.evaluate("window.__err"))
    pg.evaluate("state.editing=null")

    # ---------------------------------------------------------------- approval matrix
    login(pg, 'sa')
    pg.evaluate("go('admin');state.adminTab='matrix';render()"); pg.wait_for_timeout(1000)
    sel = f'[data-mx="P1:fm:{U["f1"]}"]'
    ck('Matrix', 'matrix shows the server assignment', pg.locator(sel).count() == 1 and pg.eval_on_selector(sel, 'e=>e.value') == U['e1'], pg.locator(sel).count())
    pg.select_option(sel, U['e2']); pg.wait_for_timeout(1800)
    ck('Matrix', 'super admin change is saved on the server', sql(f"select to_user from approval_matrix where project_id='P1' and kind='fm' and from_user='{U['f1']}'") == U['e2'])
    pg.select_option(sel, U['e1']); pg.wait_for_timeout(1500)
    login(pg, 'pm')
    ok = pg.evaluate(f"cloudSetMatrix('P1','fm','{U['f1']}','{U['e2']}')"); pg.wait_for_timeout(800)
    ck('Matrix', 'project manager cannot change the matrix (server refuses)', ok is False and sql(f"select to_user from approval_matrix where project_id='P1' and kind='fm' and from_user='{U['f1']}'") == U['e1'], ok)

    # ---------------------------------------------------------------- people (super admin)
    sql("insert into auth.users (id, email) values ('10000000-0000-0000-0000-000000000099','newbie@test.local')")
    login(pg, 'sa')
    pg.evaluate("go('admin');state.adminTab='users';render();admDrawer('users')"); pg.wait_for_timeout(800)
    ck('People', 'create-person form explains the Supabase step', 'Add user' in pg.inner_text('#admForm'), pg.inner_text('#admForm')[-300:])
    pg.fill('#admForm [name="name"]', 'Nadia Newbie'); pg.fill('#admForm [name="email"]', 'newbie@test.local')
    pg.select_option('#admForm [name="role"]', 'eng'); pg.wait_for_timeout(200)
    pg.eval_on_selector('#admForm [name="projects"][value="P1"]', 'e=>{e.checked=true}'); pg.click('#admForm [type=submit]'); pg.wait_for_timeout(2500)
    ck('People', 'super admin adds a person with role and project access on the server',
       sql("select p.name||'/'||p.role||'/'||(select string_agg(project_id, ',') from project_access where user_id=p.id) from profiles p where id='10000000-0000-0000-0000-000000000099'") == 'Nadia Newbie/eng/P1')
    ck('People', 'the new person appears with the server identity', pg.evaluate("!!DB.master.users.find(u=>u.id==='10000000-0000-0000-0000-000000000099')"))
    pg.evaluate("admDrawer('users')"); pg.wait_for_timeout(600)
    pg.fill('#admForm [name="name"]', 'Ghost Person'); pg.fill('#admForm [name="email"]', 'ghost@test.local')
    pg.select_option('#admForm [name="role"]', 'eng'); pg.eval_on_selector('#admForm [name="projects"][value="P1"]', 'e=>{e.checked=true}'); pg.click('#admForm [type=submit]'); pg.wait_for_timeout(2000)
    ck('People', 'a person without a sign-in account is refused with the next step', 'Add user' in pg.inner_text('#admErr') and pg.evaluate("!DB.master.users.some(u=>u.email==='ghost@test.local')"), pg.inner_text('#admErr'))
    pg.evaluate("closeDrawer()")

    # ---------------------------------------------------------------- costing and invoices
    login(pg, 'c1')
    pg.evaluate("state.impPid='P1';go('base')"); pg.wait_for_timeout(1000)
    head = ['Activity ID', 'Description', 'Budget quantity', 'UOM', 'Unit rate', 'Budget cost', 'Budget manhours']
    aoa = [head, ['TT-100', 'Raft', 1000, 'm3', 300, 300000, 2100], ['TT-110', 'Rebar', 200, 't', 2500, 500000, 0], ['NOPE', 'x', 1, 'm', 1, 1, 1]]
    pg.set_input_files('#costfile', book(aoa, 'Costing', 'costing_TT.xlsx')); pg.wait_for_timeout(1200)
    ck('Costing', 'refused row must be acknowledged before applying', pg.is_disabled('[data-costgo]'))
    pg.check('#reconAck'); pg.click('[data-costgo]'); pg.wait_for_timeout(2500)
    ck('Costing', 'costing file applied on the server', sql("select budget_cost||'/'||budget_mh||'/'||costed from activities where id='TT-100'") == '300000/2100/true', sql("select budget_cost||'/'||budget_mh from activities where id='TT-100'"))
    ck('Costing', 'app shows the server values', pg.evaluate("(()=>{const a=ACTS.find(x=>x.id==='TT-100');return a.bcost===300000&&a.bmh===2100})()"))
    q = sql("select count(*)||'/'||min(length(file_hash))||'/'||min(length(file_sha256))||'/'||min(recon_status)||'/'||(min(recon_diff)=1)||'/'||bool_and(recon_accepted_by is not null) from import_batches where kind='costing'")
    ck('Costing', 'upload recorded as a batch with fingerprints and the confirmed difference', q == '1/64/64/Accepted with difference/true/true', q)
    pg.set_input_files('#costfile', book(aoa, 'Costing', 'costing_TT.xlsx')); pg.wait_for_timeout(1200); pg.check('#reconAck'); pg.click('[data-costgo]'); pg.wait_for_timeout(2000)
    ck('Costing', 'same file again changes nothing', sql("select count(*) from import_batches where kind='costing'") == '1' and sql("select count(*) from baseline_history") == '1')
    ihead = ['Invoice number', 'Invoice date', 'Type', 'Invoice amount (SAR)', 'Submitted amount (SAR)', 'Approved amount (SAR)', 'Collected amount (SAR)', 'Remark']
    inv = [ihead, ['INV-1', '2026-08-31', 'Progress', 1000000, 1000000, 900000, 800000, 'IPC 1'], ['INV-ADV', '2026-08-01', 'Advance', 2000000, 2000000, 2000000, 2000000, 'Advance']]
    pg.set_input_files('#invfile', book(inv, 'Invoices', 'invoices_TT.xlsx')); pg.wait_for_timeout(1200)
    pg.click('[data-invgo]'); pg.wait_for_timeout(2500)
    ck('Invoices', 'register loaded on the server', sql("select count(*)||'/'||sum(submitted) from invoices where project_id='P1'") == '2/3000000')
    ck('Invoices', 'app totals come from the server', pg.evaluate("invTotals('P1').submitted") == 3000000 and 'Carla Costing' in pg.evaluate("(DB.invMeta.P1||{}).by||''"), pg.evaluate("DB.invMeta.P1"))
    ck('Invoices', 'clean register reconciles as Matched', sql("select recon_status from import_batches where kind='invoices' order by seq desc limit 1") == 'Matched')
    # a commit that fails half way on the server: nothing saved, failure logged, retry linked
    sql("create function test_boom() returns trigger language plpgsql as $$ begin if new.invoice_no = 'BOOM' then raise exception 'disk full (simulated)'; end if; return new; end $$; create trigger test_boom before insert on invoices for each row execute function test_boom();")
    inv2 = [ihead, ['INV-1', '2026-08-31', 'Progress', 1000000, 1000000, 900000, 800000, 'IPC 1'], ['BOOM', '2026-09-30', 'Progress', 5, 5, 0, 0, '']]
    pg.set_input_files('#invfile', book(inv2, 'Invoices', 'invoices_TT_v2.xlsx')); pg.wait_for_timeout(1200)
    pg.click('[data-invgo]'); pg.wait_for_timeout(2500)
    ck('Failures', 'a failed commit leaves the previous register intact', sql("select count(*)||'/'||sum(submitted) from invoices where project_id='P1'") == '2/3000000' and 'Nothing was saved' in pg.inner_text('#toast'), pg.inner_text('#toast'))
    ck('Failures', 'the failure is logged with its reason', sql("select status||'|'||error_message from import_batches order by seq desc limit 1") == 'failed|disk full (simulated)')
    sql("drop trigger test_boom on invoices")
    pg.click('[data-invgo]'); pg.wait_for_timeout(2500)
    ck('Failures', 'retry succeeds and is linked to the failure', sql("select (retry_of is not null)||'/'||status from import_batches order by seq desc limit 1") == 'true/committed' and sql("select count(*) from invoices where project_id='P1'") == '2')
    pg.evaluate("go('imp')"); pg.wait_for_timeout(1000)
    v = pg.inner_text('#view')
    ck('Import centre', 'server batches listed with results, failure shown as retried', 'Failed, retried' in v and 'Committed with difference' in v and v.count('IMP-') >= 4, v[:600])
    login(pg, 'f1')
    r = pg.evaluate("rpc('import_invoices',{p_project:'P1',p_file:'x',p_hash:'f'.repeat(64),p_rows:[],p_period:null}).then(()=>'ran',e=>e.message)")
    ck('Invoices', 'a foreman calling the invoice import is refused', 'Only costing' in r, r)
    r = pg.evaluate("rpc('import_baseline',{p_project:'P1',p_file:'x',p_hash:'e'.repeat(64),p_rows:[{id:'Z1',name:'Z'}]}).then(()=>'ran',e=>e.message)")
    ck('Baseline', 'a foreman calling the baseline import is refused', 'Only planning' in r, r)

    # ---------------------------------------------------------------- planner: hand-added activity, weekly update path
    login(pg, 'pl')
    ok = pg.evaluate("cloudRunBaseline('P1',[{id:'TT-120',name:'Blockwork',cls:'CON',disc:'Civil',area:'Zone B',wbs:'Masonry',uom:'m2',qty:500,bmh:900,pw:20000,bs:'2026-10-01',bf:'2026-11-15',priorQty:0}],'Added by hand: TT-120')"); pg.wait_for_timeout(1500)
    ck('Baseline', 'planner adds an activity through the server', ok is True and sql("select name from activities where id='TT-120'") == 'Blockwork' and pg.evaluate("!!ACTS.find(a=>a.id==='TT-120')"), ok)

    pg.evaluate("go('upd')"); pg.wait_for_timeout(900)
    ck('E&P progress', 'no separate E&P upload on live: the page reads the updated P6 schedule (v3.8.4)', pg.locator('#updfile').count() == 0 and 'weekly updated P6 schedule' in pg.inner_text('#view'), pg.inner_text('#view')[:300])
    login(pg, 'f1')
    r = pg.evaluate("rpc('import_commit',{p:{kind:'update',project_id:null,file_name:'upd2.xlsx',hash:'a'.repeat(64),data_date:'2026-09-22',rows:[{project_id:'P1',id:'TT-E01',ms:'IFC'}]}}).then(()=>'ran',e=>'refused: '+e.message)"); pg.wait_for_timeout(800)
    ck('E&P progress', 'a foreman still cannot change progress through the old import (server refuses)', sql("select coalesce(cur->>'ms','') from activities where id='TT-E01'") == '' and 'refused' in r, r)

    # ---------------------------------------------------------------- lifecycle through the server
    login(pg, 'pm')
    pg.evaluate("state.scope='P1';go('proj')"); pg.wait_for_timeout(1000)
    ck('Lifecycle', 'twelve stages shown, all Not started on a new server project', pg.locator('.lc12g .lc-card').count() == 12 and sql("select count(*) from lifecycle_stages") == '0')
    pg.evaluate("openStage('P1',6)"); pg.wait_for_timeout(500)
    pg.select_option('#lcForm [name="owner"]', U['pl']); pg.fill('#lcForm [name="due_date"]', '2026-10-30'); pg.click('[data-lcdo="update"]'); pg.wait_for_timeout(1500)
    ck('Lifecycle', 'the project manager assigns the owner on the server', sql("select owner::text||'/'||due_date from lifecycle_stages where stage_no=6") == U['pl'] + '/2026-10-30')
    pg.evaluate("closeDrawer()")
    login(pg, 'f1')
    r = pg.evaluate("rpc('lifecycle_act',{p:{project_id:'P1',stage_no:6,action:'update',ticks:[{k:'prepared',done:true}]}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Lifecycle', 'a foreman calling the server directly is refused', r.startswith('refused') and sql("select count(*) from lifecycle_audit") == '1', r)
    login(pg, 'pl')
    pg.evaluate("state.scope='P1';go('proj')"); pg.wait_for_timeout(900)
    pg.evaluate("openStage('P1',6)"); pg.wait_for_timeout(500)
    for k in ['prepared', 'costing', 'submitted', 'approved']: pg.click(f'[data-lctick="{k}"]')
    pg.click('[data-lcdo="submit"]'); pg.wait_for_timeout(2500)
    ck('Lifecycle', 'the owner ticks and submits through the server', sql("select status||'/'||(submitted_by::text='" + U['pl'] + "') from lifecycle_stages where stage_no=6") == 'Awaiting approval/true')
    r = pg.evaluate("rpc('lifecycle_act',{p:{project_id:'P1',stage_no:6,action:'approve'}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Lifecycle', 'the owner cannot approve (server refuses)', r.startswith('refused') and sql("select status from lifecycle_stages where stage_no=6") == 'Awaiting approval', r)
    pg.evaluate("closeDrawer()")
    login(pg, 'pm')
    pg.evaluate("go('act')"); pg.wait_for_timeout(800)
    ck('Lifecycle', 'the project manager finds it in Actions and approvals', 'Stage 6, Baseline preparation and approval: approve or return' in pg.inner_text('#view'), pg.inner_text('#view')[:400])
    pg.evaluate("openStage('P1',6)"); pg.wait_for_timeout(500); pg.click('[data-lcdo="approve"]'); pg.wait_for_timeout(2500)
    ck('Lifecycle', 'the project manager approves through the server', sql("select status||'/'||(approved_by::text='" + U['pm'] + "') from lifecycle_stages where stage_no=6") == 'Complete/true')
    ck('Lifecycle', 'history in the app comes from the server', pg.evaluate("lcAudit('P1',6).map(a=>a.action).slice(-2).join(',')") == 'Submitted for approval,Approved')
    pg.evaluate("closeDrawer()")
    pg.evaluate("go('pdash')"); pg.wait_for_timeout(800)
    ck('Dashboards', 'planning dashboard shows the server project', 'TT' in pg.inner_text('#view') and 'Planning by project' in pg.inner_text('#view'))
    pg.evaluate("go('cdash')"); pg.wait_for_timeout(800)
    v = pg.inner_text('#view')
    ck('Dashboards', 'cost dashboard reconciles the costing and invoice batches', 'Source reconciliation' in v and 'IMP-' in v, v[-600:])


    # ---------------------------------------------------------------- v2.8 Tender register through the server
    login(pg, 'sa')
    for who, d in (('hd', 'head'), ('cc', 'coordinator')):
        pg.evaluate(f"go('admin');state.adminTab='users';render();admDrawer('users','{U[who]}')"); pg.wait_for_timeout(500)
        pg.check(f'#admForm [name=pcc][value={d}]'); pg.click('#admForm [type=submit]'); pg.wait_for_timeout(2200)
    ck('Tender', 'the super admin names the Head and the costing coordinator on the server', sql("select string_agg(p.name||':'||d.designation, ',' order by p.name) from pcc_designations d join profiles p on p.id=d.user_id") == 'Cora Coordinator:coordinator,Hana Head:head')
    r = pg.evaluate("SB.from('projects').update({pe_number:'PE-999'}).eq('id','P1').then(x=>x.error?'refused: '+x.error.message:'ran')")
    ck('Tender', 'even a super admin cannot set a PE number by writing to the table', r.startswith('refused') and sql("select coalesce(pe_number,'') from projects where id='P1'") == '', r)
    login(pg, 'cc')
    pg.evaluate("state.scope='ALL';go('tender')"); pg.wait_for_timeout(1200)
    ck('Tender', 'the coordinator sees the register with the next PE number from the server', pg.inner_text('#tenNext') == 'PE-001' and pg.locator('[data-tenreg]').count() == 1, pg.inner_text('#tenNext'))
    pg.click('[data-tenreg]'); pg.wait_for_timeout(1200)
    ck('Tender', 'the form shows the server proposal, read-only', pg.input_value('#tenPe') == 'PE-001' and pg.get_attribute('#tenPe', 'readonly') is not None)
    pg.fill('#tenForm [name=te_number]', 'TE2231'); pg.fill('#tenForm [name=name]', 'Riyadh 132 kV substation'); pg.fill('#tenForm [name=client]', 'SEC'); pg.fill('#tenForm [name=location]', 'Riyadh'); pg.fill('#tenForm [name=expected_value_m]', '42.5')
    pg.click('#tenForm [type=submit]'); pg.wait_for_timeout(3000)
    ck('Tender', 'registered on the server as PE-001, pre-award, with the coordinator owning stages 1 to 4',
       sql("select id||'/'||pe_number||'/'||te_number||'/'||status from projects where te_number='TE2231'") == 'PE-001/PE-001/TE2231/Pre-award'
       and sql(f"select count(*) from lifecycle_stages where project_id='PE-001' and owner='{U['cc']}'") == '4')
    ck('Tender', 'the app shows the new project from the server', pg.evaluate("!!projById('PE-001')&&accessIds().includes('PE-001')") and 'PE-001' in pg.inner_text('#view'))
    pg.evaluate("state.scope='PE-001';go('proj');openStage('PE-001',1)"); pg.wait_for_timeout(800)
    for k in ['te', 'value']: pg.click(f'[data-lctick="{k}"]')
    pg.click('[data-lcdo="submit"]'); pg.wait_for_timeout(2500)
    ck('Tender', 'the coordinator submits stage 1 through the server', sql("select status from lifecycle_stages where project_id='PE-001' and stage_no=1") == 'Awaiting approval')
    pg.evaluate("closeDrawer();state.scope='ALL';go('tender');openTender('PE-001')"); pg.wait_for_timeout(800)
    pg.fill('#tenEdit [name=contract_signed_on]', '2026-09-10'); pg.fill('#tenEdit [name=award_on]', '2026-09-01'); pg.click('#tenEdit [type=submit]'); pg.wait_for_timeout(2500)
    ck('Tender', 'award and signing saved; stage 4 due 7 days later, on the server', sql("select status||'/'||contract_signed_on from projects where id='PE-001'") == 'Active/2026-09-10'
       and sql("select due_date from lifecycle_stages where project_id='PE-001' and stage_no=4") == '2026-09-17')
    pg.evaluate("closeDrawer()")
    login(pg, 'pm')
    r = pg.evaluate("rpc('lifecycle_act',{p:{project_id:'P1',stage_no:1,action:'na',note:'x'}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Tender', 'a project manager can no longer decide stages 1 to 5 (server refuses)', r.startswith('refused') and 'Head of Planning' in r, r)
    login(pg, 'hd')
    pg.evaluate("go('act')"); pg.wait_for_timeout(900)
    ck('Tender', 'the Head finds stage 1 in Actions and approvals', 'Stage 1, Tender L1 notification: approve or return' in pg.inner_text('#view'), pg.inner_text('#view')[:300])
    pg.evaluate("openStage('PE-001',1)"); pg.wait_for_timeout(600); pg.click('[data-lcdo="approve"]'); pg.wait_for_timeout(2500)
    ck('Tender', 'the Head approves stage 1 through the server', sql("select status||'/'||(approved_by::text='" + U['hd'] + "') from lifecycle_stages where project_id='PE-001' and stage_no=1") == 'Complete/true')
    pg.evaluate("closeDrawer();state.scope='ALL';go('tender');openTender('PE-001')"); pg.wait_for_timeout(800)
    pg.fill('#tenCxNote', 'Client cancelled after L1'); pg.click('[data-tencancel]'); cfm(pg); pg.wait_for_timeout(2500)
    ck('Tender', 'the Head cancels it; the server releases PE-001', sql("select status from projects where id='PE-001'") == 'Cancelled' and sql("select count(*) from register_audit where project_id='PE-001' and action='PE released'") == '1')
    pg.evaluate("closeDrawer()")
    login(pg, 'cc')
    pg.evaluate("state.scope='ALL';go('tender')"); pg.wait_for_timeout(1200)
    ck('Tender', 'the released number is proposed again', pg.inner_text('#tenNext') == 'PE-001', pg.inner_text('#tenNext'))
    pg.click('[data-tenreg]'); pg.wait_for_timeout(1200)
    ck('Tender', 'the form says the number was released by the cancelled TE', 'TE2231' in pg.inner_text('#tenPeHelp'), pg.inner_text('#tenPeHelp'))
    pg.fill('#tenForm [name=te_number]', 'TE2250'); pg.fill('#tenForm [name=name]', 'Dammam pumping station'); pg.click('#tenForm [type=submit]'); pg.wait_for_timeout(3000)
    ck('Tender', 'the next L1 project gets PE-001 on the server, as a new record', sql("select id||'/'||pe_number from projects where te_number='TE2250'") == 'PE-001-R2/PE-001')
    ck('Tender', 'the app history shows both TE numbers against PE-001', pg.evaluate("[...new Set(DB.regAudit.filter(a=>a.pe_number==='PE-001').map(a=>a.te_number))].sort().join()") == 'TE2231,TE2250')
    r = pg.evaluate("rpc('tender_act',{p:{action:'cancel',project_id:'PE-001-R2',note:'x'}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Tender', 'the coordinator cannot cancel (server refuses)', r.startswith('refused') and sql("select status from projects where id='PE-001-R2'") == 'Pre-award', r)
    bad = []
    for view in ['exec', 'proj', 'tender', 'act', 'dash', 'pdash', 'cdash', 'eva', 'rep', 'imp']:
        e0 = len(errs); pg.evaluate(f"go('{view}')"); pg.wait_for_timeout(400)
        if len(errs) > e0: bad.append(view)
    ck('Tender', 'every screen renders with pre-award and cancelled server projects', not bad, (bad, errs[-2:]))
    login(pg, 'sa')
    pg.evaluate(f"go('admin');state.adminTab='users';render();admDrawer('users','{U['cc']}')"); pg.wait_for_timeout(500)
    ck('Tender', 'the users screen shows designations held on the server', pg.is_checked('#admForm [name=pcc][value=coordinator]') and not pg.is_checked('#admForm [name=pcc][value=head]'))
    pg.evaluate("closeDrawer()")


    # ---------------------------------------------------------------- v2.9 governed RASA answers through the server
    pg.evaluate("closeDrawer()")
    llm = "window.__llm=[];window.claude={use:function(k){return Promise.resolve(k==='sample'?function(m){window.__llm.push(1);return Promise.resolve({text:'x'})}:null)}};"
    pg2 = new_page(llm); login(pg2, 'f1')
    n_srv = int(sql("select count(*) from invoices"))
    r = pg2.evaluate("SB.from('invoices').select('*').then(x=>x.error?'err '+x.error.message:x.data.length)")
    ck('RASA', 'the server sends a foreman no invoice rows (v8)', n_srv > 0 and r == 0, (n_srv, r))
    r = pg2.evaluate("SB.from('import_batches').select('kind').then(x=>x.error?'err':x.data.map(b=>b.kind).sort().join())")
    ck('RASA', 'nor invoice or costing batches; baseline and progress batches still arrive', 'invoices' not in r and 'costing' not in r and 'baseline' in r, r)
    a = pg2.evaluate("answer('Invoiceable value')")
    ck('RASA', 'a foreman asking for invoiceable value gets "not available for your role"', 'Not available for your role' in a and 'SAR' not in a, a[:200])
    a = pg2.evaluate("answer(\"Today's productivity\")") or ''
    ck('RASA', 'a foreman\'s answer names its sources and data date from the server records', 'Based on' in a and 'daily report' in a and 'Data date' in a, a[-300:])
    pg2.evaluate("ask('What colour is the site office?')"); pg2.wait_for_timeout(1500)
    h = pg2.evaluate("state.chat.filter(m=>m.b).pop().h")
    ck('RASA', 'on the server the language model is never called, even where one is available', pg2.evaluate("window.__llm.length") == 0 and 'No evidence in ProTrackAI for that question' in h and 'no project data is sent to any outside AI service' in h, h[:300])
    pg2.close()
    login(pg, 'pm')
    pg.evaluate("state.scope='ALL';render()")
    a = pg.evaluate("answer('Invoicing and collection')") or ''
    ck('RASA', 'a project manager\'s billing answer names the invoice register batch it came from', 'invoice register' in a and 'IMP-' in a, a[-400:])
    a = pg.evaluate("answer('What are the accruals?')")
    ck('RASA', 'untracked figures get "No evidence" on the server too', 'No evidence in ProTrackAI' in a and 'SAR' not in a)


    # ---------------------------------------------------------------- v3.0 released reporting through the server
    pg.evaluate("closeDrawer()")
    sql(f"insert into project_access values ('{U['hd']}','P1') on conflict do nothing")
    per = pg.evaluate("curMonth()")
    login(pg, 'pl')
    pg.evaluate(f"state.scope='ALL';state.relTab='planning';state.relPt='month';state.relPer='{per}';go('rel')"); pg.wait_for_timeout(900)
    pg.click('[data-relopen="P1"]'); pg.wait_for_timeout(700)
    pg.click('#sheet [data-rdtab="notes"]'); pg.fill('#relForm [name=n_issues]', 'Raft pour delayed by pump breakdown')  # v3.5: the dashboard has tabs
    pg.click('[data-reldo="submit"]'); pg.wait_for_timeout(2500)
    ck('Releases', 'the planning engineer prepares and submits the monthly progress release on the server', sql(f"select status||'/'||(narrative->>'issues') from report_releases where project_id='P1' and kind='planning' and period='{per}'") == 'Submitted/Raft pour delayed by pump breakdown')
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'approve',project_id:'P1',kind:'planning',period_type:'month',period:'{per}'}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Releases', 'the planning engineer cannot approve it (server refuses)', r.startswith('refused'), r)
    login(pg, 'pm')
    pg.evaluate(f"state.scope='ALL';state.xrPt='month';state.xrPer=null;go('xr')"); pg.wait_for_timeout(900)
    ck('Releases', 'before approval, management sees no released report', 'No monthly report has been released' in pg.inner_text('#view'), pg.inner_text('#view')[:200])
    login(pg, 'hd')
    pg.evaluate("go('act');state.actF={who:'mine'};render()"); pg.wait_for_timeout(900)
    ck('Releases', 'the Head finds it in Actions and approvals', 'Internal report' in pg.inner_text('#view') and 'approve or reject' in pg.inner_text('#view'))  # v3.6 wording (was Progress release)
    pg.evaluate(f"openRelease('P1','planning','month','{per}')"); pg.wait_for_timeout(700); pg.click('[data-reldo="approve"]'); pg.wait_for_timeout(2500)
    ck('Releases', 'the Head approves it on the server', sql(f"select status||'/'||(approved_by::text='{U['hd']}') from report_releases where project_id='P1' and kind='planning' and period='{per}'") == 'Released/true')
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'save',project_id:'P1',kind:'planning',period_type:'month',period:'{per}',figures:{{actual_pct:99}}}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Releases', 'a released version cannot be saved over (server refuses)', r.startswith('refused') and 'revise' in r.lower(), r)
    login(pg, 'c1')
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'save',project_id:'P1',kind:'cost',period_type:'month',period:'{per}',data_date:'2026-09-21',figures:{{budget_rev0:50000000,actual:21000000,commitment:6000000,ftc:31000000,eac:1}}}}}}).then(x=>x,e=>({{err:e.message}}))")
    ck('Releases', 'the costing engineer saves the cost report; the server works out EAC and VAC', r.get('figures', {}).get('eac') == 52000000 and r.get('figures', {}).get('vac') == -2000000, r)
    pg.evaluate(f"rpc('release_act',{{p:{{action:'submit',project_id:'P1',kind:'cost',period_type:'month',period:'{per}'}}}})"); pg.wait_for_timeout(800)
    login(pg, 'hd')
    pg.evaluate(f"rpc('release_act',{{p:{{action:'approve',project_id:'P1',kind:'cost',period_type:'month',period:'{per}'}}}})"); pg.wait_for_timeout(800)
    login(pg, 'pm')
    pg.evaluate("state.scope='ALL';state.xrPt='month';state.xrPer=null;go('xr')"); pg.wait_for_timeout(900)
    v = pg.inner_text('#view')
    ck('Releases', 'the project manager\'s executive report shows the released progress and cost, not live data', 'Raft pour delayed by pump breakdown' in v and pg.evaluate("sar(52000000)") in v and 'Live daily reports are not used' in v, v[:400])
    login(pg, 'f1')
    r = pg.evaluate("SB.from('report_releases').select('kind').then(x=>x.error?'err':x.data.map(r=>r.kind).sort().join())")
    ck('Releases', 'a foreman receives the progress release but never the cost report', r == 'planning', r)
    login(pg, 'c1')
    pg.evaluate("state.scope='ALL';state.logTab='vo';state.logPid='P1';go('logs')"); pg.wait_for_timeout(900)
    vo = [['Ref no', 'Type (VO or Claim)', 'Description', 'Client approval status', 'Estimated price', 'Expected price to be approved', 'Change in Rev-0 budget'],
          ['VO-001', 'VO', 'Extra piles', 'Approved', 800000, 750000, 500000], ['CL-001', 'Claim', 'Standby', 'Pending', 300000, 100000, 0], ['X-1', 'Other', 'bad', '', '', '', '']]
    pg.fill('#logMonth', per); pg.set_input_files('#logfile', files=[book(vo, 'Log', 'vo_log.xlsx')]); pg.wait_for_timeout(1200)
    pg.evaluate("(document.getElementById('logAck')||{}).checked=true"); pg.click('[data-loggo]'); pg.wait_for_timeout(2500)
    ck('Logs', 'the costing engineer uploads the change order and claim log; the server saves the two good rows as one batch', sql("select count(*) from co_log where project_id='P1'") == '2' and sql("select recon_status from import_batches where kind='volog'") == 'Accepted with difference')
    login(pg, 'f1')
    r = pg.evaluate("SB.from('co_log').select('*').then(x=>x.error?'err':x.data.length)")
    ck('Logs', 'a foreman receives none of the log', r == 0, r)

    # ---------------------------------------------------------------- v3.1 issue register and released summary through the server
    login(pg, 'pl')
    pg.evaluate("state.scope='ALL';go('iss')"); pg.wait_for_timeout(900)
    ck('Issues', 'before the v10 update the issue register says the database update is needed (the rest of the app works)', 'v10 database update' in pg.inner_text('#view'), pg.inner_text('#view')[:200])
    pv = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, 'schema-update-v10.sql')], capture_output=True, text=True)
    ck('Issues', 'the v10 update loads on top of a database already in use', pv.returncode == 0, pv.stderr[:300])
    ck('Issues', 'the setup check counts 4 issue functions', sql("select count(*) from pg_proc where proname in ('issue_act','issue_import','pt_issue_snapshot','pt_issue_apply')") == '4')
    pg.reload(); pg.wait_for_timeout(1500); login(pg, 'pl')
    pg.evaluate("state.scope='ALL';go('iss')"); pg.wait_for_timeout(900)
    ck('Issues', 'after the update the warning is gone', 'v10 database update' not in pg.inner_text('#view'))
    pg.click('[data-issnew]'); pg.wait_for_timeout(500)
    pg.select_option('#issForm [name=project_id]', 'P1')
    pg.fill('#issForm [name=description]', 'Concrete pump breakdown stopping the raft pour'); pg.select_option('#issForm [name=impact]', 'Extremely High')
    pg.fill('#issForm [name=owner]', 'Subcontractor'); pg.fill('#issForm [name=cost_impact]', 'SAR 40k standby'); pg.fill('#issForm [name=forecast_target]', '2026-10-05')
    pg.click('[data-issdo="save"]'); pg.wait_for_timeout(2000)
    ck('Issues', 'the planning engineer adds an issue; the server numbers it and records the history', sql("select issue_no||'/'||impact||'/'||(created_by::text='" + U['pl'] + "') from issues where project_id='P1'") == 'ISS-001/Extremely High/true'
       and sql("select count(*) from issue_audit where action='Created'") == '1')
    pg.evaluate("closeDrawer()")
    for who, lab in (('e1', 'a site engineer'), ('pm', 'the project manager')):
        login(pg, who)
        r = pg.evaluate("rpc('issue_act',{p:{action:'save',project_id:'P1',fields:{description:'x'}}}).then(()=>'ran',e=>'refused: '+e.message)")
        ck('Issues', f'{lab} cannot add issues (server refuses)', r.startswith('refused'), r)
    login(pg, 'f1')
    r = pg.evaluate("SB.from('issues').select('id').then(x=>x.error?'err':x.data.length)")
    ck('Issues', 'a foreman receives no issues from the server', r == 0, r)
    login(pg, 'pl')
    pg.evaluate("state.scope='ALL';go('iss')"); pg.wait_for_timeout(900)
    head = ['', 'Project', 'Region', 'Data date', 'Issue owner', 'Sub Issue owner', 'Issue Type', 'Issue Start date', 'Issue description', 'Impact', 'Action Taken', 'Action Required',
            'Priority By SEC', 'Priority by Alfanar', 'Action By', 'Planned Target', 'Forecast/Expected Target', 'Issue Status', 'Issue Closure date', 'Remarks', 'Schedule Impact', 'Cost Impact']
    rows = [head, ['', 'P1', 'Central', '2026-09-21', 'Client', 'Consultant', 'Design inputs', '2026-08-01', 'Shop drawing approval pending', 'High', 'Reminder', 'Approve', 'A', 'B', 'Client', '', '2026-10-10', 'Open', '', '', '2 weeks', ''],
            ['', 'P1', '', '2026-09-21', '', '', '', '', 'Concrete pump breakdown stopping the raft pour', 'High', 'Pump replaced', '', '', '', '', '', '', 'Open', '', '', '', ''],
            ['', 'PE-77777', '', '', '', '', '', '', 'Unknown project', 'High', '', '', '', '', '', '', '', 'Open', '', '', '', '']]
    pg.set_input_files('#issfile', files=[book(rows, 'Issue Register', 'issue_log.xlsx')]); pg.wait_for_timeout(1200)
    pg.evaluate("(document.getElementById('issAck')||{}).checked=true"); pg.click('[data-issupgo]'); pg.wait_for_timeout(2500)
    ck('Issues', 'the issue log upload: one new issue, the existing one updated (not duplicated), the unknown project refused and logged',
       sql("select count(*) from issues where project_id='P1'") == '2' and sql("select impact from issues where issue_no='ISS-001'") == 'High'
       and sql("select rows_rejected||'/'||kind from import_batches where kind='issues'") == '1/issues', sql("select count(*) from issues"))
    login(pg, 'hd')
    pg.evaluate("state.scope='ALL';go('iss')"); pg.wait_for_timeout(900)
    iid = sql("select id from issues where issue_no='ISS-002'")
    pg.evaluate(f"openIssue('{iid}')"); pg.wait_for_timeout(500); pg.fill('#issNote', 'Central region review'); pg.click('[data-issdo="review"]'); pg.wait_for_timeout(2000)
    ck('Issues', 'the Head marks an issue reviewed on the server', sql(f"select (reviewed_by::text='{U['hd']}')::text||'/'||review_note from issues where id='{iid}'") == 'true/Central region review')
    pg.evaluate("closeDrawer()")
    wk = pg.evaluate("curWeek()")
    login(pg, 'pl')
    pg.evaluate(f"rpc('release_act',{{p:{{action:'save',project_id:'P1',kind:'planning',period_type:'week',period:'{wk}',figures:{{actual_pct:30,planned_pct:35,spi:0.86}},narrative:{{issues:'Pump'}}}}}})"); pg.wait_for_timeout(800)
    pg.evaluate(f"rpc('release_act',{{p:{{action:'submit',project_id:'P1',kind:'planning',period_type:'week',period:'{wk}'}}}})"); pg.wait_for_timeout(800)
    login(pg, 'hd')
    pg.evaluate(f"rpc('release_act',{{p:{{action:'approve',project_id:'P1',kind:'planning',period_type:'week',period:'{wk}'}}}})"); pg.wait_for_timeout(800)
    ck('Issues', 'approving the weekly progress release saves the open issues with it on the server, without the cost impact',
       sql(f"select jsonb_array_length(issues_snapshot)||'/'||(issues_snapshot->0->>'impact')||'/'||(issues_snapshot::text like '%cost_impact%')::text from report_releases where kind='planning' and period='{wk}' and status='Released'") == '2/High/false')
    login(pg, 'c1')
    prev = pg.evaluate("recentMonths(3)[1]")
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'save',project_id:'P1',kind:'cost',period_type:'month',period:'{prev}',data_date:'2026-08-31',figures:{{budget_rev0:50000000,actual:18000000,commitment:5000000,ftc:33000000,inv_invoiceable:20000000,inv_submitted:19000000,inv_approved:17000000,inv_collected:12000000}}}}}}).then(x=>x,e=>({{err:e.message}}))")
    ck('Billing', 'the cost report keeps the billing figures on the server; EAC and VAC are unchanged by them', r.get('figures', {}).get('inv_collected') == 12000000 and r.get('figures', {}).get('eac') == 51000000, r)
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'save',project_id:'P1',kind:'cost',period_type:'month',period:'{prev}',figures:{{budget_rev0:1,actual:1,commitment:1,ftc:1,inv_submitted:-1}}}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Billing', 'a negative billing amount is refused by the server', r.startswith('refused') and 'negative' in r, r)
    pg.evaluate(f"cloudLoadReleases().then(()=>{{state.relTab='cost';state.relPer='{prev}';go('rel')}})"); pg.wait_for_timeout(1200); pg.evaluate(f"openRelease('P1','cost','month','{prev}')"); pg.wait_for_timeout(700)
    ck('Billing', 'the cost report form shows the saved billing figures', pg.input_value('#relForm [name=c_inv_collected]') == '12000000')
    pg.evaluate("closeDrawer()")
    login(pg, 'pm')
    pg.evaluate("state.scope='ALL';state.xrPt='month';state.xrPer=null;state.xrTab='sum';go('xr')"); pg.wait_for_timeout(900); v = pg.inner_text('#view')
    ck('Executive report', 'the released Summary shows region, sector, critical projects, billing and change order status', all(x in v for x in ['By region', 'By sector', 'Critical projects', 'Billing and collection', 'Change order and claim status']), v[:300])
    pg.evaluate("state.xrPt='week';state.xrPer=null;state.xrTab='proj';state.xrPid='P1';render()"); pg.wait_for_timeout(700); v = pg.inner_text('#view')
    ck('Executive report', 'the weekly Project view shows the issues saved with the release', 'Concrete pump breakdown stopping the raft pour' in v and 'Shop drawing approval pending' in v and 'SAR 40k' not in v, v[:300])
    pg.evaluate("state.xrTab='sum';state.xrPt='month'")
    a = pg.evaluate("answer('What are the open issues?')") or ''
    ck('Issues', 'RASA answers about issues from the register held on the server', 'open issue' in a and 'issue register' in a, a[:200])

    # ---------------------------------------------------------------- v3.2 quantity beyond the scope through the server
    login(pg, 'f1')
    r = pg.evaluate("rpc('dpr_save',{p:{project_id:'P1',report_date:'2026-09-05',lines:[{activity_id:'TT-110',qty:260,labour:[{cat:'Steel Fixer',count:4,reg:8,ot:0}],subs:[],equip:[]}],submit:true,secs:0}}).then(x=>x.id,e=>'refused: '+e.message)")
    QD = r
    ck('Quantities', 'a report beyond the scope (260 of 200 t) is accepted by the server', not str(r).startswith('refused') and sql(f"select status from dprs where id='{QD}'") == 'Submitted', r)
    pg.evaluate("cloudLoadDprs().then(()=>{state.form=null;state.editing=null;go('new')})"); pg.wait_for_timeout(1200)
    ck('Quantities', 'the new report form shows scope, executed up to yesterday, balance and plan for today', all(x in pg.inner_text('#view') for x in ['Total quantity (scope)', 'Executed up to yesterday', 'Plan for today']))
    login(pg, 'e1')
    pg.evaluate(f"state.scope='ALL';go('dpr');openDpr('{QD}')"); pg.wait_for_timeout(900)
    ck('Quantities', 'the engineer sees the variation and the justification box', 'Beyond the scope' in pg.inner_text('#sheet') and pg.locator('[data-just]').count() == 1)
    pg.click('[data-do="review"]'); pg.wait_for_timeout(600)
    ck('Quantities', 'reviewing without a justification is stopped in the app', 'Justify the quantity variation' in pg.inner_text('#actErr') and sql(f"select status from dprs where id='{QD}'") == 'Submitted')
    pg.fill('[data-just]', 'Extra starter bars at the lift core per RFI-07'); pg.click('[data-do="review"]'); pg.wait_for_timeout(1500)
    ck('Quantities', 'before the v11 update the server refuses and the app says the update is needed', 'v11 database update' in pg.inner_text('#actErr') and sql(f"select status from dprs where id='{QD}'") == 'Submitted', pg.inner_text('#actErr'))
    r = pg.evaluate(f"rpc('dpr_act',{{p_id:'{QD}',p_action:'return',p_note:'check',p_secs:0}}).then(()=>'ran',e=>'refused: '+e.message)")
    pv = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, 'schema-update-v11.sql')], capture_output=True, text=True)
    ck('Quantities', 'the v11 update loads on top of a database in use', pv.returncode == 0, pv.stderr[:300])
    ck('Quantities', 'the setup check counts 2', sql("select count(*) from pg_proc where proname in ('dpr_act','pt_dpr_over') and (proname <> 'dpr_act' or pronargs = 5)") == '2')
    login(pg, 'f1')
    if r == 'ran':
        pg.evaluate(f"rpc('dpr_save',{{p:{{id:'{QD}',project_id:'P1',report_date:'2026-09-05',lines:[{{activity_id:'TT-110',qty:260,labour:[{{cat:'Steel Fixer',count:4,reg:8,ot:0}}],subs:[],equip:[]}}],submit:true,secs:0}}}})"); pg.wait_for_timeout(800)
    login(pg, 'e1')
    r = pg.evaluate(f"rpc('dpr_act',{{p_id:'{QD}',p_action:'review',p_note:null,p_secs:0}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Quantities', 'after v11 the server itself refuses a review without a justification', r.startswith('refused') and 'TT-110' in r, r)
    pg.evaluate(f"state.scope='ALL';go('dpr');openDpr('{QD}')"); pg.wait_for_timeout(900)
    pg.fill('[data-just]', 'Extra starter bars at the lift core per RFI-07'); pg.click('[data-do="review"]'); pg.wait_for_timeout(1800)
    ck('Quantities', 'with the justification the engineer reviews it on the server; the justification is stored', sql(f"select status from dprs where id='{QD}'") == 'Reviewed'
       and sql(f"select activity_id||'/'||qty::int||'/'||(by_user::text='{U['e1']}') from dpr_qty_just where dpr_id='{QD}'") == 'TT-110/260/true')
    pg.evaluate(f"openDpr('{QD}')"); pg.wait_for_timeout(500)
    ck('Quantities', 'the report shows who justified it', 'Justified by' in pg.inner_text('#sheet') and 'RFI-07' in pg.inner_text('#sheet'))
    pg.evaluate(f"rpc('dpr_save',{{p:{{id:'{QD}',project_id:'P1',report_date:'2026-09-05',lines:[{{activity_id:'TT-110',qty:270,labour:[{{cat:'Steel Fixer',count:4,reg:8,ot:0}}],subs:[],equip:[]}}],secs:0}}}})"); pg.wait_for_timeout(800)
    login(pg, 's1')
    r = pg.evaluate(f"rpc('dpr_act',{{p_id:'{QD}',p_action:'approve',p_note:null,p_secs:0}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Quantities', 'a quantity raised after review cannot be approved (server refuses)', r.startswith('refused') and 'not been justified' in r, r)
    login(pg, 'f1')
    r = pg.evaluate("SB.from('dpr_qty_just').select('note').then(x=>x.error?'err':x.data.length)")
    ck('Quantities', 'people on the project read the justification', r == 1, r)

    # ---------------------------------------------------------------- v3.3 cost report by WBS head through the server
    login(pg, 'c1')
    cm = pg.evaluate("recentMonths(3)[2]")
    pg.evaluate(f"state.scope='ALL';state.relTab='cost';state.relPer='{cm}';go('rel');openRelease('P1','cost','month','{cm}')"); pg.wait_for_timeout(900)
    ck('Cost by WBS', 'the cost report form is in the company format', pg.locator('#crTable').count() == 1)
    pg.evaluate("document.querySelectorAll('#crTable input[type=number]').forEach(i=>{i.value='0'})")
    for k_, v_ in [('budget', 3000000), ('actual', 1800000), ('commitment', 400000), ('etc', 900000)]: pg.fill(f'#relForm [name=w0_{k_}]', str(v_))
    pg.click('[data-reldo="save"]'); pg.wait_for_timeout(1500)
    ck('Cost by WBS', 'before the v12 update the server refuses and the app says the update is needed', 'v12 database update' in pg.inner_text('#relErr') and sql(f"select count(*) from report_releases where kind='cost' and period='{cm}'") == '0', pg.inner_text('#relErr'))
    pv = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, 'schema-update-v12.sql')], capture_output=True, text=True)
    ck('Cost by WBS', 'the v12 update loads on top of a database in use', pv.returncode == 0, pv.stderr[:300])
    ck('Cost by WBS', 'the setup check counts 2', sql("select count(*) from pg_proc where proname in ('release_act','pt_cost_wbs')") == '2')
    pg.click('[data-reldo="save"]'); pg.wait_for_timeout(1800)
    ck('Cost by WBS', 'after the update the costing engineer saves it; the server works out EAC = E + F + H and J = D − I',
       sql(f"select (figures->>'eac')::numeric::bigint||'/'||(figures->>'vac')::numeric::bigint||'/'||(figures->'wbs'->0->>'var')::numeric::bigint||'/'||jsonb_array_length(figures->'wbs') from report_releases where kind='cost' and period='{cm}'") == '3100000/-100000/-100000/18')
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'submit',project_id:'P1',kind:'cost',period_type:'month',period:'{cm}'}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Cost by WBS', 'the server refuses to submit while the line with a supplement has no justification', r.startswith('refused') and 'SM' in r, r)
    pg.evaluate(f"openRelease('P1','cost','month','{cm}')"); pg.wait_for_timeout(700)
    pg.fill('#relForm [name=w0_justification]', 'Extended site management for demobilisation'); pg.click('[data-reldo="submit"]'); pg.wait_for_timeout(1800)
    ck('Cost by WBS', 'with the justification it is submitted', sql(f"select status from report_releases where kind='cost' and period='{cm}'") == 'Submitted')
    login(pg, 'hd')
    pg.evaluate(f"rpc('release_act',{{p:{{action:'approve',project_id:'P1',kind:'cost',period_type:'month',period:'{cm}'}}}})"); pg.wait_for_timeout(800)
    login(pg, 'pm')
    pg.evaluate(f"state.scope='ALL';state.xrPt='month';state.xrPer='{cm}';state.xrTab='proj';state.xrPid='P1';go('xr')"); pg.wait_for_timeout(900); v = pg.inner_text('#view')
    ck('Cost by WBS', 'the project manager sees it by WBS head in the executive report', 'Cost report by WBS head' in v and 'Extended site management for demobilisation' in v and '3,100,000' in v, v[:200])
    login(pg, 'f1')
    r = pg.evaluate("SB.from('report_releases').select('kind').eq('kind','cost').then(x=>x.error?'err':x.data.length)")
    ck('Cost by WBS', 'a foreman still receives no cost report', r == 0, r)

    # ---------------------------------------------------------------- v3.4 document rack through the server, with Storage
    import tempfile as _tf
    _td = _tf.mkdtemp()
    def _mk(n, t):
        pth = os.path.join(_td, n); open(pth, 'w').write(t); return pth
    login(pg, 'pl')
    pg.evaluate("state.scope='ALL';state.docPid='P1';go('docs')"); pg.wait_for_timeout(900)
    ck('Documents', 'before the v13 update the rack says the database update is needed', 'v13 database update' in pg.inner_text('#view'), pg.inner_text('#view')[:200])
    pv = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, 'schema-update-v13.sql')], capture_output=True, text=True)
    ck('Documents', 'the v13 update loads on top of a database in use', pv.returncode == 0, pv.stderr[:300])
    ck('Documents', 'the setup check counts 3, and the private bucket exists', sql("select count(*) from pg_proc where proname in ('doc_act','pt_doc_can','pt_doc_row')") == '3' and sql("select public::text from storage.buckets where id='project-docs'") == 'false')
    pg.reload(); pg.wait_for_timeout(1500); login(pg, 'pl')
    pg.evaluate("state.scope='ALL';state.docPid='P1';go('docs')"); pg.wait_for_timeout(900)
    ck('Documents', 'after the update the rack shows its three rows', 'v13 database update' not in pg.inner_text('#view') and pg.locator('.docrow-planning [data-docbox]').count() == 12)
    pg.evaluate("openDocBox('P01',{upload:true})"); pg.wait_for_timeout(600)
    pg.set_input_files('#docFile', _mk('Baseline Rev01.xer', 'ERMHDR\t8.0\nbaseline'))
    pg.fill('#docUpForm [name=title]', 'Approved baseline'); pg.fill('#docUpForm [name=revision]', 'Rev 01'); pg.select_option('#docUpForm [name=status]', 'Approved')
    pg.click('[data-docupgo]'); pg.wait_for_timeout(2500)
    ck('Documents', 'the planning engineer uploads the baseline: the file is in the private bucket and the document is registered by the server',
       sql("select count(*) from storage.objects where bucket_id='project-docs' and name like 'P1/P01/%/Baseline Rev01.xer'") == '1'
       and sql("select title||'/'||revision||'/'||status||'/'||file_size from documents where box_key='P01'") == 'Approved baseline/Rev 01/Approved/' + str(len('ERMHDR\t8.0\nbaseline'))
       and sql("select count(*) from doc_audit where action='Uploaded'") == '1')
    r = pg.evaluate("(async()=>{const f=new File(['x'],'nope.pdf');const {error}=await SB.storage.from('project-docs').upload('P1/K02/abc/nope.pdf',f,{upsert:false});return error?'refused':'stored'})()")
    ck('Documents', 'the planning engineer cannot put a file in the Cost row (storage refuses)', r == 'refused', r)
    login(pg, 'c1')
    pg.evaluate("state.scope='ALL';state.docPid='P1';go('docs')"); pg.wait_for_timeout(900)
    pg.evaluate("openDocBox('K02',{upload:true})"); pg.wait_for_timeout(600)
    pg.set_input_files('#docFile', _mk('Rev0 budget.pdf', '%PDF-1.4 rev0'))
    pg.fill('#docUpForm [name=title]', 'Rev 0 approved budget'); pg.fill('#docUpForm [name=revision]', 'Rev 0'); pg.select_option('#docUpForm [name=status]', 'Approved')
    pg.click('[data-docupgo]'); pg.wait_for_timeout(2500)
    ck('Documents', 'the costing engineer uploads the Rev 0 budget', sql("select count(*) from documents where box_key='K02' and revision='Rev 0'") == '1')
    r0 = sql("select id from documents where box_key='K02'")
    pg.evaluate(f"openDocItem('{r0}')"); pg.wait_for_timeout(500); pg.click(f'[data-docrev="{r0}"]'); pg.wait_for_timeout(500)
    pg.set_input_files('#docFile', _mk('Rev1 budget.pdf', '%PDF-1.4 rev1')); pg.fill('#docUpForm [name=revision]', 'Rev 1'); pg.click('[data-docupgo]'); pg.wait_for_timeout(2500)
    ck('Documents', 'a new revision is a new file and document; Rev 0 is unchanged', sql(f"select count(*) from documents where supersedes='{r0}'") == '1' and sql(f"select status from documents where id='{r0}'") == 'Approved' and sql("select count(*) from storage.objects where name like 'P1/K02/%'") == '2')
    txt = pg.evaluate(f"docBlob(DB.docs.find(d=>d.id==='{r0}')).then(b=>b.text())")
    ck('Documents', 'the costing engineer downloads Rev 0 through a signed link', txt == '%PDF-1.4 rev0', txt)
    login(pg, 'e1')
    n = pg.evaluate("SB.from('documents').select('box_key').then(x=>x.error?'err':x.data.map(r=>r.box_key).sort().join())")
    ck('Documents', 'a site engineer receives the planning documents only', n == 'P01', n)
    r = pg.evaluate(f"SB.storage.from('project-docs').createSignedUrl((()=>'')() || '{sql(f'select storage_path from documents where id=' + chr(39) + r0 + chr(39))}',600).then(x=>x.error?'refused':'signed')")
    ck('Documents', 'a site engineer cannot download a Cost file (storage refuses)', r == 'refused', r)
    login(pg, 'pm')
    r = pg.evaluate("(async()=>{const f=new File(['x'],'pm.pdf');const {error}=await SB.storage.from('project-docs').upload('P1/C05/abc/pm.pdf',f,{upsert:false});return error?'refused':'stored'})()")
    ck('Documents', 'a project manager cannot add files', r == 'refused', r)
    n = pg.evaluate("SB.from('documents').select('id').then(x=>x.error?'err':x.data.length)")
    ck('Documents', 'a project manager reads every row', n == 3, n)
    login(pg, 'f1')
    n = pg.evaluate("SB.from('documents').select('id').then(x=>x.error?'err':x.data.length)")
    ck('Documents', 'a foreman receives no documents', n == 0, n)
    login(pg, 'hd')
    pg.evaluate("state.scope='ALL';state.docPid='P1';go('docs');state.docManage=true;render()"); pg.wait_for_timeout(900)
    pg.click('.docrow-contract [data-docadd]'); pg.wait_for_timeout(400); pg.fill('#docAddForm [name=title]', 'Arbitration'); pg.click('[data-docaddgo]'); pg.wait_for_timeout(1800)
    ck('Documents', 'the Head adds a box to the Contract row on the server', sql("select row_key||'/'||title from doc_boxes where title='Arbitration'") == 'contract/Arbitration')


    # ---------------------------------------------------------------- v3.5 progress release dashboard and regional approval through the server
    sql(f"insert into project_access (user_id, project_id) values ('{U['rp']}','P1')")  # as Administration gives a planning user access
    login(pg, 'sa')
    pg.evaluate("go('admin');state.adminTab='matrix';render()"); pg.wait_for_timeout(900)
    ck('Dashboard (v14)', 'before the v14 update, Administration says regional approval needs the update', 'v14 database update' in pg.inner_text('#view'), pg.inner_text('#view')[-300:])
    pv = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, 'schema-update-v14.sql')], capture_output=True, text=True)
    ck('Dashboard (v14)', 'the v14 update loads on top of a database in use', pv.returncode == 0, pv.stderr[:300])
    ck('Dashboard (v14)', 'the setup check counts 5', sql("select (select count(*) from pg_proc where proname in ('release_setup','pt_rel_approver','pt_rel_plan_calc','pt_rel_decider')) + (select count(*) from release_settings)") == '5')
    pg.evaluate("signOut()"); pg.wait_for_timeout(600); pg.reload(); pg.wait_for_timeout(2500); login(pg, 'sa')
    pg.evaluate("go('admin');state.adminTab='matrix';render()"); pg.wait_for_timeout(900)
    pg.select_option('[data-rapadd="R1"]', U['rp']); pg.wait_for_timeout(1800)
    ck('Dashboard (v14)', 'a super admin names the regional planning section manager on the server', sql(f"select count(*) from release_approvers where region_id='R1' and user_id='{U['rp']}'") == '1')
    wk = pg.evaluate("recentWeeks(3)[2]"); mo = pg.evaluate("recentMonths(3)[2]")
    login(pg, 'pl')
    pg.evaluate(f"state.scope='ALL';state.rdTab='prog';openRelease('P1','planning','week','{wk}')"); pg.wait_for_timeout(900)
    ck('Dashboard (v14)', 'the weekly progress release opens full screen on live', pg.evaluate("document.querySelector('#sheet').classList.contains('full')"))
    pg.fill('#sheet [name="d_ext_plan_pct"]', '40'); pg.fill('#sheet [name="d_ext_act_pct"]', '30')
    pg.click('#sheet [data-rdtab="mp"]')
    for k, v in [('dir_plan', 20), ('dir_act', 18), ('ind_plan', 5), ('ind_act', 5), ('sub_plan', 10), ('sub_act', 6)]: pg.fill(f'#sheet [name="d_mp_{k}"]', str(v))
    pg.click('#sheet [data-rdtab="ms"]'); pg.fill('#sheet [name="d_tcc_orig_date"]', '2026-12-31'); pg.fill('#sheet [name="d_tcc_ext_fc_date"]', '2027-02-14')
    pg.click('#sheet [data-rdtab="notes"]'); pg.fill('#sheet [name="n_recovery"]', 'Second crew for the raft')
    pg.click('[data-reldo="submit"]'); pg.wait_for_timeout(2500)
    row = sql(f"select status||'|'||((figures->>'ext_spi')::numeric)::float8||'|'||(figures->>'mp_tot_act')||'|'||(figures->>'mp_util_pct')||'|'||(figures->>'tcc_delay_days')||'|'||(narrative->>'recovery') from report_releases where project_id='P1' and kind='planning' and period='{wk}'")
    ck('Dashboard (v14)', 'submitted on the server, which works out external SPI 0.75, manpower 29 of 35 (82.9%) and TCC 45 days late', row == 'Submitted|0.75|29|82.9|45|Second crew for the raft', row)
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'save',project_id:'P1',kind:'planning',period_type:'month',period:'{mo}',figures:{{actual_pct:10,ext_plan_pct:120}}}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Dashboard (v14)', 'the server refuses an external % over 100', r.startswith('refused') and '100' in r, r)
    r = pg.evaluate("rpc('release_setup',{p:{action:'pm_review',on:true}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Dashboard (v14)', 'only a super admin changes the approval set-up (server refuses the planner)', r.startswith('refused'), r)
    login(pg, 'pm')
    r2 = pg.evaluate(f"rpc('release_act',{{p:{{action:'return',project_id:'P1',kind:'planning',period_type:'week',period:'{wk}',note:'x'}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Dashboard (v14)', 'the project manager cannot approve or reject while the review step is off (server refuses)', r2.startswith('refused'), r2)
    login(pg, 'rp')
    if True:
        pg.evaluate("go('act');state.actF={who:'mine'};render()"); pg.wait_for_timeout(900)
        ck('Dashboard (v14)', 'the regional planning section manager finds it in Actions and approvals', 'Internal report' in pg.inner_text('#view') and 'approve or reject' in pg.inner_text('#view'))
        pg.evaluate(f"state.rdTab='notes';openRelease('P1','planning','week','{wk}')"); pg.wait_for_timeout(800)
        pg.fill('#relMgmt', 'Agree the recovery; report weekly'); pg.click('[data-reldo="approve"]'); pg.wait_for_timeout(2500)
        ck('Dashboard (v14)', 'and approves it with management remarks on the server', sql(f"select status||'/'||(approved_by::text='{U['rp']}')||'/'||(reviewed_by::text='{U['rp']}')||'/'||(narrative->>'mgmt') from report_releases where project_id='P1' and kind='planning' and period='{wk}' and rev=0") == 'Released/true/true/Agree the recovery; report weekly')
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'approve',project_id:'P1',kind:'cost',period_type:'month',period:'{mo}'}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Dashboard (v14)', 'the regional planning section manager cannot approve cost reports', r.startswith('refused'), r)
    login(pg, 'sa')
    pg.evaluate("go('admin');state.adminTab='matrix';render()"); pg.wait_for_timeout(900)
    pg.check('[data-relpmrev]'); pg.wait_for_timeout(1800)
    ck('Dashboard (v14)', 'a super admin switches on the project manager review on the server', sql("select v::text from release_settings where k='pm_review'") == 'true')
    login(pg, 'pl')
    pg.evaluate(f"rpc('release_act',{{p:{{action:'save',project_id:'P1',kind:'planning',period_type:'month',period:'{mo}',figures:{{actual_pct:12,planned_pct:14}},narrative:{{}}}}}}).then(()=>rpc('release_act',{{p:{{action:'submit',project_id:'P1',kind:'planning',period_type:'month',period:'{mo}'}}}}))"); pg.wait_for_timeout(1200)
    login(pg, 'rp')
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'approve',project_id:'P1',kind:'planning',period_type:'month',period:'{mo}'}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Dashboard (v14)', 'with the review on, the planning section manager cannot approve before the project manager reviews', r.startswith('refused') and 'review' in r.lower(), r)
    login(pg, 'pm')
    pg.evaluate("go('act');state.actF={who:'mine'};render()"); pg.wait_for_timeout(900)
    ck('Dashboard (v14)', 'the project manager finds the review in Actions and approvals', 'review or reject' in pg.inner_text('#view'))
    pg.evaluate(f"openRelease('P1','planning','month','{mo}')"); pg.wait_for_timeout(800); pg.click('[data-reldo="review"]'); pg.wait_for_timeout(2200)
    ck('Dashboard (v14)', 'the project manager marks it reviewed on the server', sql(f"select (reviewed_by::text='{U['pm']}')::text||'/'||status from report_releases where project_id='P1' and kind='planning' and period='{mo}'") == 'true/Submitted')
    login(pg, 'rp')
    r = pg.evaluate(f"rpc('release_act',{{p:{{action:'approve',project_id:'P1',kind:'planning',period_type:'month',period:'{mo}'}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Dashboard (v14)', 'then the planning section manager approves; the reviewer is kept', r == 'ran' and sql(f"select status||'/'||(reviewed_by::text='{U['pm']}') from report_releases where project_id='P1' and kind='planning' and period='{mo}'") == 'Released/true', r)
    p_ = subprocess.run(PG + ['-d', DBN, '-c', f"update report_releases set review_note='x' where project_id='P1' and kind='planning' and period='{mo}'"], capture_output=True, text=True)
    ck('Dashboard (v14)', 'the review on a released version cannot be changed, even from the database console', p_.returncode != 0, p_.stderr[:200])
    login(pg, 'pm')
    pg.evaluate(f"state.scope='ALL';state.xrPt='week';state.xrPer='{wk}';state.xrTab='proj';state.xrPid='P1';go('xr')"); pg.wait_for_timeout(900); v = pg.inner_text('#view')
    ck('Dashboard (v14)', 'the executive report shows the released milestones, external progress and manpower', 'Milestones, progress, energization and manpower' in v and '+45 days' in v and 'Second crew for the raft' in v, v[-600:])
    sql("update release_settings set v='false' where k='pm_review'")


    # ---------------------------------------------------------------- v3.6 internal weightage, updated schedule, internal and client reports
    import datetime as _dt, tempfile as _tf2
    def _xer(rows, dd):
        T = []
        def tab(name, fields, recs):
            T.append('%T\t' + name); T.append('%F\t' + '\t'.join(fields))
            for r in recs: T.append('%R\t' + '\t'.join(str(r.get(f, '')) for f in fields))
        tab('PROJECT', ['proj_id', 'proj_short_name', 'last_recalc_date'], [{'proj_id': 1, 'proj_short_name': 'TT', 'last_recalc_date': dd + ' 17:00'}])
        tab('PROJWBS', ['wbs_id', 'proj_id', 'parent_wbs_id', 'proj_node_flag', 'wbs_name'], [dict(wbs_id=a, proj_id=1, parent_wbs_id=b, proj_node_flag=c, wbs_name=d) for a, b, c, d in
            [('1', '', 'Y', 'TT'), ('2', '1', 'N', 'ENGINEERING & DESIGN'), ('3', '1', 'N', 'CONSTRUCTION'), ('4', '1', 'N', 'PROJECT CLOSE OUT')]])
        tab('RSRC', ['rsrc_id', 'rsrc_name', 'rsrc_short_name', 'rsrc_type', 'unit_id'], [{'rsrc_id': 1, 'rsrc_name': 'Price weight', 'rsrc_short_name': 'PW', 'rsrc_type': 'RT_Mat', 'unit_id': ''}])
        F = ['task_id', 'wbs_id', 'task_code', 'task_name', 'task_type', 'status_code', 'complete_pct_type', 'phys_complete_pct', 'target_start_date', 'target_end_date', 'early_end_date']
        tab('TASK', F, [dict(task_id=i + 1, wbs_id=r[1], task_code=r[0], task_name=r[2], task_type=r[6] if len(r) > 6 else 'TT_Task', status_code='TK_Active', complete_pct_type='CP_Phys', phys_complete_pct=r[4],
                             target_start_date=r[5][0] + ' 08:00', target_end_date=r[5][1] + ' 17:00', early_end_date=r[5][1] + ' 17:00') for i, r in enumerate(rows)])
        tab('TASKRSRC', ['task_id', 'rsrc_id', 'target_qty'], [{'task_id': i + 1, 'rsrc_id': 1, 'target_qty': r[3]} for i, r in enumerate(rows) if r[3]])
        return '\n'.join(T) + '\n%E\n'
    login(pg, 'pl')
    pg.evaluate("state.scope='ALL';state.impPid='P1';go('base')"); pg.wait_for_timeout(900)
    ck('Schedule (v15)', 'before the v15 update, the Baselines page says the database update is needed', 'v15 database update' in pg.inner_text('#view'), pg.inner_text('#view')[:300])
    pv = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, 'schema-update-v15.sql')], capture_output=True, text=True)
    ck('Schedule (v15)', 'the v15 update loads on top of a database in use', pv.returncode == 0, pv.stderr[:300])
    ck('Schedule (v15)', 'the setup check counts 7', sql("select (select count(*) from pg_proc where proname in ('phase_setup_save','schedule_update_commit','pt_rel_sched','pt_sched_summary')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('project_phase_setup','schedule_updates','schedule_update_rows'))") == '7')
    pg.evaluate("signOut()"); pg.wait_for_timeout(600); pg.reload(); pg.wait_for_timeout(2500); login(pg, 'pl')
    pg.evaluate("state.scope='ALL';state.impPid='P1';go('base')"); pg.wait_for_timeout(900)
    for k, v in {'DES': 20, 'CON': 80}.items(): pg.fill(f'[name="pw_{k}"]', str(v))
    pg.click('[data-pwsave="P1"]'); pg.wait_for_timeout(1800)
    ck('Schedule (v15)', 'the planning engineer saves the internal weightage on the server', sql("select (weights->>'DES')||'/'||(weights->>'CON') from project_phase_setup where project_id='P1'") == '20/80' and sql("select count(*) from phase_setup_audit") == '1')
    dd = pg.evaluate("addDays(ASOF,-10)")   # the app's data date (demo date mode on the test server)
    _rows = [('TT-E01', 2, 'Shop drawings', 20, 100, ('2026-08-01', '2026-09-30')), ('TT-100', 3, 'Raft concrete', 50, 60, ('2026-09-01', '2026-09-30')),
             ('TT-110', 3, 'Column rebar', 30, 20, ('2026-09-01', '2026-10-31')), ('TT-MS1', 4, 'TCC - Taking over certificate', 0, 0, ('2026-12-20', '2026-12-20'), 'TT_FinMile')]
    _d = _tf2.mkdtemp(); _fx = os.path.join(_d, 'TT_update.xer'); open(_fx, 'w').write(_xer(_rows, dd))
    pg.set_input_files('#schedfile', _fx); pg.wait_for_timeout(1500)
    pg.click('[data-schedgo]'); pg.wait_for_timeout(3000)
    ck('Schedule (v15)', 'the updated schedule is saved on the server with its activities and the mapping', sql("select count(*) from schedule_updates where project_id='P1'") == '1' and sql("select count(*) from schedule_update_rows where project_id='P1'") == '4'
       and sql("select wbs_map->>'CONSTRUCTION' from project_phase_setup where project_id='P1'") == 'CON', pg.inner_text('#schedBox')[:300] if pg.locator('#schedBox').count() else '')
    srv_s = json.loads(sql("select summary::text from schedule_updates where project_id='P1'") or '{}')
    app_s = pg.evaluate("(()=>{const u=schedUps('P1')[0];return u?schedSummary(DB.schedRows[u.id],u.data_date,u.weightage,u.weights):null})()")
    ck('Schedule (v15)', 'the server works out the same client and internal figures as the app', app_s is not None and all(abs(float(srv_s.get(k) or 0) - float(app_s.get(k) or 0)) < 0.011 for k in ['client_plan', 'client_act', 'int_plan', 'int_act']) and srv_s.get('tcc_date') == '2026-12-20',
       (srv_s.get('int_act'), app_s and app_s.get('int_act'), srv_s.get('client_plan'), app_s and app_s.get('client_plan')))
    ck('Schedule (v15)', 'internal actual = 20% x 100% + 80% x (50x60% + 30x20%)/80', abs(float(srv_s.get('int_act') or 0) - round(20 * 1 + 80 * (50 * .6 + 30 * .2) / 80, 2)) < 0.011, srv_s.get('int_act'))
    ck('Schedule (v15)', 'invoiceable reads the schedule % from the server', pg.evaluate("schedDone(ACTS.find(a=>a.id==='TT-100'),ASOF)") == 0.6)
    ck('E&P from the schedule (v3.8.4)', 'engineering progress comes from the updated schedule on the server: Shop drawings 100%, nothing else uploaded', pg.evaluate("(c=>c.src==='sched'&&c.pct===1)(curOf(ACTS.find(a=>a.id==='TT-E01')))") is True, pg.evaluate("curOf(ACTS.find(a=>a.id==='TT-E01'))"))
    login(pg, 'c1')
    r = pg.evaluate("rpc('schedule_update_commit',{p:{project_id:'P1',data_date:'" + dd + "',weightage:'client',rows:[{id:'X',w:1,bs:'2026-09-01',bf:'2026-09-30',pct:5}]}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Schedule (v15)', 'a costing engineer cannot upload a schedule (server refuses)', r.startswith('refused'), r)
    login(pg, 'pl')
    wk = next(w for w in pg.evaluate("recentWeeks(4)") if sql(f"select count(*) from report_releases where project_id='P1' and kind='planning' and period='{w}'") == '0' and pg.evaluate(f"periodEnd('{w}','week')>='{dd}'")); mo = pg.evaluate("curMonth()")
    pg.evaluate(f"state.scope='ALL';state.rdTab='prog';openRelease('P1','planning','week','{wk}')"); pg.wait_for_timeout(900)
    pg.fill('#relForm [name=f_actual_pct]', '70'); pg.fill('#relForm [name=r_actual_pct]', 'Site count'); pg.click('#sheet [data-reldo="submit"]'); pg.wait_for_timeout(2500)
    row = sql(f"select status||'|'||(figures->>'sched_diff_n')||'|'||coalesce(figures->>'sched_diff_text','') from report_releases where project_id='P1' and kind='planning' and period='{wk}'")
    ck('Schedule (v15)', 'an internal report with a changed actual % is submitted and the server records the difference', row.startswith('Submitted|1|actual 70'), row)
    login(pg, 'rp')
    pg.evaluate(f"state.scope='ALL';openRelease('P1','planning','week','{wk}')"); pg.wait_for_timeout(900)
    pg.click('#sheet [data-reldo="approve"]'); pg.wait_for_timeout(2000)
    ck('Schedule (v15)', 'approving without validating is refused by the server', sql(f"select status from report_releases where project_id='P1' and kind='planning' and period='{wk}'") == 'Submitted' and 'Validate the differences' in pg.evaluate("relAct.err||''"), pg.evaluate("relAct.err"))
    pg.evaluate(f"openRelease('P1','planning','week','{wk}')"); pg.wait_for_timeout(700)
    pg.check('#relValChk'); pg.fill('#relValNote', 'Agreed with site'); pg.click('#sheet [data-reldo="approve"]'); pg.wait_for_timeout(2500)
    ck('Schedule (v15)', 'with the validation the section manager approves it on the server', sql(f"select status||'/'||(sched_validated_by::text='{U['rp']}')||'/'||sched_validation_note from report_releases where project_id='P1' and kind='planning' and period='{wk}' and status='Released'") == 'Released/true/Agreed with site')
    login(pg, 'pl')
    pg.evaluate(f"state.scope='ALL';state.clTab='notes';openRelease('P1','client','month','{mo}')"); pg.wait_for_timeout(900)
    pg.fill('#relForm [name=n_summary]', 'Raft complete'); pg.click('#sheet [data-reldo="submit"]'); pg.wait_for_timeout(2500)
    row = sql(f"select status||'|'||(figures->>'sched_diff_n')||'|'||jsonb_array_length(figures->'phases')||'|'||(narrative->>'summary') from report_releases where project_id='P1' and kind='client' and period='{mo}'")
    ck('Schedule (v15)', 'the client report is prepared from the schedule and submitted on the server', row == 'Submitted|0|2|Raft complete', row)
    login(pg, 'rp')
    pg.evaluate(f"state.scope='ALL';openRelease('P1','client','month','{mo}')"); pg.wait_for_timeout(900); pg.click('#sheet [data-reldo="approve"]'); pg.wait_for_timeout(2500)
    ck('Schedule (v15)', 'the section manager approves the client report on the server', sql(f"select status||'/'||(approved_by::text='{U['rp']}') from report_releases where project_id='P1' and kind='client' and period='{mo}' and status='Released'") == 'Released/true')
    login(pg, 'pm')
    pg.evaluate("state.scope='P1';go('proj')"); pg.wait_for_timeout(900)
    ck('Schedule (v15)', 'the project manager sees progress by internal weightage on the project overview', 'internal weightage, schedule of' in pg.inner_text('#view'), pg.inner_text('#view')[:300])

    # ---------------------------------------------------------------- roles, rights and access (v16)
    login(pg, 'sa'); pg.evaluate("go('admin');state.adminTab='rights';render()"); pg.wait_for_timeout(700)
    ck('Rights (v16)', 'before the v16 update, Roles and rights says the database update is needed and every role keeps its rights', 'v16 database update' in pg.inner_text('#view') and pg.evaluate("canCost()") is True, pg.inner_text('#view')[:300])
    pv = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, 'schema-update-v16.sql')], capture_output=True, text=True)
    ck('Rights (v16)', 'the v16 update loads on top of a database in use', pv.returncode == 0, pv.stderr[:300])
    ck('Rights (v16)', 'the setup check counts 8', sql("select (select count(*) from pg_proc where proname in ('rights_save','pt_right','people_access','pt_rights')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('app_roles','role_rights','user_rights','screen_rights'))") == '8')
    pg.evaluate("cloudLoadAll(true).then(()=>render())"); pg.wait_for_timeout(1800)
    ck('Rights (v16)', 'after it, the tab has no warning', 'v16 database update' not in pg.inner_text('#view') and pg.locator('#rightsPanel').count() == 1)
    pg.uncheck('[data-rr="costing|report.cost.prepare"]'); pg.wait_for_timeout(1500)
    ck('Rights (v16)', 'unticking a right for a role is saved on the server through rights_save', sql("select allow from role_rights where role_key='costing' and right_key='report.cost.prepare'") == 'f'
       and sql("select count(*) from rights_audit where action='Role right' and by_user='%s'" % U['sa']) == '1')
    pg.evaluate(f"state.adminTab='users';render();admDrawer('users','{U['c1']}');document.querySelector('#urWrap').open=true"); pg.wait_for_timeout(500)
    pg.select_option(f'#urBox select[data-ur="{U["c1"]}|report.cost.prepare"]', '1'); pg.wait_for_timeout(1500)
    ck('Rights (v16)', 'a person exception (Allow) is saved on the server', sql(f"select allow from user_rights where user_id='{U['c1']}' and right_key='report.cost.prepare'") == 't')
    pg.evaluate("closeDrawer()")
    pg.evaluate("state.adminTab='rights';render()"); pg.wait_for_timeout(400)
    pg.fill('#crName', 'Site Planner'); pg.select_option('#crBase', 'plan'); pg.click('[data-crcreate]'); pg.wait_for_timeout(1500)
    ck('Rights (v16)', 'a custom role is created on the server from Planning Engineer', sql("select base_role||'/'||active from app_roles where key='c_site_planner'") == 'plan/true')
    pg.check('[data-rr="c_site_planner|report.internal.approve"]'); pg.wait_for_timeout(1500)
    ck('Rights (v16)', '...and given the right to approve internal and client reports', sql("select allow from role_rights where role_key='c_site_planner' and right_key='report.internal.approve'") == 't')
    pg.uncheck('[data-sr="pm|cdash"]'); pg.wait_for_timeout(1500)
    ck('Rights (v16)', 'a screen hidden for project managers is saved on the server', sql("select visible from screen_rights where role_key='pm' and view_key='cdash'") == 'f')
    pg.evaluate(f"state.adminTab='users';render();admDrawer('users','{U['pl']}')"); pg.wait_for_timeout(500)
    pg.select_option('#admForm [name="role"]', 'c_site_planner'); pg.select_option('#admForm [name="accmode"]', 'all'); pg.click('#admForm [type=submit]'); pg.wait_for_timeout(2500)
    ck('Rights (v16)', 'the planning engineer is given the custom role and All projects on the server (admin_save_person)', sql(f"select role||'/'||coalesce(custom_role,'-')||'/'||all_projects from profiles where id='{U['pl']}'") == 'plan/c_site_planner/true', sql(f"select role||'/'||coalesce(custom_role,'-')||'/'||all_projects from profiles where id='{U['pl']}'"))
    ck('Rights (v16)', 'the users list shows the custom role and All projects', 'Site Planner' in pg.inner_text('#view') and 'All projects' in pg.inner_text('#view'), pg.inner_text('#view')[:300])
    r = pg.evaluate("rpc('rights_save',{p:{action:'role_right',role_key:'foreman',right_key:'money.view',allow:true}}).then(()=>'saved').catch(e=>'refused '+srvMsg(e))")
    ck('Rights (v16)', 'the server refuses cost figures for foremen even from a super admin', r.startswith('refused') and 'Foremen never' in r, r)
    login(pg, 'c1')
    ck('Rights (v16)', 'the costing engineer reads his own exception and keeps the right the role lost', pg.evaluate("canPrepRel('cost')") is True and pg.evaluate("DB.rights.role.costing['report.cost.prepare']") is False)
    r = pg.evaluate("rpc('rights_save',{p:{action:'role_right',role_key:'pm',right_key:'money.view',allow:false}}).then(()=>'saved').catch(e=>'refused '+srvMsg(e))")
    ck('Rights (v16)', 'anyone but a super admin is refused by rights_save', r.startswith('refused') and 'Only a super admin' in r, r)
    ck('Rights (v16)', 'a costing engineer does not read the history', pg.evaluate("(DB.rights.audit||[]).length") == 0 and sql("select count(*) from rights_audit") != '0')
    login(pg, 'cc')
    ck('Rights (v16)', 'the costing coordinator keeps it through the position, whatever the role setting', pg.evaluate("canPrepRel('cost')") is True and sql(f"select pt_release_preparer('{U['cc']}','cost')") == 't')
    sql(f"delete from user_rights where user_id='{U['c1']}'")
    login(pg, 'c1')
    ck('Rights (v16)', 'without his exception the costing engineer follows the role: the app and the server refuse his cost report', pg.evaluate("canPrepRel('cost')") is False
       and pg.evaluate("rpc('release_act',{p:{action:'save',project_id:'P1',kind:'cost',period_type:'month',period:'2026-11',figures:{budget_rev0:1,actual:1,commitment:1,ftc:1}}}).then(()=>'saved').catch(e=>'refused '+srvMsg(e))").startswith('refused'))
    login(pg, 'pl')
    ck('Rights (v16)', 'the planning engineer signs in with the custom role and every project', pg.evaluate("roleName(me())") == 'Site Planner' and pg.evaluate("me().allProjects") is True and pg.evaluate("accessIds().length") == pg.evaluate("PROJECTS.length"))
    ck('Rights (v16)', '...he may approve internal reports (app and server agree)', pg.evaluate("relCanApprove('P1','planning')") is True and sql(f"select pt_rel_approver('{U['pl']}','P1')") == 't')
    login(pg, 'pm')
    ck('Rights (v16)', 'the project manager no longer has the cost dashboard in the menu', 'cdash' not in pg.evaluate("NAV_VIEWS") and 'eva' in pg.evaluate("NAV_VIEWS"), pg.evaluate("NAV_VIEWS"))
    sql("delete from role_rights; delete from user_rights; delete from screen_rights")
    sql(f"update profiles set custom_role=null, all_projects=false where id='{U['pl']}'; insert into project_access values ('{U['pl']}','P1') on conflict do nothing")

    # ---------------------------------------------------------------- material tracking (v17)
    login(pg, 'pl'); pg.evaluate("state.scope='P1';go('mat')"); pg.wait_for_timeout(700)
    ck('Materials (v17)', 'before the v17 update, Material tracking says the database update is needed', 'v17 database update' in pg.inner_text('#view'), pg.inner_text('#view')[:300])
    pv = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, 'schema-update-v17.sql')], capture_output=True, text=True)
    ck('Materials (v17)', 'the v17 update loads on top of a database in use', pv.returncode == 0, pv.stderr[:300])
    ck('Materials (v17)', 'the setup check counts 7', sql("select (select count(*) from pg_proc where proname in ('material_setup_save','material_item_save','pt_mat_keeper')) + (select count(*) from information_schema.tables where table_schema='public' and table_name in ('material_setup','material_acts','material_items','material_audit'))") == '7')
    pg.evaluate("cloudLoadAll(true).then(()=>render())"); pg.wait_for_timeout(1800)
    STG = ['PR Creation', 'PO Creation', 'Base Design', 'GAFM Approval', 'Manufacturing', 'FAT', 'Shipment', 'Delivery', 'Installation Readiness']
    MROWS = [dict(id=f'MT{i}-{j}', name=f'{m} - {u}', wbs='Procurement', wbs_leaf=f'{m} package', material=m, uact=u, bs=f'2026-{j + 1:02d}-01', bf=f'2026-{j + 1:02d}-25', pct=0)
             for i, m in enumerate(['GIS Equipment', 'Power Transformer']) for j, u in enumerate(STG)]
    MAPS = {u: k for u, k in zip(STG, ['PR', 'PO', 'BD', 'GAFM', 'MFG', 'FAT', 'RFS', 'DEL', 'CIV'])}
    r = pg.evaluate(f"mtSave('setup',{json.dumps(dict(project_id='P1', action='baseline', mat_code='Material Name', uact_code='Unified Activity Name', wbs_filter=['Procurement'], stage_map=MAPS, file_name='TT_baseline.xer', file_hash='mtb1', data_date='2026-01-01', rows=MROWS))}).then(r=>r||mtSave.err)")
    ck('Materials (v17)', 'the planning engineer loads the baseline into Material Tracking on the server', sql("select count(*) from material_acts where project_id='P1'") == '18' and sql("select count(*) from material_items where project_id='P1' and selected") == '2', r)
    pg.evaluate("render()"); pg.wait_for_timeout(500)
    pg.fill('[data-mtf="P1|GIS Equipment|po_number"]', '4500077001'); pg.press('[data-mtf="P1|GIS Equipment|po_number"]', 'Tab'); pg.wait_for_timeout(1500)
    pg.fill('[data-mtf="P1|GIS Equipment|supplier"]', 'Siemens Energy'); pg.press('[data-mtf="P1|GIS Equipment|supplier"]', 'Tab'); pg.wait_for_timeout(1500)
    ck('Materials (v17)', 'PO number and supplier typed in the table are saved on the server, with the history', sql("select po_number||'/'||supplier from material_items where project_id='P1' and material='GIS Equipment'") == '4500077001/Siemens Energy'
       and sql("select string_agg(field, ',' order by id) from material_audit where material='GIS Equipment'") == 'PO Number,Supplier Name')
    UPROWS = [dict(id='TT-100', name='Raft concrete', wbs='Structure Works', w=100, bs='2026-09-01', bf='2026-09-30', pct=50)] + \
             [dict(r, w=0, pct=100 if r['id'] in ('MT0-0', 'MT0-1', 'MT0-2', 'MT0-3', 'MT0-4', 'MT0-5', 'MT0-6') else (40 if r['id'] == 'MT0-7' else 0), mat=r['material'], uact=r['uact'],
                   **({'as': r['bs'], 'af': r['bf']} if r['id'] in ('MT0-0', 'MT0-1', 'MT0-2', 'MT0-3', 'MT0-4', 'MT0-5', 'MT0-6') else ({'as': r['bs'], 'ef': '2026-08-30'} if r['id'] == 'MT0-7' else {}))) for r in MROWS]
    r = pg.evaluate(f"schedCommit({json.dumps(dict(project_id='P1', data_date=pg.evaluate('ASOF'), weightage='internal', file_name='TT_update_Aug.xer', file_hash='mtu1', weight_basis='Duration', rows=UPROWS))}).then(r=>r?'ok':schedCommit.err)")
    ck('Materials (v17)', 'an updated schedule keeps the material codes on the server', r == 'ok' and sql("select count(*) from schedule_update_rows where project_id='P1' and mat is not null") == '18', r)
    pg.evaluate("render()"); pg.wait_for_timeout(500)
    G = pg.evaluate("(()=>{const r=mtMaterials('P1').find(r=>r.material==='GIS Equipment');return {del:r.delivery,dl:r.cells.DEL.status,fat:r.cells.FAT.status}})()")
    ck('Materials (v17)', 'statuses come from the update on the server: FAT completed, delivery started and delayed', G == {'del': 'Delivery Started', 'dl': 'Delayed', 'fat': 'Completed'}, G)
    r = pg.evaluate(f"mtSave('setup',{json.dumps(dict(project_id='P1', action='baseline', mat_code='Material Name', uact_code='Unified Activity Name', wbs_filter=['Procurement'], stage_map=MAPS, file_name='TT_baseline_rev1.xer', file_hash='mtb2', data_date='2026-02-01', rows=MROWS))}).then(r=>r||mtSave.err)")
    ck('Materials (v17)', 'a revised baseline on the server keeps PO number and supplier', sql("select po_number||'/'||supplier from material_items where material='GIS Equipment'") == '4500077001/Siemens Energy', r)
    r = pg.evaluate("rpc('material_item_save',{p:{project_id:'P1',material:'GIS Equipment',po_number:'X'}}).then(()=>'saved').catch(e=>'refused '+srvMsg(e))")
    login(pg, 'c1'); pg.evaluate("state.scope='P1';go('mat')"); pg.wait_for_timeout(700)
    r2 = pg.evaluate("rpc('material_item_save',{p:{project_id:'P1',material:'GIS Equipment',po_number:'X'}}).then(()=>'saved').catch(e=>'refused '+srvMsg(e))")
    ck('Materials (v17)', 'a costing engineer reads the tracking but the server refuses his edits (and the app shows no input boxes)', pg.evaluate("mtFiltered().length") == 2 and pg.locator('[data-mtf]').count() == 0 and r2.startswith('refused'), r2)

    # ---------------------------------------------------------------- v3.8.5: executive report layouts, materials in progress releases (no database update)
    login(pg, 'sa'); pg.evaluate("state.scope='ALL';state.xrTab='sum';go('xr')"); pg.wait_for_timeout(900)
    r = pg.evaluate("lySaveDefault('*','xr',xrPack({pt:'week',tiles:['released','progress','matlate'],secs:['mat','progress','critical']})).then(ok=>ok+'|'+lySaveDefault.err)")
    ck('Layouts (v3.8.5)', 'the super admin saves the company default of the executive report on the server', r.startswith('true') and sql("select exec_layout->'xr'->'secs'->>0 from role_config where role='*'") == 'mat', r)
    r = pg.evaluate("lySaveDefault('pm','xr',xrPack({pt:'month',tiles:['released'],secs:['region','mat']})).then(ok=>ok+'|'+lySaveDefault.err)")
    ck('Layouts (v3.8.5)', 'and a default for project managers', r.startswith('true') and sql("select exec_layout->'xr'->'secs'->>0 from role_config where role='pm'") == 'region', r)
    login(pg, 'pl'); pg.evaluate("state.scope='ALL';state.xrTab='sum';go('xr')"); pg.wait_for_timeout(900)
    r = pg.evaluate("(s=>s.src+'|'+s.L.secs[0]+'|'+s.L.pt)(xrLayoutSrc())")
    ck('Layouts (v3.8.5)', 'a planning engineer without a layout sees the company default from the server (weekly first, materials on top)', r == 'all|mat|week', r)
    login(pg, 'pm'); pg.evaluate("state.scope='ALL';state.xrTab='sum';go('xr')"); pg.wait_for_timeout(900)
    r = pg.evaluate("(s=>s.src+'|'+s.L.secs[0])(xrLayoutSrc())")
    ck('Layouts (v3.8.5)', 'a project manager sees the project manager default', r == 'role|region', r)
    r = pg.evaluate("lySaveMine('xr',xrPack({pt:'month',tiles:['spi'],secs:['critical','mat']})).then(ok=>ok+'|'+(lyPushMine.err||''))")
    ck('Layouts (v3.8.5)', 'he saves his own layout on the server', r.startswith('true') and sql(f"select prefs->'xr'->'secs'->>0 from user_prefs where user_id='{U['pm']}'") == 'critical', r)
    login(pg, 'pm'); pg.evaluate("state.scope='ALL';state.xrTab='sum';go('xr')"); pg.wait_for_timeout(900)
    r = pg.evaluate("(s=>s.src+'|'+s.L.secs[0])(xrLayoutSrc())")
    ck('Layouts (v3.8.5)', 'his layout comes back from the server at the next sign-in', r == 'mine|critical', r)
    r = pg.evaluate("SB.from('role_config').update({exec_layout:{xr:{secs:['supp']}}}).eq('role','*').select('role').then(x=>x.error?'err':String((x.data||[]).length))")
    ck('Layouts (v3.8.5)', 'the server refuses a default changed by anyone but the super admin', r in ('err', '0') and sql("select exec_layout->'xr'->'secs'->>0 from role_config where role='*'") == 'mat', r)
    r = pg.evaluate("lySaveDefault('*','xr',null).then(ok=>ok+'|'+lySaveDefault.err)")
    ck('Layouts (v3.8.5)', '...and the app does not offer it', r.startswith('false'), r)
    r = pg.evaluate("SB.from('user_prefs').select('user_id').then(x=>x.error?'err':String((x.data||[]).length))")
    ck('Layouts (v3.8.5)', 'each person reads only his own layout', r == '1', r)
    pg.evaluate("state.execTab='sum';go('exec')"); pg.wait_for_timeout(700)
    pg.evaluate("execPrefsEdit().group='sector';savePrefs()"); pg.wait_for_timeout(1200)
    ck('Layouts (v3.8.5)', 'the working summary layout is kept on the server too, beside the report layout', sql(f"select (prefs->'exec'->>'group')||'/'||(prefs->'xr'->'secs'->>0) from user_prefs where user_id='{U['pm']}'") == 'sector/critical')
    r = pg.evaluate("lySaveMine('xr',null).then(ok=>ok+'|'+(lyPushMine.err||''))")
    ck('Layouts (v3.8.5)', 'Reset removes his report layout and keeps the summary one', r.startswith('true') and sql(f"select (prefs->'xr' is null)::text||'/'||(prefs->'exec'->>'group') from user_prefs where user_id='{U['pm']}'") == 'true/sector' and pg.evaluate("xrLayoutSrc().src") == 'role', r)
    login(pg, 'pl')
    snap = pg.evaluate("relMatSnap('P1')")
    wk = next(w for w in pg.evaluate("recentWeeks(8)") if sql(f"select count(*) from report_releases where project_id='P1' and kind='planning' and period='{w}'") == '0')
    pg.evaluate(f"state.scope='ALL';state.rdTab='mat';openRelease('P1','planning','week','{wk}')"); pg.wait_for_timeout(900)
    v = pg.inner_text('#sheet [data-rdp="mat"]')
    pg.click('#sheet [data-reldo="save"]'); pg.wait_for_timeout(2500)
    row = sql(f"select (figures->>'mat_n')||'/'||(figures->>'mat_late')||'/'||coalesce(figures->>'mat_dd_date','')||'/'||coalesce(length(figures->>'mat_late_text'),0) from report_releases where project_id='P1' and kind='planning' and period='{wk}'")
    ck('Materials in releases (v3.8.5)', 'a progress release saved on the server carries the Material Tracking snapshot (monitored, delayed, data date, the delayed list)',
       snap.get('mat_n', 0) > 0 and row.startswith(f"{snap['mat_n']}/{snap['mat_late']}/") and 'Materials monitored' in v, (row, snap, v[:200]))
    pg.evaluate("document.querySelector('#sheet [data-close]')&&document.querySelector('#sheet [data-close]').click()"); pg.wait_for_timeout(400)

    # ---------------------------------------------------------------- load failure is visible, never silent
    urllib.request.urlopen(urllib.request.Request(URL + '__sb/fail', data=json.dumps({'tables': ['activities']}).encode(), headers={'content-type': 'application/json'}))
    pg.evaluate("cloudLoadAll(true).then(()=>render())"); pg.wait_for_timeout(1500)
    ck('Errors', 'a failed server load shows a warning with Try again', pg.locator('[data-cloudreload]').count() >= 1 and 'could not be loaded' in pg.inner_text('#view'), pg.inner_text('#view')[:200])
    urllib.request.urlopen(urllib.request.Request(URL + '__sb/fail', data=b'{"tables":[]}', headers={'content-type': 'application/json'}))
    pg.click('[data-cloudreload]'); pg.wait_for_timeout(2000)
    try: pg.wait_for_function("!document.querySelector('[data-cloudreload]')", timeout=12000)   # the reload takes longer as more is loaded
    except Exception: pass
    ck('Errors', 'Try again recovers', pg.locator('[data-cloudreload]').count() == 0, pg.evaluate("JSON.stringify(CLOUD_LOAD)"))

    # ---------------------------------------------------------------- browser data from before the move
    pg.evaluate("signOut()"); pg.wait_for_timeout(600); pg.close()
    seed = """(()=>{if(sessionStorage.getItem('seeded'))return;sessionStorage.setItem('seeded','1');
      const K='protrack-demo-v1';const d=JSON.parse(localStorage.getItem(K)||'null');if(!d)return;
      d.dprs.push({id:'DPR-0900',date:'2026-09-05',p:'P1',foreman:'Fahad Foreman',engineer:'',lines:[{act:'TT-100',qty:25,labour:[{cat:'Carpenter',count:5,reg:8,ot:1}],subs:[],equip:[]}],remarks:'entered before the move',attachments:['site.jpg'],status:'Approved',audit:[{t:'2026-09-05 17:10',who:'Fahad Foreman',action:'Submitted'},{t:'2026-09-06 09:00',who:'Paul Manager',action:'Approved'}],late:false,returned:false});
      d.master.acts.push({id:'TT-200',p:'P1',cls:'CON',disc:'Civil',area:'Zone C',wbs:'Finishes',name:'Plaster',uom:'m2',qty:800,bmh:1200,p6mh:1200,pw:10000,bs:'2026-09-01',bf:'2026-10-15',priorQty:0,crew:[['Mason',6],['Helper',4]],pace:1,pp:0.67});
      d.dprs.push({id:'DPR-0902',date:'2026-09-07',p:'P1',foreman:'Fahad Foreman',engineer:'',lines:[{act:'TT-200',qty:60,labour:[{cat:'Mason',count:6,reg:8,ot:0}],subs:[],equip:[]}],remarks:'',attachments:[],status:'Approved',audit:[{t:'2026-09-07 17:00',who:'Fahad Foreman',action:'Submitted'}],late:false,returned:false});
      d.dprs.push({id:'DPR-0901',date:'2026-09-06',p:'P1',foreman:'Fahad Foreman',engineer:'',lines:[{act:'TT-100',qty:10,labour:[{cat:'Carpenter',count:4,reg:8,ot:0}],subs:[],equip:[]}],remarks:'',attachments:[],status:'Submitted',audit:[{t:'2026-09-06 17:00',who:'Fahad Foreman',action:'Submitted'}],late:false,returned:false});
      localStorage.setItem(K,JSON.stringify(d));})()"""
    pg = new_page(); pg.evaluate(seed); pg.reload(); pg.wait_for_timeout(900)
    login(pg, 'sa')
    S = pg.evaluate("Object.keys(unsynced().dprs)")
    ck('Move to server', 'browser-only reports are kept aside when server data loads', 'DPR-0900' in S and 'DPR-0901' in S, S)
    ck('Move to server', 'they are not shown as server reports', pg.evaluate("!DB.dprs.some(d=>d.id==='DPR-0900')"))
    pg.evaluate("go('admin');state.adminTab='system';render()"); pg.wait_for_timeout(900)
    view = pg.inner_text('#view')
    ck('Move to server', 'System tab lists data waiting for the server', 'waiting for the server' in view and pg.locator('[data-migrate="P1"]').count() == 1, view[-400:])
    with pg.expect_download() as dl:
        pg.click('[data-migrate="P1"]'); cfm(pg)
    pg.wait_for_timeout(3500)
    ck('Move to server', 'a browser backup downloads before moving', dl.value.suggested_filename.startswith('protrack-browser-backup'), dl.value.suggested_filename)
    ck('Move to server', 'reports created on the server with history', sql("select string_agg(id||':'||status, ',' order by id) from dprs where id in ('DPR-0900','DPR-0901','DPR-0902')") == 'DPR-0900:Approved,DPR-0901:Submitted,DPR-0902:Approved')
    ck('Move to server', 'a browser-only activity is imported first, so its report can follow', sql("select name||'/'||budget_mh from activities where id='TT-200'") == 'Plaster/1200')
    ck('Move to server', 'moved history verifies', sql("select bool_and(dpr_audit_verify(id)) from dprs where id in ('DPR-0900','DPR-0901','DPR-0902')") == 't')
    recon = pg.inner_text('#migBox')
    ck('Move to server', 'reconciliation shown and matching', 'Reconciliation' in recon and 'Check' not in recon.split('Reconciliation')[1].split('Server figures')[0], recon[:500])
    with pg.expect_download() as dl2:
        pg.click('[data-migrate="P1"]'); cfm(pg)
    pg.wait_for_timeout(3000)
    ck('Move to server', 'moving again creates nothing twice', sql("select count(*) from dprs where id in ('DPR-0900','DPR-0901','DPR-0902')") == '3' and 'already' in pg.inner_text('#migBox'), pg.inner_text('#migBox')[:300])

    # ---------------------------------------------------------------- backups
    with pg.expect_download() as dl3:
        pg.click('[data-bkserver]')
    path = dl3.value.path(); data = json.load(open(path))
    pr = next((x for x in data.get('projects', []) if (x.get('project') or {}).get('id') == 'P1'), {})
    pe1 = next((x for x in data.get('projects', []) if (x.get('project') or {}).get('id') == 'PE-001'), {})
    ck('Backup', 'server backup carries the Tender details, lifecycle stages and register history (v2.8)',
       (pe1.get('project') or {}).get('te_number') == 'TE2231' and len(pe1.get('lifecycle_stages', [])) >= 4 and len(pe1.get('register_audit', [])) >= 4 and len(pe1.get('lifecycle_audit', [])) >= 4,
       {k: (len(v) if isinstance(v, list) else '') for k, v in pe1.items()})
    ck('Backup', 'server backup also holds the document rack records (v3.4)', len(pr.get('documents', [])) == 3 and len(pr.get('doc_audit', [])) >= 3 and len(pr.get('doc_boxes', [])) >= 1, {k: len(v) for k, v in pr.items() if isinstance(v, list)})
    ck('Backup', 'server backup also holds the releases, logs, issues and quantity justifications (v3.0 to v3.2)', len(pr.get('report_releases', [])) >= 3 and len(pr.get('co_log', [])) == 2 and len(pr.get('issues', [])) == 2 and len(pr.get('issue_audit', [])) >= 2 and len(pr.get('dpr_qty_just', [])) == 1,
       {k: len(v) for k, v in pr.items() if isinstance(v, list)})
    ck('Backup', 'server backup holds every report with lines and history', data.get('format') == 'protrack-server-backup' and len(pr.get('dprs', [])) == int(sql("select count(*) from dprs where project_id='P1'")) and len(pr.get('dpr_audit', [])) >= 8, {k: len(v) for k, v in pr.items() if isinstance(v, list)})
    with pg.expect_download() as dl4:
        pg.click('[data-bkbrowser]')
    bk = json.load(open(dl4.value.path()))
    ck('Backup', 'browser backup includes the waiting list', bk.get('format') == 'protrack-browser-backup' and 'DPR-0900' in (bk.get('unsynced') or {}).get('dprs', {}))
    ck('General', 'no script errors in server mode', not errs, errs[:3])

    # ---------------------------------------------------------------- demo page next to the live site
    pg.evaluate("signOut()"); pg.wait_for_timeout(600)
    ck('Demo page', 'live sign-in links to the demo page', pg.locator('#authCard a[href="demo.html"]').count() == 1)
    live_cache = pg.evaluate("localStorage.getItem('protrack-demo-v1')")
    sb_calls = []
    pg.on('request', lambda r: sb_calls.append(r.url) if '/__sb/' in r.url else None)
    pg.goto(URL + 'demo.html'); pg.wait_for_load_state('load')
    try: pg.wait_for_function("typeof CLOUD !== 'undefined'", timeout=15000)
    except Exception as ex: print('demo page did not start:', errs[-3:], pg.url, file=sys.stderr)
    pg.wait_for_timeout(800)
    ck('Demo page', 'demo page never connects to the server', pg.evaluate("CLOUD") is False and pg.evaluate("typeof window.supabase") == 'undefined', pg.evaluate("CLOUD"))
    ck('Demo page', 'sign-in says it is sample data and lists demo accounts', 'Demo page with sample data' in pg.inner_text('#authCard') and pg.locator('details.demo').count() == 1)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1800)
    ck('Demo page', 'demo account signs in to the sample projects', pg.locator('#app').is_visible() and pg.evaluate("PROJECTS.length") >= 6 and pg.evaluate("PROJECTS.some(p=>p.id==='RMX')"), pg.evaluate("PROJECTS.map(p=>p.id)"))
    ck('Demo page', 'demo data kept under its own key, live cache untouched', pg.evaluate("KEY") == 'protrack-demopage-v1' and pg.evaluate("localStorage.getItem('protrack-demo-v1')") == live_cache and pg.evaluate("!!localStorage.getItem('protrack-demopage-v1')"))
    ck('Demo page', 'no server requests from the demo page', not sb_calls, sb_calls[:3])
    ck('Demo page', 'no script errors on the demo page', not errs, errs[:3])
    pg.goto(URL + 'demo.html?r=1'); pg.wait_for_timeout(1500)
    if pg.locator('#app').is_visible(): pg.evaluate("signOut()"); pg.wait_for_timeout(800)
    ck('Demo page', 'the sample-data sign-in links team members to the server sign-in (live.html)', pg.locator('#authCard a[href="live.html"]').count() == 1)
    pg.goto(URL + 'demo.html?r=2#dpr=DPR-0900'); pg.wait_for_timeout(1500)
    ck('Demo page', 'an approval-email link that lands on the sample-data page is sent on to the live app', pg.url.endswith('live.html?r=2#dpr=DPR-0900'), pg.url)
    pg.goto(URL + 'demo.html?r=3#access_token=abc&type=recovery'); pg.wait_for_timeout(1500)
    ck('Demo page', 'so is a password-reset link', 'live.html?r=3#access_token=abc' in pg.url, pg.url)
    b.close()
srv.terminate()
summary = {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'mode': 'server (local PostgreSQL + Supabase stand-in)', 'summary': summary, 'results': R}, indent=1))
