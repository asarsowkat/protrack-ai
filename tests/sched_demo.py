"""ProTrackAI v3.6 in demo (browser) mode: internal weightage by phase, updated schedules, internal and client reporting.
The planning engineer sets the phase weightage, uploads an updated P6 schedule (a small synthetic XER built here), maps
main WBS branches or an activity code to phases; ProTrackAI works out client and internal progress, milestones and
look-ahead; every progress report uses the internal weightage; invoiceable uses the client weightage with the
schedule's % complete; internal and client reports are compared with the schedule and differences are validated.
Usage: python3 sched_demo.py /path/to/index.html > results_sched_demo.json"""
import sys, json, os, tempfile, time
from datetime import date
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
XLSX_STUB = """window.XLSX={read:function(){return{SheetNames:[],Sheets:{}}},utils:{sheet_to_json:function(){return[]},aoa_to_sheet:function(a){return{aoa:a}},json_to_sheet:function(){return{}},book_new:function(){return{SheetNames:[],Sheets:{}}},book_append_sheet:function(wb,ws,n){wb.SheetNames.push(n);wb.Sheets[n]=ws},encode_range:function(){return'A1'},decode_range:function(){return{s:{r:0,c:0},e:{r:0,c:0}}},encode_cell:function(){return'A1'}},write:function(){return new Uint8Array([80,75,3,4])},writeFile:function(){}};"""
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:300]})
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        if 'xlsx' in u.lower(): return r.fulfill(body=XLSX_STUB, content_type='application/javascript')
        return r.abort()
    return r.continue_()

def xer(rows, dd='2026-09-20 17:00', code=True):
    """a small, synthetic P6 export: project, 7 main WBS branches (+ one sub-branch), a unitless weighting resource, activity codes"""
    T = []
    def tab(name, fields, recs):
        T.append('%T\t' + name); T.append('%F\t' + '\t'.join(fields))
        for r in recs: T.append('%R\t' + '\t'.join(str(r.get(f, '')) for f in fields))
    tab('PROJECT', ['proj_id', 'proj_short_name', 'last_recalc_date'], [{'proj_id': 1, 'proj_short_name': 'JDC-UPD', 'last_recalc_date': dd}])
    W = [('1', '', 'Y', 'JDC updated schedule'), ('2', '1', 'N', 'PROJECT PREPARATION'), ('3', '1', 'N', 'ENGINEERING & DESIGN'), ('4', '1', 'N', 'EQUIPMENT & MATERIAL'),
         ('5', '1', 'N', 'CONSTRUCTION'), ('6', '1', 'N', 'INSTALLATION'), ('7', '1', 'N', 'TESTING & COMMISSIONING'), ('8', '1', 'N', 'PROJECT CLOSE OUT'), ('9', '5', 'N', 'Building A')]
    tab('PROJWBS', ['wbs_id', 'proj_id', 'parent_wbs_id', 'proj_node_flag', 'wbs_name'], [dict(wbs_id=a, proj_id=1, parent_wbs_id=b, proj_node_flag=c, wbs_name=d) for a, b, c, d in W])
    tab('UMEASURE', ['unit_id', 'unit_abbrev'], [{'unit_id': 1, 'unit_abbrev': 'h'}])
    tab('RSRC', ['rsrc_id', 'rsrc_name', 'rsrc_short_name', 'rsrc_type', 'unit_id'], [{'rsrc_id': 1, 'rsrc_name': 'Price weight', 'rsrc_short_name': 'PW', 'rsrc_type': 'RT_Mat', 'unit_id': ''},
                                                                                     {'rsrc_id': 2, 'rsrc_name': 'Labour', 'rsrc_short_name': 'LAB', 'rsrc_type': 'RT_Labor', 'unit_id': 1}])
    F = ['task_id', 'wbs_id', 'task_code', 'task_name', 'task_type', 'status_code', 'complete_pct_type', 'phys_complete_pct', 'target_drtn_hr_cnt', 'remain_drtn_hr_cnt', 'act_work_qty', 'remain_work_qty',
         'target_work_qty', 'target_start_date', 'target_end_date', 'early_start_date', 'early_end_date', 'act_start_date', 'act_end_date']
    tab('TASK', F, [dict(task_id=i + 1, **r['t']) for i, r in enumerate(rows)])
    tab('TASKRSRC', ['task_id', 'rsrc_id', 'target_qty'], [{'task_id': i + 1, 'rsrc_id': 1 if r['w'] else 2, 'target_qty': r['w'] or 10} for i, r in enumerate(rows)])
    if code:
        tab('ACTVTYPE', ['actv_code_type_id', 'actv_code_type'], [{'actv_code_type_id': 1, 'actv_code_type': 'Phase'}])
        vals = sorted(set(r['code'] for r in rows))
        tab('ACTVCODE', ['actv_code_id', 'actv_code_type_id', 'short_name', 'actv_code_name'], [{'actv_code_id': j + 1, 'actv_code_type_id': 1, 'short_name': v[:3], 'actv_code_name': v} for j, v in enumerate(vals)])
        tab('TASKACTV', ['task_id', 'actv_code_type_id', 'actv_code_id'], [{'task_id': i + 1, 'actv_code_type_id': 1, 'actv_code_id': vals.index(r['code']) + 1} for i, r in enumerate(rows)])
    return '\n'.join(T) + '\n%E\n'
