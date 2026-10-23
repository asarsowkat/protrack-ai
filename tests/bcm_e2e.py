#!/usr/bin/env python3
"""ProTrackAI v3.35 in server mode: Budget & Cost Management, Automatic WBS Classification, against a local PostgreSQL
built from schema.sql and every update v2 to v39, through fake_supabase.py (files kept by the stand-in storage, under the
database's own storage rules). Every allow and refuse is the database's. The real SheetJS 0.18.5 reads the workbooks.
Usage: python3 bcm_e2e.py APP_HTML SUPABASE_DIR XLSX_FULL_MIN_JS > results_bcm_e2e.json"""
import json, os, subprocess, sys, time, urllib.request
from playwright.sync_api import sync_playwright

APP = os.path.abspath(sys.argv[1]); DBDIR = os.path.abspath(sys.argv[2]); XL = open(sys.argv[3]).read()
HERE = os.path.dirname(os.path.abspath(__file__)); FX = os.path.join(HERE, 'fixtures', 'bcm'); fx = lambda *n: [os.path.join(FX, x) for x in n]
DBN, PORT, PW = 'pt_bcm_e2e', 8767, 'Test-Pass-2026'
URL = f'http://127.0.0.1:{PORT}/'
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
R = []
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:400]})
    print(('PASS ' if cond else 'FAIL ') + area + ': ' + name + ('' if cond else '  -> ' + str(detail)[:400]), file=sys.stderr)
def sql(q):
    p = subprocess.run(PG + ['-d', DBN, '-c', q], capture_output=True, text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()
subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 40)]:
    path = os.path.join(DBDIR, f)
    if not os.path.exists(path): continue
    p = subprocess.run(PG + ['-d', DBN, '-f', path], capture_output=True, text=True)
    if p.returncode: raise SystemExit(f + ': ' + p.stderr)
