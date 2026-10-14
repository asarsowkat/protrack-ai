"""ProTrackAI v3.8.1 in demo (browser) mode: Material Tracking set up without an extra upload.
1) Importing the original baseline XER (Baselines → Original baseline) also sets up Material Tracking: material
   activities and baseline dates from that file; actual and forecast dates then come from the weekly updated schedule.
2) For a project whose baseline is already loaded, the next weekly updated schedule upload sets it up instead.
Earlier description (mat_demo.py): Material Tracking (Materials & Procurement).
A planning engineer loads a baseline XER (synthetic, built here: a Procurement WBS with Material Name and Unified Activity
Name activity codes, plus construction activities), picks the codes, WBS and materials, maps the milestones; the
dashboard shows one row per material with the current stage, nine milestone statuses (Not Started, In Progress,
Completed, Delayed), Delivery Status, KPIs, charts, filters, search, sorting, Excel and PDF; PO number, supplier and
remarks are kept by hand with a history and never overwritten by a new baseline or an updated schedule; rights; phone.
Usage: python3 mt_auto_demo.py /path/to/live.html > results_mt_auto_demo.json"""
import sys, json
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'live.html'
R = []
CHART = "window.__cfg=[];window.Chart=function(el,cfg){window.__cfg.push(cfg);return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
XLSX = "window.__xl=[];window.XLSX={utils:{aoa_to_sheet:a=>({aoa:a}),book_new:()=>({SheetNames:[],Sheets:{}}),book_append_sheet:(wb,ws,n)=>{wb.SheetNames.push(n);wb.Sheets[n]=ws;window.__xl.push([n,ws.aoa])}},write:()=>new Uint8Array([80,75,3,4])};"
PDF = "window.__pdf=null;window.jspdf={jsPDF:function(){return {setFontSize(){},text(){},autoTable(o){window.__pdf=o},output(){return new Blob(['%PDF'])}}}};"
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:260]})
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        if 'xlsx' in u.lower(): return r.fulfill(body=XLSX, content_type='application/javascript')
        if 'jspdf' in u.lower(): return r.fulfill(body=PDF, content_type='application/javascript')
        return r.abort()
    return r.continue_()

def xer(dd, mats, extra_status=None):
    """A small P6 XER: WBS Procurement (materials) and Construction; code types Material Name, Unified Activity Name."""
    st = extra_status or {}
    U = ['PR Creation', 'PO Creation', 'Base Design', 'GAFM Approval', 'Manufacturing', 'FAT', 'Shipment', 'Delivery', 'Installation Readiness']
    L = ['ERMHDR\t19.12', '%T\tPROJECT', '%F\tproj_id\tproj_short_name\tlast_recalc_date', f'%R\t1\tMT-TEST\t{dd} 00:00',
         '%T\tPROJWBS', '%F\twbs_id\tproj_id\tparent_wbs_id\twbs_name\tproj_node_flag',
         '%R\t10\t1\t\tMT-TEST\tY', '%R\t11\t1\t10\tProcurement\tN', '%R\t12\t1\t10\tConstruction\tN']
    for i, m in enumerate(mats): L.append(f'%R\t{20 + i}\t1\t11\t{m} package\tN')
    L += ['%T\tACTVTYPE', '%F\tactv_code_type_id\tactv_code_type', '%R\t1\tMaterial Name', '%R\t2\tUnified Activity Name', '%R\t3\tArea']
    L += ['%T\tACTVCODE', '%F\tactv_code_id\tactv_code_type_id\tactv_code_name']
    for i, m in enumerate(mats): L.append(f'%R\t{100 + i}\t1\t{m}')
    for j, u in enumerate(U): L.append(f'%R\t{200 + j}\t2\t{u}')
    L.append('%R\t300\t3\tZone A')
    tasks, ta = [], []
    for i, m in enumerate(mats):
        for j, u in enumerate(U):
            tid = 1000 + i * 20 + j; code = f'MT{i}-{j}'
            bs = f'2026-{j + 1:02d}-01'; bf = f'2026-{j + 1:02d}-25'
            s = st.get(code, {})
            tasks.append(f"%R\t{tid}\t{20 + i}\t{code}\t{m} - {u}\t{s.get('status', 'TK_NotStart')}\tCP_Phys\t{s.get('pct', 0)}\t{bs} 08:00\t{bf} 17:00\t{s.get('es', bs)} 08:00\t{s.get('ef', bf)} 17:00\t{s.get('as', '')}\t{s.get('af', '')}\t200\t0\tTT_Task")
            ta += [f'%R\t{tid}\t1\t{100 + i}', f'%R\t{tid}\t2\t{200 + j}']
    tasks.append("%R\t9000\t12\tC-100\tFoundations\tTK_Active\tCP_Phys\t40\t2026-03-01 08:00\t2026-12-31 17:00\t2026-03-01 08:00\t2026-12-31 17:00\t2026-03-01 08:00\t\t800\t480\tTT_Task")
    ta.append('%R\t9000\t3\t300')
    L += ['%T\tTASK', '%F\ttask_id\twbs_id\ttask_code\ttask_name\tstatus_code\tcomplete_pct_type\tphys_complete_pct\ttarget_start_date\ttarget_end_date\tearly_start_date\tearly_end_date\tact_start_date\tact_end_date\ttarget_drtn_hr_cnt\tremain_drtn_hr_cnt\ttask_type'] + tasks
    L += ['%T\tTASKACTV', '%F\ttask_id\tactv_code_type_id\tactv_code_id'] + ta + ['%E']
    return '\n'.join(L)

