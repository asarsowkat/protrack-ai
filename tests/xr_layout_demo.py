"""ProTrackAI v3.8.5 in demo (browser) mode: the Executive report (released) can be customised. The super admin sets
the default for everyone or for a role; each person can save their own layout (tiles, sections and their order, the
report shown first) and reset it. Material Tracking is in the released report (as released with each progress report)
and in the live working summary. Usage: python3 xr_layout_demo.py /path/to/live.html > results_xr_layout_demo.json"""
import sys, json
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'live.html'
R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:300]})
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
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1500)
    J = lambda js: pg.evaluate(js)
    J("aiHint=()=>{};rasaBubble=()=>{}")
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(400); J("aiHint=()=>{};rasaBubble=()=>{};state.scope='ALL';render()")
    SA = J("me().id"); EX = J("DB.master.users.find(u=>u.role==='exec').id"); PM = J("(teamOf('JBS','pm')[0]||{}).id"); PM2 = J("(DB.master.users.filter(u=>u.role==='pm'&&u.id!==(teamOf('JBS','pm')[0]||{}).id)[0]||{}).id")
    def xr(tab='sum'):
        J(f"state.scope='ALL';state.xrTab='{tab}';state.xrPer=null;state.xrPt=null;go('xr')"); pg.wait_for_timeout(500)
    secs = lambda: J("[...document.querySelectorAll('#xrBody > [data-xrs]')].filter(e=>e.dataset.xrs!=='_note').map(e=>e.dataset.xrs)")
    tiles = lambda: J("[...document.querySelectorAll('#xrBody > .g-kpi > [data-xrt]')].map(e=>e.dataset.xrt)")
    # ---- Material Tracking in the released report
    as_(EX); xr()
    ck('Released report', 'the standard layout shows a Material tracking section and a Materials delayed tile', 'mat' in secs() and 'matlate' in tiles(), (secs(), tiles()))
    v = pg.inner_text('[data-xrs="mat"]')
    ck('Released report', 'materials as released: counts by delivery status and the delayed materials, per project, with a total', 'Jubail 380kV' in v and 'Delayed materials' in v and 'Total' in v and 'Shunt Reactor' in v, v[:400])
    ck('Released report', 'projects whose release carries no materials say so; nothing live is filled in', 'No Material Tracking in this release' in v)
    J("state.xrTab='proj';state.xrPid='JBS';render()"); pg.wait_for_timeout(400); v = pg.inner_text('#view')
    ck('Released report', 'the Project view shows the materials released with that report', 'Material tracking' in v and 'Materials monitored' in v and 'As released with this progress report' in v, v[:300])
    # ---- one person's own layout
    xr(); ck('Own layout', 'the page says which layout is shown', 'Showing the standard layout' in pg.inner_text('#xrSrc'))
    pg.click('[data-xrcust="1"]'); pg.wait_for_timeout(300)
    ck('Own layout', 'customising offers tiles, sections in order and the report shown first; no default controls for a non-admin', pg.locator('[data-xrlt]').count() == 8 and pg.locator('[data-xrls]').count() == 10 and pg.locator('[name="xrlpt"]').count() == 1 and pg.locator('[data-xrldef]').count() == 0)
    pg.uncheck('[data-xrls="sector"]'); pg.wait_for_timeout(250)
    ck('Own layout', 'unticking a section hides it at once', 'sector' not in secs(), secs())
    for _ in range(12):
        if J("document.querySelector('[data-xrlmv=\"mat|-1\"]').disabled"): break
        pg.click('[data-xrlmv="mat|-1"]'); pg.wait_for_timeout(150)
    ck('Own layout', 'moving Material tracking up puts it first', secs()[0] == 'mat', secs())
    pg.check('[data-xrlt="matdel"]'); pg.uncheck('[data-xrlt="spi"]'); pg.wait_for_timeout(250)
    ck('Own layout', 'tiles follow the ticks', 'matdel' in tiles() and 'spi' not in tiles(), tiles())
    pg.select_option('[name="xrlpt"]', 'week'); pg.wait_for_timeout(300)
    pg.click('[data-xrlsave]'); pg.wait_for_timeout(400)
    ck('Own layout', 'Save as my layout keeps it for this person', J("lyMine().xr&&lyMine().xr.secs[0]") == 'mat' and 'Showing your own layout' in pg.inner_text('#xrSrc'))
    xr(); ck('Own layout', 'it comes back on the next visit, weekly first', secs()[0] == 'mat' and 'sector' not in secs() and J("state.xrPt||xrLayout().pt") == 'week' and 'Weekly' in J("document.querySelector('[data-xrpt]').selectedOptions[0].textContent"))
    as_(PM); xr()
    ck('Own layout', 'another person keeps the standard layout', secs()[0] == 'region' and 'sector' in secs(), secs())
    # ---- super admin defaults
    as_(SA); xr(); pg.click('[data-xrcust="1"]'); pg.wait_for_timeout(300)
    ck('Defaults', 'the super admin sees "Default for others" with Everyone and each role', pg.locator('[data-xrldef]').count() == 2 and J("[...document.querySelectorAll('#xrlRole option')].map(o=>o.value).includes('*')") and J("[...document.querySelectorAll('#xrlRole option')].map(o=>o.value).includes('pm')"))
    pg.uncheck('[data-xrls="region"]'); pg.uncheck('[data-xrls="supp"]'); pg.wait_for_timeout(200)
    pg.select_option('#xrlRole', '*'); pg.click('[data-xrldef="save"]'); pg.wait_for_timeout(400)
    ck('Defaults', 'saved as the company default', J("JSON.stringify(lyDefaults()['*'].xr.secs)").find('region') < 0)
    pg.click('[data-xrcust="0"]'); pg.wait_for_timeout(200)
    as_(PM); xr()
    ck('Defaults', 'a person without their own layout now sees the company default', 'region' not in secs() and 'supp' not in secs() and 'company default' in pg.inner_text('#xrSrc'), (secs(), pg.inner_text('#xrSrc')))
    as_(EX); xr()
    ck('Defaults', 'a person with their own layout keeps it', secs()[0] == 'mat' and 'region' in secs())
    as_(SA); xr(); pg.click('[data-xrcust="1"]'); pg.wait_for_timeout(300)
    pg.check('[data-xrls="region"]'); pg.wait_for_timeout(150)
    for _ in range(12):
        if J("document.querySelector('[data-xrlmv=\"region|-1\"]').disabled"): break
        pg.click('[data-xrlmv="region|-1"]'); pg.wait_for_timeout(100)
    pg.uncheck('[data-xrls="critical"]'); pg.wait_for_timeout(150)
    pg.select_option('#xrlRole', 'pm'); pg.click('[data-xrldef="save"]'); pg.wait_for_timeout(400); pg.click('[data-xrcust="0"]')
    as_(PM); xr()
    ck('Defaults', 'a role default wins over the company default for that role', secs()[0] == 'region' and 'critical' not in secs() and 'the default for Project Manager' in pg.inner_text('#xrSrc'), (secs(), pg.inner_text('#xrSrc')))
    if PM2:
        as_(PM2); xr(); ck('Defaults', '...for every project manager', secs()[0] == 'region' and 'critical' not in secs(), secs())
    as_(EX); xr(); pg.click('[data-xrcust="1"]'); pg.wait_for_timeout(200); pg.click('[data-xrlreset]'); pg.wait_for_timeout(400)
    ck('Defaults', 'Reset to the default takes a person back to the default', J("!lyMine().xr") and 'region' not in secs() and 'company default' in pg.inner_text('#xrSrc'), (secs(), pg.inner_text('#xrSrc')))
    as_(SA); xr(); pg.click('[data-xrcust="1"]'); pg.wait_for_timeout(200); pg.select_option('#xrlRole', 'pm'); pg.click('[data-xrldef="del"]'); pg.wait_for_timeout(400); pg.click('[data-xrcust="0"]')
    as_(PM); xr()
    ck('Defaults', 'removing the role default goes back to the company default', 'company default' in pg.inner_text('#xrSrc') and 'critical' in secs())
    r = J("lySaveDefault('*','xr',null).then(ok=>ok+'|'+lySaveDefault.err)")
    ck('Defaults', 'only the super admin sets defaults', r.startswith('false') and 'super admin' in r, r)
    # ---- the progress release carries the materials
    as_(SA); J("state.rdTab='mat';openRelease('JBS','planning','month',curMonth())"); pg.wait_for_timeout(500)
    tabs = J("[...document.querySelectorAll('#sheet [data-rdtab]')].map(b=>b.textContent.trim())")
    ck('Progress release', 'the release has a Materials tab', 'Materials' in tabs, tabs)
    v = pg.inner_text('#sheet [data-rdp="mat"]')
    ck('Progress release', 'it shows the monitored materials by delivery status and the delayed ones', 'Materials monitored' in v and 'Delayed' in v, v[:300])
    J("document.querySelector('#sheet [data-close]')&&document.querySelector('#sheet [data-close]').click()")
    pid = J("(()=>{const r=relRows().find(r=>r.kind==='planning'&&r.status==='Draft'&&mtSetup(r.project_id));return r?r.project_id:''})()")
    if pid:
        per = J(f"relRows().find(r=>r.kind==='planning'&&r.status==='Draft'&&r.project_id==='{pid}').period")
        J(f"state.rdTab='overview';openRelease('{pid}','planning','month','{per}')"); pg.wait_for_timeout(500)
        f = J("relFormPayload().figures")
        ck('Progress release', 'saving a draft takes the Material Tracking snapshot with it (as the server stores it)', f.get('mat_n', 0) > 0 and 'mat_late' in f and 'mat_dd_date' in f and (f.get('mat_late_text') is None or len(f['mat_late_text']) <= 300), {k: f.get(k) for k in f if k.startswith('mat')})
        J("document.querySelector('#sheet [data-close]')&&document.querySelector('#sheet [data-close]').click()")
    # ---- the live working summary
    as_(EX); J("state.execTab='sum';go('exec')"); pg.wait_for_timeout(600); v = pg.inner_text('#execBody')
    ck('Working summary', 'the live summary has a Material tracking panel per project (live, monitored materials)', 'Material tracking' in v and 'Live, monitored materials' in v and 'Jubail 380kV' in v, v[-600:])
    ck('Working summary', 'a Materials delayed tile is offered (and shown by default)', J("KPI_DEFS.some(k=>k[0]==='matlate')") and 'Materials delayed' in J("[...document.querySelectorAll('#execBody .kpi .l')].map(e=>e.textContent).join('|')"))
    ck('Working summary', 'and a Materials delayed column for the breakdown table', J("COL_DEFS.some(c=>c[0]==='matlate')"))
    pg.click('[data-execedit="1"]'); pg.wait_for_timeout(300); pg.select_option('[name="emat"]', '1'); pg.wait_for_timeout(300)
    ck('Working summary', 'the panel can be hidden from Customise this view', 'Live, monitored materials' not in pg.inner_text('#execBody'))
    pg.click('[data-execreset]'); pg.wait_for_timeout(300)
    ck('Working summary', 'Reset to default shows it again', 'Live, monitored materials' in pg.inner_text('#execBody'))
    as_(SA); J("state.execTab='sum';go('exec')"); pg.wait_for_timeout(400); pg.click('[data-execedit="1"]'); pg.wait_for_timeout(300)
    ck('Working summary', 'the super admin can save the working summary as a default too', pg.locator('[data-exldef]').count() == 2)
    pg.select_option('[name="egroup"]', 'sector'); pg.wait_for_timeout(300); pg.select_option('#exlRole', '*'); pg.click('[data-exldef="save"]'); pg.wait_for_timeout(400)
    pg.click('[data-execreset]'); pg.wait_for_timeout(300)
    as_(PM); J("state.execTab='sum';go('exec')"); pg.wait_for_timeout(500)
    ck('Working summary', 'people who have not changed theirs see the default', J("execPrefs().group") == 'sector' and 'company default' in pg.inner_text('#execSrc'), (J("execPrefs().group"), pg.inner_text('#execSrc')))
    ck('Page', 'no script errors', not errs, errs)
    b.close()
print(json.dumps({'suite': 'xr_layout_demo', 'page': APP, 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
