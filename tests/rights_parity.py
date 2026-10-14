"""ProTrackAI v3.7: with no rights changed, every person keeps exactly the rights they had in v3.6.
Signs in on a demo page, then for every active demo person works out the menu, the bottom bar, the project access
and every permission the app checks (daily report actions, baselines, costing, cost figures, reports, approvals,
issues, documents, Tender register, lifecycle), and writes them out. Run it on the v3.6 page and on the v3.7 page
(on v3.7 the custom role seeded for the demo is taken away first) and compare.
Usage: python3 rights_parity.py page.html out.json [--clear]"""
import sys, json
from playwright.sync_api import sync_playwright
APP, OUT = sys.argv[1], sys.argv[2]
CLEAR = '--clear' in sys.argv
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        return r.abort()
    return r.continue_()
PROBE = r"""(()=>{
  const T=(f)=>{try{const v=f();return v===undefined?'u':JSON.stringify(v)}catch(e){return 'E:'+e.message}};
  const out={};const pids=PROJECTS.map(p=>p.id);
  const dprs={};['Draft','Submitted','Reviewed','Approved'].forEach(s=>{dprs[s]=DB.dprs.filter(d=>d.status===s).slice(0,6)});
  const keep={uid:state.uid,role:state.role,view:state.view};
  for(const u of DB.master.users.filter(x=>x.active!==false)){
    state.uid=u.id;state.role=u.role;state.view='dash';
    const r={};
    ['canCreate','canBaseline','canCost','canUpdate','canExec','canImpView','canPlanDash','canCostDash','canTenderView','canRegister','canRelView','canXr',
     'canLogsView','canLogUpload','canIssView','canDocsView','canIssReview','rasaMoneyOk','isSiteRole','canApproveRel','isRegionPlanner'].forEach(n=>{r[n]=T(()=>window[n]?window[n]():eval(n+'()'))});
    ['planning','client','cost'].forEach(k=>{r['canPrepRel:'+k]=T(()=>canPrepRel(k));r['relStaff:'+k]=T(()=>relStaff(k))});
    r.access=T(()=>accessIds().slice().sort());
    pids.forEach(p=>{r['p:'+p]=T(()=>[canIssEdit(p),lcBoss(p,3),lcBoss(p,8),relCanApprove(p,'planning'),relCanApprove(p,'client'),relCanApprove(p,'cost')])});
    r.docs=T(()=>['contract','planning','cost'].map(w=>[docCanRead(w),docCanKeep(w)]));
    r.dpr=T(()=>Object.fromEntries(Object.entries(dprs).map(([s,ds])=>[s,ds.map(d=>actionsFor(d).join('+'))])));
    r.rel=T(()=>relRows().slice(0,40).map(x=>[relVisible(x),relCanReview(x),relCanReturn(x)]));
    try{renderNav();r.nav=[...document.querySelectorAll('#nav [data-go]')].map(b=>b.dataset.go).join(',');r.bottom=[...document.querySelectorAll('#bottom [data-go]')].map(b=>b.dataset.go).join(',')}catch(e){r.nav='E:'+e.message}
    out[u.id]={name:u.name,role:u.role,r};
  }
  state.uid=keep.uid;state.role=keep.role;state.view=keep.view;renderNav();
  return out})()"""
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};state.scope='ALL';render()")
    if CLEAR:
        pg.evaluate("DB.rights={roles:[],role:{},user:{},screen:{},audit:[]};DB.master.users.forEach(u=>{delete u.crole;delete u.allProjects});save();render()")
    res = pg.evaluate(PROBE)
    json.dump({'page': APP, 'people': len(res), 'errors': errs, 'probe': res}, open(OUT, 'w'), indent=0, sort_keys=True)
    print(APP, len(res), 'people,', len(errs), 'page errors')
    b.close()
