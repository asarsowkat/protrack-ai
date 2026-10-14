"""ProTrackAI v3.8.3 on a phone: the full menu (every domain and screen, as on a laptop) opens from Menu in the bottom
bar; the bar keeps Menu and four shortcuts so nothing is cut off; picking a screen closes the menu; ✕ and Esc close it;
laptops are unchanged. Usage: python3 mobile_menu_demo.py /path/to/live.html > results_mobile_menu_demo.json"""
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
    for W, H, tag, scheme in [(390, 844, 'Phone', 'light'), (430, 932, 'Phone (dark)', 'dark'), (820, 1180, 'Tablet', 'light')]:
        pg = b.new_page(viewport={'width': W, 'height': H}, has_touch=True, is_mobile=True, color_scheme=scheme); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
        pg.goto('file://' + APP); pg.wait_for_timeout(800)
        pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1500)
        J = lambda js: pg.evaluate(js)
        J("aiHint=()=>{};rasaBubble=()=>{}")
        vis = J("[...document.querySelectorAll('#bottom button')].filter(b=>b.offsetParent).map(b=>b.textContent.trim())")
        ck(tag, 'the bottom bar shows Menu and four shortcuts, nothing cut off', vis[0] == 'Menu' and len(vis) == 5 and J("document.querySelector('#bottom').scrollWidth<=document.querySelector('#bottom').clientWidth+1"), vis)
        ck(tag, 'the side menu is closed to start with', not J("!!document.querySelector('.side').offsetParent"))
        pg.click('#bottom [data-mnav]'); pg.wait_for_timeout(300)
        ck(tag, 'Menu opens the full menu over the whole screen', J("document.body.classList.contains('mnav')") and J("document.querySelector('.side').getBoundingClientRect().width") >= W - 1)
        groups = J("[...document.querySelectorAll('#nav [data-navgrp]')].map(b=>b.textContent.trim())")
        ck(tag, 'every domain is there, as on a laptop (Planning & Scheduling, Cost Control, Materials & Procurement, Administration…)', all(any(g.startswith(x) for g in groups) for x in ['Home', 'Projects', 'Planning', 'Cost Control', 'Daily Reports', 'Materials', 'Claims', 'Invoices', 'Reports', 'Administration']), groups)
        ck(tag, 'the menu shows the version, so an old copy is easy to spot', 'ProTrackAI v' in pg.inner_text('.side-foot'))
        pg.click('[data-navgrp="planning"]'); pg.wait_for_timeout(200)
        pg.click('#nav [data-navkey^="planning"][data-go="rel"]'); pg.wait_for_timeout(500)
        ck(tag, 'picking a screen (Internal Reporting) opens it and closes the menu', J("state.view") == 'rel' and not J("document.body.classList.contains('mnav')"))
        pg.click('#bottom [data-mnav]'); pg.wait_for_timeout(200); pg.click('.mnavx'); pg.wait_for_timeout(200)
        ck(tag, '✕ closes the menu', not J("document.body.classList.contains('mnav')"))
        pg.click('#bottom [data-mnav]'); pg.wait_for_timeout(200); pg.keyboard.press('Escape'); pg.wait_for_timeout(200)
        ck(tag, 'Esc closes the menu', not J("document.body.classList.contains('mnav')"))
        pg.click('#bottom [data-mnav]'); pg.wait_for_timeout(200); pg.click('[data-navgrp="materials"]'); pg.wait_for_timeout(150); pg.click('#nav [data-go="mat"]'); pg.wait_for_timeout(500)
        ck(tag, 'Material tracking is reachable on the phone', J("state.view") == 'mat' and not J("document.body.classList.contains('mnav')"))
        ck(tag, 'the page never scrolls sideways', J("document.documentElement.scrollWidth") <= W + 1)
        ck(tag, 'no script errors', not errs, errs)
        pg.close()
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1500)
    ck('Laptop', 'unchanged: the side menu shows, the bottom bar and the close button do not', pg.evaluate("!!document.querySelector('.side').offsetParent&&!document.querySelector('#bottom').offsetParent&&!document.querySelector('.mnavx').offsetParent"))
    b.close()
print(json.dumps({'suite': 'mobile_menu_demo', 'page': APP, 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
