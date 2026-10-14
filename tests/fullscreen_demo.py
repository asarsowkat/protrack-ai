"""ProTrackAI v3.7.2: a daily report opened for review or approval, and Create / Edit project, open full screen.
The daily report shows its figures in one row and its activities side by side on wide screens, and keeps the
review and approval buttons in view at the bottom. Other settings forms (people, trades, regions...) stay as a side
panel. Usage: python3 fullscreen_demo.py /path/to/live.html > results_fullscreen_demo.json"""
import sys, json
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'live.html'
R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:260]})
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        return r.abort()
    return r.continue_()
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    for W, H, tag in [(1440, 900, 'Desktop'), (390, 844, 'Phone')]:
        pg = b.new_page(viewport={'width': W, 'height': H}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
        pg.goto('file://' + APP); pg.wait_for_timeout(800)
        pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
        J = lambda js: pg.evaluate(js)
        J("aiHint=()=>{};rasaBubble=()=>{}")
        SA = J("me().id")
        D, PM = J("(()=>{const d=DB.dprs.find(d=>d.status==='Reviewed'&&d.lines.length>1);return [d.id,(DB.master.users.find(u=>u.role==='pm'&&accessIds(u).includes(d.p))||{}).id]})()")
        pg.select_option('#role', PM); pg.wait_for_timeout(300)
        J(f"go('dpr');openDpr('{D}')"); pg.wait_for_timeout(400)
        w = J("document.querySelector('#sheet').getBoundingClientRect().width")
        ck(tag, 'a daily report opened by the project manager for approval fills the screen', w >= W - 1, w)
        ck(tag, 'the approval buttons are there', J("[...document.querySelectorAll('#sheet [data-do]')].map(b=>b.dataset.do)") == ['approve', 'return', 'reject'])
        ck(tag, 'they stay in view at the bottom while scrolling', J("(()=>{const a=document.querySelector('#sheet .dpract');return getComputedStyle(a).position==='sticky'&&a.getBoundingClientRect().bottom<=innerHeight+1})()"))
        if W > 1100:
            ck(tag, 'the four figures are in one row and the activities side by side', J("getComputedStyle(document.querySelector('#sheet .dprfacts')).gridTemplateColumns.split(' ').length") == 4 and J("getComputedStyle(document.querySelector('#sheet .dprlines')).display") == 'grid')
        J("closeDrawer()")
        ck(tag, 'closing it returns the panel to its normal size', not J("document.querySelector('#sheet').classList.contains('full')"))
        EN, DS = J("(()=>{const d=DB.dprs.find(d=>d.status==='Submitted'&&routeOf(d).rev&&routeOf(d).rev.active!==false);return d?[routeOf(d).rev.id,d.id]:['','']})()")
        if EN:
            pg.select_option('#role', EN); pg.wait_for_timeout(300); J(f"go('dpr');openDpr('{DS}')"); pg.wait_for_timeout(300)
            ck(tag, 'a report opened by the site engineer for review is full screen too', J("document.querySelector('#sheet').classList.contains('full')") and 'review' in J("[...document.querySelectorAll('#sheet [data-do]')].map(b=>b.dataset.do)"))
            J("closeDrawer()")
        pg.select_option('#role', SA); pg.wait_for_timeout(300)
        J("go('admin');state.adminTab='projects';render();admDrawer('projects')"); pg.wait_for_timeout(300)
        w = J("document.querySelector('#sheet').getBoundingClientRect().width")
        ck(tag, 'Create project fills the screen', w >= W - 1 and 'Create project' in pg.inner_text('#sheet h2'), w)
        J("closeDrawer()"); J("admDrawer('projects',PROJECTS[0].id)"); pg.wait_for_timeout(300)
        ck(tag, 'Edit project fills the screen too', J("document.querySelector('#sheet').classList.contains('full')"))
        J("admDrawer('users',DB.master.users.find(u=>u.role==='plan').id)"); pg.wait_for_timeout(200)
        ck(tag, 'other settings forms (people) stay a side panel', not J("document.querySelector('#sheet').classList.contains('full')") and (W < 600 or J("document.querySelector('#sheet').getBoundingClientRect().width") < 700))
        J("closeDrawer()")
        ck(tag, 'the page never scrolls sideways', J("document.documentElement.scrollWidth") <= W + 1)
        ck(tag, 'no script errors', not errs, errs)
        pg.close()
    b.close()
print(json.dumps({'suite': 'fullscreen_demo', 'page': APP, 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
