"""ProTrackAI regression suite (v2.2 baseline, extended for v2.3 domain navigation). Read-only: runs the app in a
browser on its built-in demo data and records behaviour. Usage:
  python3 baseline_regression.py /path/to/index.html [/path/to/sample.xer]
External CDN libraries are blocked; a minimal Chart.js stub is served so dashboards render.
Excel/PDF/PowerPoint paths need those libraries and are reported as SKIPPED."""
import sys,json,time
from playwright.sync_api import sync_playwright
APP=sys.argv[1] if len(sys.argv)>1 else 'index.html'
XER=sys.argv[2] if len(sys.argv)>2 else None
PW='ProTrack@2026';R=[]
STUB="window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
def ck(area,name,cond,detail=''):
    R.append({'area':area,'check':name,'result':'PASS' if cond else 'FAIL','detail':'' if cond else str(detail)[:200]})
def skip(area,name,why):R.append({'area':area,'check':name,'result':'SKIPPED','detail':why})
def route(r):
    u=r.request.url
    if 'chart' in u.lower() and u.startswith('http'):return r.fulfill(body=STUB,content_type='application/javascript')
    return r.abort() if u.startswith('http') else r.continue_()
def login(pg,email):
    pg.goto('file://'+APP);pg.wait_for_timeout(800)
    pg.fill('#lgId',email);pg.fill('#lgPw',PW);pg.click('#lgBtn');pg.wait_for_timeout(1400)
