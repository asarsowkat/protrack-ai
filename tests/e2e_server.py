#!/usr/bin/env python3
"""ProTrackAI v2.5 in server mode, end to end: the real app in Chromium, talking to a local PostgreSQL built
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
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql', 'schema-update-v2.sql', 'schema-update-v3.sql', 'schema-update-v4.sql']:
    p = subprocess.run(PG + ['-d', DBN, '-f', os.path.join(DBDIR, f)], capture_output=True, text=True)
    if p.returncode: raise SystemExit(f + ': ' + p.stderr)
people = [('sa', 'Sara Admin', 'sa'), ('pm', 'Paul Manager', 'pm'), ('e1', 'Eng. Omar Engineer', 'eng'), ('e2', 'Eng. Hadi Other', 'eng'),
          ('s1', 'Samir SiteManager', 'sm'), ('f1', 'Faisal Foreman', 'foreman'), ('f2', 'Fahad Foreman', 'foreman'),
          ('c1', 'Carla Costing', 'costing'), ('pl', 'Peter Planner', 'plan')]
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
        pg.fill('#lgId', f'{who}@test.local'); pg.fill('#lgPw', PW); pg.click('#lgBtn'); pg.wait_for_timeout(2600)
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
    pg.click('[data-costgo]'); pg.wait_for_timeout(2500)
    ck('Costing', 'costing file applied on the server', sql("select budget_cost||'/'||budget_mh||'/'||costed from activities where id='TT-100'") == '300000/2100/true', sql("select budget_cost||'/'||budget_mh from activities where id='TT-100'"))
    ck('Costing', 'app shows the server values', pg.evaluate("(()=>{const a=ACTS.find(x=>x.id==='TT-100');return a.bcost===300000&&a.bmh===2100})()"))
    ck('Costing', 'upload recorded as a batch with a file fingerprint', sql("select count(*)||'/'||min(length(file_hash)) from import_batches where kind='costing'") == '1/64')
    pg.set_input_files('#costfile', book(aoa, 'Costing', 'costing_TT.xlsx')); pg.wait_for_timeout(1200); pg.click('[data-costgo]'); pg.wait_for_timeout(2000)
    ck('Costing', 'same file again changes nothing', sql("select count(*) from import_batches where kind='costing'") == '1' and sql("select count(*) from baseline_history") == '1')
    ihead = ['Invoice number', 'Invoice date', 'Type', 'Invoice amount (SAR)', 'Submitted amount (SAR)', 'Approved amount (SAR)', 'Collected amount (SAR)', 'Remark']
    inv = [ihead, ['INV-1', '2026-08-31', 'Progress', 1000000, 1000000, 900000, 800000, 'IPC 1'], ['INV-ADV', '2026-08-01', 'Advance', 2000000, 2000000, 2000000, 2000000, 'Advance']]
    pg.set_input_files('#invfile', book(inv, 'Invoices', 'invoices_TT.xlsx')); pg.wait_for_timeout(1200)
    pg.click('[data-invgo]'); pg.wait_for_timeout(2500)
    ck('Invoices', 'register loaded on the server', sql("select count(*)||'/'||sum(submitted) from invoices where project_id='P1'") == '2/3000000')
    ck('Invoices', 'app totals come from the server', pg.evaluate("invTotals('P1').submitted") == 3000000 and 'Carla Costing' in pg.evaluate("(DB.invMeta.P1||{}).by||''"), pg.evaluate("DB.invMeta.P1"))
    login(pg, 'f1')
    r = pg.evaluate("rpc('import_invoices',{p_project:'P1',p_file:'x',p_hash:'f'.repeat(64),p_rows:[],p_period:null}).then(()=>'ran',e=>e.message)")
    ck('Invoices', 'a foreman calling the invoice import is refused', 'Only costing' in r, r)
    r = pg.evaluate("rpc('import_baseline',{p_project:'P1',p_file:'x',p_hash:'e'.repeat(64),p_rows:[{id:'Z1',name:'Z'}]}).then(()=>'ran',e=>e.message)")
    ck('Baseline', 'a foreman calling the baseline import is refused', 'Only planning' in r, r)

    # ---------------------------------------------------------------- planner: hand-added activity, weekly update path
    login(pg, 'pl')
    ok = pg.evaluate("cloudRunBaseline('P1',[{id:'TT-120',name:'Blockwork',cls:'CON',disc:'Civil',area:'Zone B',wbs:'Masonry',uom:'m2',qty:500,bmh:900,pw:20000,bs:'2026-10-01',bf:'2026-11-15',priorQty:0}],'Added by hand: TT-120')"); pg.wait_for_timeout(1500)
    ck('Baseline', 'planner adds an activity through the server', ok is True and sql("select name from activities where id='TT-120'") == 'Blockwork' and pg.evaluate("!!ACTS.find(a=>a.id==='TT-120')"), ok)

    r = pg.evaluate("cloudCommitUpdate({dataDate:'2026-09-21',file:'upd.xlsx'},[{a:ACTS.find(a=>a.id==='TT-E01'),ms:'IDC',pct:0.4,rem:'IDC sent'}]).then(()=>document.querySelector('#toast').textContent)"); pg.wait_for_timeout(800)
    ck('Weekly update', 'planner progress update saved on the server', sql("select cur->>'ms' from activities where id='TT-E01'") == 'IDC' and sql("select count(*) from weekly_updates") == '1', r)
    ck('Weekly update', 'app shows the server progress', pg.evaluate("curOf(ACTS.find(a=>a.id==='TT-E01')).ms") == 'IDC')
    login(pg, 'f1')
    r = pg.evaluate("cloudCommitUpdate({dataDate:'2026-09-22',file:'upd2.xlsx'},[{a:ACTS.find(a=>a.id==='TT-E01'),ms:'IFC',pct:1,rem:'x'}]).then(()=>document.querySelector('#toast').textContent)"); pg.wait_for_timeout(800)
    ck('Weekly update', 'a foreman cannot change progress (server refuses)', sql("select cur->>'ms' from activities where id='TT-E01'") == 'IDC' and 'refused' in r, r)

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
    pr = data['projects'][0] if data.get('projects') else {}
    ck('Backup', 'server backup holds every report with lines and history', data.get('format') == 'protrack-server-backup' and len(pr.get('dprs', [])) == 4 and len(pr.get('dpr_audit', [])) >= 8, {k: len(v) for k, v in pr.items() if isinstance(v, list)})
    with pg.expect_download() as dl4:
        pg.click('[data-bkbrowser]')
    bk = json.load(open(dl4.value.path()))
    ck('Backup', 'browser backup includes the waiting list', bk.get('format') == 'protrack-browser-backup' and 'DPR-0900' in (bk.get('unsynced') or {}).get('dprs', {}))
    ck('General', 'no script errors in server mode', not errs, errs[:3])
    b.close()
srv.terminate()
summary = {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'mode': 'server (local PostgreSQL + Supabase stand-in)', 'summary': summary, 'results': R}, indent=1))
