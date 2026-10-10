"""ProTrackAI v3.1 in demo (browser) mode: the issue register and the released executive summary.
Planning and costing engineers keep the issues of their own projects; the Head of Planning and Cost Control reviews
them by region or sector; every change is kept; the Excel issue log uploads with refused rows listed; open issues are
saved with each approved progress release; the executive report has a released Summary (region, sector, critical
projects, billing and collection, change order and claim status) and a Project view; RASA answers about issues.
Usage: python3 issues_demo.py /path/to/index.html > results_issues_demo.json"""
import sys, json, time, re, tempfile
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
XLSX_STUB = """window.XLSX={read:function(ab){var j=JSON.parse(new TextDecoder().decode(new Uint8Array(ab)));var n=j.sheet||'Sheet1';var o={SheetNames:[n],Sheets:{}};o.Sheets[n]={aoa:j.aoa};return o},
utils:{sheet_to_json:function(ws){return ws.aoa||[]},aoa_to_sheet:function(a){window.__aoa=a;return{aoa:a}},json_to_sheet:function(){return{}},book_new:function(){return{SheetNames:[],Sheets:{}}},book_append_sheet:function(wb,ws,n){wb.SheetNames.push(n);wb.Sheets[n]=ws},encode_range:function(){return'A1'},decode_range:function(){return{s:{r:0,c:0},e:{r:0,c:0}}},encode_cell:function(){return'A1'}},
write:function(){return new Uint8Array([80,75,3,4])},writeFile:function(){}};"""
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:260]})
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        if 'xlsx' in u.lower(): return r.fulfill(body=XLSX_STUB, content_type='application/javascript')
        return r.abort()
    return r.continue_()
def book(aoa, sheet='Issue Register'):
    f = tempfile.NamedTemporaryFile('wb', suffix='.xlsx', delete=False); f.write(json.dumps({'aoa': aoa, 'sheet': sheet}).encode()); f.close(); return f.name