nav=lambda pg:pg.locator('#nav [data-go]').evaluate_all("e=>e.map(x=>x.dataset.go)")
with sync_playwright() as p:
    b=p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg=b.new_page(viewport={'width':1440,'height':900});errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept());pg.route('**/*',route)
    # --- authentication
    pg.goto('file://'+APP);pg.wait_for_timeout(800)
    pg.fill('#lgId','asarudeen@company.com');pg.fill('#lgPw','wrong');pg.click('#lgBtn');pg.wait_for_timeout(900)
    ck('Auth','wrong password refused',pg.is_visible('#loginForm'))
    pg.fill('#lgPw',PW);pg.click('#lgBtn');pg.wait_for_timeout(1400)
    ck('Auth','demo super admin signs in',pg.evaluate("state.role")=='sa')
    ck('Auth','server mode off without key (demo mode)',pg.evaluate("CLOUD")==False)
    LIVE='date=live' in APP
    ck('Data','date basis: demo pins 22 Sept 2026, live uses today',pg.evaluate("TODAY")==(pg.evaluate("localISO()") if LIVE else '2026-09-22'),pg.evaluate("TODAY+' '+DATE_MODE"))
    ck('Data','each date mode keeps its own storage',pg.evaluate("KEY")==('protrack-live-v1' if LIVE else 'protrack-demo-v1'),pg.evaluate("KEY"))
    stats=pg.evaluate("({projects:PROJECTS.length,acts:ACTS.length,dprs:DB.dprs.length,users:DB.master.users.length,subs:SUBS.length})")
    ck('Data','sample data loaded',stats['projects']>0 and stats['dprs']>0,stats)
    # --- every view renders for super admin
    for v in ['exec','proj','dash','dpr','new','upd','base','eva','rep','deck','perf','admin']:
        n0=len(errs)
        if v in pg.evaluate("[...document.querySelectorAll('#nav [data-go]')].map(b=>b.dataset.go)"):
            pg.evaluate(f"go('{v}')");pg.wait_for_timeout(700)
            ck('Navigation',f'view {v} renders',len(errs)==n0 and len(pg.inner_text('#view'))>50,errs[n0:n0+1])
    # --- reports
    pg.evaluate("go('rep')");pg.wait_for_timeout(500)
    ids=pg.evaluate("Object.keys(REPORTS)")
    for rid in ids:
        n0=len(errs);t=time.time()
        try:r=pg.evaluate(f"(()=>{{const b=REPORTS['{rid}'].build();return b.rows.length}})()");ok=True
        except Exception as e:r=str(e);ok=False
        ck('Reports',f'report {rid} builds ({round(time.time()-t,2)} s)',ok and len(errs)==n0,r)
    skip('Exports','Excel / PDF / PowerPoint export','CDN libraries (SheetJS, jsPDF, PptxGenJS) unreachable from the test environment')
    # --- formulas, reference checks against hand calculation
    f=pg.evaluate("""(()=>{const a=ACTS.find(x=>isCon(x));const d={labour:[{cat:'Carpenter',count:2,reg:8,ot:2}],subs:[],qty:10,act:a.id,p:a.p,date:TODAY};
      return {mh:mhOf(d),cost:costOf(d),rate:rateAt('Carpenter',TODAY),earned:earnedOf(d),pp:a.pp}})()""")
    ck('Formulas','manhours = count x (regular + OT)',f['mh']==20,f)
    ck('Formulas','labour cost = count x rate x (reg + 1.5 x OT)',abs(f['cost']-2*f['rate']*(8+1.5*2))<1e-6,f)
    ck('Formulas','earned manhours = quantity / planned rate',abs(f['earned']-10/f['pp'])<1e-9,f)
    e=pg.evaluate("(()=>{const e=evm(scopeActs(),ASOF);return {spi:e.spi,ev:e.ev,pv:e.pv,cpi:e.cpi}})()")
    ck('Formulas','SPI = EV / PV',abs(e['spi']-e['ev']/e['pv'])<1e-9,e)
    ck('Formulas','submitted (unapproved) reports count as progress',pg.evaluate("VALID.has('Submitted')"),'VALID set')
    zero=lambda v:pg.evaluate("""(()=>{const p=PROJECTS.find(x=>x.id==='QOT');const keep=JSON.stringify(p.billing||null);
      p.billing=defBilling();%sPHASES.forEach(([k])=>p.billing.phases[k]={cap:0,rel1:'',pct1:0,rel2:'',pct2:0});const r=billing(p,ASOF);
      p.billing=JSON.parse(keep);return {billable:r.billable,contract:r.contract}})()"""%("p.billing.v=2;" if v else ""))
    bc=zero(True)
    ck('Formulas','boundary: a 0% phase cap now bills nothing on progress (v2.4 fix)',bc['billable']==0 and bc['contract']>0,bc)
    bl=zero(False)
    ck('Formulas','terms saved before v2.4 keep their old meaning (0 read as no cap)',bl['billable']>0,bl)
    # --- workflow, matrix and timers
    def as_(uid):pg.select_option('#role',uid);pg.wait_for_timeout(700)
    as_('U18');ck('Roles','foreman menu limited (v2.7 adds Actions and approvals)',nav(pg)==['act','dpr','new','perf'],nav(pg))
    pg.evaluate("go('new')");pg.wait_for_timeout(1500)
    ck('Timers','preparation clock visible',pg.locator('#formTimer').count()==1)
    pg.select_option('[data-lk="area"][data-l="0"]','Zone A');pg.select_option('[data-lk="wbs"][data-l="0"]','Structure Works');pg.fill('[data-lk="qty"][data-l="0"]','40');pg.wait_for_timeout(1200)
    pg.click('[data-save="submit"]');pg.wait_for_timeout(900)
    d=pg.evaluate("(()=>{const d=DB.dprs[DB.dprs.length-1];return {id:d.id,st:d.status,t:!!(d.timing&&d.timing.create)}})()")
    ck('Workflow','foreman submits',d['st']=='Submitted',d);ck('Timers','preparation time recorded',d['t'],d)
    rid=d['id'];act=lambda: pg.evaluate(f"actionsFor(DB.dprs.find(x=>x.id==='{rid}'))")
    as_('U11');ck('Workflow','assigned site engineer may review','review' in act(),act())
    as_('U12');ck('Workflow','unassigned site engineer may not review','review' not in act(),act())
    as_('U11');pg.evaluate(f"openDpr('{rid}')");pg.wait_for_timeout(2200);pg.click('#sheet [data-do="review"]');pg.wait_for_timeout(600);pg.keyboard.press('Escape')
    as_('U42');ck('Workflow','assigned site manager may approve','approve' in act(),act())
    pg.evaluate(f"openDpr('{rid}')");pg.wait_for_timeout(2200);pg.click('#sheet [data-do="approve"]');pg.wait_for_timeout(1200);pg.keyboard.press('Escape')
    r=pg.evaluate(f"(()=>{{const d=DB.dprs.find(x=>x.id==='{rid}');return {{st:d.status,rev:!!d.timing.review,apr:!!d.timing.approve,audit:d.audit.map(a=>a.action),mail:(DB.outbox||[]).some(m=>m.dpr==='{rid}')}}}})()")
    ck('Workflow','approved with audit trail',r['st']=='Approved' and 'Approved' in r['audit'],r)
    ck('Timers','review and approval time recorded',r['rev'] and r['apr'],r)
    ck('Email','approval email prepared (not sent in demo)',r['mail'],r)
    # --- role restrictions are client-side only
    as_('U11');pg.evaluate("go('admin')");pg.wait_for_timeout(500)
    ck('Security','site engineer forcing Settings view via script',pg.inner_text('#pageTitle')!='Settings',pg.inner_text('#pageTitle'))
    as_('U11');cost=pg.evaluate("typeof billing==='function'&&billing(PROJECTS[0],ASOF).contract>0")
    ck('Security','contract value reachable from browser console as site engineer (expected: true = gap)',cost==True,cost)
    as_('U16');ck('Security','any user can switch identity via "Acting as" in demo mode',pg.evaluate("state.role")=='foreman')
    # --- P6 import
    if XER:
        as_('U28');pg.evaluate("go('base')");pg.wait_for_timeout(600)
        t=time.time();pg.set_input_files('#p6file',XER);pg.wait_for_timeout(3500)
        txt=pg.inner_text('#view')
        ck('P6','XER parsed with activity count','945 activities' in txt or 'activities found' in txt,txt[:160])
        ck('P6','DCMA check computed on import',pg.evaluate("!!(state.imp&&state.imp.dcma)||Object.keys(DB.dcma||{}).length>0"))
    else: skip('P6','XER import','no sample file given')
    skip('P6','PMXML import','parser present (parsePMXML); no PMXML sample available')
    # --- v2.3 domain navigation and project overview
    as_('U28');pg.evaluate("state.scope='ALL';go('exec')");pg.wait_for_timeout(600)
    groups=pg.locator('#nav [data-navgrp]').evaluate_all("e=>e.map(x=>x.dataset.navgrp)")
    tops=pg.locator('#nav .nav-top').all_inner_texts()
    ck('Navigation v2.3','super admin sees all 12 domains',len(tops)==12,tops)
    planned=pg.locator('#nav .nav-item.planned')
    ck('Navigation v2.3','planned items present and disabled (v2.7 cost reconciliation, v2.8 Tender register, v3.0 cost report, supplements and change order log are live)',planned.count()>=10 and planned.evaluate_all("e=>e.every(b=>b.disabled&&/Planned/.test(b.textContent))"),planned.count())
    pg.click('[data-navgrp="cost"]');pg.wait_for_timeout(200)
    pl=pg.locator('[data-navgrp="cost"] + .nav-sub .planned').first
    pl.click(force=True);pg.wait_for_timeout(300)
    ck('Navigation v2.3','clicking a planned item changes nothing',pg.evaluate("state.view")=='exec')
    pg.click('[data-navgrp="cost"] + .nav-sub [data-go="eva"]');pg.wait_for_timeout(700)
    ck('Navigation v2.3','live item opens its screen',pg.evaluate("state.view")=='eva' and pg.inner_text('#pageTitle')=='Earned value')
    pg.click('[data-navgrp="materials"]');pg.wait_for_timeout(200);pg.click('[data-navgrp="materials"] + .nav-sub [data-go="base"]');pg.wait_for_timeout(900)
    ck('Navigation v2.3','section link opens Baselines',pg.evaluate("state.view")=='base')
    pg.click('[data-navgrp="invoices"]');pg.wait_for_timeout(200);pg.click('[data-navgrp="invoices"] + .nav-sub [data-navrep="cash"]');pg.wait_for_timeout(700)
    ck('Navigation v2.3','report link opens the named report',pg.evaluate("state.view+':'+state.report")=='rep:cash')
    pg.evaluate("go('proj')");pg.wait_for_timeout(700)
    ck('Overview','multi-project scope shows a picker',pg.locator('[data-projpick]').count()==pg.evaluate("scopeProjects().length"))
    pg.click('[data-projpick="QOT"]');pg.wait_for_timeout(1000)
    v=pg.inner_text('#view')
    ck('Overview','picking sets the app scope',pg.evaluate("state.scope")=='QOT')
    ck('Overview','twelve governed lifecycle stages (v2.7)',pg.locator('.lc-card').count()==12 and pg.locator('.lc-chip').count()==12)
    ck('Overview','every stage shows a status from the governed workflow (v2.7)',pg.evaluate("[...document.querySelectorAll('.lc-card .lc-st')].every(e=>/Not started|In progress|Awaiting approval|Complete|Not applicable/.test(e.textContent))"))
    ck('Overview','untracked figures show Planned, not numbers','Approved variations' in v and pg.locator('.fins .pend').count()>=2)
    ck('Overview','no NaN or undefined on the page',not any(x in v for x in ['NaN','undefined','Infinity']),[x for x in ['NaN','undefined','Infinity'] if x in v])
    ck('Overview','SPI tile matches the executive figure',pg.inner_text('[data-kpi="spi"] .v')==pg.evaluate("evm(ACTS.filter(a=>a.p==='QOT'),ASOF).spi.toFixed(2)"))
    ck('Overview','critical items listed',pg.locator('.acts li').count()>0)
    rc=pg.evaluate("(()=>{const r=projMonthly(PROJECTS.find(x=>x.id==='QOT'),projKPI(PROJECTS.find(x=>x.id==='QOT')));return [Math.round(r.filter(x=>x.cum!=null).at(-1).cum),Math.round(evm(ACTS.filter(a=>a.p==='QOT'),ASOF).ac)]})()")
    ck('Overview','cost chart ends at the actual-cost figure',abs(rc[0]-rc[1])<=1,rc)
    as_('U11');pg.evaluate("go('proj')");pg.wait_for_timeout(900)
    v=pg.inner_text('#view')
    ck('Overview','site engineer: no cost figures',pg.locator('[data-kpi="cpi"]').count()==0 and 'Contract and financial summary' not in v and 'Open PO' not in v)
    ck('Navigation v2.3','site engineer sees no planned items',pg.locator('#nav .nav-item.planned').count()==0)
    as_('U18')
    ck('Navigation v2.3','foreman domains: actions, daily reports, reports, RASA (v2.7)',[t.split('\n')[0] for t in pg.locator('#nav .nav-top').all_inner_texts()]==['Projects & Handover','Daily Reports','Reports & Dashboards','RASA AI Assistant'],pg.locator('#nav .nav-top').all_inner_texts())
    ck('Navigation v2.3','foreman cannot open the overview',pg.evaluate("[...document.querySelectorAll('#nav [data-go]')].map(b=>b.dataset.go).includes('proj')")==False)
    # --- RASA
    as_('U28');pg.click('#aiFab');pg.wait_for_timeout(600)
    ck('RASA','opens with welcome state',pg.evaluate("RasaState.cur")=='WELCOME')
    pg.click('[data-rasaqa="schedule"]');pg.wait_for_timeout(3500)
    ck('RASA','quick action answers from data','SPI' in pg.inner_text('#aiMsgs'))
    ck('RASA','LLM fallback only inside claude.ai (window.claude)',pg.evaluate("typeof window.claude")=='undefined')
    ck('General','no uncaught script errors',len(errs)==0,errs[:3])
    b.close()
out={'run_at':time.strftime('%Y-%m-%d %H:%M'),'app':APP,'results':R,
     'summary':{k:sum(1 for r in R if r['result']==k) for k in ['PASS','FAIL','SKIPPED']}}
print(json.dumps(out,indent=1))
