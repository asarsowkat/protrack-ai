"""ProTrackAI v3.8.4 in demo (browser) mode: engineering and procurement progress comes from the weekly updated P6
schedule. No separate E&P Excel upload: the E&P progress page reads the schedule, the import centre no longer offers
"Weekly progress", and the compliance, planning dashboard, project overview and RASA name the updated schedule.
Usage: python3 ep_sched_demo.py /path/to/live.html > results_ep_sched_demo.json"""
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
    J("aiHint=()=>{};rasaBubble=()=>{};state.scope='ALL'")
    # ---- progress from the updated schedule
    row = J("(()=>{const u=schedAt('QOT');return schedRowsOf(u).find(r=>r.id==='QOT-E1020')})()")
    c = J("curOf(actById('QOT-E1020'))")
    ck('Source', 'an engineering activity in the updated schedule takes its % complete from it (Foundation design 70%)', c.get('src') == 'sched' and abs(c['pct'] - row['pct'] / 100) < 1e-9, (c, row))
    ck('Source', 'its data date is the schedule\'s and its status reads In progress', c['dataDate'] == J("String(schedAt('QOT').data_date).slice(0,10)") and J("msName(actById('QOT-E1020'),curOf(actById('QOT-E1020')).ms)") == 'In progress', c)
    ck('Source', 'a completed activity reads Completed', J("msName(actById('QOT-E1010'),curOf(actById('QOT-E1010')).ms)") == 'Completed')
    J("(()=>{const r=schedRowsOf(schedAt('QOT')).find(r=>r.id==='QOT-E1020');r.pct=85;r.ef='2026-12-20'})()")
    ck('Source', 'the next updated schedule moves it: 85% and its forecast finish, with nothing else to upload', abs(J("curOf(actById('QOT-E1020')).pct") - 0.85) < 1e-9 and J("curOf(actById('QOT-E1020')).ff") == '2026-12-20')
    ck('Source', 'earned value follows the schedule too', abs(J("nonConPct(actById('QOT-E1020'))") - 0.85) < 1e-9)
    ck('Source', 'a date before the first updated schedule does not use it', J("nonConPct(actById('QOT-E1020'),addDays(String(schedAt('QOT').data_date).slice(0,10),-60))") < 0.85)
    ck('Source', 'a project with no updated schedule yet keeps the progress loaded before', J("curOf(actById('RMX-D1020')).src") is None and J("curOf(actById('RMX-D1020')).pct") == 0.4)
    ck('Source', 'construction activities are unchanged (daily reports)', J("curOf(ACTS.find(a=>a.p==='QOT'&&isCon(a))).src") is None)
    J("DB.notes=[];epLateNotify('QOT')")
    ck('Alert', 'saving an updated schedule warns about design or procurement items forecast late', 'forecast late in the updated schedule' in J("DB.notes.map(n=>n.text).join(' ')"), J("DB.notes"))
    # ---- the E&P page has no upload
    J("go('upd')"); pg.wait_for_timeout(700); v = pg.inner_text('#view')
    ck('E&P page', 'no template download and no upload any more', pg.locator('#updfile').count() == 0 and pg.locator('[data-updtpl]').count() == 0)
    ck('E&P page', 'it says the progress comes from the weekly updated P6 schedule', 'weekly updated P6 schedule' in v and 'no separate upload' in v.lower(), v[:300])
    ck('E&P page', 'each project shows its updated schedule and data date; one without says so', 'QOT_updated_schedule' in v and 'none loaded' in v, v[:900])
    ck('E&P page', 'engineering and procurement cards and the status table are still there', 'Engineering progress' in v and 'Procurement progress' in v and 'Status by activity' in v and 'Foundation design' in v)
    pg.click('#view [data-go="base"]'); pg.wait_for_timeout(500)
    ck('E&P page', 'the button opens Baselines and P6 import', J("state.view") == 'base')
    ck('Menu', 'the menu calls it "E&P progress"', J("[...document.querySelectorAll('#nav [data-go=\"upd\"]')].map(b=>b.textContent.trim()).join('|')").find('E&P progress') >= 0, J("[...document.querySelectorAll('#nav [data-go=\"upd\"]')].map(b=>b.textContent.trim())"))
    J("go('imp')"); pg.wait_for_timeout(600)
    ck('Import centre', 'no "Weekly progress" upload in the import centre', 'Weekly progress' not in pg.inner_text('#view') and pg.locator('#view [data-impgoto="upd"]').count() == 0)
    # ---- compliance and dashboards name the updated schedule
    J("state.perfTab='compliance';go('perf')"); pg.wait_for_timeout(600)
    rows = J("complianceRows().map(x=>({p:x.p.id,upd:x.upd,w:x.issues.filter(i=>i.k==='weekly').map(i=>i.t)}))")
    q = next(r for r in rows if r['p'] == 'QOT')
    ck('Compliance', 'a project whose updated schedule is current is up to date', not q['w'] and q['upd'] == J("String(schedAt('QOT').data_date).slice(0,10)"), q)
    J("DB.schedUpdates.filter(u=>u.project_id==='JBS').forEach(u=>u.data_date=addDays(ASOF,-20));DB.updates=DB.updates.filter(u=>u.p!=='JBS')")
    jb = next(r for r in J("complianceRows().map(x=>({p:x.p.id,w:x.issues.filter(i=>i.k==='weekly').map(i=>i.t)}))") if r['p'] == 'JBS')
    ck('Compliance', 'an updated schedule older than nine days is flagged by its age', jb['w'] and 'Updated schedule 20 days old' in jb['w'][0], jb)
    ck('Compliance', 'the table and its note name the updated schedule', 'Updated schedule' in pg.inner_text('#view') and 'weekly updated P6 schedule' in pg.inner_text('#view'))
    J("state.perfTab='planners';go('perf')"); pg.wait_for_timeout(600)
    ck('Planners', 'planning engineers are scored on weeks with an updated schedule', 'Updated schedules' in pg.inner_text('#view'))
    J("go('pdash')"); pg.wait_for_timeout(600); v = pg.inner_text('#view')
    ck('Planning dashboard', 'the KPI and column are the weekly updated schedule', 'Updated schedules stale' in v and 'Weekly update (P6)' in v and 'weekly updated P6 schedule' in v, v[:500])
    lc = J("JSON.stringify(projLifecycle(projById('QOT'),projKPI(projById('QOT'))))")
    ck('Project overview', 'the lifecycle check lists the weekly updated schedule with its data date', 'Weekly updated schedule (P6)' in lc and 'Weekly E&P' not in lc, lc[:400])
    J("state.scope='QOT'")
    a = J("answer('Design and procurement')") or ''
    ck('RASA', 'design and procurement answers name the weekly updated P6 schedule and its data date', 'weekly updated P6 schedule' in a, a[:400])
    J("state.scope='ALL'")
    ck('Page', 'no script errors', not errs, errs)
    b.close()
print(json.dumps({'suite': 'ep_sched_demo', 'page': APP, 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
