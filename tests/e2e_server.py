#!/usr/bin/env python3
"""ProTrackAI v2.5+ (extended to v2.8) in server mode, end to end: the real app in Chromium, talking to a local PostgreSQL built
from the real ProTrack schema (schema.sql + v2 + v3 + v4) through fake_supabase.py.
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
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql', 'schema-update-v4.sql', 'schema-update-v5.sql', 'schema-update-v6.sql', 'schema-update-v7.sql', 'schema-update-v8.sql']:
    p = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, f)], capture_output=True, text=True)
    if p.returncode: raise SystemExit(f + ': ' + p.stderr)
people = [('sa', 'Sara Admin', 'sa'), ('pm', 'Paul Manager', 'pm'), ('e1', 'Eng. Omar Engineer', 'eng'), ('e2', 'Eng. Hadi Other', 'eng'),
          ('s1', 'Samir SiteManager', 'sm'), ('f1', 'Faisal Foreman', 'foreman'), ('f2', 'Fahad Foreman', 'foreman'),
          ('c1', 'Carla Costing', 'costing'), ('pl', 'Peter Planner', 'plan'), ('cc', 'Cora Coordinator', 'costing'), ('hd', 'Hana Head', 'plan')]
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
    uh = ['Activity ID', 'Milestone reached', 'Actual start', 'Actual finish', 'Forecast finish', 'Data date', 'Remarks']
    pg.set_input_files('#updfile', book([uh, ['TT-E01', 'IDC', '2026-08-05', '', '2026-10-10', '2026-09-21', 'IDC sent']], 'Update', 'update_wk38.xlsx')); pg.wait_for_timeout(1200)
    pg.click('[data-updgo]'); pg.wait_for_timeout(2500)
    r = pg.inner_text('#toast')
    ck('Weekly update', 'planner progress update saved on the server in one batch', sql("select cur->>'ms' from activities where id='TT-E01'") == 'IDC' and sql("select count(*) from weekly_updates") == '1' and sql("select count(*) from import_batches where kind='update' and status='committed'") == '1', r)
    ck('Weekly update', 'app shows the server progress', pg.evaluate("curOf(ACTS.find(a=>a.id==='TT-E01')).ms") == 'IDC')
    login(pg, 'f1')
    r = pg.evaluate("rpc('import_commit',{p:{kind:'update',project_id:null,file_name:'upd2.xlsx',hash:'a'.repeat(64),data_date:'2026-09-22',rows:[{project_id:'P1',id:'TT-E01',ms:'IFC'}]}}).then(()=>'ran',e=>'refused: '+e.message)"); pg.wait_for_timeout(800)
    ck('Weekly update', 'a foreman cannot change progress (server refuses)', sql("select cur->>'ms' from activities where id='TT-E01'") == 'IDC' and 'refused' in r, r)

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

    # ---------------------------------------------------------------- load failure is visible, never silent
    urllib.request.urlopen(urllib.request.Request(URL + '__sb/fail', data=json.dumps({'tables': ['activities']}).encode(), headers={'content-type': 'application/json'}))
    pg.evaluate("cloudLoadAll(true).then(()=>render())"); pg.wait_for_timeout(1500)
    ck('Errors', 'a failed server load shows a warning with Try again', pg.locator('[data-cloudreload]').count() >= 1 and 'could not be loaded' in pg.inner_text('#view'), pg.inner_text('#view')[:200])
    urllib.request.urlopen(urllib.request.Request(URL + '__sb/fail', data=b'{"tables":[]}', headers={'content-type': 'application/json'}))
    pg.click('[data-cloudreload]'); pg.wait_for_timeout(2000)
    ck('Errors', 'Try again recovers', pg.locator('[data-cloudreload]').count() == 0)

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
    ck('Backup', 'server backup holds every report with lines and history', data.get('format') == 'protrack-server-backup' and len(pr.get('dprs', [])) == 4 and len(pr.get('dpr_audit', [])) >= 8, {k: len(v) for k, v in pr.items() if isinstance(v, list)})
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
