#!/usr/bin/env python3
"""ProTrackAI v3.39 in server mode: budget supplement / returns requests and change requests against a local PostgreSQL built
from schema.sql and every update v2 to v43, through fake_supabase.py. Approval Hub is played by SQL calls with the anon role
and the token the super admin makes on the screen. Every allow and refuse is the database's.
Usage: python3 wf_e2e.py APP_HTML SUPABASE_DIR XLSX_FULL_MIN_JS > results_wf_e2e.json"""
import json, os, subprocess, sys, time, urllib.request
from playwright.sync_api import sync_playwright

APP = os.path.abspath(sys.argv[1]); DBDIR = os.path.abspath(sys.argv[2]); XL = open(sys.argv[3]).read()
HERE = os.path.dirname(os.path.abspath(__file__)); FX = os.path.join(HERE, 'fixtures', 'bcm'); fx = lambda *n: [os.path.join(FX, x) for x in n]
DBN, PORT, PW = 'pt_wf_e2e', 8768, 'Test-Pass-2026'
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
for f in ['tests/TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 44)]:
    path = os.path.join(DBDIR, f)
    if not os.path.exists(path): continue
    p = subprocess.run(PG + ['-d', DBN, '-f', path], capture_output=True, text=True)
    if p.returncode: raise SystemExit(f + ': ' + p.stderr)
people = [('sa', 'Sara Admin', 'sa'), ('pe', 'Pia Planner', 'plan'), ('cc', 'Cody Coordinator', 'costing'), ('pm', 'Paul Manager', 'pm'), ('fo', 'Faisal Foreman', 'foreman')]
U = {k: f'40000000-0000-0000-0000-0000000000{i:02d}' for i, (k, _, _) in enumerate(people, 1)}
sql("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k, _, _ in people))
sql("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, n, r in people))
sql("insert into regions (id, name) values ('R1','Western'); insert into sectors (id, name) values ('S1','Power')")
sql("insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status, pe_number) values ('P1','Thuwal KAUST 2','TK2','R1','S1','2022-12-29','2026-12-31',33.6,'Active','PE-262')")
sql("insert into project_access (user_id, project_id) values " + ",".join(f"('{U[k]}','P1')" for k in ['pe', 'cc', 'pm', 'fo']))
sql(f"insert into pcc_designations (user_id, designation) values ('{U['cc']}', 'coordinator')")
TODAY = sql("select pt_today_sa()"); MON = TODAY[:7]
def anon(fn, p):
    pp = json.dumps(p).replace("'", "''")
    r = subprocess.run(PG + ['-d', DBN, '-c', f"set role anon; select {fn}('{pp}'::jsonb);"], capture_output=True, text=True)
    return (json.loads(r.stdout.strip().splitlines()[-1]) if r.returncode == 0 and r.stdout.strip() else None), r.stderr
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
        pg.evaluate("window.aiHint=()=>{};window.rasaBubble=()=>{}")
    J = pg.evaluate
    toast = lambda: J("document.querySelector('#toast').textContent")
    def wf(extra=''): J(f"state.wfUi=Object.assign(wfUi(),{{pid:'P1'{extra}}});go('wfr')"); pg.wait_for_timeout(1500)
    login('pe'); wf(",open:null,tab:'list'")
    ck('Server', 'the app sees the v43 update', J("DB.wfV43") is True and 'need the v43' not in pg.inner_text('#view'))
    pg.click('[data-wfnew="BRF"]'); pg.wait_for_timeout(2500); fid = J("wfUi().open")
    ck('BRF', 'the planning engineer prepares BR-01 on the server', sql(f"select ref_no || '/' || status || '/' || prepared_by_name from wf_forms where id='{fid}'") == 'BR-01/Draft/Pia Planner')
    def line(i, desc, cat, uf, supp=None, sav=None):
        r = pg.locator(f'[data-wfl="{i}"]'); r.locator('[data-wl="description"]').fill(desc); r.locator('[data-wl="category"]').select_option(cat); r.locator('[data-wl="user_field"]').select_option(uf)
        if supp: r.locator('[data-wl="supp"]').fill(str(supp))
        if sav: r.locator('[data-wl="sav"]').fill(str(sav))
    line(0, 'Estimate overrun in salaries according to delay in TCC', 'Project Execution', 'SM', supp=120000)
    pg.click('[data-wfladd]'); pg.wait_for_timeout(2000); line(1, 'Saving as per attached sheets', 'Cont-Savings', 'CONT', sav=1939967)
    pg.click('[data-wfsubmit]'); pg.wait_for_timeout(3000)
    ck('Submit', 'submitted on the server: queued for Approval Hub, with the VP in the chain', sql(f"select f.status || '/' || o.status || '/' || (f.approvers ->> -1) from wf_forms f join wf_outbox o on o.form_id = f.id where f.id='{fid}'") == 'Submitted/Queued/Vice President', toast())
    r = J(f"rpc('wf_form_save',{{p:{{id:'{fid}',lines:[]}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Submit', 'the server refuses a change after submission', 'not changed' in r, r)
    login('sa'); wf(",open:null,tab:'hub'")
    ck('Hub', 'the super admin sees the link not connected, with one submission waiting', 'Not connected' in pg.inner_text('#view') and '1 submission waiting' in pg.inner_text('#view'), pg.inner_text('#view')[:600])
    pg.click('[data-wfhub="new_token"]'); pg.wait_for_timeout(2000); tok = J("(document.querySelector('#wfTok code')||{}).textContent||''")
    ck('Hub', 'connecting shows the token once', tok.startswith('pthub_') and 'Connected' in pg.inner_text('#view'), tok)
    n, err = anon('wf_hub_next', {'token': tok})
    ck('Hub', 'Approval Hub takes the submission with the token', n and len(n['items']) == 1 and n['items'][0]['payload']['ref_no'] == 'BR-01' and n['items'][0]['payload']['project']['pe_number'] == 'PE-262', err)
    anon('wf_hub_update', {'token': tok, 'message_id': n['items'][0]['message_id'], 'status': 'received', 'wf_no': 'WF-1001', 'step': 'Project Manager'})
    login('pe'); wf(f",open:'{fid}'")
    ck('Hub', 'the form shows In approval with the WF number and the step', 'WF WF-1001' in pg.inner_text('#view') and 'In approval' in pg.inner_text('#view'))
    r, err = anon('wf_hub_update', {'token': tok, 'form_id': fid, 'status': 'approved', 'date': TODAY, 'approver': 'Vice President'})
    ck('Hub', 'Approval Hub approves: posted to the budget supplement log at once', r and r['status'] == 'Approved' and sql(f"select count(*) from budget_supplements where wf_form='{fid}' and wf_no='WF-1001' and version='{MON}'") == '2', err)
    login('cc'); wf(f",open:'{fid}'"); v = pg.inner_text('#view')
    ck('Form', 'the form says approved by the hub and where it was posted', 'Posted to the budget supplement log: BR-01/1, BR-01/2' in v and 'hub' in v, v[-1200:])
    J("state.logTab='supp';go('logs')"); pg.wait_for_timeout(1500)
    ck('Log', 'the supplement log screen shows the rows posted by the WF', 'BR-01/2' in pg.inner_text('#view'))
    wf(f",open:'{fid}'")
    prev = J("wfPrev(wfForm(wfUi().open).decided_on.slice(0,7))"); pg.select_option('#wfVer', prev); pg.fill('#wfVerR', 'management approved the values in the previous month'); pg.click('[data-wfver]'); pg.wait_for_timeout(2500)
    ck('Version', 'the costing coordinator moves the version to the previous month on the server', sql(f"select string_agg(distinct version, ',') from budget_supplements where wf_form='{fid}'") == prev and sql(f"select version from wf_forms where id='{fid}'") == prev, toast())
    rid = sql("select id from budget_supplements where supp_no='BR-01/1'")
    r = J(f"rpc('supp_update',{{p:{{action:'remove',project_id:'P1',id:{rid},reason:'no longer needed'}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Log', 'the server refuses to remove a row posted from a WF', 'posted from the approved WF' in r, r)
    # by hand while the hub is off, a change request
    login('sa'); wf(",open:null,tab:'hub'"); pg.click('[data-wfhub="off"]'); pg.wait_for_timeout(2000)
    login('cc'); wf(",open:null,tab:'list'"); pg.click('[data-wfnew="CRF"]'); pg.wait_for_timeout(2500); cid = J("wfUi().open")
    pg.fill('[data-wfd="description"]', 'Additional 132kV cable route'); pg.fill('[data-wfd="price_submitted"]', '600000'); pg.select_option('[data-wfd="client_status"]', 'Submitted'); pg.fill('[data-wfd="cost_current"]', '400000')
    pg.click('[data-wfsubmit]'); pg.wait_for_timeout(3000)
    ck('CRF', 'the costing coordinator submits CR-01 on the server', sql(f"select ref_no || '/' || status from wf_forms where id='{cid}'") == 'CR-01/Submitted', toast())
    login('pe'); wf(f",open:'{cid}'")
    r = J(f"rpc('wf_form_act',{{p:{{action:'record',id:'{cid}',decision:'approved',wf_no:'WF-4004',date:'{TODAY}'}}}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Record', 'the server refuses a decision recorded by someone without wf.record', 'coordinator' in r, r)
    login('cc'); wf(f",open:'{cid}'"); pg.fill('#wfRW', 'WF-4004'); J(f"document.querySelector('#wfRT').removeAttribute('max');document.querySelector('#wfRT').value='{TODAY}'"); pg.click('[data-wfrecord]'); pg.wait_for_timeout(3000)
    ck('CRF', 'recorded by hand: added to the change order and claim log on the server', sql("select kind || '/' || est_price::numeric(12,0) || '/' || est_cost::numeric(12,0) || '/' || wf_no from co_log where ref_no='CR-01'") == 'VO/600000/400000/WF-4004'
       and sql(f"select decision_source || '/' || recorded_by_name from wf_forms where id='{cid}'") == 'manual/Cody Coordinator', toast())
    login('pm'); wf(",open:null,tab:'list'")
    ck('Rights', 'a project manager reads the forms but does not start one', 'BR-01' in pg.inner_text('#view') and pg.locator('[data-wfnew]').count() == 0)
    r = J("rpc('wf_form_save',{p:{project_id:'P1',kind:'BRF'}}).then(()=>'ran',e=>'refused: '+e.message)")
    ck('Rights', '...and the server refuses it', 'wf.initiate' in r, r)
    login('fo')
    ck('Rights', 'a foreman does not see the page, and the server gives him no form', not J("navOn('wfr')") and J("SB.from('wf_forms').select('id').then(x=>(x.data||[]).length)") == 0)
    ck('Page', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'suite': 'wf_e2e', 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
