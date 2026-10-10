"""ProTrackAI v2.8 in demo (browser) mode: Tender register, PE numbers (proposal, duplicates, release and
reallocation), designations, stages 1 to 5 approved by the Head of Planning and Cost Control, stage 4 due 7 days
after signing. Usage: python3 tender_demo.py /path/to/index.html > results_tender_demo.json"""
import sys, json, time
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:240]})
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        return r.abort()
    return r.continue_()
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true)")
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(450)
    J = lambda js: pg.evaluate(js)
    SA = J("me().id"); PRIYA = 'U40'; NABIL = 'U30'; ENG = J("(DB.master.users.find(u=>u.role==='eng')||{}).id")
    PID = J("PROJECTS[0].id"); PM = J(f"(teamOf('{PID}','pm')[0]||{{}}).id")
    n0 = J("PROJECTS.length")

    # ---- demo designations and menu
    ck('Designations', 'demo: the planning manager is Head of Planning and Cost Control, Priya Raman is costing coordinator', J("isHead(userById('U28'))&&isCoord(userById('U40'))&&!isHead(userById('U40'))"))
    ck('Navigation', 'Tender register is live in Projects & Handover (no longer planned)', pg.locator('#nav [data-go="tender"]').count() == 1 and pg.locator('#nav .planned', has_text='Tender register').count() == 0)
    ck('Demo data', 'demo projects carry sample TE numbers, clients and locations', J("PROJECTS.every(p=>/^TE\\d+$/.test(p.te)&&p.client&&p.location)"))
    pg.evaluate("state.scope='ALL';go('tender')"); pg.wait_for_timeout(500)
    v = pg.inner_text('#view')
    ck('Register', 'one row per project in scope, with PE, TE, client and status', pg.locator('#view tbody tr[data-tenopen]').count() == J("scopeProjects().length") and 'TE number' in v and 'PE number history' in v, v[:300])
    ck('Register', 'next PE number shown (demo projects have no PE numbers, so PE-001)', 'PE-001' in pg.inner_text('#tenNext'))

    # ---- costing coordinator registers an L1 project
    as_(PRIYA); pg.evaluate("state.scope='ALL';go('tender')"); pg.wait_for_timeout(400)
    ck('Permissions', 'the costing coordinator sees the register button', pg.locator('[data-tenreg]').count() == 1)
    pg.click('[data-tenreg]'); pg.wait_for_timeout(500)
    ck('Register form', 'proposed PE number is filled in and read-only for the coordinator', pg.input_value('#tenPe') == 'PE-001' and pg.get_attribute('#tenPe', 'readonly') is not None and 'Only a super admin can change it' in pg.inner_text('#sheet'))
    pg.fill('#tenForm [name=te_number]', 'te2231'); pg.fill('#tenForm [name=name]', 'Riyadh 132 kV substation'); pg.fill('#tenForm [name=client]', 'SEC')
    pg.fill('#tenForm [name=location]', 'Riyadh'); pg.fill('#tenForm [name=expected_value_m]', '42.5'); pg.click('#tenForm [type=submit]'); pg.wait_for_timeout(600)
    P1 = J("(PROJECTS.find(p=>p.te==='TE2231')||{}).id")
    ck('Register', 'TE2231 registered as PE-001, pre-award', P1 == 'PE-001' and J("projById('PE-001').status") == 'Pre-award' and J("projById('PE-001').expected") == 42.5, P1)
    ck('Register', 'the coordinator owns stages 1 to 4 and sees the project', J(f"[1,2,3,4].every(n=>lcGet('PE-001',n).owner==='{PRIYA}')") and J("accessIds().includes('PE-001')"))
    ck('Register', 'history shows the registration and the PE allocation', J("DB.regAudit.filter(a=>a.project_id==='PE-001').map(a=>a.action).join()") == 'Registered,PE allocated')
    ck('Register', 'the same TE number cannot be registered twice', J("tenderActLocal.length&&(()=>{try{tenderActLocal('register',null,{te_number:' TE2231 ',name:'x'});return false}catch(e){return /already registered/.test(e.message)}})()"))
    ck('Register', 'the coordinator cannot pick another PE number (the proposal is used)', J("(()=>{const r=tenderActLocal('register',null,{te_number:'TE2232',name:'Second',pe_number:'PE-900'});return r.pe_number})()") == 'PE-002')
    ck('Permissions', 'the coordinator cannot cancel a project', J("(()=>{try{tenderActLocal('cancel','PE-002',{},'x');return false}catch(e){return /Head of Planning/.test(e.message)}})()"))
    pm_ = J("(DB.master.users.find(u=>u.role==='pm')||{}).id"); as_(pm_); pg.evaluate("go('tender')"); pg.wait_for_timeout(300)
    ck('Permissions', 'a project manager can view the register but not register', pg.locator('#nav [data-go="tender"]').count() == 1 and pg.locator('[data-tenreg]').count() == 0)
    as_(ENG)
    ck('Permissions', 'a site engineer has no Tender register', pg.locator('#nav [data-go="tender"]').count() == 0)
    pg.evaluate("go('tender')"); pg.wait_for_timeout(300)
    ck('Permissions', 'forcing it as a site engineer shows nothing', 'PE number history' not in pg.inner_text('#view'))

    # ---- super admin: own PE number, duplicates
    as_(SA)
    ck('PE numbers', 'a super admin can choose another PE number', J("tenderActLocal('register',null,{te_number:'TE2240',name:'Jeddah depot',pe_number:'pe 50'}).pe_number") == 'PE-050')
    ck('PE numbers', 'the next proposal continues after it', J("peProposeLocal().proposed") == 'PE-051')
    ck('PE numbers', 'PE-0050 is the same number and is refused', J("(()=>{try{tenderActLocal('register',null,{te_number:'TE2241',name:'x',pe_number:'PE-0050'});return false}catch(e){return /already given/.test(e.message)}})()"))
    ck('PE numbers', 'a code that is not a PE number is refused', J("(()=>{try{tenderActLocal('register',null,{te_number:'TE2241',name:'x',pe_number:'XY-1'});return false}catch(e){return /looks like PE-123/.test(e.message)}})()"))
    ck('PE numbers', 'the admin project form refuses a code already given as a live PE number', J("(()=>{state.adm={type:'projects',id:null};admDrawer('projects',null);const f=$('#admForm');f.elements.code.value='PE-50';f.elements.name.value='x';f.elements.short.value='x';saveAdm(new FormData(f));return $('#admErr').textContent})()").startswith('That PE number is already given'))
    pg.evaluate("closeDrawer()")

    # ---- stages 1 to 5: Head approves, project manager does not
    as_(PRIYA)
    ck('Stages 1-5', 'the coordinator ticks stage 1 and submits it', J("lcAct('PE-001',1,'update',{ticks:[{k:'te',done:true},{k:'value',done:true}]})") and J("lcAct('PE-001',1,'submit')") and J("lcGet('PE-001',1).status") == 'Awaiting approval')
    ck('Stages 1-5', 'the stage drawer names the Head as approver', 'Head of Planning and Cost Control' in J("(openStage('PE-001',1),$('#sheet').innerText)"))
    ck('Stages 1-5', 'the coordinator cannot approve their own submission', J("lcAct('PE-001',1,'approve')") is False)
    pg.evaluate("closeDrawer()")
    ck('Stages 1-5', 'the stage 1 evidence shows the TE details and expected value', 'TE2231' in J("lcEvidence(projById('PE-001'),'te').note") and '42.5' in J("lcEvidence(projById('PE-001'),'value').note"))
    as_(SA)
    pg.evaluate("go('act');state.actF={who:'mine'};render()"); pg.wait_for_timeout(300)
    ck('Actions', 'the Head sees stage 1 waiting under Mine', 'Stage 1, Tender L1 notification: approve or return' in pg.inner_text('#view'))
    ck('Stages 1-5', 'the Head approves it', J("lcAct('PE-001',1,'approve')") and J("lcGet('PE-001',1).status") == 'Complete')
    # a project manager on an older project can no longer approve stage 2
    ck('Stages 1-5', 'reopen stage 2 on an existing project', J(f"lcAct('{PID}',2,'reopen',{{note:'Check PE number'}})"))
    own2 = J(f"lcGet('{PID}',2).owner"); as_(own2); J(f"lcAct('{PID}',2,'submit')")
    if PM: as_(PM)
    ck('Stages 1-5', 'the project manager cannot approve stage 2 any more', J(f"lcAct('{PID}',2,'approve')") is False and J(f"lcGet('{PID}',2).status") == 'Awaiting approval')
    ck('Stages 6-12', 'the project manager still decides stages 6 to 12', J(f"lcBoss('{PID}',8)") is True and J(f"lcBoss('{PID}',2)") is False)
    # name a second Head through the users screen
    as_(SA); pg.evaluate(f"go('admin');state.adminTab='users';render();admDrawer('users','{NABIL}')"); pg.wait_for_timeout(400)
    ck('Designations', 'the user form has the two designations', pg.locator('#admForm [name=pcc][value=head]').count() == 1 and pg.locator('#admForm [name=pcc][value=coordinator]').count() == 1)
    pg.check('#admForm [name=pcc][value=head]'); pg.click('#admForm [type=submit]'); pg.wait_for_timeout(400)
    ck('Designations', 'saving names Nabil Haddad Head of Planning and Cost Control', J(f"isHead(userById('{NABIL}'))"))
    nab_on = J(f"accessIds(userById('{NABIL}')).includes('{PID}')")
    as_(NABIL)
    ck('Stages 1-5', 'a Head who is not a super admin approves stage 2 on a project they can see', nab_on and J(f"lcAct('{PID}',2,'approve')") is True and J(f"lcGet('{PID}',2).status") == 'Complete', nab_on)
    ck('Stages 6-12', 'but not stages 6 to 12', J(f"lcBoss('{PID}',9)") is False)

    # ---- Tender details and the 7-day handover
    as_(PRIYA); pg.evaluate("state.scope='ALL';go('tender')"); pg.wait_for_timeout(300)
    pg.evaluate("openTender('PE-001')"); pg.wait_for_timeout(300)
    pg.fill('#tenEdit [name=contract_signed_on]', '2026-09-10'); pg.fill('#tenEdit [name=award_on]', '2026-09-01'); pg.click('#tenEdit [type=submit]'); pg.wait_for_timeout(400)
    ck('Handover', 'recording the award makes the project Active', J("projById('PE-001').status") == 'Active')
    ck('Handover', 'stage 4 falls due 7 days after the contract signing', J("lcGet('PE-001',4).due_date") == '2026-09-17')
    J("tenderActLocal('update','PE-001',{contract_signed_on:'2026-09-12'})")
    ck('Handover', 'a corrected signing date moves it', J("lcGet('PE-001',4).due_date") == '2026-09-19')
    J("lcAct('PE-001',4,'update',{fields:{due_date:'2026-09-30'}})"); J("tenderActLocal('update','PE-001',{contract_signed_on:'2026-09-13'})")
    ck('Handover', 'a due date set by hand is left alone', J("lcGet('PE-001',4).due_date") == '2026-09-30')
    ck('Handover', 'the coordinator cannot change a recorded TE number', J("(()=>{try{tenderActLocal('update','PE-001',{te_number:'TE9'});return false}catch(e){return /Only a super admin/.test(e.message)}})()"))
    ck('Handover', 'a refused change leaves the record untouched', J("(()=>{try{tenderActLocal('update','PE-001',{client:'Changed',name:''})}catch(e){}return projById('PE-001').client})()") == 'SEC')

    # ---- cancel, release, reallocate, reinstate
    as_(SA); pg.evaluate("openTender('PE-001')"); pg.wait_for_timeout(300)
    pg.fill('#tenCxNote', 'Client cancelled after L1'); pg.click('[data-tencancel]'); pg.wait_for_timeout(500)
    ck('Cancel', 'the Head cancels PE-001; nothing is deleted', J("projById('PE-001').status") == 'Cancelled' and J("Object.keys(DB.lifecycle['PE-001']).length") >= 4)
    ck('Cancel', 'its PE number is released', J("DB.regAudit.some(a=>a.project_id==='PE-001'&&a.action==='PE released'&&a.pe_number==='PE-001')"))
    ck('Cancel', 'its stages are read-only', J("lcAct('PE-001',4,'update',{fields:{next_action:'x'}})") is False and 'read-only' in J("(openStage('PE-001',4),$('#sheet').innerText)"))
    pg.evaluate("closeDrawer()")
    ck('Cancel', 'its stages leave the actions list', not J("actionItems().some(x=>x.pid==='PE-001')"))
    ck('Reallocate', 'PE-001 is now proposed first', J("peProposeLocal().proposed") == 'PE-001' and J("peProposeLocal().released[0].te") == 'TE2231')
    as_(PRIYA)
    r = J("tenderActLocal('register',null,{te_number:'TE2250',name:'Dammam pumping station',region:PROJECTS[0].region})")
    ck('Reallocate', 'the next L1 project gets PE-001 again, as a new record', r['pe_number'] == 'PE-001' and r['id'] == 'PE-001-R2', r)
    ck('Reallocate', 'the history shows both TE numbers against PE-001', J("[...new Set(DB.regAudit.filter(a=>a.pe_number==='PE-001').map(a=>a.te_number))].sort().join()") == 'TE2231,TE2250')
    pg.evaluate("go('tender')"); pg.wait_for_timeout(300)
    ck('Reallocate', 'the register shows PE-001 twice: one cancelled, one pre-award', pg.locator('#view tbody tr[data-tenopen]', has_text='PE-001').count() == 2)
    as_(SA)
    ck('Reinstate', 'reinstating with the old number is refused while another project holds it', J("(()=>{try{tenderActLocal('reinstate','PE-001',{},'Client revived it');return false}catch(e){return /now belongs/.test(e.message)}})()"))
    ck('Reinstate', 'with a new PE number it comes back with its earlier status', J("tenderActLocal('reinstate','PE-001',{pe_number:'PE-060'},'Client revived it').status") == 'Active' and J("pcode(projById('PE-001'))") == 'PE-060')
    ck('Change PE', 'a change needs a reason', J("(()=>{try{tenderActLocal('change_pe','PE-050',{pe_number:'PE-070'},'');return false}catch(e){return /comment/.test(e.message)}})()"))
    ck('Change PE', 'the super admin changes PE-050 to PE-070, and PE-050 is released', J("tenderActLocal('change_pe','PE-050',{pe_number:'PE-070'},'Allocated in error').pe") == 'PE-070' and J("peProposeLocal().proposed") == 'PE-050')
    as_(PRIYA)
    ck('Change PE', 'only a super admin changes a PE number', J("(()=>{try{tenderActLocal('change_pe','PE-002',{pe_number:'PE-071'},'x');return false}catch(e){return /Only a super admin/.test(e.message)}})()"))

    # ---- older browsers: v2.7 checklists are updated once, keeping ticks
    as_(SA)
    J(f"""(()=>{{const s=lcBlank('{PID}',3);s.status='In progress';s.deliverables=[{{k:'loa',label:'Letter of award received',req:true,done:true,by:'X',at:'2026-01-01 10:00'}},{{k:'terms',label:'Contract value and payment terms recorded',req:true,done:true}},{{k:'bonds',label:'Bonds',req:false,done:false}}];DB.lifecycle['{PID}'][3]=s;DB.lcV=27;lcUpgrade28()}})()""")
    d = J(f"lcGet('{PID}',3).deliverables")
    ck('Upgrade', 'an in-progress stage 3 from v2.7 takes the SAP steps and keeps its tick', [x['k'] for x in d if x['req']] == ['loa', 'wbs', 'fwbs', 'sapact', 'contract'] and d[0]['done'] and d[0]['label'].startswith('Notice of award'), d)
    ck('Upgrade', 'old items stay, optional and marked', any(x['k'] == 'terms' and x.get('legacy') and not x['req'] and x['done'] for x in d))
    ck('Upgrade', 'the change is in the stage history, once', J(f"DB.lcAudit.filter(a=>a.project_id==='{PID}'&&a.stage_no===3&&a.action==='Checklist updated').length") == 1 and (J("lcUpgrade28(),1") == 1) and J(f"DB.lcAudit.filter(a=>a.project_id==='{PID}'&&a.stage_no===3&&a.action==='Checklist updated').length") == 1)

    # ---- admin form keeps a cancelled project cancelled; every screen renders
    J("tenderActLocal('cancel','PE-002',{},'Client cancelled')")
    pg.evaluate("go('admin');state.adminTab='projects';render();admDrawer('projects','PE-002')"); pg.wait_for_timeout(300)
    ck('Admin', 'a cancelled project shows its status as Cancelled, not editable', pg.locator('#admForm input[value="Cancelled"][disabled]').count() == 1 and 'Tender register' in pg.inner_text('#sheet'))
    pg.fill('#admForm [name=short]', 'Second (edited)')
    J("$('#admForm [name=city]').innerHTML='<option value=\"'+DB.master.cities[0].id+'\">c</option>';$('#admForm [name=finish]').value='2027-12-31';$('#admForm [name=start]').value='2026-01-01'")
    pg.click('#admForm [type=submit]'); pg.wait_for_timeout(300)
    ck('Admin', 'saving it from Settings keeps it cancelled', J("projById('PE-002').status") == 'Cancelled' and J("projById('PE-002').short") == 'Second (edited)', J("projById('PE-002').status"))
    pg.evaluate("closeDrawer();state.scope='ALL'")
    bad = []
    for view in ['exec', 'proj', 'tender', 'act', 'dash', 'dpr', 'pdash', 'upd', 'base', 'imp', 'cdash', 'eva', 'rep', 'deck', 'perf', 'admin']:
        e0 = len(errs); pg.evaluate(f"go('{view}')"); pg.wait_for_timeout(250)
        if len(errs) > e0: bad.append(view)
    for pid in ['PE-001', 'PE-001-R2', 'PE-002']:
        e0 = len(errs); pg.evaluate(f"state.scope='{pid}';go('proj')"); pg.wait_for_timeout(250)
        for view in ['exec', 'dash', 'pdash', 'cdash', 'eva', 'rep']:
            pg.evaluate(f"go('{view}')"); pg.wait_for_timeout(150)
        if len(errs) > e0: bad.append(pid)
    ck('General', 'every screen renders with pre-award, reallocated and cancelled projects present', not bad, (bad, errs[-3:]))
    pg.evaluate("state.scope='ALL'")
    ck('General', 'project count grew only by the projects registered here', J("PROJECTS.length") == n0 + 4, J("PROJECTS.length"))
    pg.reload(); pg.wait_for_timeout(1500)
    ck('General', 'register, designations and history survive a reload', J("projById('PE-001-R2').te") == 'TE2250' and J(f"isHead(userById('{NABIL}'))") and J("DB.regAudit.length") >= 12)
    ck('General', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
