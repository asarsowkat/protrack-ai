"""ProTrackAI v3.3 in demo (browser) mode: the monthly cost report in the company format, by WBS head.
Columns A tender, B1 Rev-0, B2 revised Rev-0, C previous version (from the last released report), D current budget, E actual,
F commitment, G = D - E - F, H ETC, I = E + F + H, J = D - I, justification (needed when J is not zero, before submitting);
header POC and TCC; contract value and gross margin; Excel fill and export; totals-only drafts. All figures are fictional.
Usage: python3 cost_demo.py /path/to/index.html > results_cost_demo.json"""
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
def book(aoa, sheet='PE-1'):
    f = tempfile.NamedTemporaryFile('wb', suffix='.xlsx', delete=False); f.write(json.dumps({'aoa': aoa, 'sheet': sheet}).encode()); f.close(); return f.name
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);state.scope='ALL';render()")
    J = lambda js: pg.evaluate(js)
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(400); J("state.scope='ALL';render()")
    SA = J("me().id"); P0 = J("PROJECTS[0].id"); MON = J("recentMonths(3)")
    CO = J(f"(teamOf('{P0}','costing')[0]||{{}}).id"); FM = J(f"(teamOf('{P0}','foreman')[0]||{{}}).id"); EX = J("DB.master.users.find(u=>u.role==='exec').id")
    tryact = lambda p_: J(f"(()=>{{try{{relActLocal({json.dumps(p_)});return 'ok'}}catch(e){{return e.message}}}})()")
    val = lambda n: J(f"document.querySelector('#relForm [name={n}]').value")

    # ---- seeded reports in the company format
    ck('Demo data', 'the seeded cost reports are by WBS head, with the 18 company heads', J("DB.releases.filter(r=>r.kind==='cost').every(r=>isWbs(r.figures)&&r.figures.wbs.length===18)"))
    ok = J("""DB.releases.filter(r=>r.kind==='cost').every(r=>{const f=r.figures,s=k=>f.wbs.reduce((t,l)=>t+(+l[k]||0),0);
      return f.wbs.every(l=>Math.abs(l.balance-(l.budget-l.actual-l.commitment))<1e-6&&Math.abs(l.eac-(l.actual+l.commitment+l.etc))<1e-6&&Math.abs(l.var-(l.budget-l.eac))<1e-6)
        &&Math.abs(f.budget_current-s('budget'))<1e-6&&Math.abs(f.eac-s('eac'))<1e-6&&Math.abs(f.vac-(f.budget_current-f.eac))<1e-6&&Math.abs(f.ftc-(f.commitment+f.etc))<1e-6&&Math.abs(f.eac-(f.actual+f.ftc))<1e-6})""")
    ck('Formulas', 'every line: G = D − E − F, I = E + F + H, J = D − I; totals are the sums; forecast to complete = F + H, so EAC = actual + forecast to complete as before', ok)
    ck('Formulas', 'previous version C of a later month = current budget D of the month before, line by line', J("""(()=>{const rs=DB.releases.filter(r=>r.kind==='cost'&&r.status==='Released');return rs.filter(r=>r.figures.prev_period_text).every(r=>{const p=rs.find(x=>x.project_id===r.project_id&&x.period===r.figures.prev_period_text);return p&&r.figures.wbs.every(l=>Math.abs(l.prev-((p.figures.wbs.find(y=>y.code===l.code)||{}).budget||0))<1e-6)})&&rs.some(r=>r.figures.prev_period_text)})()"""))

    # ---- executive report, project view
    as_(EX); J(f"state.xrPt='month';state.xrPer=null;state.xrTab='proj';state.xrPid='{P0}';go('xr')"); pg.wait_for_timeout(400); v = pg.inner_text('#view')
    ck('Executive report', 'the project view shows the cost report by WBS head in the company layout', all(x in v for x in ['Cost report by WBS head', 'Tender', 'Rev-0', 'Revised Rev-0', 'Prev. version', 'Current budget', 'Commitment', 'Balance', 'ETC', 'EAC', 'Supp. (−) / savings (+)', 'Justification', 'Overall', 'Site Management', 'Management Reserve', 'Gross margin', '% Gross margin', 'Planned TCC', 'Actual POC']), v[:300])
    per = J("(()=>{const rels=relRows().filter(r=>relVisible(r)&&r.status==='Released'&&r.period_type==='month');return [...new Set(rels.map(r=>r.period))].sort().reverse()[0]})()")
    f = J(f"relReleased('{P0}','cost','month','{per}').figures")
    ck('Executive report', 'the overall EAC and the gross margin on EAC are shown as worked out', J(f"crFmt({f['eac']})") in v and (not f.get('contract_value') or J(f"crFmt({f['contract_value']}-{f['eac']})") in v))
    J(f"crExport('{P0}','{per}',relReleased('{P0}','cost','month','{per}').figures)"); pg.wait_for_timeout(400)
    A = J("window.__aoa")
    ck('Excel', 'export in the company layout: header row, letters row, Overall row with the totals, one row per WBS head, contract value and gross margin', A and A[4][0] == 'User Field' and A[5][6] == '(D)' and A[7][1] == 'Overall' and A[7][11] == round(f['eac']) and len(A) == 8 + 18 + 4 and A[-3][1] == 'Contract Value', A and A[:8])
    J("state.xrTab='sum';render()"); pg.wait_for_timeout(300)
    ck('Executive report', 'the summary\'s cost table says current budget', 'Current budget' in pg.inner_text('#view'))

    # ---- a new report: prefilled from the last released one
    as_(CO)
    pc = J(f"PROJECTS.find(p=>teamOf(p.id,'costing').some(u=>u.id==='{CO}')&&!relOpen(p.id,'cost','month','{MON[0]}')&&!relReleased(p.id,'cost','month','{MON[0]}'))?.id")
    prev = J(f"crPrev('{pc}','{MON[0]}')")
    J(f"state.relTab='cost';state.relPer='{MON[0]}';go('rel');openRelease('{pc}','cost','month','{MON[0]}')"); pg.wait_for_timeout(400); sh = pg.inner_text('#sheet')
    ck('Form', 'a new cost report opens in the company format, in a wide panel', pg.locator('#crTable').count() == 1 and J("document.querySelector('#sheet').classList.contains('wide')"))
    ck('Form', 'previous version C is fixed to the last released report, which is named', prev is not None and J(f"perLabel('month','{prev['period']}')") in sh and J("document.querySelector('#relForm [name=w0_prev]').type") == 'hidden')
    ck('Form', 'tender, Rev-0 and revised Rev-0 are carried from the last report', float(val('w0_rev0')) == round(prev['figures']['wbs'][0]['rev0']))
    J("document.querySelectorAll('#crTable input[type=number]').forEach(i=>{i.value='0'})")
    for k, x in [('budget', 1000000), ('actual', 600000), ('commitment', 150000), ('etc', 300000)]: pg.fill(f'#relForm [name=w0_{k}]', str(x))
    for k, x in [('budget', 5000000), ('actual', 3000000), ('commitment', 800000), ('etc', 900000)]: pg.fill(f'#relForm [name=w3_{k}]', str(x))
    pg.fill('#relForm [name=w0_justification]', 'Additional budget for the demobilisation plan'); pg.wait_for_timeout(200)
    ck('Form', 'as you type: G, I and J per line (a supplement in brackets) and the overall', pg.inner_text('[data-crc="0:balance"]') == '250,000' and pg.inner_text('[data-crc="0:eac"]') == '1,050,000' and pg.inner_text('[data-crc="0:var"]') == '(50,000)'
       and pg.inner_text('[data-crc="3:var"]') == '300,000' and pg.inner_text('[data-crt="eac"]') == '5,750,000' and pg.inner_text('[data-crt="var"]') == '250,000', [pg.inner_text(s_) for s_ in ['[data-crc="0:var"]', '[data-crt="eac"]', '[data-crt="var"]']])
    pg.fill('#relForm [name=w1_actual]', '-5'); pg.wait_for_timeout(200)
    ck('Form', 'a negative amount is flagged as you type', 'cannot be negative' in pg.inner_text('#relErr'))
    pg.fill('#relForm [name=w1_actual]', '0'); pg.wait_for_timeout(200)
    pg.click('[data-reldo="save"]'); pg.wait_for_timeout(400)
    d = J(f"relOpen('{pc}','cost','month','{MON[0]}')")
    F_ = d['figures'] if d else {}
    ck('Save', 'saved with every line and the totals: current budget 6,000,000, EAC 5,750,000, VAC 250,000, forecast to complete 2,150,000',
       d and F_['budget_current'] == 6000000 and F_['eac'] == 5750000 and F_['vac'] == 250000 and F_['ftc'] == 2150000 and len(F_['wbs']) == 18, d and {k: F_.get(k) for k in ('budget_current', 'eac', 'vac', 'ftc')})
    ck('Save', 'the justification is kept with its line', d and F_['wbs'][0]['justification'] == 'Additional budget for the demobilisation plan')
    ck('Save', 'previous version stays the last released report\'s even if a browser sends another value', J(f"(()=>{{const f=JSON.parse(JSON.stringify(relOpen('{pc}','cost','month','{MON[0]}').figures));f.wbs[0].prev=1;return crCompute('{pc}','{MON[0]}',f).wbs[0].prev}})()") == round(prev['figures']['wbs'][0]['budget']))
    base = {'action': 'save', 'project_id': pc, 'kind': 'cost', 'period_type': 'month', 'period': MON[0]}
    ck('Rules', 'a WBS code twice is refused', 'appears twice' in tryact({**base, 'figures': {'wbs': [{'code': 'SM', 'budget': 1}, {'code': 'sm', 'budget': 1}]}}))
    ck('Rules', 'POC over 100% is refused', 'between 0 and 100' in tryact({**base, 'figures': {'actual_poc': 150, 'wbs': [{'code': 'SM', 'budget': 1}]}}))
    J("closeDrawer()")

    # ---- fill from the company Excel
    HEAD = ['', 'User Field', 'WBS Head', 'Tender', 'Rev-0', 'Revised Rev-0 (as per latest approved CRF)', 'Prev. Version Feb.26', 'Current Budget', 'Actual', 'Commitment', 'Balance', 'ETC', 'EAC', 'SUPP (-)/ SAVINGS (+)', 'Justification']
    rows = [['', '', '', '', '', '', '', '', '', '', 'PE-1 (SAMPLE)'], ['', '', '', '', '', '', '', '', '', '', 'Planned TCC', '16-May-26', 'Planned POC%', 0.293],
            ['', '', '', '', '', '', '', '', '', '', 'Forecasted TCC', '16-May-26', 'Actual POC%', 0.1687], [], HEAD,
            ['', '', '', '(A)', '(B1)', '(B2)', '(C)', '(D)', '(E)', '(F)', '(G)= D-E-F', '(H)', '(I)= E+F+H', '(J)= D-I', ''],
            ['', '', '', 'Dec-24', 'May-25', 'May-25', 'Jul-26', 'Aug-26', 'Aug-26', 'Aug-26', 'Aug-26', 'Aug-26', 'Aug-26', 'Aug-26', 'Budget revision planned'],
            ['', '', 'Overall', 1000, 1000, 1000, 900, 999999, 400, 50, 0, 300, 750, 0, 'Expected potential savings - sample'],
            ['', 'SM', 'Site Management', 100, 100, 100, 110, 150, 120, '-', 30, 60, 180, '(30)', 'Addl. budget for demobilisation (sample)'],
            ['', 'MTRL.ELC', 'Electrical Material', 600, 600, 600, 500, 450, 200, 50, 200, 150, 400, 50, 'Savings on cable (sample)'],
            ['', 'CONT', 'Contingency', 300, 300, 300, 290, 200, 80, 0, 120, 90, 170, 30, ''],
            ['', 'XX', 'Not a head', 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, ''], [],
            ['', '', 'Contract Value', 1200, 1200, 1200, 1200, 1200, '', '', '', '', 1200], ['', '', 'Gross Margin', 200, 200, 200]]
    J(f"openRelease('{pc}','cost','month','{MON[0]}')"); pg.wait_for_timeout(400)
    pg.set_input_files('#crfile', book(rows)); pg.wait_for_timeout(900); sh = pg.inner_text('#sheet')
    ck('Excel', 'the company sheet fills the form: lines by user field code, unknown rows ignored', J("document.querySelectorAll('#crTable [name$=_code]').length") == 3 and val('w0_code') == 'SM' and float(val('w0_budget')) == 150 and float(val('w0_commitment')) == 0, sh[:300])
    ck('Excel', 'header read: POC as percentages, TCC dates, column months, contract value, overall note',
       val('h_planned_poc') == '29.3' and val('h_forecast_tcc_date') == '2026-05-16' and val('h_tender_month_text') == '2024-12' and val('h_contract_value') == '1200' and val('h_overall_note_text') == 'Expected potential savings - sample',
       [val(x) for x in ['h_planned_poc', 'h_forecast_tcc_date', 'h_tender_month_text', 'h_contract_value', 'h_overall_note_text']])
    ck('Excel', 'the file\'s Overall row is checked against its lines and a difference is reported', 'Filled from' in sh and 'differs from the sum of the lines' in sh, sh[:400])
    ck('Excel', 'previous version still comes from the last released report, not the file', J("document.querySelector('#relForm [name=w0_prev]').type") == 'hidden')
    pg.click('[data-reldo="save"]'); pg.wait_for_timeout(400)
    d = J(f"relOpen('{pc}','cost','month','{MON[0]}')")
    ck('Excel', 'saved after the check: EAC = 180 + 400 + 170 = 750 and VAC = 800 − 750 = 50', d and d['figures']['eac'] == 750 and d['figures']['vac'] == 50 and d['figures']['wbs'][0]['justification'] == 'Addl. budget for demobilisation (sample)', d and {k: d['figures'].get(k) for k in ('eac', 'vac')})
    pg.click('[data-reldo="submit"]'); pg.wait_for_timeout(400)
    ck('Rules', 'submitting is refused while a line with a supplement or saving has no justification (CONT)', 'CONT' in pg.inner_text('#relErr') + J("document.querySelector('.toast')?.innerText||''") and J(f"relOpen('{pc}','cost','month','{MON[0]}').status") == 'Draft')
    J(f"openRelease('{pc}','cost','month','{MON[0]}')"); pg.wait_for_timeout(300)
    pg.fill('#relForm [name=w2_justification]', 'Balance contingency retained'); pg.click('[data-reldo="submit"]'); pg.wait_for_timeout(500)
    ck('Rules', 'with the justification it is submitted', J(f"relOpen('{pc}','cost','month','{MON[0]}').status") == 'Submitted')
    J("closeDrawer()")

    # ---- totals-only drafts (quick upload) can be converted
    pq = J(f"PROJECTS.find(p=>p.id!=='{pc}'&&teamOf(p.id,'costing').some(u=>u.id==='{CO}')&&!relOpen(p.id,'cost','month','{MON[0]}')&&!relReleased(p.id,'cost','month','{MON[0]}'))?.id")
    if pq:
        tryact({**base, 'project_id': pq, 'figures': {'budget_rev0': 100, 'actual': 40, 'commitment': 10, 'ftc': 50}})
        J(f"openRelease('{pq}','cost','month','{MON[0]}')"); pg.wait_for_timeout(300)
        ck('Totals only', 'a totals-only draft still opens as before and offers the company format', pg.locator('#relForm [name=c_budget_rev0]').count() == 1 and pg.locator('[data-crconvert]').count() == 1)
        pg.click('[data-crconvert]'); pg.wait_for_timeout(300)
        ck('Totals only', '"Use the company format" switches the form to WBS heads', pg.locator('#crTable').count() == 1)
        J("closeDrawer()")

    # ---- approval and the next month
    as_(SA); J(f"relActLocal({{action:'approve',project_id:'{pc}',kind:'cost',period_type:'month',period:'{MON[0]}'}})")
    nxt = J(f"(()=>{{const [y,m]='{MON[0]}'.split('-').map(Number);const d=new Date(Date.UTC(y,m,1));return d.toISOString().slice(0,7)}})()")
    ck('Next month', 'next month\'s previous version is this month\'s current budget', J(f"crDefaults('{pc}','{nxt}').wbs.map(l=>l.prev).join()") == '150,450,200')
    as_(FM)
    ck('Rights', 'a foreman sees no cost report', J("canRelView()") is False and J("rasaMoneyOk()") is False)
    pg.reload(); pg.wait_for_timeout(1500)
    ck('General', 'the WBS report survives a reload', J(f"relReleased('{pc}','cost','month','{MON[0]}').figures.wbs.length") == 3)
    ck('General', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
