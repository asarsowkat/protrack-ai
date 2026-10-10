"""ProTrackAI v3.2 in demo (browser) mode: activity quantities in the daily report.
When an activity is chosen the report shows its scope, what was executed up to yesterday, the balance, the balance
duration and today's plan (balance / balance duration); the actual quantity is entered; a quantity beyond the scope is
accepted, but the reviewer must justify it while reviewing and the approver cannot approve an unjustified quantity.
Usage: python3 qty_demo.py /path/to/index.html > results_qty_demo.json"""
import sys, json, time, re
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
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
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);state.scope='ALL';render()")
    J = lambda js: pg.evaluate(js)
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(400); J("state.scope='ALL';render()")
    SA = J("me().id"); PID = J("PROJECTS[0].id")
    FM = J(f"(teamOf('{PID}','foreman')[0]||{{}}).id"); EN = J(f"(teamOf('{PID}','eng')[0]||{{}}).id"); SM = J(f"(teamOf('{PID}','sm')[0]||{{}}).id")
    # use a reviewer and approver the route really assigns
    as_(FM); J("state.form=null;state.editing=null;go('new')"); pg.wait_for_timeout(500)
    f = J("(()=>{const f=state.form;return {p:f.p,act:f.lines[0].act,date:f.date,foreman:f.foreman}})()")
    A = J(f"actById('{f['act']}')")
    P = J(f"(()=>{{const P=qtyPos(actById('{f['act']}'),'{f['date']}',null);return {{scope:P.scope,before:P.before,bal:P.bal,rem:P.rem,plan:P.plan,sameDay:P.sameDay}}}})()")
    exp_before = J(f"(()=>{{const a=actById('{f['act']}');return (+a.priorQty||0)+lines().filter(l=>l.act===a.id&&VALID.has(l.status)&&l.date<'{f['date']}').reduce((t,l)=>t+(+l.qty||0),0)}})()")
    exp_rem = J(f"workdays('{f['date']}',addDays(bfOf(actById('{f['act']}')),1))")
    sh = pg.inner_text('#view')

    # ---- facts on the form
    ck('Form', 'choosing an activity shows its scope, executed up to yesterday, balance, balance duration and plan for today',
       all(x in sh for x in ['Total quantity (scope)', 'Executed up to yesterday', 'Balance', 'Balance duration', 'Plan for today']), sh[:400])
    ck('Form', 'scope is the activity\'s total quantity', abs(P['scope'] - A['qty']) < 1e-6, (P, A['qty']))
    ck('Form', 'executed up to yesterday = earlier progress + every submitted, reviewed or approved report before the date', abs(P['before'] - exp_before) < 1e-6, (P['before'], exp_before))
    ck('Form', 'balance = scope − executed up to yesterday', abs(P['bal'] - max(0, P['scope'] - P['before'])) < 1e-6)
    ck('Form', 'plan for today = balance ÷ balance duration (working days to the planned finish)', P['rem'] == exp_rem and abs(P['plan'] - P['bal'] / max(1, exp_rem)) < 1e-6, (P, exp_rem))
    ck('Form', 'the figures shown match (plan for today)', J(f"fmt({P['plan']},1)") in sh)
    ck('Form', 'the quantity field is "Actual quantity today"', 'Actual quantity today' in sh)
    J(f"state.form.date=addDays('{f['date']}',-1);updateSummary()"); pg.wait_for_timeout(200)
    P1 = J(f"qtyPos(actById('{f['act']}'),addDays('{f['date']}',-1),null).before")
    ck('Form', 'changing the date recalculates the figures', J(f"document.querySelector('#qpos0').innerText.includes(fmt({P1},1))"))
    J(f"state.form.date='{f['date']}';updateSummary()")
    # past finish, not started, complete
    ck('Rules', 'after the planned finish the whole balance is due today', J(f"(()=>{{const a=actById('{f['act']}'),P=qtyPos(a,addDays(bfOf(a),3),null);return P.bal>0?Math.abs(P.plan-P.bal)<1e-9&&/Past the planned finish/.test(P.why):true}})()"))
    ck('Rules', 'before the planned start the plan for today is 0', J(f"(()=>{{const a=actById('{f['act']}'),P=qtyPos(a,addDays(bsOf(a),-3),null);return P.plan===0&&/Planned start/.test(P.why)}})()"))

    # ---- a quantity beyond the scope is accepted
    big = round(P['bal'] + 25, 1)
    pg.fill('[data-lk="qty"]', str(big)); pg.wait_for_timeout(250); sh = pg.inner_text('#view')
    ck('Form', 'a quantity beyond the scope shows how much over, and that the site engineer must justify it', 'Beyond the scope by' in sh and 'must justify' in sh, sh[-500:])
    pg.fill('[data-lk="qty"]', str(round(P['plan'], 1))); pg.wait_for_timeout(250)
    ck('Form', 'within the scope there is no warning', 'Beyond the scope' not in pg.inner_text('#view'))
    pg.fill('[data-lk="qty"]', str(big)); pg.wait_for_timeout(200)
    n0 = J("DB.dprs.length")
    pg.click('[data-save="submit"]'); pg.wait_for_timeout(600)
    d = J(f"DB.dprs.slice().sort((a,b)=>(+b.id.replace(/\\D/g,''))-(+a.id.replace(/\\D/g,'')))[0]")
    DID = d['id']
    ck('Submit', 'the report beyond the scope is accepted and submitted', J("DB.dprs.length") == n0 + 1 and d['status'] == 'Submitted' and abs(d['lines'][0]['qty'] - big) < 1e-6, d['status'])
    ck('Submit', 'a notification says the quantity is beyond the scope', J(f"DB.notes.some(n=>n.text.includes('{DID}')&&/beyond the scope/.test(n.text))"))
    ck('List', 'the report list marks it "Beyond scope"', J(f"(go('dpr'),document.querySelector('[data-open=\"{DID}\"]').innerText.includes('Beyond scope'))"))

    # ---- review: justification required
    REV = J(f"(routeOf(DB.dprs.find(x=>x.id==='{DID}')).rev||{{}}).id") or J(f"(teamOf('{PID}','pm')[0]||{{}}).id")
    as_(REV); J(f"openDpr('{DID}')"); pg.wait_for_timeout(300); sh = pg.inner_text('#sheet')
    ck('Review', 'the report shows the scope figures as at its date and the variation', 'Total quantity (scope)' in sh and 'Beyond the scope' in sh and 'Justify the quantity variation' in sh, sh[:500])
    pg.click('[data-do="review"]'); pg.wait_for_timeout(300)
    ck('Review', 'marking it reviewed without a justification is refused, naming the activity', 'Justify the quantity variation' in pg.inner_text('#actErr') and A['name'] in pg.inner_text('#actErr') and J(f"DB.dprs.find(x=>x.id==='{DID}').status") == 'Submitted')
    pg.fill('[data-just]', 'ok'); pg.click('[data-do="review"]'); pg.wait_for_timeout(300)
    ck('Review', 'a justification of a word or two is refused', J(f"DB.dprs.find(x=>x.id==='{DID}').status") == 'Submitted')
    pg.fill('[data-just]', 'Re-measured on site after the pour; drawing rev C adds the lift pit'); pg.click('[data-do="review"]'); pg.wait_for_timeout(400)
    d = J(f"DB.dprs.find(x=>x.id==='{DID}')")
    ck('Review', 'with a justification it is reviewed; the justification is kept with the quantities, who and when',
       d['status'] == 'Reviewed' and len(d.get('qtyJust', [])) == 1 and d['qtyJust'][0]['activity_id'] == f['act'] and abs(d['qtyJust'][0]['qty'] - big) < 1e-6 and d['qtyJust'][0]['cum_qty'] > d['qtyJust'][0]['scope_qty'], d.get('qtyJust'))
    ck('Review', 'the audit trail shows "Quantity variation justified"', any(a['action'] == 'Quantity variation justified' and 'drawing rev C' in (a.get('note') or '') for a in d['audit']))
    sh = pg.inner_text('#sheet')
    ck('Review', 'the report shows the justification', 'Justified by' in sh and 'drawing rev C' in sh)

    # ---- approval: the quantity must have been justified
    APR = J(f"(routeOf(DB.dprs.find(x=>x.id==='{DID}')).apr||{{}}).id") or SA
    if REV == EN:
        J(f"(()=>{{const x=DB.dprs.find(x=>x.id==='{DID}');x.lines[0].qty={big + 5};save()}})()")   # an edit after review raises it
        as_(APR); J(f"openDpr('{DID}')"); pg.wait_for_timeout(300); pg.click('[data-do="approve"]'); pg.wait_for_timeout(300)
        ck('Approve', 'a quantity raised after review cannot be approved until it is justified', 'has not been justified' in pg.inner_text('#actErr') and J(f"DB.dprs.find(x=>x.id==='{DID}').status") == 'Reviewed', pg.inner_text('#actErr'))
        J(f"(()=>{{const x=DB.dprs.find(x=>x.id==='{DID}');x.lines[0].qty={big};save()}})()")
    as_(APR); J(f"openDpr('{DID}')"); pg.wait_for_timeout(300); pg.click('[data-do="approve"]'); pg.wait_for_timeout(500)
    ck('Approve', 'with the justified quantity it is approved', J(f"DB.dprs.find(x=>x.id==='{DID}').status") == 'Approved', pg.inner_text('#actErr') if pg.locator('#actErr').count() else '')
    J("closeDrawer()")

    # ---- a report within the scope reviews as before
    W = J(f"DB.dprs.find(d=>d.status==='Submitted'&&qtyOverOf(d).length===0)")
    if W:
        RV = J(f"(routeOf(DB.dprs.find(x=>x.id==='{W['id']}')).rev||{{}}).id") or SA
        as_(RV); J(f"openDpr('{W['id']}')"); pg.wait_for_timeout(300)
        ck('Review', 'a report within the scope has no justification box and is reviewed as before', pg.locator('[data-just]').count() == 0)
        pg.click('[data-do="review"]'); pg.wait_for_timeout(300)
        ck('Review', '...reviewed', J(f"DB.dprs.find(x=>x.id==='{W['id']}').status") == 'Reviewed')
        J("closeDrawer()")
    ck('Formulas', 'progress and earned value still cap an activity at its scope', J(f"(()=>{{const a=actById('{f['act']}'),e=evm([a],TODAY);return e.ev<=e.bac+1e-6}})()"))
    pg.reload(); pg.wait_for_timeout(1500)
    ck('General', 'the justification survives a reload', J(f"(DB.dprs.find(x=>x.id==='{DID}').qtyJust||[]).length") == 1)
    ck('General', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