with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1500)
    J = lambda js: pg.evaluate(js)
    J("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);state.scope='ALL';render()")
    def as_(uid, scope='ALL'): pg.select_option('#role', uid); pg.wait_for_timeout(300); J(f"state.scope='{scope}';render()")
    MATS = ['GIS Equipment', 'Power Transformer', 'Cable Drum']
    P1, P2 = J("PROJECTS.filter(p=>!mtSetup(p.id)&&teamOf(p.id,'plan').length).slice(0,2).map(p=>p.id)")
    PL1 = J(f"teamOf('{P1}','plan')[0].id"); PL2 = J(f"teamOf('{P2}','plan')[0].id")

    # ---- 1. the original baseline import sets it up
    as_(PL1, P1); J(f"state.impPid='{P1}';state.bset='ORG';go('base')"); pg.wait_for_timeout(500)
    pg.set_input_files('#p6file', files=[{'name': 'P1_original_baseline.xer', 'mimeType': 'text/plain', 'buffer': xer('2026-01-01', MATS).encode()}]); pg.wait_for_timeout(900)
    box = pg.inner_text('#impBox')
    ck('Original baseline', 'the import preview offers to set up Material Tracking from the same file, ticked', 'Also set up Material Tracking from this baseline' in box and J("document.querySelector('[data-mta=\"imp|on\"]').checked"), box[-600:])
    ck('Original baseline', 'the activity codes and the Procurement branch are picked; 27 material activities, 3 materials', J("state.imp.mt.mc") == 'Material Name' and J("state.imp.mt.uc") == 'Unified Activity Name' and J("state.imp.mt.wbs") == ['Procurement'] and '27 material activities, 3 materials' in box)
    pg.click('[data-impgo]'); pg.wait_for_timeout(1500)
    ck('Original baseline', 'one import: the baseline activities and Material Tracking (27 activities, 3 materials, all monitored)', len(J(f"mtActs('{P1}')")) == 27 and J(f"Object.values(mtItems('{P1}')).filter(x=>x.selected).length") == 3, J("document.querySelector('#toast')&&document.querySelector('#toast').textContent"))
    ck('Original baseline', 'the baseline dates come from the baseline file', J(f"mtActs('{P1}').find(a=>a.act_id==='MT0-4').bf") == '2026-05-25')
    ck('Original baseline', 'the milestones are matched from the Unified Activity Names', J(f"mtSetup('{P1}').stage_map.Shipment") == 'RFS' and J(f"mtSetup('{P1}').stage_map['Installation Readiness']") == 'CIV')
    J("go('mat')"); pg.wait_for_timeout(400)
    ck('Original baseline', 'Material tracking shows the materials straight away, with no upload on its page', J("mtFiltered().length") == 3 and 'Material activities from' in pg.inner_text('#mtSetup'))
    # weekly update: actual and forecast
    S = {'MT0-0': dict(status='TK_Complete', pct=100, **{'as': '2026-01-02 08:00', 'af': '2026-01-20 17:00'}), 'MT0-1': dict(status='TK_Active', pct=50, ef='2026-03-15', **{'as': '2026-02-01 08:00'})}
    J(f"state.impPid='{P1}';go('base')"); pg.wait_for_timeout(400)
    pg.set_input_files('#schedfile', files=[{'name': 'P1_update_W33.xer', 'mimeType': 'text/plain', 'buffer': xer('2026-02-15', MATS, S).encode()}]); pg.wait_for_timeout(800)
    ck('Weekly update', 'when Material Tracking exists, the weekly upload does not ask again', J("!document.querySelector('[data-mta^=\"sched|\"]')"))
    J("state.sched.wt='internal';state.sched.wres='__dur'"); J("render()"); pg.wait_for_timeout(300)
    pg.click('[data-schedgo]'); pg.wait_for_timeout(1200)
    G = J(f"(()=>{{const r=mtMaterials('{P1}').find(r=>r.material==='GIS Equipment');return {{pr:r.cells.PR.status,po:r.cells.PO.status,poDate:r.cells.PO.date,cur:r.cur.uact}}}})()")
    ck('Weekly update', 'actual and forecast come from the weekly updated schedule: PR Creation completed, PO Creation running with its forecast', G['pr'] == 'Completed' and G['po'] in ('In Progress', 'Delayed') and G['poDate'] == '2026-03-15' and G['cur'] == 'PO Creation', G)
    ck('Weekly update', 'the baseline dates stay those of the original baseline', J(f"mtActs('{P1}').find(a=>a.act_id==='MT0-1').bf") == '2026-02-25')

    # ---- 2. a project whose baseline is already loaded: the next weekly upload sets it up
    as_(PL2, P2); J(f"state.impPid='{P2}';go('base')"); pg.wait_for_timeout(400)
    S2 = {'MT1-0': dict(status='TK_Complete', pct=100, **{'as': '2026-01-03 08:00', 'af': '2026-01-22 17:00'})}
    pg.set_input_files('#schedfile', files=[{'name': 'P2_update_W33.xer', 'mimeType': 'text/plain', 'buffer': xer('2026-02-15', MATS, S2).encode()}]); pg.wait_for_timeout(800)
    sb = pg.inner_text('#schedPanel') if J("!!document.querySelector('#schedPanel')") else pg.inner_text('#view')
    ck('First weekly update', 'a project without Material Tracking is offered it in the weekly upload, ticked', 'Also set up Material Tracking from this schedule' in sb and J("document.querySelector('[data-mta=\"sched|on\"]').checked"), sb[-500:])
    J("state.sched.wt='internal';state.sched.wres='__dur'"); J("render()"); pg.wait_for_timeout(300)
    pg.click('[data-schedgo]'); pg.wait_for_timeout(1500)
    ck('First weekly update', 'saving the update also sets up Material Tracking (27 activities, 3 materials)', len(J(f"mtActs('{P2}')")) == 27 and J(f"Object.keys(mtItems('{P2}')).length") == 3, J("mtSave.err"))
    ck('First weekly update', 'the update rows carry the material codes, so statuses come from it: Power Transformer PR Creation completed', J(f"mtMaterials('{P2}').find(r=>r.material==='Power Transformer').cells.PR.status") == 'Completed')
    ck('First weekly update', 'baseline dates are the planned dates of that file where the activity is not in the ProTrackAI baseline', J(f"mtActs('{P2}').find(a=>a.act_id==='MT1-0').bf") == '2026-01-25')
    ck('First weekly update', 'the set-up history says where it came from', 'Set up from the weekly updated schedule' in J(f"JSON.stringify(DB.matAudit.filter(a=>a.project_id==='{P2}'))"))
    J("state.mtDraft=null;go('mat')"); pg.wait_for_timeout(300)
    ck('Page', 'the Material tracking page explains it is set up from the schedules already loaded; a file load there is optional', 'Load a schedule file here instead' in pg.inner_text('#mtSetup'))
    pg.select_option('#role', J("(DB.master.users.find(u=>u.role==='sa')||{}).id")); pg.wait_for_timeout(300)
    J("state.mt=null;mtState().pid='';state.scope='ALL';go('mat')"); pg.wait_for_timeout(300)
    Q = J("PROJECTS.find(p=>!mtSetup(p.id)).id")
    if Q:
        J(f"mtState().pid='{Q}';render()"); pg.wait_for_timeout(300)
        ck('Page', 'a project not set up yet says to tick the option at the original baseline import or the next weekly upload', 'Also set up Material Tracking' in pg.inner_text('#mtSetup'))
    ck('Page', 'no script errors', not errs, errs)
    b.close()
print(json.dumps({'suite': 'mt_auto_demo', 'page': APP, 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
