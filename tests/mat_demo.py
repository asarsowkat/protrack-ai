"""ProTrackAI v3.8 in demo (browser) mode: Material Tracking (Materials & Procurement).
A planning engineer loads a baseline XER (synthetic, built here: a Procurement WBS with Material Name and Unified Activity
Name activity codes, plus construction activities), picks the codes, WBS and materials, maps the milestones; the
dashboard shows one row per material with the current stage, nine milestone statuses (Not Started, In Progress,
Completed, Delayed), Delivery Status, KPIs, charts, filters, search, sorting, Excel and PDF; PO number, supplier and
remarks are kept by hand with a history and never overwritten by a new baseline or an updated schedule; rights; phone.
Usage: python3 mat_demo.py /path/to/live.html > results_mat_demo.json"""
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
    pg = b.new_page(viewport={'width': 1440, 'height': 900}, accept_downloads=True); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1500)
    J = lambda js: pg.evaluate(js)
    J("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);state.scope='ALL';render()")
    SA = J("me().id")
    def as_(uid, scope='ALL'): pg.select_option('#role', uid); pg.wait_for_timeout(300); J(f"state.scope='{scope}';render()")

    # ---- the menu and the demo
    ck('Menu', 'Materials & Procurement has Material tracking (no longer "planned")', J("DOMAINS.find(d=>d.k==='materials').items.some(i=>i.v==='mat'&&i.label==='Material tracking')") and J("NAV_VIEWS.includes('mat')"))
    J("go('mat')"); pg.wait_for_timeout(500)
    ck('Demo data', 'the demo tracks the materials of the Jubail substation and the Riyadh-Qassim line', J("mtAllRows().length") == 10 and J("['JBS','QOT'].every(p=>mtSetup(p))"))
    kp = pg.inner_text('#view .rkpis')
    ck('KPIs', 'eight summary figures: total, not delivered, delivery started, delivered, delayed, manufacturing in progress, pending FAT, pending shipment',
       all(x in kp for x in ['Total materials tracked', 'Not Delivered', 'Delivery Started', 'Delivered', 'Delayed materials', 'Manufacturing in progress', 'Pending FAT', 'Pending shipment']), kp)
    K = J("mtKPIs(mtFiltered())")
    ck('KPIs', 'not delivered + delivery started + delivered + no delivery activity = total', K['nd'] + K['ds'] + K['dv'] + J("mtFiltered().filter(r=>r.delivery==='No delivery activity').length") == K['total'], K)
    cfg = J("window.__cfg.map(c=>[c.type,c.data.labels.length,c.data.datasets.length])")
    ck('Charts', 'three charts: delivery status distribution, supplier-wise status, procurement progress by milestone', cfg[-3:] == [['doughnut', 4, 1], ['bar', J("new Set(mtFiltered().map(r=>r.item.supplier||'No supplier yet')).size"), 3], ['bar', 9, 4]], cfg)
    heads = J("[...document.querySelectorAll('.mttbl thead th')].map(t=>t.textContent.trim())")
    need = ['WBS', 'Material', 'Unified Activity Name', 'Current schedule status', 'Baseline start', 'Baseline finish', 'Current start', 'Current finish', '% complete', 'PR Creation', 'PO Creation', 'Base Design', 'GAFM Approval', 'Manufacturing', 'FAT', 'Release for Shipment', 'Delivery at Site', 'Civil Readiness', 'Delivery Status', 'PO Number', 'Supplier Name', 'Remarks']
    ck('Table', 'all 21 columns of the specification plus Delivery Status', all(h in heads for h in need), heads)

    # ---- set-up from a baseline XER, as the planning engineer of a project without it
    PID = J("PROJECTS.find(p=>!mtSetup(p.id)&&teamOf(p.id,'plan').length).id"); PL = J(f"teamOf('{PID}','plan')[0].id")
    as_(PL, PID); J("go('mat')"); pg.wait_for_timeout(300)
    ck('Set-up', 'a project without Material Tracking explains it is set up from the original baseline import or the next weekly upload (v3.8.1), with a file load as a fallback', 'Also set up Material Tracking' in pg.inner_text('#mtSetup') and 'Load a schedule file here instead' in pg.inner_text('#mtSetup') and J("mtAllRows().length") == 0)
    MATS = ['GIS Equipment', 'Power Transformer', 'Cable Drum']
    base = xer('2026-01-01', MATS)
    pg.set_input_files('#mtFile', files=[{'name': 'MT_baseline.xer', 'mimeType': 'text/plain', 'buffer': base.encode()}]); pg.wait_for_timeout(700)
    f = pg.inner_text('#mtSetup')
    ck('Set-up', 'the XER is read: 28 activities, the code types offered, Material Name and Unified Activity Name picked', '28 activities' in f and J("state.mtDraft.mc") == 'Material Name' and J("state.mtDraft.uc") == 'Unified Activity Name', f[:300])
    ck('Set-up', 'the Procurement WBS is picked, Construction is not', J("state.mtDraft.wbs") == ['Procurement'])
    ck('Set-up', 'each Unified Activity Name is matched to a milestone (Shipment → Release for Shipment, Delivery → Delivery at Site, Installation Readiness → Civil Readiness)',
       J("[...document.querySelectorAll('[data-mtdmap]')].map(s=>s.dataset.mtdmap+'='+s.value).sort().join(',')") == 'Base Design=BD,Delivery=DEL,FAT=FAT,GAFM Approval=GAFM,Installation Readiness=CIV,Manufacturing=MFG,PO Creation=PO,PR Creation=PR,Shipment=RFS')
    ck('Set-up', 'the three materials are listed to choose from', J("[...document.querySelectorAll('[name=mtdsel]')].map(c=>c.value).sort()") == sorted(MATS))
    pg.uncheck('[name=mtdsel][value="Cable Drum"]'); pg.wait_for_timeout(100)
    pg.click('#mtDraftForm [type=submit]'); pg.wait_for_timeout(600)
    ck('Set-up', 'loading keeps 27 material activities and three materials, two monitored', len(J(f"mtActs('{PID}')")) == 27 and J(f"Object.values(mtItems('{PID}')).filter(x=>x.selected).length") == 2 and J(f"mtItems('{PID}')['Cable Drum'].selected") is False)
    ck('Table', 'one row per monitored material', J("mtFiltered().map(r=>r.material).sort()") == ['GIS Equipment', 'Power Transformer'])
    ck('Table', 'before any update: every milestone Not Started or, once its baseline finish has passed, Delayed', J(f"mtMaterials('{PID}').every(r=>Object.values(r.cells).every(c=>['Not Started','Delayed'].includes(c.status)))"))
    pg.check('[data-mtflt="all"]'); pg.wait_for_timeout(300)
    ck('Table', 'Show materials not monitored brings back Cable Drum', J("mtFiltered().length") == 3); pg.uncheck('[data-mtflt="all"]'); pg.wait_for_timeout(200)

    # ---- an updated schedule: statuses refresh
    S = {'MT0-0': dict(status='TK_Complete', pct=100, **{'as': '2026-01-02 08:00', 'af': '2026-01-20 17:00'}), 'MT0-1': dict(status='TK_Complete', pct=100, **{'as': '2026-02-01 08:00', 'af': '2026-02-24 17:00'}),
         'MT0-2': dict(status='TK_Complete', pct=100, **{'as': '2026-03-01 08:00', 'af': '2026-03-20 17:00'}), 'MT0-3': dict(status='TK_Complete', pct=100, **{'as': '2026-04-01 08:00', 'af': '2026-04-25 17:00'}),
         'MT0-4': dict(status='TK_Complete', pct=100, **{'as': '2026-05-01 08:00', 'af': '2026-05-25 17:00'}), 'MT0-5': dict(status='TK_Complete', pct=100, **{'as': '2026-06-01 08:00', 'af': '2026-06-20 17:00'}),
         'MT0-6': dict(status='TK_Complete', pct=100, **{'as': '2026-07-01 08:00', 'af': '2026-07-22 17:00'}), 'MT0-7': dict(status='TK_Active', pct=50, ef='2026-09-10', **{'as': '2026-08-01 08:00'}),
         'MT1-0': dict(status='TK_Complete', pct=100, **{'as': '2026-01-02 08:00', 'af': '2026-01-20 17:00'}), 'MT1-1': dict(status='TK_Complete', pct=100, **{'as': '2026-02-01 08:00', 'af': '2026-02-24 17:00'}),
         'MT1-2': dict(status='TK_Complete', pct=100, **{'as': '2026-03-01 08:00', 'af': '2026-03-20 17:00'}), 'MT1-3': dict(status='TK_Complete', pct=100, **{'as': '2026-04-01 08:00', 'af': '2026-04-25 17:00'}),
         'MT1-4': dict(status='TK_Active', pct=60, es='2026-05-01', ef='2026-09-30', **{'as': '2026-05-01 08:00'})}
    upd = xer('2026-08-15', MATS, S)
    J(f"""(()=>{{const P=parseSchedXER({json.dumps(upd)});const rows=schedRowsFor({{pid:'{PID}',parsed:P,map:{{wbs_map:{{}},code_map:{{}}}},ctype:'',wres:'__dur'}});
        return schedCommitLocal({{project_id:'{PID}',data_date:'2026-08-15',weightage:'internal',file_name:'MT_update.xer',file_hash:'mtu1',weight_basis:'Duration',rows}})}})()""")
    J("render()"); pg.wait_for_timeout(400)
    G = J(f"(()=>{{const r=mtMaterials('{PID}').find(r=>r.material==='GIS Equipment');return {{st:r.status,cur:r.cur.uact,del:r.delivery,fat:r.cells.FAT.status,rfs:r.cells.RFS.status,dl:r.cells.DEL.status,civ:r.cells.CIV.status,proc:r.proc,pct:r.cur.pct}}}})()")
    ck('Schedule update', 'the updated schedule keeps the material codes of each activity', J(f"schedRowsOf(schedAt('{PID}','9999-12-31')).filter(r=>r.mat).length") == 27)
    ck('Schedule update', 'GIS Equipment: FAT and shipment Completed, delivery running → Delivery Started, current stage Delivery', G['fat'] == 'Completed' and G['rfs'] == 'Completed' and G['del'] == 'Delivery Started' and G['cur'] == 'Delivery' and G['pct'] == 50, G)
    ck('Delayed', 'a running delivery whose forecast finish (10 Sept) is after its baseline finish (25 Aug) is Delayed', G['dl'] == 'Delayed', G)
    ck('Delayed', 'a stage not started whose baseline finish (25 Sept) is still ahead of the data date and has no late forecast is Not Started', G['civ'] == 'Not Started', G)
    T = J(f"(()=>{{const r=mtMaterials('{PID}').find(r=>r.material==='Power Transformer');return {{mfg:r.cells.MFG.status,fat:r.cells.FAT.status,del:r.delivery,proc:r.proc}}}})()")
    ck('Delayed', 'Power Transformer manufacturing, running with a forecast after its baseline finish, is Delayed; FAT (baseline finish passed, not started) is Delayed too', T['mfg'] == 'Delayed' and T['fat'] == 'Delayed', T)
    ck('Delivery Status', 'no delivery started → Not Delivered; the procurement status is the current stage (Manufacturing)', T['del'] == 'Not Delivered' and T['proc'] == 'Manufacturing', T)

    # ---- manual fields and history
    pg.fill(f'[data-mtf="{PID}|GIS Equipment|po_number"]', '4500099001'); pg.press(f'[data-mtf="{PID}|GIS Equipment|po_number"]', 'Tab'); pg.wait_for_timeout(300)
    pg.fill(f'[data-mtf="{PID}|GIS Equipment|supplier"]', 'Siemens Energy'); pg.press(f'[data-mtf="{PID}|GIS Equipment|supplier"]', 'Tab'); pg.wait_for_timeout(300)
    pg.fill(f'[data-mtf="{PID}|GIS Equipment|remarks"]', 'FAT witnessed by client\nSea freight'); pg.press(f'[data-mtf="{PID}|GIS Equipment|remarks"]', 'Tab'); pg.wait_for_timeout(300)
    it = J(f"mtItems('{PID}')['GIS Equipment']")
    ck('Manual fields', 'PO number, supplier and multi-line remarks are saved', it['po_number'] == '4500099001' and it['supplier'] == 'Siemens Energy' and it['remarks'] == 'FAT witnessed by client\nSea freight', it)
    A = J(f"DB.matAudit.filter(a=>a.project_id==='{PID}'&&a.material==='GIS Equipment').map(a=>[a.field,a.after,a.by_name])")
    ck('Manual fields', 'each change is in the history: field, new value, user and date', [x[0] for x in A] == ['PO Number', 'Supplier Name', 'Remarks'] and all(x[2] for x in A), A)
    J(f"mtHistory('{PID}','GIS Equipment')"); pg.wait_for_timeout(200)
    ck('Manual fields', 'History shows the material\'s activities and every change', 'PO Number' in pg.inner_text('#sheet') and 'Supplier Name' in pg.inner_text('#sheet') and 'Delivery at Site' in pg.inner_text('#sheet'))
    ck('Manual fields', 'History opens full screen, with the nine milestones, the activities and the changes (v3.8.2)', J("document.querySelector('#sheet').classList.contains('full')") and J("document.querySelector('#sheet').getBoundingClientRect().width") >= 1439 and J("document.querySelectorAll('#sheet .mthm').length") == 9)
    J("closeDrawer()")
    ck('Manual fields', 'closing it returns the panel to its normal size', not J("document.querySelector('#sheet').classList.contains('full')"))
    ck('Manual fields', 'the supplier box suggests known suppliers and subcontractors', J("document.querySelectorAll('#mtSup option').length") >= 1)
    base2 = xer('2026-02-01', MATS + ['Shunt Reactor'])
    pg.set_input_files('#mtFile', files=[{'name': 'MT_baseline_rev1.xer', 'mimeType': 'text/plain', 'buffer': base2.encode()}]); pg.wait_for_timeout(600)
    pg.click('#mtDraftForm [type=submit]'); pg.wait_for_timeout(600)
    it = J(f"mtItems('{PID}')['GIS Equipment']")
    ck('Never overwritten', 'a revised baseline keeps PO number, supplier, remarks and the choice of monitored materials, and adds the new material', it['po_number'] == '4500099001' and it['supplier'] == 'Siemens Energy' and J(f"!!mtItems('{PID}')['Shunt Reactor']") and J(f"mtItems('{PID}')['Cable Drum'].selected") is False)
    J(f"""(()=>{{const P=parseSchedXER({json.dumps(xer('2026-09-01', MATS, S))});const rows=schedRowsFor({{pid:'{PID}',parsed:P,map:{{wbs_map:{{}},code_map:{{}}}},ctype:'',wres:'__dur'}});
        return schedCommitLocal({{project_id:'{PID}',data_date:'2026-09-01',weightage:'internal',file_name:'MT_update2.xer',file_hash:'mtu2',weight_basis:'Duration',rows}})}})()""")
    ck('Never overwritten', 'another updated schedule changes statuses only', J(f"mtItems('{PID}')['GIS Equipment'].remarks") == 'FAT witnessed by client\nSea freight')
    J("render()"); pg.wait_for_timeout(300)

    # ---- mapping and monitored materials later
    pg.select_option('#mtSetForm [data-mtmap="Installation Readiness"]', ''); pg.uncheck('#mtSetForm [name=mtsel][value="Shunt Reactor"]'); pg.click('#mtSetForm [type=submit]'); pg.wait_for_timeout(500)
    ck('Set-up', 'the mapping and the monitored materials can be changed without loading again', J(f"mtSetup('{PID}').stage_map['Installation Readiness']") == '' and J(f"mtItems('{PID}')['Shunt Reactor'].selected") is False
       and J(f"mtMaterials('{PID}').find(r=>r.material==='GIS Equipment').cells.CIV") is None)

    # ---- filters, search, sorting, export
    as_(SA); J("mtState().pid='';mtState().q='';go('mat')"); pg.wait_for_timeout(400)
    n_all = J("mtFiltered().length")
    pg.select_option('[data-mtflt="del"]', 'Delivered'); pg.wait_for_timeout(300)
    ck('Filters', 'Delivery status filter', J("mtFiltered().every(r=>r.delivery==='Delivered')") and 0 < J("mtFiltered().length") < n_all)
    pg.select_option('[data-mtflt="del"]', ''); pg.select_option('[data-mtflt="sup"]', 'Siemens Energy'); pg.wait_for_timeout(300)
    ck('Filters', 'Supplier filter', J("mtFiltered().length") >= 2 and J("mtFiltered().every(r=>r.item.supplier==='Siemens Energy')"))
    pg.select_option('[data-mtflt="sup"]', ''); pg.select_option('[data-mtflt="proc"]', 'Manufacturing'); pg.wait_for_timeout(300)
    ck('Filters', 'Procurement status filter (current stage)', J("mtFiltered().length") > 0 and J("mtFiltered().every(r=>r.proc==='Manufacturing')"))
    pg.select_option('[data-mtflt="proc"]', ''); pg.wait_for_timeout(200)
    for k, v, cond in [('wbs', 'GIS Equipment package', "r.wbs==='GIS Equipment package'"), ('mat', 'Cable Drum', "r.material==='Cable Drum'")]:
        pg.select_option(f'[data-mtflt="{k}"]', v); pg.wait_for_timeout(250)
        ck('Filters', f'{k.upper() if k == "wbs" else "Material"} filter', J("mtFiltered().length") > 0 and J(f"mtFiltered().every(r=>{cond})")); pg.select_option(f'[data-mtflt="{k}"]', ''); pg.wait_for_timeout(200)
    if J("document.querySelector('[data-mtflt=\"pid\"]')!==null"):
        pg.select_option('[data-mtflt="pid"]', 'JBS'); pg.wait_for_timeout(250); ck('Filters', 'Project filter', J("mtFiltered().every(r=>r.pid==='JBS')") and J("mtFiltered().length") == 6); pg.select_option('[data-mtflt="pid"]', ''); pg.wait_for_timeout(200)
    for q, cond in [('4500099001', "r.item.po_number==='4500099001'"), ('hitachi', "/hitachi/i.test(r.item.supplier||'')"), ('reactor', "/reactor/i.test(r.material)")]:
        pg.fill('[data-mtflt="q"]', q); pg.wait_for_timeout(600)
        ck('Search', f'search by {"PO number" if q[0] == "4" else "supplier" if q == "hitachi" else "material"} ("{q}")', J("mtFiltered().length") > 0 and J(f"mtFiltered().every(r=>{cond})"), J("mtFiltered().map(r=>r.material)"))
    pg.fill('[data-mtflt="q"]', ''); pg.wait_for_timeout(600)
    pg.select_option('[data-mtflt="sort"]', 'sup'); pg.wait_for_timeout(250)
    sups = J("mtFiltered().map(r=>r.item.supplier||'')"); named = [x for x in sups if x]; ck('Sorting', 'by supplier (materials without a supplier last)', named == sorted(named, key=str.lower) and sups == named + [''] * (len(sups) - len(named)), sups)
    pg.select_option('[data-mtflt="sort"]', 'st'); pg.wait_for_timeout(250)
    sts = J("mtFiltered().map(r=>['Delayed','In Progress','Not Started','Completed'].indexOf(r.status))"); ck('Sorting', 'by status (delayed first)', sts == sorted(sts), sts)
    pg.select_option('[data-mtflt="sort"]', 'del'); pg.wait_for_timeout(250)
    ds = J("mtFiltered().map(r=>r.delDate||'9999')"); ck('Sorting', 'by delivery date', ds == sorted(ds), ds)
    with pg.expect_download() as dl: pg.click('[data-mtexp="xlsx"]')
    ck('Export', 'Excel: material tracking, summary and history sheets', dl.value.suggested_filename.startswith('Material_tracking_') and dl.value.suggested_filename.endswith('.xlsx')
       and J("window.__xl.map(x=>x[0])") == ['Material tracking', 'Summary', 'History'] and J("window.__xl[0][1][2].length") == 23 and len(J("window.__xl[0][1]")) == 3 + J("mtFiltered().length"))
    with pg.expect_download() as dl: pg.click('[data-mtexp="pdf"]')
    ck('Export', 'PDF: one table row per material', dl.value.suggested_filename.endswith('.pdf') and len(J("window.__pdf.body")) == J("mtFiltered().length"))

    # ---- rights
    CO = J(f"(teamOf('{PID}','costing')[0]||{{}}).id")
    if CO:
        as_(CO, PID); J("go('mat')"); pg.wait_for_timeout(300)
        ck('Rights', 'a costing engineer sees the tracking but cannot edit (no input boxes; refused if tried)', J("document.querySelectorAll('[data-mtf]').length") == 0 and J("mtFiltered().length") > 0
           and 'Only the people who keep' in J(f"(()=>{{try{{mtItemLocal({{project_id:'{PID}',material:'GIS Equipment',po_number:'1'}});return 'saved'}}catch(e){{return e.message}}}})()"))
    HD = J("(DB.master.users.find(u=>isHead(u)&&u.active!==false)||{}).id")
    if HD:
        as_(HD); J("go('mat')"); pg.wait_for_timeout(300)
        ck('Rights', 'the Head of Planning and Cost Control can edit (position)', J("document.querySelectorAll('[data-mtf]').length") > 0)
    FO = J(f"(DB.master.users.find(u=>u.role==='foreman'&&u.active!==false)||{{}}).id")
    as_(FO); ck('Rights', 'foremen do not have Material tracking in the menu', 'mat' not in J("NAV_VIEWS"))
    as_(SA); J("go('admin');state.adminTab='rights';render()"); pg.wait_for_timeout(300)
    ck('Rights', 'Roles and rights lists the new right and the new screen', J("!!document.querySelector('[data-rr=\"plan|materials.keep\"]')&&document.querySelector('[data-rr=\"plan|materials.keep\"]').checked") and J("!!document.querySelector('[data-sr=\"pm|mat\"]')"))
    J("(()=>{const k=state.uid,r=state.role;rightsLocal({action:'role_right',role_key:'costing',right_key:'materials.keep',allow:true})})()")
    if CO:
        as_(CO, PID); J("go('mat')"); pg.wait_for_timeout(300)
        ck('Rights', 'once the super admin gives costing engineers the right, they can edit', J("document.querySelectorAll('[data-mtf]').length") > 0)
    ck('Page', 'no script errors', not errs, errs)

    # ---- phone
    ph = b.new_page(viewport={'width': 390, 'height': 844}); ph.route('**/*', route); perr = []; ph.on('pageerror', lambda e: perr.append(str(e)))
    ph.goto('file://' + APP); ph.wait_for_timeout(800)
    ph.fill('#lgId', 'asarudeen@company.com'); ph.fill('#lgPw', 'ProTrack@2026'); ph.click('#lgBtn'); ph.wait_for_timeout(1500)
    ph.evaluate("aiHint=()=>{};rasaBubble=()=>{};go('mat')"); ph.wait_for_timeout(500)
    ck('Phone', 'the page fits the phone width (the table scrolls inside its box)', ph.evaluate("document.documentElement.scrollWidth") <= 392, ph.evaluate("document.documentElement.scrollWidth"))
    ck('Phone', 'no script errors', not perr, perr)
    b.close()
print(json.dumps({'suite': 'mat_demo', 'page': APP, 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