HEAD = ['', 'Project', 'Region', 'Data date', 'Issue owner', 'Sub Issue owner', 'Issue Type', 'Issue Start date', 'Issue description', 'Impact', 'Action Taken', 'Action Required',
        'Priority By SEC', 'Priority by Alfanar', 'Action By', 'Planned Target', 'Forecast/Expected Target', 'Issue Status', 'Issue Closure date', 'Remarks', 'Schedule Impact', 'Cost Impact']
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);state.scope='ALL';render()")
    J = lambda js: pg.evaluate(js)
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(400); J("state.scope='ALL';render()")
    def act(p): return J(f"(()=>{{try{{const r=issueActLocal({json.dumps(p)});return r?'ok':'none'}}catch(e){{return e.message}}}})()")
    V = lambda: pg.inner_text('#view')
    SA = J("me().id"); P0 = J("PROJECTS[0].id")
    PL = J(f"(teamOf('{P0}','plan')[0]||{{}}).id"); CO = J(f"(teamOf('{P0}','costing')[0]||{{}}).id")
    PM = J(f"(teamOf('{P0}','pm')[0]||{{}}).id"); FM = J(f"(teamOf('{P0}','foreman')[0]||{{}}).id"); EX = J("DB.master.users.find(u=>u.role==='exec').id")
    OTHER = J(f"(PROJECTS.find(p=>!teamOf(p.id,'plan').some(u=>u.id==='{PL}'))||{{}}).id")
    HEADU = J("(pccHeads()[0]||{}).id")

    # ---- demo seeds and menus
    ck('Demo data', 'sample issues are seeded for every demo project, some reviewed, some closed', J("PROJECTS.every(p=>DB.issues.some(i=>i.project_id===p.id))") and J("DB.issues.some(i=>i.reviewed_by)") and J("DB.issues.some(i=>i.status==='Closed')"))
    ck('Demo data', 'seeded released progress reports carry the open issues; seeded cost reports carry billing', J("DB.releases.some(r=>r.kind==='planning'&&r.status==='Released'&&(r.issues_snapshot||[]).length)") and J("DB.releases.some(r=>r.kind==='cost'&&r.status==='Released'&&r.figures.inv_collected!=null)"))
    for who, lab, want in [(SA, 'super admin', True), (PL, 'planning engineer', True), (CO, 'costing engineer', True), (EX, 'executive', True), (PM, 'project manager', True), (FM, 'foreman', False)]:
        if not who: continue
        as_(who); ck('Navigation', f'Issue register in Projects & Handover for the {lab}: {"yes" if want else "no"}', (pg.locator('#nav [data-go="iss"]').count() == 1) == want)
    as_(SA)
    ck('Navigation', 'the Head of Planning and Cost Control exists in the demo', bool(HEADU))

    # ---- screen
    J("state.issF=null;go('iss')"); pg.wait_for_timeout(300); v = V()
    ck('Screen', 'shows open issues, extremely high, past target and not reviewed, with region and sector tables', all(x in v for x in ['Open issues', 'Extremely high, open', 'Past target', 'Not reviewed', 'Open issues by region', 'Open issues by sector']), v[:300])
    n_open = J("issFiltered().length")
    ck('Screen', 'the list defaults to open issues, most severe first', n_open == J("DB.issues.filter(i=>i.status==='Open').length") and J("(()=>{const L=issFiltered();return L.every((x,i)=>!i||issRank(L[i-1].impact)<=issRank(x.impact))})()"))
    reg = J("DB.master.regions.find(r=>DB.issues.some(i=>i.status==='Open'&&projById(i.project_id).region===r.id)).id")
    pg.click(f'[data-issby="region:{reg}"]'); pg.wait_for_timeout(300)
    ck('Screen', 'tapping a region row filters the register to that region', J("state.issF.region") == reg and J(f"issFiltered().every(i=>projById(i.project_id).region==='{reg}')") and J("issFiltered().length") < n_open, J("issFiltered().length"))
    pg.click('[data-issclear]'); pg.wait_for_timeout(300)
    J("state.issF.over=true;render()"); pg.wait_for_timeout(200)
    ck('Screen', '"only past target" shows open issues whose target date has passed', J("issFiltered().length") > 0 and J("issFiltered().every(issOverdue)"))
    J("state.issF={st:'Open'};render()")
    J("issExport(issFiltered())"); pg.wait_for_timeout(400)
    ck('Excel', 'the export has the company issue log columns plus issue no and reviewer', J("window.__aoa&&window.__aoa[0].includes('Priority by client')&&window.__aoa[0].includes('Issue no')&&window.__aoa.length-1===issFiltered().length"))

    # ---- planning engineer adds and keeps an issue
    as_(PL); J("go('iss')"); pg.wait_for_timeout(300)
    pg.click('[data-issnew]'); pg.wait_for_timeout(300)
    opts = J("[...document.querySelectorAll('#issForm [name=project_id] option')].map(o=>o.value)")
    ck('Rights', 'a planning engineer can add issues only to his own projects', opts and all(J(f"teamOf('{x}','plan').some(u=>u.id==='{PL}')") for x in opts) and (OTHER is None or OTHER not in opts), opts)
    pg.select_option('#issForm [name=project_id]', P0)
    n0 = J(f"DB.issues.filter(i=>i.project_id==='{P0}').length")
    pg.click('[data-issdo="save"]'); pg.wait_for_timeout(300)
    ck('Rules', 'an issue without a description is refused, saying why', 'Describe the issue' in pg.inner_text('#issErr') and J(f"DB.issues.filter(i=>i.project_id==='{P0}').length") == n0, pg.inner_text('#issErr'))
    pg.fill('#issForm [name=description]', 'Cable drum delivery held at port customs'); pg.select_option('#issForm [name=impact]', 'High'); pg.fill('#issForm [name=owner]', 'Vendor')
    pg.fill('#issForm [name=issue_type]', 'Delivery'); pg.select_option('#issForm [name=priority_client]', 'A'); pg.fill('#issForm [name=forecast_target]', '2026-10-30')
    pg.click('[data-issdo="save"]'); pg.wait_for_timeout(400)
    new = J(f"DB.issues.find(i=>i.project_id==='{P0}'&&i.description==='Cable drum delivery held at port customs')")
    ck('Rules', 'the planning engineer adds an issue; it gets the next ISS number and a history entry', new and new['issue_no'] == 'ISS-' + str(n0 + 1).zfill(3) and new['status'] == 'Open' and J(f"issAuditOf('{new['id'] if new else ''}').some(a=>a.action==='Created')"), new)
    IID = new['id'] if new else ''
    ck('Rules', 'impact must be one of the four levels', 'Impact must be' in act({'action': 'save', 'id': IID, 'fields': {'impact': 'Severe'}}))
    ck('Rules', 'priority must be A, B or C', 'Priority must be' in act({'action': 'save', 'id': IID, 'fields': {'priority_internal': 'Z'}}))
    ck('Rules', 'dates must be real dates', 'not a valid date' in act({'action': 'save', 'id': IID, 'fields': {'planned_target': '2026-13-40'}}))
    ck('Rules', 'an update records which fields changed', act({'action': 'save', 'id': IID, 'fields': {'action_required': 'Clear customs this week', 'action_by': 'Logistics'}, 'note': 'update'}) == 'ok' and J(f"issAuditOf('{IID}').some(a=>a.action==='Updated'&&a.detail.changes.includes('action_by'))"))
    if OTHER:
        ck('Rights', 'a planning engineer cannot change another project\'s issues', act({'action': 'save', 'project_id': OTHER, 'fields': {'description': 'x'}}) != 'ok')
    ck('Rights', 'a planning engineer cannot mark issues reviewed', 'Only the Head' in act({'action': 'review', 'id': IID}))
    ck('Rules', 'close the issue', act({'action': 'close', 'id': IID, 'closed_on': '2026-09-20'}) == 'ok' and J(f"DB.issues.find(i=>i.id==='{IID}').status") == 'Closed')
    ck('Rules', 'a closed issue cannot be edited', 'reopen it first' in act({'action': 'save', 'id': IID, 'fields': {'remarks': 'x'}}))
    ck('Rules', 'reopening needs a comment', 'Add a comment' in act({'action': 'reopen', 'id': IID}))
    ck('Rules', 'reopen with a comment', act({'action': 'reopen', 'id': IID, 'note': 'Customs asked for more documents'}) == 'ok' and J(f"DB.issues.find(i=>i.id==='{IID}').status") == 'Open')
    if CO:
        as_(CO); ck('Rights', 'the costing engineer of the project can also keep its issues', act({'action': 'save', 'id': IID, 'fields': {'cost_impact': 'SAR 50k demurrage'}}) == 'ok')
    if PM:
        as_(PM); J(f"openIssue('{IID}')"); pg.wait_for_timeout(300)
        ck('Rights', 'a project manager sees issues but cannot change them', 'View only' in pg.inner_text('#sheet') and act({'action': 'save', 'id': IID, 'fields': {'remarks': 'pm'}}) != 'ok'); J("closeDrawer()")
    as_(EX)
    ck('Rights', 'an executive cannot change or review issues', act({'action': 'save', 'id': IID, 'fields': {'remarks': 'x'}}) != 'ok' and act({'action': 'review', 'id': IID}) != 'ok')
    as_(HEADU or SA); J("go('iss')"); pg.wait_for_timeout(300)
    J(f"openIssue('{IID}')"); pg.wait_for_timeout(300); pg.fill('#issNote', 'Discussed in the regional review'); pg.click('[data-issdo="review"]'); pg.wait_for_timeout(400)
    ck('Review', 'the Head marks an issue reviewed with a note; it is kept in the history', J(f"!!DB.issues.find(i=>i.id==='{IID}').reviewed_by") and J(f"issAuditOf('{IID}').some(a=>a.action==='Reviewed'&&a.note==='Discussed in the regional review')"))
    J("closeDrawer()")

    # ---- upload (the company issue log layout)
    as_(PL); J("go('iss')"); pg.wait_for_timeout(300)
    code0 = J(f"pcode(projById('{P0}'))"); codeO = J(f"pcode(projById('{OTHER}'))") if OTHER else 'PE-NOPE'
    rows = [HEAD,
            ['', code0, 'Central', '2026-09-21', 'Client', 'Consultant', 'Design inputs', '2026-08-01', 'Soil report not yet shared by the client', 'High', 'Requested by letter', 'Share the soil report', 'A', 'B', 'Client', '2026-09-30', '2026-10-15', 'Open', '', '', '1 month', ''],
            ['', code0, '', '2026-09-21', 'Internal', 'Supply chain', 'PO Issuance Delay', 'NA', 'Cable drum delivery held at port customs', 'Extremely High', 'Escalated', 'Clear customs', 'NA', 'A', 'Logistics', '', '2026-10-20', 'Open', '', '', '', ''],
            ['', code0, '', '2026-09-21', 'Vendor', '', 'Delivery', '2026-07-01', 'Old punch items closed', 'Low', '', '', 'C', 'C', 'PM', '', '', 'Closed', '2026-09-10', '', '', ''],
            ['', codeO, '', '2026-09-21', 'Client', '', 'Permits', '2026-07-01', 'Permit pending on another project', 'High', '', '', 'A', 'A', 'Client', '', '', 'Open', '', '', '', ''],
            ['', 'PE-99999', '', '', '', '', '', '', 'Unknown project row', 'High', '', '', '', '', '', '', '', 'Open', '', '', '', ''],
            ['', code0, '', '', '', '', '', '', '', 'High', '', '', '', '', '', '', '', 'Open', '', '', '', ''],
            ['', code0, '', '', '', '', '', '', 'Severity spelled wrong', 'Critical', '', '', '', '', '', '', '', 'Open', '', '', '', ''],
            ['', '', '', '', '', '', '', '', '', '', 'continuation text', '', '', '', '', '', '', '', '', '', '', '']]
    f = book(rows)
    pg.set_input_files('#issfile', f); pg.wait_for_timeout(700)
    U = J("state.issUp")
    errs_ = {r['row']: r['err'] for r in U['rows'] if r['err']} if U and U.get('rows') else {}
    ck('Upload', 'the company issue log header row is recognised', U and U.get('rows') and len(U['rows']) == 8, U and U.get('error'))
    ck('Upload', 'rows are refused for another engineer\'s project, an unknown project, a missing description, a wrong impact and a blank continuation row',
       len(errs_) == 5 and any('not one of your projects' in e or 'unknown project' in e for e in errs_.values()) and any('unknown project PE-99999' in e for e in errs_.values()) and any('description missing' in e for e in errs_.values()) and any('impact must be' in e for e in errs_.values()), errs_)
    ck('Upload', 'text such as "NA" in a date or priority column is kept in Remarks instead of refusing the row', any('(From upload:' in (r.get('remarks') or '') and 'NA' in r['remarks'] for r in U['rows'] if not r['err']))
    v = V()
    ck('Upload', 'the preview lists the refused rows and says which rows match existing issues', 'refused' in v and '1 matching existing issues' in v, v[-600:])
    pg.click('[data-issupgo]'); pg.wait_for_timeout(300)
    ck('Upload', 'saving with refused rows needs the confirmation box', J("!!state.issUp"))
    J("document.querySelector('#issAck').checked=true"); pg.click('[data-issupgo]'); pg.wait_for_timeout(500)
    ck('Upload', 'saved: two new issues (one already closed), and the existing issue updated rather than duplicated',
       J(f"DB.issues.filter(i=>i.project_id==='{P0}'&&i.description==='Cable drum delivery held at port customs').length") == 1 and J(f"DB.issues.find(i=>i.id==='{IID}').impact") == 'Extremely High'
       and J(f"DB.issues.find(i=>i.project_id==='{P0}'&&i.description==='Soil report not yet shared by the client')?.status") == 'Open'
       and J(f"DB.issues.find(i=>i.project_id==='{P0}'&&i.description==='Old punch items closed')?.status") == 'Closed')
    ck('Upload', 'the upload is logged in the import history with its refused rows', J("DB.batches.some(b=>b.kind==='issues'&&b.rows_rejected===5&&b.detail.rejected.length===5)"))
    pg.set_input_files('#issfile', f); pg.wait_for_timeout(700); J("document.querySelector('#issAck')&&(document.querySelector('#issAck').checked=true)"); pg.click('[data-issupgo]'); pg.wait_for_timeout(500)
    ck('Upload', 'the same file again changes nothing', J("DB.batches.filter(b=>b.kind==='issues').length") == 1)
    J("issTemplate()"); pg.wait_for_timeout(300)
    ck('Excel', 'the template has the company issue log columns and an example row', J("window.__aoa&&window.__aoa[0].includes('Issue description')&&window.__aoa[0].includes('Priority (internal)')&&window.__aoa.length===2"))

    # ---- issues saved with the approved progress release
    MON = J("recentMonths(3)")
    as_(PL); J(f"state.relTab='planning';state.relPer='{MON[0]}';go('rel')"); pg.wait_for_timeout(200)
    st = J(f"relOpen('{P0}','planning','month','{MON[0]}')?.status") or ''
    if not st:
        J(f"openRelease('{P0}','planning','month','{MON[0]}')"); pg.wait_for_timeout(300); pg.click('[data-reldo="submit"]'); pg.wait_for_timeout(400)
    elif st == 'Draft':
        J(f"relActLocal({{action:'submit',project_id:'{P0}',kind:'planning',period_type:'month',period:'{MON[0]}'}})")
    J("closeDrawer()")
    open_now = J(f"issSnapshot('{P0}').map(x=>x.no)")
    as_(SA); J(f"relActLocal({{action:'approve',project_id:'{P0}',kind:'planning',period_type:'month',period:'{MON[0]}'}})")
    rel = J(f"relReleased('{P0}','planning','month','{MON[0]}')")
    ck('Release', 'approving a progress release saves the project\'s open issues with it, most severe first', rel and [x['no'] for x in rel.get('issues_snapshot', [])] == open_now and rel['issues_snapshot'][0]['impact'] == 'Extremely High', rel and rel.get('issues_snapshot'))
    as_(PL); act({'action': 'close', 'id': IID})
    ck('Release', 'closing an issue later does not change the released version', J(f"relReleased('{P0}','planning','month','{MON[0]}').issues_snapshot.some(x=>x.description==='Cable drum delivery held at port customs')"))

    # ---- billing in the monthly cost report
    as_(CO)
    pc = J(f"PROJECTS.find(p=>teamOf(p.id,'costing').some(u=>u.id==='{CO}')&&!relOpen(p.id,'cost','month','{MON[0]}')&&!relReleased(p.id,'cost','month','{MON[0]}'))?.id") or P0
    J(f"openRelease('{pc}','cost','month','{MON[0]}')"); pg.wait_for_timeout(300); sh = pg.inner_text('#sheet')
    ck('Cost report', 'the cost report has a "Billing to date" section with the four invoice register figures', 'Billing to date' in sh and pg.locator('#relForm [name=c_inv_collected]').count() == 1, sh[-400:])
    pre = J("document.querySelector('#relForm [name=c_inv_submitted]')?.value")
    ck('Cost report', 'billing is filled in from the invoice register when there is one', (pre != '') == bool(J(f"relInvDefaults('{pc}')")), pre)
    tr = lambda p_: J(f"(()=>{{try{{relActLocal({json.dumps(p_)});return 'ok'}}catch(e){{return e.message}}}})()")
    base = {'action': 'save', 'project_id': pc, 'kind': 'cost', 'period_type': 'month', 'period': MON[0], 'data_date': '2026-09-21'}
    ck('Cost report', 'billing amounts cannot be negative', 'cannot be negative' in tr({**base, 'figures': {'budget_rev0': 100, 'actual': 40, 'commitment': 10, 'ftc': 70, 'inv_collected': -1}}))
    ck('Cost report', 'billing is optional and does not change EAC or VAC', tr({**base, 'figures': {'budget_rev0': 100, 'actual': 40, 'commitment': 10, 'ftc': 70}}) == 'ok' and J(f"relOpen('{pc}','cost','month','{MON[0]}').figures.eac") == 110)
    J("closeDrawer()")

    # ---- executive report: Summary and Project view
    as_(EX); J("state.xrPt='month';state.xrPer=null;state.xrTab='sum';go('xr')"); pg.wait_for_timeout(400); v = V()
    ck('Executive report', 'Summary and Project view tabs', pg.locator('[data-xrtab="sum"]').count() == 1 and pg.locator('[data-xrtab="proj"]').count() == 1)
    ck('Executive report', 'the Summary has region, sector, critical projects, billing and collection, and change order and claim status', all(x in v for x in ['By region', 'By sector', 'Critical projects', 'Billing and collection', 'Change order and claim status']), v[:400])
    per = J("(()=>{const t='month',rels=relRows().filter(r=>relVisible(r)&&r.status==='Released'&&SCOPE.has(r.project_id)&&r.period_type===t);return [...new Set(rels.map(r=>r.period))].sort().reverse()[0]})()")
    agg = J(f"(()=>{{const L=xrRows('month','{per}');return {{rel:L.filter(x=>x.pr).length,n:L.length,inv:xrAgg(L).inv,crit:L.filter(x=>x.why.length).map(x=>x.p.short)}}}})()")
    ck('Executive report', 'figures come from the released versions only (counts and invoiced total match the saved reports)', f"{agg['rel']} of {agg['n']}" in v and (agg['inv'] == 0 or J(f"sar({agg['inv']})") in v), agg)
    ck('Executive report', 'every critical project is listed with the reason', all(c in v.split('Critical projects')[1].split('Billing and collection')[0] for c in agg['crit']), agg['crit'])
    ck('Executive report', 'a critical project carrying an extremely high released issue says so', J(f"xrRows('month','{per}').filter(x=>x.iss.some(i=>i.impact==='Extremely High')).every(x=>x.why.some(w=>/extremely high issue/.test(w)))"))
    pg.locator('[data-xrproj]').first.click(); pg.wait_for_timeout(400); v = V()
    ck('Executive report', '"Project view" from a critical row opens that project', J("state.xrTab") == 'proj' and 'Issues and bottlenecks' in v and 'Release history' in v and 'Cost and billing' in v)
    J(f"state.xrPid='{P0}';state.xrPer='{MON[0]}';render()"); pg.wait_for_timeout(300); v = V()
    ck('Executive report', 'the project view shows the issues saved with the release, not today\'s register', 'Cable drum delivery held at port customs' in v)
    J("state.xrPt='week';state.xrPer=null;render()"); pg.wait_for_timeout(300); v = V()
    ck('Executive report', 'the weekly project view carries no cost', 'Cost and billing' not in v and 'Approved budget' not in v and 'Current budget' not in v)
    J("state.xrPt='month';state.xrPer=null;state.xrTab='sum';render()")
    if PM:
        as_(PM); J("state.xrTab='sum';go('xr')"); pg.wait_for_timeout(300)
    if FM:
        as_(FM); ck('Executive report', 'a foreman still has no executive report', J("canXr()") is False)

    # ---- RASA
    as_(SA)
    a = J("answer('What are the open issues?')") or ''
    ck('RASA', 'issues are answered from the issue register, with the source', 'open issue' in a and 'issue register' in a and 'Based on' in re.sub('<[^>]+>', ' ', a), re.sub('<[^>]+>', ' ', a)[:300])
    rn = J(f"DB.master.regions.find(r=>r.id==='{reg}').name")
    a = J(f"answer('Bottlenecks in {rn} region')") or ''
    ck('RASA', 'a question naming a region is answered for that region', f'{rn} Region' in a, re.sub('<[^>]+>', ' ', a)[:200])
    if FM:
        as_(FM); ck('RASA', 'a foreman asking about issues gets "not available for your role"', 'Not available for your role' in (J("answer('What are the open issues?')") or ''))
    as_(SA)
    pg.reload(); pg.wait_for_timeout(1500)
    ck('General', 'issues, history and the upload survive a reload', J(f"DB.issues.some(i=>i.id==='{IID}')") and J(f"issAuditOf('{IID}').length") >= 6 and J("DB.batches.some(b=>b.kind==='issues')"))
    ck('General', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
