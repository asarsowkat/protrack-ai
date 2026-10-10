"""ProTrackAI v3.0 in demo (browser) mode: released reporting. Progress releases (weekly and monthly) and monthly
cost reports are prepared, submitted, approved by the Head of Planning and Cost Control (never by the person who
submitted), returned and revised; released versions never change; the executive report reads released versions only;
the change order / claim and budget supplement logs upload all-or-nothing and feed the cost report.
Usage: python3 release_demo.py /path/to/index.html > results_release_demo.json"""
import sys, json, time, re, os, tempfile
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
XLSX_STUB = """window.XLSX={read:function(ab){var j=JSON.parse(new TextDecoder().decode(new Uint8Array(ab)));var n=j.sheet||'Sheet1';var o={SheetNames:[n],Sheets:{}};o.Sheets[n]={aoa:j.aoa};return o},
utils:{sheet_to_json:function(ws){return ws.aoa||[]},aoa_to_sheet:function(a){return{aoa:a}},json_to_sheet:function(){return{}},book_new:function(){return{SheetNames:[],Sheets:{}}},book_append_sheet:function(wb,ws,n){wb.SheetNames.push(n);wb.Sheets[n]=ws},encode_range:function(){return'A1'},decode_range:function(){return{s:{r:0,c:0},e:{r:0,c:0}}},encode_cell:function(){return'A1'}},
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
def book(aoa):
    f = tempfile.NamedTemporaryFile('wb', suffix='.xlsx', delete=False); f.write(json.dumps({'aoa': aoa}).encode()); f.close(); return f.name
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);state.scope='ALL';render()")
    J = lambda js: pg.evaluate(js)
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(400); J("state.scope='ALL';render()")
    def tryact(p): return J(f"(()=>{{try{{relActLocal({json.dumps(p)});return 'ok'}}catch(e){{return e.message}}}})()")
    SA = J("me().id"); PID = J("PROJECTS[0].id"); PL = J(f"(teamOf('{PID}','plan')[0]||{{}}).id"); CO = J(f"(teamOf('{PID}','costing')[0]||{{}}).id")
    PM = J(f"(teamOf('{PID}','pm')[0]||{{}}).id"); FM = J(f"(teamOf('{PID}','foreman')[0]||{{}}).id"); EX = J("DB.master.users.find(u=>u.role==='exec').id")
    MON = J("recentMonths(3)"); WK = J("recentWeeks(3)")

    # ---- demo seeds and menus
    ck('Demo data', 'sample releases, cost reports and logs are seeded for the demo projects', J("DB.releases.filter(r=>r.status==='Released').length") >= 30 and J("DB.coLog.length") > 0 and J("DB.suppLog.length") > 0)
    ck('Navigation', 'Home has the released executive report and the live summary', pg.locator('#nav [data-go="xr"]').count() == 1 and pg.locator('#nav [data-go="exec"]').count() == 1)
    ck('Navigation', 'Progress releases, Monthly cost report, Budget supplements and the change order and claim log are live menu items', all(pg.locator(f'#nav .nav-item', has_text=t).count() >= 1 for t in ['Progress releases', 'Monthly cost report', 'Budget supplements', 'Change order and claim log']))
    ck('Navigation', 'Variation register, Claims register and Budget revisions are no longer marked planned', all(pg.locator('#nav .planned', has_text=t).count() == 0 for t in ['Variation register', 'Claims register', 'Budget revisions']))

    # ---- executive report: released versions only
    J("go('xr')"); pg.wait_for_timeout(400)
    v = pg.inner_text('#view')
    ck('Executive report', 'opens on the latest released month and says live daily reports are not used', 'Live daily reports are not used' in v and J(f"perLabel('month','{MON[1]}')") in v, v[:300])
    rel = J(f"relReleased('{PID}','planning','month','{MON[1]}').figures.actual_pct")
    live = J(f"relPlanSnapshot('{PID}').actual_pct")
    ck('Executive report', 'progress shown is the released figure, not today\'s live figure', f"{rel:.1f}%" in v and rel != live, (rel, live))
    J(f"state.xrPer='{MON[2]}';render()"); pg.wait_for_timeout(300)
    a2 = J(f"relReleased('{PID}','planning','month','{MON[2]}').figures.actual_pct")
    ck('Executive report', 'an earlier month shows that month\'s saved version', J(f"perLabel('month','{MON[2]}')") in pg.inner_text('#view') and f"{a2:.1f}%" in pg.inner_text('#view'))
    J("state.xrPt='week';state.xrPer=null;render()"); pg.wait_for_timeout(300)
    v = pg.inner_text('#view')
    ck('Executive report', 'weekly reports show progress only', 'Weekly reports carry progress only' in v and 'Approved budget' not in v and 'Current budget' not in v)
    J("state.xrPt='month';state.xrPer=null;render()")
    as_(FM); J("go('xr')")
    ck('Executive report', 'a foreman has no executive report', 'Executive report ·' not in pg.inner_text('#view'))
    eng = J("(DB.master.users.find(u=>u.role==='eng')||{}).id"); as_(eng)
    ck('Executive report', 'site staff never see cost figures in it', J("(state.xrPt='month',renderXr(),/Approved budget|Current budget|EAC/.test(document.querySelector('#view').innerText))") is False)

    # ---- progress release workflow
    as_(PL)
    p0 = J(f"PROJECTS.find(p=>!relOpen(p.id,'planning','month','{MON[0]}')&&!relReleased(p.id,'planning','month','{MON[0]}')&&teamOf(p.id,'plan').some(u=>u.id==='{PL}'))")
    if not p0:
        p0 = J(f"PROJECTS.find(p=>teamOf(p.id,'plan').some(u=>u.id==='{PL}'))")
        J(f"(()=>{{const r=relOpen('{p0['id']}','planning','month','{MON[0]}');if(r)DB.releases=DB.releases.filter(x=>x!==r)}})()")
    P0 = p0['id']
    J(f"state.relTab='planning';state.relPt='month';state.relPer='{MON[0]}';go('rel')"); pg.wait_for_timeout(300)
    ck('Releases', 'the planning engineer sees Progress releases with Prepare buttons', pg.locator(f'[data-relopen="{P0}"]').count() == 1 and 'Prepare' in pg.inner_text(f'[data-relopen="{P0}"]'))
    pg.click(f'[data-relopen="{P0}"]'); pg.wait_for_timeout(400)
    comp = J(f"relPlanSnapshot('{P0}').actual_pct")
    ck('Releases', 'the form starts from what ProTrackAI computes now', pg.input_value('#relForm [name=f_actual_pct]') == str(comp) or float(pg.input_value('#relForm [name=f_actual_pct]')) == comp)
    pg.fill('#relForm [name=f_actual_pct]', str(round(comp + 1.5, 1))); pg.fill('#relForm [name=n_issues]', 'Cable pulling measured on site')
    pg.click('[data-reldo="save"]'); pg.wait_for_timeout(400)
    ck('Releases', 'changing a figure without a reason is refused', J(f"!relOpen('{P0}','planning','month','{MON[0]}')") and 'reason' in pg.inner_text('#toast').lower(), pg.inner_text('#toast'))
    pg.fill('#relForm [name=r_actual_pct]', 'Site measurement on the 20th'); pg.click('[data-reldo="save"]'); pg.wait_for_timeout(400)
    r = J(f"relOpen('{P0}','planning','month','{MON[0]}')")
    ck('Releases', 'with a reason the draft is saved, and the change is recorded with the computed value', r and r['status'] == 'Draft' and r['overrides'][0]['field'] == 'actual_pct' and r['overrides'][0]['computed'] == comp, r and r['overrides'])
    as_(EX); J("state.xrPt='month';state.xrPer=null;go('xr')")
    ck('Releases', 'management does not see a draft', J(f"!relRows().some(r=>r.project_id==='{P0}'&&r.period==='{MON[0]}'&&relVisible(r)&&r.status!=='Released')"))
    as_(PL); J(f"openRelease('{P0}','planning','month','{MON[0]}')"); pg.wait_for_timeout(300); pg.click('[data-reldo="submit"]'); pg.wait_for_timeout(400)
    ck('Releases', 'the planning engineer submits it', J(f"relOpen('{P0}','planning','month','{MON[0]}').status") == 'Submitted')
    ck('Releases', 'the planning engineer has no Approve button', pg.locator('[data-reldo="approve"]').count() == 0)
    J("closeDrawer()")
    if PM: as_(PM)
    ck('Releases', 'a project manager cannot approve', tryact({'action': 'approve', 'project_id': P0, 'kind': 'planning', 'period_type': 'month', 'period': MON[0]}).startswith('Only the Head'))
    as_(SA); J("go('act');state.actF={who:'mine'};render()"); pg.wait_for_timeout(300)
    lab0 = J(f"perLabel('month','{MON[0]}')")
    ck('Actions', 'the Head sees the release waiting under Mine', f"Progress release, {lab0}: approve or return" in pg.inner_text('#view'), pg.inner_text('#view')[:400])
    J(f"openRelease('{P0}','planning','month','{MON[0]}')"); pg.wait_for_timeout(300); pg.click('[data-reldo="return"]'); pg.wait_for_timeout(300)
    ck('Releases', 'returning needs a comment', J(f"relOpen('{P0}','planning','month','{MON[0]}').status") == 'Submitted')
    pg.fill('#relNote', 'Explain the SPI drop'); pg.click('[data-reldo="return"]'); pg.wait_for_timeout(400)
    ck('Releases', 'the Head returns it with a comment; it is back to draft and shows as returned', J(f"relReturned(relOpen('{P0}','planning','month','{MON[0]}'))") is True)
    as_(PL); J("go('act');state.actF={who:'mine'};render()"); pg.wait_for_timeout(300)
    ck('Actions', 'the planning engineer sees it returned under Mine', 'fix and resubmit' in pg.inner_text('#view'))
    J(f"relActLocal({{action:'submit',project_id:'{P0}',kind:'planning',period_type:'month',period:'{MON[0]}'}})")
    as_(SA); J(f"openRelease('{P0}','planning','month','{MON[0]}')"); pg.wait_for_timeout(300); pg.click('[data-reldo="approve"]'); pg.wait_for_timeout(400)
    rr = J(f"relReleased('{P0}','planning','month','{MON[0]}')")
    ck('Releases', 'the Head approves; it is released', rr and rr['approved_by'] == SA)
    ck('Releases', 'a released period cannot be saved over', tryact({'action': 'save', 'project_id': P0, 'kind': 'planning', 'period_type': 'month', 'period': MON[0], 'figures': {'actual_pct': 10}}).endswith('use Revise to issue a new revision'))
    as_(PL)
    ck('Releases', 'a revision needs a reason', tryact({'action': 'revise', 'project_id': P0, 'kind': 'planning', 'period_type': 'month', 'period': MON[0]}).startswith('Add a comment'))
    ck('Releases', 'the planning engineer starts revision 1 with a reason', tryact({'action': 'revise', 'project_id': P0, 'kind': 'planning', 'period_type': 'month', 'period': MON[0], 'note': 'Late measurement'}) == 'ok' and J(f"relOpen('{P0}','planning','month','{MON[0]}').rev") == 1)
    J(f"relActLocal({{action:'submit',project_id:'{P0}',kind:'planning',period_type:'month',period:'{MON[0]}'}})")
    ck('Releases', 'while revision 1 waits, management still sees revision 0', J(f"relReleased('{P0}','planning','month','{MON[0]}').rev") == 0)
    as_(SA); J(f"relActLocal({{action:'approve',project_id:'{P0}',kind:'planning',period_type:'month',period:'{MON[0]}'}})")
    ck('Releases', 'approving revision 1 supersedes revision 0; both are kept', J(f"relRows().filter(r=>r.project_id==='{P0}'&&r.kind==='planning'&&r.period==='{MON[0]}').map(r=>r.rev+r.status).sort().join()") == '0Superseded,1Released')
    J(f"relActLocal({{action:'save',project_id:'{P0}',kind:'planning',period_type:'week',period:'{WK[0]}',figures:relPlanSnapshot('{P0}')}});relActLocal({{action:'submit',project_id:'{P0}',kind:'planning',period_type:'week',period:'{WK[0]}'}})")
    ck('Releases', 'a super admin who submitted cannot approve their own', tryact({'action': 'approve', 'project_id': P0, 'kind': 'planning', 'period_type': 'week', 'period': WK[0]}).startswith('You submitted'))
    J(f"openRelease('{P0}','planning','week','{WK[0]}')"); pg.wait_for_timeout(300)
    ck('Releases', 'the drawer says so instead of offering Approve', pg.locator('[data-reldo="approve"]').count() == 0 and 'someone else approves it' in pg.inner_text('#sheet'))
    J("closeDrawer()")

    # ---- cost report
    as_(CO)
    pc = J(f"PROJECTS.find(p=>teamOf(p.id,'costing').some(u=>u.id==='{CO}')&&!relOpen(p.id,'cost','month','{MON[0]}'))")['id']
    ck('Cost report', 'a planning engineer cannot prepare a cost report', (as_(PL), tryact({'action': 'save', 'project_id': pc, 'kind': 'cost', 'period_type': 'month', 'period': MON[0], 'figures': {}}))[1].startswith('Only a costing engineer'))
    as_(CO)
    ck('Cost report', 'cost reports are monthly only', tryact({'action': 'save', 'project_id': pc, 'kind': 'cost', 'period_type': 'week', 'period': WK[0], 'figures': {}}) == 'Cost reports are monthly')
    J(f"state.relTab='cost';state.relPer='{MON[0]}';go('rel')"); pg.wait_for_timeout(300); pg.click(f'[data-relopen="{pc}"]'); pg.wait_for_timeout(400)
    # v3.3: the cost report is by WBS head in the company format (current budget D entered; EAC = actual + commitment + ETC)
    J("document.querySelectorAll('#crTable input[type=number]').forEach(i=>{i.value='0'})")
    for k, v in [('budget', 100000000), ('actual', 40000000), ('commitment', 15000000), ('etc', 46000000)]: pg.fill(f'#relForm [name=w0_{k}]', str(v))
    pg.wait_for_timeout(200)
    pg.fill('#relForm [name=w0_justification]', 'Supplement expected for site management')
    supp = J(f"suppApproved('{pc}','{MON[0]}')")
    ck('Cost report', 'the form works out current budget, EAC and VAC as you type', pg.inner_text('[data-crt="eac"]') == '101,000,000' and pg.inner_text('[data-crt="budget"]') == '100,000,000' and pg.inner_text('[data-crt="var"]') == '(1,000,000)', (pg.inner_text('[data-crt="eac"]'), pg.inner_text('[data-crt="budget"]')))
    pg.click('[data-reldo="submit"]'); pg.wait_for_timeout(400)
    c = J(f"relOpen('{pc}','cost','month','{MON[0]}')")
    ck('Cost report', 'saved and submitted with the formulas applied (approved supplements from the log shown alongside)', c and c['status'] == 'Submitted' and c['figures']['eac'] == 101000000 and c['figures']['budget_current'] == 100000000 and c['figures']['supplements_approved'] == supp and supp > 0 and c['figures']['vac'] == -1000000, c and {k: c['figures'].get(k) for k in ('eac', 'budget_current', 'vac', 'supplements_approved')})
    as_(SA); J(f"relActLocal({{action:'approve',project_id:'{pc}',kind:'cost',period_type:'month',period:'{MON[0]}'}})")
    as_(EX); J(f"state.xrPt='month';state.xrPer='{MON[0]}';go('xr')"); pg.wait_for_timeout(300)
    ck('Cost report', 'management sees the released cost report in the executive report', J("sar(101000000)") in pg.inner_text('#view'))
    as_(SA); J("go('cdash')"); pg.wait_for_timeout(300)
    ck('Cost dashboard', 'commitments and approved supplements now come from the last released cost report; accruals stay not tracked', 'report' in pg.inner_text('#view') and 'not tracked yet' in pg.inner_text('#view').lower())

    # ---- cost upload (several projects)
    as_(CO); J(f"state.relTab='cost';state.relPer='{MON[0]}';go('rel')"); pg.wait_for_timeout(300)
    pids = J(f"PROJECTS.filter(p=>teamOf(p.id,'costing').some(u=>u.id==='{CO}')).map(p=>p.id)")
    tgt = J(f"PROJECTS.filter(p=>teamOf(p.id,'costing').some(u=>u.id==='{CO}')&&!relOpen(p.id,'cost','month','{MON[0]}')&&!relReleased(p.id,'cost','month','{MON[0]}')).map(p=>p.id)") or pids[:1]
    rows = [[t, MON[0], 50000000, 20000000, 5000000, 31000000, 'Uploaded'] for t in tgt] + [['NOPE', MON[0], 1, 1, 1, 1, ''], [tgt[0], MON[0], '', 1, 1, 1, '']]
    pg.set_input_files('#relfile', book([['ProTrack monthly cost figures'], [], ['Project (PE number)', 'Month (YYYY-MM)', 'Rev-0 budget', 'Actual cost to date', 'Commitments', 'Forecast cost to complete', 'Comments'], *rows])); pg.wait_for_timeout(800)
    v = pg.inner_text('#relUpBox')
    ck('Cost upload', 'the preview refuses an unknown project and a missing amount, and keeps the rest', 'unknown project' in v and 'every amount is needed' in v and f"{len(tgt)} ready" in v, v[:300])
    pg.click('[data-relupgo]'); pg.wait_for_timeout(600)
    ck('Cost upload', 'each valid row becomes that project\'s draft with the formulas applied, none submitted', all(J(f"(relOpen('{t}','cost','month','{MON[0]}')||{{}}).status") == 'Draft' and J(f"relOpen('{t}','cost','month','{MON[0]}').figures.eac") == 51000000 for t in tgt))

    # ---- logs
    J("state.logTab='vo';go('logs')"); pg.wait_for_timeout(300)
    lp = J("state.logPid")
    n_before = J(f"(DB.batches||[]).filter(b=>b.kind==='volog'&&b.project_id==='{lp}').length")
    vo = [['ProTrack change order and claim log'], [], ['Ref no', 'Type (VO or Claim)', 'Description', 'Submission status', 'Submission date', 'Client approval status', 'Estimated price', 'Estimated cost', 'Expected price to be approved', 'Price considered internally', 'Cost considered internally', 'Change in Rev-0 budget', 'Internal WF status', 'Overall approval status with client', 'Remarks'],
          ['VO-010', 'VO', 'Extra earthing', 'Submitted', '2026-09-10', 'Approved', 200000, 150000, 190000, 'Yes', 'Yes', 150000, 'Internally approved', 'Approved', ''],
          ['CL-010', 'Claim', 'Standby of crane', 'Submitted', '2026-09-12', 'Pending', 300000, '', 120000, 'No', 'Partial', 0, 'Under internal review', 'Pending', ''],
          ['X-1', 'Other', 'bad type', '', '', '', '', '', '', '', '', '', '', '', '']]
    pg.fill('#logMonth', MON[0]); pg.set_input_files('#logfile', book(vo)); pg.wait_for_timeout(700)
    v = pg.inner_text('#view')
    ck('Logs', 'the preview reads your columns and refuses a row with an unknown type', '2 ready, 1 refused' in v and 'type must be VO or Claim' in v, v[-500:])
    pg.click('[data-loggo]'); pg.wait_for_timeout(300)
    ck('Logs', 'refused rows must be acknowledged before anything is saved', J(f"(DB.batches||[]).filter(b=>b.kind==='volog'&&b.project_id==='{lp}').length") == n_before)
    J("(document.getElementById('logAck')||{}).checked=true"); pg.click('[data-loggo]'); pg.wait_for_timeout(500)
    bb = J(f"(DB.batches||[]).filter(b=>b.kind==='volog'&&b.project_id==='{lp}').sort((a,b)=>b.seq-a.seq)[0]")
    ck('Logs', 'acknowledged, the two good rows are saved as a new batch for the month, the difference recorded', bb['source_period'] == MON[0] and bb['rows_accepted'] == 2 and bb['recon_status'] == 'Accepted with difference', bb)
    ck('Logs', 'the earlier month\'s log is kept and can still be shown', J(f"voLatest('{lp}','{MON[1]}').rows.length") == 3 and J(f"voLatest('{lp}','{MON[0]}').rows.length") == 2)
    same = book(vo)
    pg.fill('#logMonth', MON[0]); pg.set_input_files('#logfile', same); pg.wait_for_timeout(700)
    J("(document.getElementById('logAck')||{}).checked=true"); pg.click('[data-loggo]'); pg.wait_for_timeout(300)
    nb = J(f"(DB.batches||[]).filter(b=>b.kind==='volog'&&b.project_id==='{lp}').length")
    pg.fill('#logMonth', MON[0]); pg.set_input_files('#logfile', same); pg.wait_for_timeout(700)
    J("(document.getElementById('logAck')||{}).checked=true"); pg.click('[data-loggo]'); pg.wait_for_timeout(300)
    ck('Logs', 'the same file for the same month again changes nothing', J(f"(DB.batches||[]).filter(b=>b.kind==='volog'&&b.project_id==='{lp}').length") == nb and 'nothing changed' in pg.inner_text('#toast'), pg.inner_text('#toast'))
    J("state.logUp=null;state.logTab='supp';render()"); pg.wait_for_timeout(200)
    su = [['Supplement no', 'Date', 'Description', 'Amount (SAR)', 'Category', 'Linked VO / claim', 'Approval status', 'Remarks'],
          ['BS-10', '2026-09-20', 'Finance cost of delayed payment', 400000, 'Finance', '', 'Approved', ''], ['BS-11', '', 'Weather damage', 5000, 'Weather', '', 'Approved', '']]
    pg.fill('#logMonth', MON[0]); pg.set_input_files('#logfile', book(su)); pg.wait_for_timeout(700)
    ck('Logs', 'a supplement outside the seven categories is refused', 'category must be one of' in pg.inner_text('#view'))
    J("(document.getElementById('logAck')||{}).checked=true"); pg.click('[data-loggo]'); pg.wait_for_timeout(500)
    ck('Logs', 'the new supplement log feeds the next cost report (approved only)', J(f"suppApproved('{lp}','{MON[0]}')") == 400000)
    as_(FM); J("go('logs')")
    ck('Logs', 'a foreman cannot open the logs', 'Change order and claim log' not in pg.inner_text('#view'))
    as_(PL); J("go('logs')")
    ck('Logs', 'a planning engineer can read the logs but has no upload', ('Change order and claim log' in pg.inner_text('#view') or 'Budget supplement log' in pg.inner_text('#view')) and pg.locator('#logfile').count() == 0)

    # ---- RASA reads released data
    as_(SA)
    a = J("answer('What are the commitments?')") or ''
    ck('RASA', 'commitments are answered from the released cost reports, naming them', 'commitments' in a.lower() and 'cost report for' in a and 'no SAP connection' in a, re.sub('<[^>]+>', ' ', a)[:300])
    a = J("answer('Which change orders are pending?')") or ''
    ck('RASA', 'change orders and claims are answered from the latest logs', 'change orders' in a and 'IMP-' in a, re.sub('<[^>]+>', ' ', a)[:300])
    a = J("answer('Show the monthly report')") or ''
    ck('RASA', 'the released progress is answered from releases, not live data', 'progress release' in a and 'not live daily reports' in a)
    as_(FM)
    ck('RASA', 'a foreman asking about commitments gets "not available for your role"', 'Not available for your role' in (J("answer('What are the commitments?')") or ''))
    as_(SA)
    pg.reload(); pg.wait_for_timeout(1500)
    ck('General', 'releases, revisions and logs survive a reload', J(f"relReleased('{P0}','planning','month','{MON[0]}').rev") == 1 and J("DB.suppLog.some(r=>r.supp_no==='BS-10')"))
    ck('General', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