people = [('sa', 'Sara Admin', 'sa'), ('co', 'Carla Costing', 'costing'), ('ap', 'Adam Approver', 'pm'), ('pl', 'Peter Planner', 'plan'), ('fo', 'Faisal Foreman', 'foreman')]
U = {k: f'30000000-0000-0000-0000-0000000000{i:02d}' for i, (k, _, _) in enumerate(people, 1)}
sql("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k, _, _ in people))
sql("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, n, r in people))
sql("insert into regions (id, name) values ('R1','Central'); insert into sectors (id, name) values ('S1','Buildings')")
sql("insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status) values ('P1','Test Tower','TT','R1','S1','2026-08-01','2027-12-31',50,'Active')")
sql("insert into project_access (user_id, project_id) values " + ",".join(f"('{U[k]}','P1')" for k in ['co', 'ap', 'pl', 'fo']))
sql(f"insert into user_rights (user_id, right_key, allow) values ('{U['ap']}', 'bcm.approve', true)")

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
    if 'xlsx' in u: return r.fulfill(body=XL, content_type='application/javascript')
    if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
    return r.abort()

with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    ctx = b.new_context(viewport={'width': 1440, 'height': 900}, accept_downloads=True); ctx.route('**/*', route); errs = []
    pg = ctx.new_page(); pg.on('pageerror', lambda e: errs.append(str(e))); pg.goto(URL); pg.wait_for_timeout(900)
    def login(who):
        if pg.locator('#app').is_visible(): pg.evaluate("signOut()"); pg.wait_for_timeout(700)
        pg.fill('#lgId', f'{who}@test.local'); pg.fill('#lgPw', PW); pg.click('#lgBtn')
        pg.wait_for_selector('#app', state='visible', timeout=15000); pg.wait_for_timeout(2500)
        pg.evaluate("window.aiHint=()=>{};window.rasaBubble=()=>{};window.__jb=BCM_JOBS.length")
    J = pg.evaluate
    toast = lambda: J("document.querySelector('#toast').textContent")
    def wait_jobs(k=1, n=160):
        for _ in range(n):
            pg.wait_for_timeout(500)
            if J(f"BCM_JOBS.length>=window.__jb+{k}&&BCM_JOBS.every(j=>j.ok||j.err)"): break
        J("window.__jb=BCM_JOBS.length")
    def open_sec(sec): J(f"go('bcm');bcmUi().sec='{sec}';render()"); pg.wait_for_timeout(1200)

    # ---- before approval: nothing classifies
    login('co'); open_sec('intake')
    ck('Server', 'the app sees the v39 update', J("DB.bcmSrv") is True and J("bcmOf('wbs').length") == 50)
    ck('Server', 'the starting master is waiting for approval (overview says so)', J("bcmOf('wbs').every(m=>!m.cur)") and (J("bcmUi().sec='ov';render();document.querySelector('#view').innerText.includes('The WBS master is not approved yet')")))
    J("bcmUi().sec='intake';render()"); pg.wait_for_timeout(300)
    pg.fill('#bcmTr', 'T-2026-118'); pg.select_option('#bcmPt', '132 kV substation'); pg.click('[data-bcmnewbatch]'); pg.wait_for_timeout(1500)
    bid = J("bcmUi().bid")
    ck('Intake', 'the costing engineer creates a batch on the server', sql(f"select tender_ref||'/'||currency||'/'||created_by_name from bcm_batches where id='{bid}'") == 'T-2026-118/SAR/Carla Costing')
    pg.set_input_files('#bcmFiles', fx('01_simple.xlsx', '12_not_a_workbook.xlsx')); wait_jobs(2)
    ck('Intake', 'the file is stored in the private bucket under the batch folder and registered with its SHA-256', sql(f"select count(*) from storage.objects where bucket_id='bcm-tender' and name like 'bcm/P1/{bid}/%.xlsx'") == '1' and sql(f"select status||'/'||run from bcm_files where batch_id='{bid}'") == 'Extracted/1')
    ck('Intake', 'its rows are on the server, exact, with their cells', sql(f"select count(*)||'/'||sum(amount) filter (where kind='item')::text from bcm_lines where batch_id='{bid}'") == '7/6572300.000000' and sql(f"select refs->>'amount' from bcm_lines where batch_id='{bid}' and row_no=2") == 'F2')
    ck('Intake', 'nothing is classified while no element is approved, and the person is told why', 'no approved element' in J("BCM_JOBS.find(j=>j.name==='01_simple.xlsx').steps.join(' ')") and sql(f"select count(*) from bcm_class where batch_id='{bid}'") == '0')
    ck('Intake', 'the text file is refused before anything is stored', J("BCM_JOBS.some(j=>j.name==='12_not_a_workbook.xlsx'&&/not an Excel workbook/.test(j.err))") and sql("select count(*) from bcm_files") == '1')
    # ---- approvals: the costing engineer cannot; the approver approves all
    open_sec('master')
    ck('Master', 'the costing engineer (no bcm.approve) is not offered approval', pg.locator('[data-bcmapprall]').count() == 0)
    r = J("rpc('bcm_master_act',{p:{action:'approve',id:'W-SM'}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Master', '...and the server refuses it', 'bcm.approve' in r, r)
    login('ap'); open_sec('master')
    J("window.confirmBox=()=>Promise.resolve(true)"); pg.click('[data-bcmapprall]'); pg.wait_for_timeout(6000)
    ck('Master', 'the approver approves the whole starting master and rules (parents first) on the server', sql("select count(*) from bcm_master where cur is not null and ent in ('wbs','rule')") == '88' and sql("select count(*) from bcm_master_hist where action='Approved' and decided_by_name='Adam Approver'") == '88', toast())
    # ---- classification on the server
    login('co'); open_sec('auto')
    pg.click(f'[data-bcmrun="{bid}"]'); pg.wait_for_timeout(3000)
    st = sql(f"select string_agg(l.descr||'='||c.status||'/'||coalesce(c.wbs_id,''), ' | ' order by l.row_no) from bcm_class c join bcm_lines l on l.id=c.line_id where c.batch_id='{bid}' and l.kind='item'")
    ck('Classification', 'run on the server: rebar automatic (CIV-06), transformer held for review, excavation waiting for a cost type', 'Supply of rebar Grade 60=Auto-Classified/W-CIV-06' in st and 'Transformer supply 132/13.8kV 40MVA=Pending Review/W-ELM-02' in st and 'Excavation for cable trench=Pending Review/W-CIV-03' in st, st)
    r = J(f"rpc('bcm_classify',{{p:{{lines:[{{id:bcmLinesOf('{bid}').find(l=>/Transformer/.test(l.desc)).id,status:'Auto-Classified',wbs_id:'W-ELM-02',cost_type:'Material',conf:0.99,layer:'rule',refs:{{rule:'R-011'}},flags:[]}}]}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Classification', 'the server refuses an automatic classification of the high-value line even when the app sends no flag', 'high value' in r, r)
    # ---- review on the server
    open_sec('review'); J("bcmUi().F={st:'Auto-Classified'};render()"); pg.wait_for_timeout(300); pg.click('[data-bcmselall]'); pg.click('[data-bcmbulk="confirm"]'); pg.wait_for_timeout(2500)
    ck('Review', 'bulk confirmation of the automatic lines is recorded on the server, with who', sql(f"select count(*) from bcm_class where batch_id='{bid}' and status='Confirmed' and decided_by_name='Carla Costing'") == '4' and sql("select count(*) from bcm_class_hist where action='Confirmed (bulk)'") == '4')
    exc = J(f"bcmLinesOf('{bid}').find(l=>/Excavation/.test(l.desc)).id")
    J(f"bcmOpenLine('{exc}')"); pg.wait_for_timeout(1200)
    pg.select_option('#bcmLT', 'Subcontract'); pg.fill('#bcmLR', 'excavation is let to the civil subcontractor'); pg.select_option('#bcmLS', 'project'); pg.click('[data-bcmdo="override"]'); pg.wait_for_timeout(2500)
    ck('Review', 'an override with a reason is stored on the server, marked overridden', sql(f"select status||'/'||cost_type||'/'||override from bcm_class where line_id='{exc}'") == 'Confirmed/Subcontract/true')
    ck('Learning', '...and the project mapping is proposed on the server, waiting', sql("select count(*) from bcm_master where ent='map' and cur is null and pend->'data'->>'key'='Excavation for cable trench' and pend->>'by_name'='Carla Costing'") == '1')
    J("closeDrawer()"); tr = J(f"bcmLinesOf('{bid}').find(l=>/Transformer/.test(l.desc)).id")
    J(f"bcmOpenLine('{tr}')"); pg.wait_for_timeout(1200); pg.click('[data-bcmdo="confirm"]'); pg.wait_for_timeout(2000)
    ck('Review', 'the high-value line is confirmed on its own', sql(f"select status from bcm_class where line_id='{tr}'") == 'Confirmed')
    ck('Review', 'the line history comes from the server', 'Confirmed' in pg.inner_text('#sheet') and 'Engine' in pg.inner_text('#sheet'))
    J("closeDrawer()")
    # ---- mapping approval, then a second file uses it
    login('ap'); open_sec('learn')
    mid = sql("select id from bcm_master where ent='map'")
    pg.click(f'[data-bcmappr="{mid}"]'); pg.wait_for_timeout(2500)
    ck('Learning', 'someone else approves the mapping on the server (version 1)', sql(f"select ver||'/'||(pend is null) from bcm_master where id='{mid}'") == '1/true')
    login('co'); open_sec('intake')
    pg.set_input_files('#bcmFiles', fx('10_negative_rev1.xlsx')); wait_jobs(1)
    st = sql(f"select c.status||'/'||c.layer||'/'||c.cost_type from bcm_class c join bcm_lines l on l.id=c.line_id join bcm_files f on f.id=l.file_id where f.name='10_negative_rev1.xlsx' and l.descr like 'Excavation%'")
    ck('Learning', 'Rev 1 is classified by the approved mapping: automatic, accepted by the server', st == 'Auto-Classified/map/Subcontract', st)
    pg.set_input_files('#bcmFiles', fx('01_simple.xlsx')); wait_jobs(1)
    ck('Intake', 'the same file again is refused (the app checks; the server would refuse it too)', 'already uploaded' in J("BCM_JOBS[0].steps.join(' ')") and sql("select count(*) from bcm_files") == '2')
    fid = sql("select id from bcm_files where name='01_simple.xlsx'")
    r = J(f"rpc('bcm_file_add',{{p:{{batch_id:'{bid}',name:'copy.xlsx',sha256:bcmFile('{fid}').sha256,size:10,kind:'xlsx',path:bcmFile('{fid}').path}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Intake', '...and the server refuses a second registration of the same fingerprint', 'already uploaded' in r, r)
    pg.click(f'[data-bcmverify="{fid}"]'); pg.wait_for_timeout(2500)
    ck('Intake', 'Verify reading downloads the stored file from the server and reads it again: the same rows', 'Verified' in toast(), toast())
    # ---- people without the right
    login('pl'); open_sec('intake')
    ck('Rights', 'a planner sees the batch but is not offered uploads', J("!document.querySelector('#bcmFiles')") and 'T-2026-118' in pg.inner_text('#view'))
    r = J("rpc('bcm_batch_save',{p:{project_id:'P1',tender_ref:'X',currency:'SAR'}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Rights', '...and the server refuses a batch from him', 'bcm.upload' in r, r)
    r = J(f"rpc('bcm_review',{{p:{{ids:['{exc}'],action:'undo',reason:'not mine to undo'}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Rights', '...or a review decision', 'bcm.review' in r, r)
    login('fo')
    ck('Rights', 'a foreman does not see the module, and the server gives him no line', not J("navOn('bcm')") and J("SB.from('bcm_lines').select('id').then(x=>(x.data||[]).length)") == 0)
    ck('Page', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'suite': 'bcm_e2e', 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