def task(code, name, wbs, w, bs, bf, pct=0, typ='CP_Phys', st='TK_Active', ttype='TT_Task', ef=None, af=None, extra=None, ph='Construction'):
    t = dict(wbs_id=wbs, task_code=code, task_name=name, task_type=ttype, status_code=st, complete_pct_type=typ, phys_complete_pct=pct, target_start_date=bs + ' 08:00', target_end_date=bf + ' 17:00',
             early_end_date=(ef or bf) + ' 17:00', act_end_date=(af + ' 17:00') if af else '')
    t.update(extra or {})
    return {'t': t, 'w': w, 'code': ph}
def frac(bs, bf, dd=date(2026, 9, 20)):
    bs, bf = date.fromisoformat(bs), date.fromisoformat(bf)
    return 1 if dd >= bf else 0 if dd <= bs else (dd - bs).days / (bf - bs).days

with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);window.__saved=[];saveFile=async(n,b)=>{window.__saved.push(n)};window.__printed='';window.open=()=>({document:{write:h=>{window.__printed+=h},close(){}}});state.scope='ALL';render()")
    J = lambda js: pg.evaluate(js)
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(400); J("state.scope='ALL';render()")
    def tryact(p): return J(f"(()=>{{try{{relActLocal({json.dumps(p)});return 'ok'}}catch(e){{return e.message}}}})()")
    SA = J("me().id"); PID = 'JDC'; PL = J(f"teamOf('{PID}','plan')[0].id"); PSM = 'U48'; CO = J(f"teamOf('{PID}','costing')[0].id"); PM = J(f"teamOf('{PID}','pm')[0].id")
    MON = J("curMonth()"); WK = J("curWeek()")

    # ---- names and menus
    nav = J("[...document.querySelectorAll('#nav .nav-item')].map(x=>x.textContent.trim())")
    ck('Menus', 'Planning & Scheduling has Internal Reporting and Client Reporting (Progress releases renamed)', 'Internal Reporting' in nav and 'Client Reporting' in nav and 'Progress releases' not in nav, nav)
    ck('Demo data', 'two sample projects have phase weightage and an updated schedule', J("Object.keys(DB.phaseSetup).sort().join()") == 'JBS,QOT' and J("DB.schedUpdates.length") == 2)
    s0 = J("DB.schedUpdates.find(u=>u.project_id==='QOT')")
    re = J("(()=>{const u=DB.schedUpdates.find(u=>u.project_id==='QOT');return schedSummary(DB.schedRows[u.id],u.data_date,u.weightage,u.weights)})()")
    ck('Demo data', 'the stored summary is what the formulas give from the activities', all(abs((s0['summary'][k] or 0) - (re[k] or 0)) < 1e-9 for k in ['client_plan', 'client_act', 'int_plan', 'int_act']), (s0['summary']['int_act'], re['int_act']))

    # ---- internal weightage by phase
    as_(PL); J(f"state.impPid='{PID}';state.scope='ALL';go('base')"); pg.wait_for_timeout(500)
    ck('Weightage', 'the Baselines page has Internal weightage by phase with the seven phases', pg.locator('#phasePanel [data-pwin]').count() == 7 and all(x in pg.inner_text('#phasePanel') for x in ['General works', 'Design', 'Material', 'Construction', 'Installation', 'Testing & commissioning', 'Project close out']))
    W = {'GEN': 5, 'DES': 10, 'MAT': 30, 'CON': 30, 'INS': 15, 'TC': 7, 'CLO': 3}
    for k, v in W.items(): pg.fill(f'[name="pw_{k}"]', str(v if k != 'CLO' else 4))
    pg.wait_for_timeout(200)
    ck('Weightage', 'the total updates as you type', pg.inner_text('#pwTot') == '101.00%', pg.inner_text('#pwTot'))
    pg.click(f'[data-pwsave="{PID}"]'); pg.wait_for_timeout(400)
    ck('Weightage', 'a total other than 100% is refused', 'add up to 100%' in pg.inner_text('#pwErr') and J(f"hasPhaseW('{PID}')") is False, pg.inner_text('#pwErr'))
    pg.fill('[name="pw_CLO"]', '3'); pg.click(f'[data-pwsave="{PID}"]'); pg.wait_for_timeout(500)
    ck('Weightage', 'the planning engineer saves the weightage; the history keeps it', J(f"phaseSetupOf('{PID}').weights.CON") == 30 and J(f"DB.phaseAudit.filter(a=>a.project_id==='{PID}').length") == 1)
    as_(CO); J(f"state.impPid='{PID}';go('base')"); pg.wait_for_timeout(400)
    ck('Weightage', 'a costing engineer has no weightage or schedule upload panel', pg.locator('#phasePanel').count() == 0 and pg.locator('#schedfile').count() == 0)
    ck('Weightage', '...and cannot save it (checked again when saving)', 'Only a planning engineer' in J(f"(()=>{{try{{phaseSetupLocal({{project_id:'{PID}',weights:{json.dumps(W)}}});return 'saved'}}catch(e){{return e.message}}}})()"))

    # ---- an updated schedule
    as_(PL); J(f"state.impPid='{PID}';go('base')"); pg.wait_for_timeout(400)
    X = J(f"ACTS.find(a=>a.p==='{PID}'&&a.bs&&a.bf).id"); XB = J(f"(a=>[a.bs,a.bf])(ACTS.find(a=>a.id==='{X}'))")
    rows = [task('U-GEN1', 'Site mobilisation', 2, 5, '2026-01-15', '2026-03-15', 100, st='TK_Complete', af='2026-03-10', ph='General'),
            task('U-DES1', 'Design package', 3, 10, '2026-02-01', '2026-10-31', 80, ph='Design'),
            task('U-MAT1', 'Chillers supply', 4, 30, '2026-03-01', '2026-12-31', 0, typ='CP_Drtn', extra={'target_drtn_hr_cnt': 1000, 'remain_drtn_hr_cnt': 600}, ph='Material'),
            task('U-CON1', 'Structure works', 9, 25, '2026-05-01', '2027-01-31', 30, ph='Construction'),
            task(X, 'Existing activity', 5, 3, '2026-01-01', '2026-02-01', 50, ph='Construction'),
            task('U-INS1', 'MEP installation', 6, 20, '2026-08-01', '2027-02-28', 0, typ='CP_Units', extra={'act_work_qty': 200, 'remain_work_qty': 800}, ph='Installation'),
            task('U-TC1', 'Testing', 7, 7, '2027-01-01', '2027-03-15', 0, st='TK_NotStart', ph='Testing'),
            task('U-MS1', 'TCC - Taking over certificate', 8, 0, '2027-03-31', '2027-03-31', 0, ttype='TT_FinMile', ef='2027-04-10', ph='Close out')]
    d = tempfile.mkdtemp(); fx = os.path.join(d, 'JDC_update_Sep.xer'); open(fx, 'w').write(xer(rows))
    pg.set_input_files('#schedfile', fx); pg.wait_for_timeout(800)
    box = pg.inner_text('#schedBox')
    ck('Upload', 'the preview reads the data date, the activities and the weighting resource', J("state.sched.dd") == '2026-09-20' and J("state.sched.parsed.rows.length") == 8 and J("state.sched.wres") == 'PW', (J("state.sched.dd"), J("state.sched.wres")))
    ck('Upload', 'each main WBS branch is suggested a phase (sub-branches roll up to their main branch)', J("JSON.stringify(state.sched.map.wbs_map)") == json.dumps({'PROJECT PREPARATION': 'GEN', 'ENGINEERING & DESIGN': 'DES', 'EQUIPMENT & MATERIAL': 'MAT', 'CONSTRUCTION': 'CON', 'INSTALLATION': 'INS', 'TESTING & COMMISSIONING': 'TC', 'PROJECT CLOSE OUT': 'CLO'}, separators=(',', ':')) and 'Building A' not in box, J("JSON.stringify(state.sched.map.wbs_map)"))
    ck('Upload', '% complete follows the P6 type: physical, duration and units; not started is 0; completed is 100', J("state.sched.parsed.rows.map(r=>r.pct).join()") == '100,80,40,30,50,20,0,0', J("state.sched.parsed.rows.map(r=>r.pct).join()"))
    # expected figures (client weightage = the Price weight resource; the existing activity uses the ProTrackAI baseline dates)
    pl = {'U-GEN1': frac('2026-01-15', '2026-03-15'), 'U-DES1': frac('2026-02-01', '2026-10-31'), 'U-MAT1': frac('2026-03-01', '2026-12-31'), 'U-CON1': frac('2026-05-01', '2027-01-31'), X: frac(*XB), 'U-INS1': frac('2026-08-01', '2027-02-28'), 'U-TC1': 0}
    w = {'U-GEN1': 5, 'U-DES1': 10, 'U-MAT1': 30, 'U-CON1': 25, X: 3, 'U-INS1': 20, 'U-TC1': 7}; ac = {'U-GEN1': 1, 'U-DES1': .8, 'U-MAT1': .4, 'U-CON1': .3, X: .5, 'U-INS1': .2, 'U-TC1': 0}
    ph = {'GEN': ['U-GEN1'], 'DES': ['U-DES1'], 'MAT': ['U-MAT1'], 'CON': ['U-CON1', X], 'INS': ['U-INS1'], 'TC': ['U-TC1']}
    cp = sum(w[k] * pl[k] for k in w) / 100 * 100; ca = sum(w[k] * ac[k] for k in w) / 100 * 100
    pp = {k: sum(w[i] * pl[i] for i in v) / sum(w[i] for i in v) for k, v in ph.items()}; pa = {k: sum(w[i] * ac[i] for i in v) / sum(w[i] for i in v) for k, v in ph.items()}
    iw = sum(W[k] for k in ph); ip = sum(W[k] * pp[k] for k in ph) / iw * 100; ia = sum(W[k] * pa[k] for k in ph) / iw * 100
    sm = J("schedSummary(schedRowsFor(state.sched),state.sched.dd,state.sched.wt,phaseSetupOf(state.sched.pid).weights)")
    ck('Upload', 'client planned and actual % = Σ(weight × %) ÷ Σ weight', abs(sm['client_plan'] - round(cp, 2)) < 0.011 and abs(sm['client_act'] - round(ca, 2)) < 0.011, (sm['client_plan'], cp, sm['client_act'], ca))
    ck('Upload', 'internal % = Σ(phase weightage × phase %) over the phases in the schedule; close out (no activities) is listed', abs(sm['int_plan'] - round(ip, 2)) < 0.011 and abs(sm['int_act'] - round(ia, 2)) < 0.011 and sm['missing_phases'] == ['CLO'], (sm['int_plan'], ip, sm['int_act'], ia, sm['missing_phases']))
    ck('Upload', 'the TCC forecast comes from the milestone', sm['tcc_date'] == '2027-04-10' and sm['tcc_actual'] is False)
    ck('Upload', 'the preview shows the client and internal figures and the phase table', f"{sm['client_act']:.1f}%" in box.replace(',', '') or f"{round(sm['client_act'],1)}%" in box, box[-600:])
    # activity code instead of the main WBS
    pg.select_option('[data-schedctype]', 'Phase'); pg.wait_for_timeout(400)
    ck('Upload', 'the phase can come from a P6 activity code instead (values suggested too)', 'Activity code values' in pg.inner_text('#schedBox') and J("state.sched.map.code_map['Testing']") == 'TC' and J("state.sched.map.code_map['Close out']") == 'CLO')
    pg.select_option('[data-schedctype]', ''); pg.wait_for_timeout(300)
    pg.select_option('[data-schedmap="CONSTRUCTION"]', ''); pg.wait_for_timeout(300)
    ck('Upload', 'an unmapped weighted branch blocks saving while internal weightage is set', pg.locator('[data-schedgo]').is_disabled() and 'no phase' in pg.inner_text('#schedBox'))
    pg.select_option('[data-schedmap="CONSTRUCTION"]', 'CON'); pg.wait_for_timeout(300)
    n0 = J("DB.schedUpdates.length"); inv0 = J(f"billPosition(projById('{PID}')).invoiceable"); e0 = J(f"(a=>{{const e=evm([a],ASOF);return e.bac?Math.min(1,e.ev/e.bac):0}})(ACTS.find(a=>a.id==='{X}'))")
    pg.click('[data-schedgo]'); pg.wait_for_timeout(800)
    u = J(f"schedUps('{PID}')[0]")
    ck('Upload', 'saving keeps the update with its summary and the mapping', J("DB.schedUpdates.length") == n0 + 1 and u['data_date'] == '2026-09-20' and u['weightage'] == 'client' and J(f"phaseSetupOf('{PID}').wbs_map.CONSTRUCTION") == 'CON', u and u.get('file_name'))
    ck('Upload', 'the matched activity keeps the ProTrackAI baseline dates', J(f"DB.schedRows[schedUps('{PID}')[0].id].find(r=>r.id==='{X}').bs") == XB[0])
    ck('Upload', 'the update is listed with client and internal figures', 'JDC_update_Sep.xer' in pg.inner_text('#schedPanel'))
    pg.set_input_files('#schedfile', fx); pg.wait_for_timeout(600); pg.click('[data-schedgo]'); pg.wait_for_timeout(600)
    ck('Upload', 'the same file again changes nothing', J("DB.schedUpdates.length") == n0 + 1)
    ck('Weightage', 'once a schedule is reported, changing the weightage needs a reason', 'Give a reason' in J(f"(()=>{{try{{phaseSetupLocal({{project_id:'{PID}',weights:{json.dumps(dict(W, CON=25, GEN=10))}}});return 'saved'}}catch(e){{return e.message}}}})()"))

    # ---- every report uses the internal weightage; invoiceable the client weightage
    P = J(f"progOf('{PID}')")
    ck('Reports', 'project progress is the internal weightage of the latest updated schedule', abs(P['act'] * 100 - sm['int_act']) < 1e-6 and P['basis'] == 'internal')
    J(f"state.scope='{PID}';go('proj')"); pg.wait_for_timeout(500)
    v = pg.inner_text('#view')
    ck('Reports', 'the project overview shows it, with its source', f"{round(sm['int_act'])}%" in v and 'internal weightage, schedule of 20 Sept 2026' in v, v[:400])
    snap = J(f"relPlanSnapshot('{PID}')")
    ck('Reports', 'the internal report starts from it', abs(snap['actual_pct'] - sm['int_act']) < 0.006 and abs(snap['planned_pct'] - sm['int_plan']) < 0.006, (snap['actual_pct'], sm['int_act']))
    rr = J(f"REPORTS.projprog.build().rows.find(r=>r.code==='{PID}')") if J("typeof REPORTS!=='undefined'") else None
    ck('Reports', 'the progress-by-project report uses it', rr is not None and abs(rr['ap'] * 100 - sm['int_act']) < 1e-6, rr)
    J("state.scope='ALL';go('dash')"); pg.wait_for_timeout(500)
    ck('Reports', 'the dashboard notes where progress comes from', 'internal weightage' in pg.inner_text('#view'))
    inv1 = J(f"billPosition(projById('{PID}')).invoiceable"); pr = J(f"priceOf(ACTS.find(a=>a.id==='{X}'))")
    ck('Invoiceable', 'invoiceable uses the schedule % complete with the client price weighting', J(f"schedDone(ACTS.find(a=>a.id==='{X}'),ASOF)") == 0.5 and J(f"billing(projById('{PID}'),ASOF).rows.reduce((t,r)=>t+r.gross,0)") > 0, (inv0, inv1))
    gross = J(f"billing(projById('{PID}'),ASOF).rows.reduce((t,r)=>t+r.gross,0)")
    J(f"window.__keep=DB.schedRows;DB.schedRows={{}}"); g0 = J(f"billing(projById('{PID}'),ASOF).rows.reduce((t,r)=>t+r.gross,0)"); J("DB.schedRows=window.__keep")
    ck('Invoiceable', '...changing earned value by price × (schedule % − daily-report %) for the activities in the schedule', abs((gross - g0) - pr * (0.5 - e0)) < 1, (gross - g0, pr * (0.5 - e0)))

    # ---- internal report compared with the schedule, validated by the section manager
    J(f"state.relTab='planning';state.relPt='month';state.relPer='{MON}';go('rel')"); pg.wait_for_timeout(400)
    ck('Internal report', 'the list is called Internal reporting, with a Client reporting tab', 'Internal reporting' in pg.inner_text('#view') and pg.locator('[data-reltab="client"]').count() == 1)
    J(f"state.rdTab='prog';openRelease('{PID}','planning','month','{MON}')"); pg.wait_for_timeout(400)
    ck('Internal report', 'the report says it follows the updated schedule (internal weightage)', 'Internal weightage · updated schedule of 20 Sept 2026' in pg.inner_text('#sheet'))
    stale = pg.locator('#sheet [data-schedfill]').count()
    if stale: pg.click('#sheet [data-schedfill]'); pg.wait_for_timeout(300)
    ck('Internal report', 'a draft started before the schedule can take its figures from it in one click', not stale or abs(float(pg.input_value('#relForm [name=f_planned_pct]')) - sm['int_plan']) < 0.006, (stale, pg.input_value('#relForm [name=f_planned_pct]')))
    ck('Internal report', 'external progress (client weightage) is filled in from the schedule', abs(float(pg.input_value('#sheet [name="d_ext_act_pct"]')) - sm['client_act']) < 0.006, pg.input_value('#sheet [name="d_ext_act_pct"]'))
    pg.click('#sheet [data-reldo="save"]'); pg.wait_for_timeout(500)
    ck('Internal report', 'saved as the schedule gives it, there is no difference to validate', J(f"relOpen('{PID}','planning','month','{MON}').figures.sched_diff_n") == 0 and 'match the updated schedule' in pg.inner_text('#sheet'), J(f"relOpen('{PID}','planning','month','{MON}').figures.sched_diff_text"))
    pg.click('#sheet [data-rdtab="prog"]'); pg.fill('#relForm [name=f_actual_pct]', '45'); pg.fill('#relForm [name=r_actual_pct]', 'Site count higher than P6'); pg.click('#sheet [data-reldo="save"]'); pg.wait_for_timeout(500)
    r = J(f"relOpen('{PID}','planning','month','{MON}')")
    ck('Internal report', 'a manual change of progress is recorded as a difference from the schedule', r['figures'].get('sched_diff_n',0) >= 1 and 'actual 45' in r['figures']['sched_diff_text'], r['figures'].get('sched_diff_text'))
    ck('Internal report', 'the report shows the difference in amber', 'Differs from the updated schedule' in pg.inner_text('#sheet'))
    n0 = J("DB.notes?DB.notes.length:0")
    pg.click('#sheet [data-reldo="submit"]'); pg.wait_for_timeout(500)
    ck('Internal report', 'submitting notifies that the section manager must validate the differences', J("DB.notes.some(n=>/differs from the updated schedule.*must validate the differences/.test(n.text))"))
    as_(PSM)
    ai = J(f"actionItems().filter(x=>x.pid==='{PID}'&&x.mine&&/validate the differences/.test(x.what)).length")
    ck('Internal report', 'the regional planning section manager sees it to approve and validate', ai >= 1, ai)
    J(f"state.rdTab='overview';openRelease('{PID}','planning','month','{MON}')"); pg.wait_for_timeout(400)
    ck('Internal report', 'he has the check box and note to validate', pg.locator('#relValChk').count() == 1 and pg.locator('#relValNote').count() == 1)
    pg.click('#sheet [data-reldo="approve"]'); pg.wait_for_timeout(400)
    ck('Internal report', 'approving without validating is refused', J(f"relOpen('{PID}','planning','month','{MON}').status") == 'Submitted' and 'Validate the differences' in J("relAct.err||''"), J("relAct.err"))
    pg.check('#relValChk'); pg.fill('#relValNote', 'Site measurement accepted; P6 to be corrected next week'); pg.click('#sheet [data-reldo="approve"]'); pg.wait_for_timeout(500)
    rr = J(f"relReleased('{PID}','planning','month','{MON}')")
    ck('Internal report', 'with the check and a note it is approved, and the validation is kept', rr and rr['sched_validated_by'] == PSM and rr['sched_validation_note'].startswith('Site measurement'), rr and rr.get('sched_validated_by'))
    J(f"openRelease('{PID}','planning','month','{MON}')"); pg.wait_for_timeout(300)
    ck('Internal report', 'the released report shows who validated and why', 'Validated by Faris Al-Zahrani' in pg.inner_text('#sheet'))
    J("closeDrawer()")

    # ---- client reporting
    as_(PL); J(f"state.relTab='client';state.relPt='month';state.relPer='{MON}';go('rel')"); pg.wait_for_timeout(400)
    v = pg.inner_text('#view')
    ck('Client report', 'Client reporting lists the projects, weekly or monthly', 'Client reporting' in v and pg.locator('[data-relpt]').count() == 1)
    J(f"state.clTab='overview';openRelease('{PID}','client','month','{MON}')"); pg.wait_for_timeout(400)
    sh = pg.inner_text('#sheet')
    ck('Client report', 'it opens full screen with tabs: overview, phases, milestones, look-ahead, notes, approval', J("document.querySelector('#sheet').classList.contains('full')") and J("[...document.querySelectorAll('#sheet [data-cltab]')].map(b=>b.textContent.trim()).join('|')") == 'Overview|Progress by phase|Milestones|Look-ahead|Report notes|Approval')
    ck('Client report', 'planned and actual progress come from the schedule, client weightage', abs(float(pg.input_value('#relForm [name=c_act_pct]')) - sm['client_act']) < 0.006 and abs(float(pg.input_value('#relForm [name=c_plan_pct]')) - sm['client_plan']) < 0.006)
    ck('Client report', 'it shows no internal weightage figures', f"{round(sm['int_act'],1)}%" not in sh and 'internal weightage' not in sh.lower().replace('internal weightage, management remarks and cost are never in it', ''), sh[:300])
    pg.click('#sheet [data-cltab="phases"]'); pg.wait_for_timeout(150)
    ck('Client report', 'progress by phase lists the phases in the schedule', J("document.querySelectorAll('#sheet [data-clp=phases] tbody tr').length") == 6)
    pg.click('#sheet [data-cltab="look"]'); pg.wait_for_timeout(150)
    ck('Client report', 'the look-ahead lists open activities of the next 30 days', 'U-MAT1' in pg.inner_text('#sheet [data-clp="look"]') and 'U-GEN1' not in pg.inner_text('#sheet [data-clp="look"]'))
    pg.click('#sheet [data-cltab="notes"]'); pg.fill('#relForm [name=n_summary]', 'Design 80% complete; chillers in fabrication'); pg.fill('#relForm [name=n_issues]', 'Approval of the shop drawings for level 3')
    pg.click('#sheet [data-reldo="save"]'); pg.wait_for_timeout(500)
    c = J(f"relOpen('{PID}','client','month','{MON}')")
    ck('Client report', 'saved with variance and SPI worked out, and no differences', c and c['figures']['sched_diff_n'] == 0 and abs(c['figures']['var_pct'] - round(c['figures']['act_pct'] - c['figures']['plan_pct'], 2)) < 1e-9 and len(c['figures']['phases']) == 6, c and c['figures'].get('sched_diff_text'))
    pg.click('#sheet [data-clexp="xlsx"]'); pg.wait_for_timeout(400)
    ck('Client report', 'it exports to Excel (marked DRAFT until approved)', any('Client_report_JDC' in x and 'DRAFT' in x for x in J("window.__saved")), J("window.__saved"))
    pg.click('#sheet [data-reldo="submit"]'); pg.wait_for_timeout(400)
    no = tryact({'action': 'approve', 'project_id': PID, 'kind': 'client', 'period_type': 'month', 'period': MON})
    ck('Client report', 'the planner cannot approve it', 'Only the Head' in no or 'someone else' in no, no)
    as_(PM)
    ck('Client report', 'the project manager cannot approve it', 'regional planning section manager' in tryact({'action': 'approve', 'project_id': PID, 'kind': 'client', 'period_type': 'month', 'period': MON}))
    as_(PSM); J(f"openRelease('{PID}','client','month','{MON}')"); pg.wait_for_timeout(300)
    pg.click('#sheet [data-reldo="approve"]'); pg.wait_for_timeout(500)
    ck('Client report', 'the regional planning section manager approves it for issue', J(f"relReleased('{PID}','client','month','{MON}').approved_by") == PSM)
    J(f"openRelease('{PID}','client','month','{MON}')"); pg.wait_for_timeout(300); J("window.__printed=''"); pg.click('#sheet [data-clexp="print"]'); pg.wait_for_timeout(300)
    pr = J("window.__printed")
    ck('Client report', 'the approved report prints (save as PDF) with client figures, phases, milestones and notes, no DRAFT mark', 'Client progress report' in pr and 'Progress by phase' in pr and 'TCC - Taking over certificate' in pr and 'chillers in fabrication' in pr and 'DRAFT' not in pr)
    ck('Client report', 'the printed report has no internal figures or management remarks', f"{round(sm['int_act'],1)}%" not in pr and 'Management remarks' not in pr)
    J("closeDrawer()"); as_(PL)
    J(f"state.clTab='overview';openRelease('RMX','client','week','{WK}')"); pg.wait_for_timeout(300)
    ck('Client report', 'a project with no client-weighted schedule says so', 'No updated schedule' in pg.inner_text('#sheet'))
    J("closeDrawer()")
    J(f"state.clTab='overview';openRelease('QOT','client','week','{WK}')"); pg.wait_for_timeout(300)
    ck('Client report', 'weekly client reports work the same way', abs(float(pg.input_value('#relForm [name=c_act_pct]')) - J("DB.schedUpdates.find(u=>u.project_id==='QOT').summary.client_act")) < 0.006)
    J("closeDrawer()")

    # ---- internal-weighted schedule
    rows2 = [task('U-DES1', 'Design package', 3, 40, '2026-02-01', '2026-10-31', 90, ph='Design'), task('U-CON1', 'Structure works', 5, 60, '2026-05-01', '2027-01-31', 40, ph='Construction')]
    fx2 = os.path.join(d, 'JDC_internal.xer'); open(fx2, 'w').write(xer(rows2, '2026-09-21 17:00'))
    J(f"state.impPid='{PID}';go('base')"); pg.wait_for_timeout(400)
    pg.check('[data-schedwt][value="internal"]'); pg.wait_for_timeout(200); pg.set_input_files('#schedfile', fx2); pg.wait_for_timeout(600); pg.click('[data-schedgo]'); pg.wait_for_timeout(600)
    u2 = J(f"schedUps('{PID}')[0]")
    ck('Upload', 'a schedule loaded with internal weightage gives internal % directly; client figures stay with the last client-weighted schedule',
       u2['weightage'] == 'internal' and abs(u2['summary']['int_act'] - round((40 * .9 + 60 * .4), 2)) < 0.011 and u2['summary']['client_act'] is None and J(f"schedAt('{PID}',ASOF,'client').file_name") == 'JDC_update_Sep.xer')

    # ---- phone width
    pg.set_viewport_size({'width': 390, 'height': 844}); J(f"state.clTab='overview';openRelease('{PID}','client','month','{MON}')"); pg.wait_for_timeout(400)
    ck('Phone', 'the client report fits a phone screen', J("document.querySelector('#sheet').scrollWidth<=document.querySelector('#sheet').clientWidth+2"), J("[document.querySelector('#sheet').scrollWidth,document.querySelector('#sheet').clientWidth]"))
    J("closeDrawer();go('base')"); pg.wait_for_timeout(400)
    ck('Phone', 'the Baselines page fits a phone screen', J("document.documentElement.scrollWidth<=window.innerWidth+2"), J("[document.documentElement.scrollWidth,window.innerWidth]"))
    ck('Errors', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
