"""ProTrackAI v3.7.1: the costing file is now called the "Master Manpower Costing Sheet" everywhere it is shown,
while the saved values stay the same (a project's budget manhour source is still stored as 'Costing file', and
uploads are still of kind 'costing'), so nothing on the server changes. The tender costing documents in the
document rack keep their own names. Usage: python3 mmcs_demo.py /path/to/live.html > results_mmcs_demo.json"""
import sys, json
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'live.html'
N = 'Master Manpower Costing Sheet'
R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
XLSX = "window.XLSX={utils:{aoa_to_sheet:a=>({aoa:a}),book_new:()=>({SheetNames:[],Sheets:{}}),book_append_sheet:(wb,ws,n)=>{wb.SheetNames.push(n);wb.Sheets[n]=ws}},write:()=>new Uint8Array([80,75,3,4])};"
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:260]})
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        if 'xlsx' in u.lower(): return r.fulfill(body=XLSX, content_type='application/javascript')
        return r.abort()
    return r.continue_()
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    J = lambda js: pg.evaluate(js)
    J("aiHint=()=>{};rasaBubble=()=>{};state.scope='ALL';render()")
    PID = J("PROJECTS.find(p=>ACTS.some(a=>a.p===p.id)).id")
    J(f"state.impPid='{PID}';state.scope='{PID}';go('base')"); pg.wait_for_timeout(600)
    v = pg.inner_text('#view')
    ck('Baselines', 'the section is called Master Manpower Costing Sheet, with its template and upload buttons', N in v and 'Download the sheet template' in v and f'Upload the {N}' in v, v[:300])
    ck('Baselines', 'the old name is not shown', 'Costing file' not in v and 'costing file' not in v)
    ck('Menu', 'the Cost Control menu entry has the new name', J(f"[...document.querySelectorAll('#nav button')].some(b=>b.textContent.trim()==='{N}')"))
    saved = J("""(async()=>{let n=null,blob=null;const k=saveFile;saveFile=(name,bl)=>{n=name;blob=bl;return Promise.resolve()};try{await costingTemplate()}finally{saveFile=k}return n})()""")
    ck('Template', 'the downloaded template is named Master_Manpower_Costing_Sheet_<project>_<date>.xlsx', bool(saved) and saved.startswith(f'Master_Manpower_Costing_Sheet_{PID}_'), saved)
    J(f"go('admin');state.adminTab='projects';render();admDrawer('projects','{PID}')"); pg.wait_for_timeout(300)
    opts = J("[...document.querySelectorAll('#admForm [name=mhsrc] option')].map(o=>[o.value,o.textContent])")
    ck('Project settings', 'Budget manhours from offers the Master Manpower Costing Sheet; the saved value is unchanged', ['Costing file', N] in opts and J("document.querySelector('#admForm [name=mhsrc]').value") == 'Costing file', opts)
    J("closeDrawer()")
    ck('Import centre', 'uploads of kind costing are listed under the new name', J("IMPORT_KINDS.costing") == N)
    ck('Roles and rights', 'the costing right uses the new name', J("RIGHT_N['costing.manage']") == f'Load the {N} and invoice registers')
    ck('Document rack', 'the tender costing documents keep their own name', 'Original tender costing files' in pg.content())
    ck('Version', 'the side menu shows v3.7.1 or later', (lambda m: m is not None and tuple(int(x) for x in m.group(1).split('.')) >= (3, 7, 1))(__import__('re').search(r'ProTrackAI v(\d+(?:\.\d+)+)', pg.inner_text('#sideVer'))))
    ck('Page', 'no script errors', not errs, errs)
    b.close()
print(json.dumps({'suite': 'mmcs_demo', 'page': APP, 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
