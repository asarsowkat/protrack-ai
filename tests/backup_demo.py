"""ProTrackAI v2.5: backup and restore in demo (browser-only) mode.
Usage: python3 backup_demo.py /path/to/index.html > results_backup.json"""
import sys, json, time
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
R = []
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:240]})
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        return r.abort()
    return r.continue_()
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    ctx = b.new_context(viewport={'width': 1440, 'height': 900}, accept_downloads=True)
    pg = ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{}")
    pg.evaluate("go('admin');state.adminTab='system';render()"); pg.wait_for_timeout(700)
    v = pg.inner_text('#view')
    ck('Backup', 'System tab offers backup and restore', 'Backup and restore' in v and pg.locator('[data-bkbrowser]').count() == 1 and pg.locator('#restorefile').count() == 1, v[-300:])
    ck('Backup', 'no server items shown in demo mode', pg.locator('[data-bkserver]').count() == 0 and 'waiting for the server' not in v)
    n0 = pg.evaluate("DB.dprs.length")
    with pg.expect_download() as dl:
        pg.click('[data-bkbrowser]')
    path = dl.value.path(); bk = json.load(open(path))
    ck('Backup', 'backup file holds the whole browser data', bk.get('format') == 'protrack-browser-backup' and len(bk['data']['dprs']) == n0 and bk.get('app') == pg.evaluate("APP_VERSION"), {k: bk.get(k) for k in ('format', 'app')})
    # change something, then restore
    pg.evaluate("DB.dprs.splice(0,5);save();render()"); n1 = pg.evaluate("DB.dprs.length")
    pg.evaluate("go('admin');state.adminTab='system';render()"); pg.wait_for_timeout(500)
    pg.set_input_files('#restorefile', path); pg.wait_for_timeout(800)
    prev = pg.inner_text('#restoreBox')
    ck('Restore', 'preview compares the browser with the backup before anything changes', str(n1) in prev.replace(',', '') and str(n0) in prev.replace(',', '') and pg.evaluate("DB.dprs.length") == n1, prev[:300])
    with pg.expect_download() as dl2:
        pg.click('[data-restorego]'); pg.wait_for_timeout(400); pg.click('[data-cfm="1"]')
    pg.wait_for_timeout(1200)
    ck('Restore', 'a backup of the current data downloads first', dl2.value.suggested_filename.startswith('protrack-browser-backup'), dl2.value.suggested_filename)
    ck('Restore', 'restore brings the data back', pg.evaluate("DB.dprs.length") == n0, pg.evaluate("DB.dprs.length"))
    pg.reload(); pg.wait_for_timeout(1500)
    ck('Restore', 'restored data survives a reload', pg.evaluate("DB.dprs.length") == n0)
    pg.evaluate("go('admin');state.adminTab='system';render()"); pg.wait_for_timeout(500)
    pg.set_input_files('#restorefile', {'name': 'notes.json', 'mimeType': 'application/json', 'buffer': b'{"hello":1}'}); pg.wait_for_timeout(600)
    ck('Restore', 'a file that is not a ProTrack backup is refused clearly', 'not a ProTrack browser backup' in pg.inner_text('#restoreBox') and pg.locator('[data-restorego]').count() == 0, pg.inner_text('#restoreBox'))
    pg.set_input_files('#restorefile', {'name': 'broken.json', 'mimeType': 'application/json', 'buffer': b'{not json'}); pg.wait_for_timeout(600)
    ck('Restore', 'a damaged file is refused clearly', 'not valid JSON' in pg.inner_text('#restoreBox'), pg.inner_text('#restoreBox'))
    ck('General', 'no script errors', not errs, errs[:2])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
