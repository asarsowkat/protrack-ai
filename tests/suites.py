"""ProTrackAI functional suites (rebuilt in v2.4 after the earlier suites were lost).
Runs the real app in Chromium on its demo data. Network is blocked; SheetJS is replaced by a small
stand-in that hands the app the rows of a JSON "workbook", so the app's own column matching,
validation, preview and apply logic is exercised. Only SheetJS's binary file reading is not tested.
Usage: python3 suites.py /path/to/index.html  >  results.json"""
import sys,json,time
from playwright.sync_api import sync_playwright
APP=sys.argv[1] if len(sys.argv)>1 else 'index.html'
PW='ProTrack@2026';R=[]
CHART="window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
XLSX_STUB="""window.__xl={sheets:[]};window.XLSX={read:function(ab){var t=new TextDecoder().decode(new Uint8Array(ab));var j=JSON.parse(t);var n=j.sheet||'Sheet1';var o={SheetNames:[n],Sheets:{}};o.Sheets[n]={aoa:j.aoa};return o},
utils:{sheet_to_json:function(ws){return ws.aoa||[]},aoa_to_sheet:function(a){window.__xl.sheets.push(a);return{aoa:a}},json_to_sheet:function(r){window.__xl.sheets.push(r);return{}},
book_new:function(){return{SheetNames:[],Sheets:{}}},book_append_sheet:function(wb,ws,n){wb.SheetNames.push(n);wb.Sheets[n]=ws},encode_range:function(){return'A1'},decode_range:function(){return{s:{r:0,c:0},e:{r:0,c:0}}},encode_cell:function(){return'A1'}},
write:function(){return new Uint8Array([80,75,3,4])},writeFile:function(){}};"""
def ck(area,name,cond,detail=''):
    R.append({'area':area,'check':name,'result':'PASS' if cond else 'FAIL','detail':'' if cond else str(detail)[:240]})
def route(r):
    u=r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower():return r.fulfill(body=CHART,content_type='application/javascript')
        if 'xlsx' in u.lower():return r.fulfill(body=XLSX_STUB,content_type='application/javascript')
        return r.abort()
    return r.continue_()
def book(aoa,sheet='Sheet1',name='file.xlsx'):
    return {'name':name,'mimeType':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','buffer':json.dumps({'sheet':sheet,'aoa':aoa}).encode()}
def page(b,url=None):
    pg=b.new_page(viewport={'width':1440,'height':900});errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept());pg.route('**/*',route)
    pg.goto(url or 'file://'+APP);pg.wait_for_timeout(800)
    pg.fill('#lgId','asarudeen@company.com');pg.fill('#lgPw',PW);pg.click('#lgBtn');pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{}")
    return pg,errs
def as_(pg,who):
    uid=pg.evaluate(f"(DB.master.users.find(u=>u.name==='{who}')||DB.master.users.find(u=>u.id==='{who}')||{{}}).id")
    pg.select_option('#role',uid);pg.wait_for_timeout(600)
def ack(pg):
    # v2.6: refused rows must be acknowledged before Apply is enabled
    if pg.locator('#reconAck').count(): pg.check('#reconAck'); pg.wait_for_timeout(150)
def cfm(pg):
    pg.wait_for_timeout(250)
    if pg.locator('[data-cfm="1"]').count():pg.click('[data-cfm="1"]');pg.wait_for_timeout(400)
with sync_playwright() as p:
    b=p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    def sec1():
        pg,errs=page(b)
        ref=pg.evaluate("""(()=>{const p=PROJECTS.find(x=>x.id==='QOT');const keep=JSON.stringify(p.billing||null);
          p.billing={v:2,adv:{pct:10,recover:10},ret:{pct:10,cap:5,tcc:50,fac:50},phases:{ENG:{cap:90,rel1:'TCC',pct1:10,rel2:'',pct2:0},PRC:{cap:90,rel1:'TCC',pct1:10,rel2:'',pct2:0},CON:{cap:80,rel1:'TCC',pct1:10,rel2:'FAC',pct2:10},TC:{cap:80,rel1:'TCC',pct1:10,rel2:'FAC',pct2:10}}};
          const r=billing(p,ASOF);const acts=ACTS.filter(a=>a.p===p.id);let contract=0,billable=0;
          PHASES.forEach(([k])=>{const g=acts.filter(a=>phaseOf(a)===k),price=g.reduce((x,a)=>x+priceOf(a),0);if(!price)return;contract+=price;
            const earned=g.reduce((x,a)=>{const e=evm([a],ASOF);return x+priceOf(a)*(e.bac?Math.min(1,e.ev/e.bac):0)},0),c=p.billing.phases[k];
            const done=m=>{const d=msDone(p,m);return !!(d&&d<=ASOF)};const rel=(c.rel1&&done(c.rel1)?price*c.pct1/100:0)+(c.rel2&&done(c.rel2)?price*c.pct2/100:0);
            billable+=Math.min(price,Math.min(earned,price*c.cap/100)+rel)});
          const held=Math.min(billable*.1,contract*.05),tcc=msDone(p,'TCC'),fac=msDone(p,'FAC'),released=held*((tcc&&tcc<=ASOF?50:0)+(fac&&fac<=ASOF?50:0))/100,rec=Math.min(contract*.1,billable*.1);
          const out={app:{contract:r.contract,billable:r.billable,held:r.held,net:r.net},ref:{contract,billable,held,net:billable-held+released-rec}};p.billing=JSON.parse(keep);return out})()""")
        close=lambda a,b2:abs(a-b2)<=0.01*max(1,abs(b2))/100
        ck('Billing','engine matches an independent re-calculation (contract, billable, retention, net)',all(close(ref['app'][k],ref['ref'][k]) for k in ref['ref']),ref)
        # payment terms form
        pg.evaluate("go('admin');admDrawer('projects','QOT')");pg.wait_for_timeout(900)
        ck('Billing','payment terms form opens',pg.locator('#billForm').count()==1)
        pg.fill('#billForm [name="retpct"]','10');pg.fill('#billForm [name="retcap"]','0')
        pg.click('#billForm [type=submit]');cfm(pg)
        ck('Billing','retention 10% with a 0% cap is refused with an explanation','nothing is held' in pg.inner_text('#billErr'),pg.inner_text('#billErr') if pg.locator('#billErr').count() else '')
        pg.fill('#billForm [name="retcap"]','');pg.fill('#billForm [name="cap_CON"]','')
        pg.click('#billForm [type=submit]');cfm(pg)
        ck('Billing','blank phase cap (= 100%) plus milestone releases over 100% is refused','more than 100%' in pg.inner_text('#billErr'),pg.inner_text('#billErr'))
        pg.fill('#billForm [name="pct1_CON"]','0');pg.fill('#billForm [name="pct2_CON"]','0')
        pg.click('#billForm [type=submit]');cfm(pg)
        t=pg.evaluate("(()=>{const b=PROJECTS.find(x=>x.id==='QOT').billing;return b&&{v:b.v,retcap:b.ret.cap,con:b.phases.CON.cap}})()")
        ck('Billing','blank retention cap saves as "no cap"',t and t['retcap'] is None,t)
        ck('Billing','blank phase cap saves as 100%',t and t['con']==100,t)
        ck('Billing','saved terms carry the v2.4 marker',t and t['v']==2,t)
        nocap=pg.evaluate("(()=>{const p=PROJECTS.find(x=>x.id==='QOT');const r=billing(p,ASOF);return {held:r.held,raw:r.billable*p.billing.ret.pct/100}})()")
        ck('Billing','no cap: retention held = full percentage of billable',abs(nocap['held']-nocap['raw'])<0.01,nocap)
        leg=pg.evaluate("(()=>{const p=PROJECTS.find(x=>x.id==='QOT');const keep=JSON.stringify(p.billing);p.billing={adv:{pct:0,recover:0},ret:{pct:10,cap:0,tcc:50,fac:50},phases:{ENG:{cap:0},PRC:{cap:0},CON:{cap:0},TC:{cap:0}}};const B=billOf(p),r=billing(p,ASOF);p.billing=JSON.parse(keep);return {cap:B.phases.CON.cap,ret:B.ret.cap,held:r.held,raw:r.billable*.1}})()")
        ck('Billing','pre-v2.4 terms: 0 caps still read as "no cap" (historical figures unchanged)',leg['cap']==100 and leg['ret'] is None and abs(leg['held']-leg['raw'])<0.01,leg)
        ck('Billing','no script errors',not errs,errs[:2])
        pg.close()
    try:
        sec1()
    except Exception as ex:
        ck('A','section ran to the end',False,str(ex).split(chr(10))[0])
    def sec2():
        pg,errs=page(b)
        as_(pg,'Priya Raman');pg.evaluate("state.impPid='QOT';go('base')");pg.wait_for_timeout(800)
        ids=pg.evaluate("ACTS.filter(a=>a.p==='QOT'&&isCon(a)).slice(0,3).map(a=>a.id)")
        n0=pg.evaluate("ACTS.filter(a=>a.p==='QOT').length")
        head=['Activity ID','Description','Budget quantity','UOM','Unit rate','Budget cost','Budget manhours']
        aoa=[head,[ids[0],'A',100,'m3',50,5000,400],[ids[1],'B',200,'t',20,4000,800],['NOPE-999','unknown',10,'m',1,10,5],[ids[2],'no qty','','m3',1,1,1]]
        pg.set_input_files('#costfile',book(aoa,'Costing','costing_QOT.xlsx'));pg.wait_for_timeout(1200)
        st=pg.evaluate("state.cost&&state.cost.rows.map(r=>({id:r.id,err:r.err||null}))")
        ck('Costing upload','file is read into a preview',bool(st) and len(st)>=4,st)
        ck('Costing upload','unknown activity ID is rejected',bool(st) and any(r['id']=='NOPE-999' and r['err'] for r in st),st)
        ck('Costing upload','row without a budget quantity is rejected',bool(st) and any(r['id']==ids[2] and r['err'] for r in st),st)
        ck('Costing upload','nothing changes before Apply',pg.evaluate(f"ACTS.find(a=>a.id==='{ids[0]}').bcost")!=5000)
        ck('Costing upload','Apply waits for the refused rows to be acknowledged (v2.6)',pg.is_disabled('[data-costgo]'))
        ack(pg);pg.click('[data-costgo]');pg.wait_for_timeout(900)
        a=pg.evaluate(f"(()=>{{const a=ACTS.find(x=>x.id==='{ids[0]}');return {{qty:a.qty,uom:a.uom,bcost:a.bcost,bmh:a.bmh,pp:a.pp}}}})()")
        ck('Costing upload','valid rows applied: quantity, unit, cost, manhours',a['qty']==100 and a['uom']=='m3' and a['bcost']==5000 and a['bmh']==400,a)
        ck('Costing upload','planned rate recalculated = quantity / manhours',abs(a['pp']-0.25)<1e-9,a)
        ck('Costing upload','upload logged with the number of rows applied',pg.evaluate("DB.costing.QOT&&DB.costing.QOT.n")==2,pg.evaluate("DB.costing.QOT"))
        pg.set_input_files('#costfile',book(aoa,'Costing','costing_QOT.xlsx'));pg.wait_for_timeout(1000);ack(pg);pg.click('[data-costgo]');pg.wait_for_timeout(800)
        ck('Costing upload','uploading the same file again is safe: no duplicated activities, same values',pg.evaluate("ACTS.filter(a=>a.p==='QOT').length")==n0 and pg.evaluate(f"ACTS.find(a=>a.id==='{ids[0]}').bcost")==5000)
        pg.set_input_files('#costfile',book([['Code?','Qty'],['x',1]],'Costing','bad.xlsx'));pg.wait_for_timeout(900)
        ck('Costing upload','missing Activity ID column gives a clear message','Activity ID' in pg.inner_text('#costBox'),pg.inner_text('#costBox')[:160])
        pg.evaluate("window.__xl&&(window.__xl.sheets=[])");pg.click('[data-costtpl]');pg.wait_for_timeout(900)
        tpl=pg.evaluate("(window.__xl.sheets.at(-1)||[]).find(r=>Array.isArray(r)&&r.some(c=>/^Activity ID$/i.test(String(c).trim())))||null")
        ck('Costing upload','template header lists Activity ID, budget quantity and UOM',bool(tpl) and any('quantity' in str(c).lower() for c in tpl) and any('UOM' in str(c) for c in tpl),tpl)
        ck('Costing upload','no script errors',not errs,errs[:2])
        pg.close()
    try:
        sec2()
    except Exception as ex:
        ck('B','section ran to the end',False,str(ex).split(chr(10))[0])
    def sec3():
        pg,errs=page(b)
        as_(pg,'Priya Raman');pg.evaluate("state.impPid='QOT';go('base')");pg.wait_for_timeout(800)
        head=['Invoice number','Invoice date','Type','Invoice amount (SAR)','Submitted amount (SAR)','Approved amount (SAR)','Collected amount (SAR)','Remark']
        aoa=[head,['INV-1','2026-03-31','Progress',1000000,1000000,900000,800000,'IPC 1'],['INV-2','2026-04-30','Progress',500000,500000,600000,0,'over-approved'],
             ['INV-3','2026-05-31','Progress',400000,400000,300000,350000,'over-collected'],['INV-ADV','2026-01-15','Advance',2000000,2000000,2000000,2000000,'Advance']]
        pg.set_input_files('#invfile',book(aoa,'Invoices','invoices_QOT.xlsx'));pg.wait_for_timeout(1100)
        st=pg.evaluate("state.inv&&state.inv.rows.map(r=>({no:r.no,err:r.err||null}))")
        ck('Invoice register','approved above submitted is rejected',bool(st) and any(r['no']=='INV-2' and r['err'] for r in st),st)
        ck('Invoice register','collected above approved is rejected',bool(st) and any(r['no']=='INV-3' and r['err'] for r in st),st)
        ack(pg);pg.click('[data-invgo]');pg.wait_for_timeout(800)
        t=pg.evaluate("(()=>{const t=invTotals('QOT');return {n:invOf('QOT').length,sub:t.submitted,appr:t.approved,coll:t.collected}})()")
        ck('Invoice register','only valid rows stored',t['n']==2,t)
        ck('Invoice register','totals: submitted, approved, collected',t['sub']==3000000 and t['appr']==2900000 and t['coll']==2800000,t)
        aoa[1][7]='IPC 1 (revised remark)'
        pg.set_input_files('#invfile',book(aoa,'Invoices','invoices_QOT.xlsx'));pg.wait_for_timeout(900);ack(pg);pg.click('[data-invgo]');pg.wait_for_timeout(600)
        ck('Invoice register','re-upload replaces the register, never doubles it',pg.evaluate("invOf('QOT').length")==2)
        ck('Invoice register','upload history kept',pg.evaluate("(DB.invHist.QOT||[]).length")>=2)
        ck('Invoice register','no script errors',not errs,errs[:2])
        pg.close()
    try:
        sec3()
    except Exception as ex:
        ck('C','section ran to the end',False,str(ex).split(chr(10))[0])
    def sec4():
        pg,errs=page(b)
        as_(pg,'U11');pg.evaluate("go('rep')");pg.wait_for_timeout(600)
        grants=pg.evaluate("roleCfg().reports.eng.slice().sort()")
        shown=sorted(pg.locator('.replist [data-rep]').evaluate_all("e=>e.map(x=>x.dataset.rep)"))
        ck('Role access','site engineer sees exactly the reports granted to the role',shown==grants,(shown,grants))
        pg.evaluate("go('exec')");pg.wait_for_timeout(700);v=pg.inner_text('#view')
        ck('Role access','site engineer: no cost or billing on the executive summary',not any(x in v for x in ['Cost, CPI','Invoiceable','Contract value','Billing and collection']))
        ck('Role access','site engineer cannot customise the summary',pg.locator('[data-execedit]').count()==0)
        as_(pg,'U28');pg.evaluate("go('admin');state.adminTab='roles';render()");pg.wait_for_timeout(600)
        pg.check('[data-rolerep="eng:unitrate"]');pg.wait_for_timeout(300)
        ck('Role access','cost tiles never offered to site roles',pg.locator('[data-rolekpi="eng:cpi"]').count()==0)
        as_(pg,'U11');pg.evaluate("go('rep')");pg.wait_for_timeout(500)
        ck('Role access','a new grant appears immediately',pg.locator('.replist [data-rep="unitrate"]').count()==1)
        as_(pg,'U18');ck('Role access','foreman: daily reports, new report, own performance only',pg.locator('#nav [data-go]').evaluate_all("e=>[...new Set(e.map(x=>x.dataset.go))]")==['dpr','new','perf'])
        as_(pg,'Tariq Al-Mutairi');pg.evaluate("go('base')");pg.wait_for_timeout(800);v=pg.inner_text('#view')
        ck('Role access','project manager reaches costing, invoices and purchase orders','Costing file' in v and 'Invoice register' in v and 'purchase orders' in v.lower())
        ck('Role access','no script errors',not errs,errs[:2])
        pg.close()
    try:
        sec4()
    except Exception as ex:
        ck('D','section ran to the end',False,str(ex).split(chr(10))[0])
    def sec5():
        pg,errs=page(b)
        as_(pg,'Imran Sheikh');pg.evaluate("go('new')");pg.wait_for_timeout(1000)
        pg.select_option('[data-lk="area"][data-l="0"]','Zone A');pg.select_option('[data-lk="wbs"][data-l="0"]','Structure Works');pg.fill('[data-lk="qty"][data-l="0"]','12');pg.wait_for_timeout(900)
        pg.click('[data-save="submit"]');pg.wait_for_timeout(800);rid=pg.evaluate("DB.dprs.at(-1).id")
        route_=lambda: pg.evaluate(f"(()=>{{const R=routeOf(DB.dprs.find(x=>x.id==='{rid}'));return [R.revName,R.aprName]}})()")
        ck('Approval matrix','report routed to the assigned engineer and manager',route_()==['Eng. Omar Hassan','Eng. Mansour Al-Qahtani'],route_())
        as_(pg,'U28');pg.evaluate("go('admin');state.adminTab='matrix';render()");pg.wait_for_timeout(600)
        pg.select_option('[data-mx="RMX:fm:U18"]','');pg.wait_for_timeout(500)
        ck('Approval matrix','unassigned foreman falls to the project manager',route_()[0]=='Tariq Al-Mutairi',route_())
        ck('Approval matrix','change written to the change log','Imran Sheikh' in pg.evaluate("DB.master.log[0].text"))
        as_(pg,'Tariq Al-Mutairi');ck('Approval matrix','project manager can then review',"review" in pg.evaluate(f"actionsFor(DB.dprs.find(x=>x.id==='{rid}'))"))
        as_(pg,'U11');ck('Approval matrix','former engineer can no longer review',"review" not in pg.evaluate(f"actionsFor(DB.dprs.find(x=>x.id==='{rid}'))"))
        ck('Approval matrix','no script errors',not errs,errs[:2])
        pg.close()
    try:
        sec5()
    except Exception as ex:
        ck('E','section ran to the end',False,str(ex).split(chr(10))[0])
    def sec6():
        pg,errs=page(b)
        pg.evaluate("rasaRefreshInsights(false)");ins=pg.evaluate("RASA.insights.map(i=>i.id)")
        ck('RASA','insights computed for the super admin',len(ins)>0,ins)
        ck('RASA','at most four insights, alerts first',len(ins)<=4 and pg.evaluate("(()=>{const s=RASA.insights.map(i=>i.sev);return s.join(',')===s.slice().sort((a,b)=>({warn:0,insight:1,info:2})[a]-({warn:0,insight:1,info:2})[b]).join(',')})()"))
        as_(pg,'U11');pg.evaluate("rasaRefreshInsights(false)")
        ck('RASA','site engineer gets no cost or billing insight',not any(i in ('cpi','bill') for i in pg.evaluate("RASA.insights.map(i=>i.id)")))
        as_(pg,'U18');pg.evaluate("rasaRefreshInsights(false)")
        ck('RASA','foreman gets only his own queue or drafts',all(i in ('queue','drafts') for i in pg.evaluate("RASA.insights.map(i=>i.id)")),pg.evaluate("RASA.insights.map(i=>i.id)"))
        as_(pg,'U28');pg.evaluate("state.scope='ALL';go('exec')");pg.wait_for_timeout(500)
        pg.click('#aiFab');pg.wait_for_timeout(500);pg.click('[data-rasaqa="schedule"]');pg.wait_for_timeout(3000)
        ck('RASA','schedule analysis quotes the SPI shown on the tile',('SPI is '+pg.inner_text('#view [data-kpi="spi"] .v')) in pg.inner_text('#aiMsgs').replace('\n',' '))
        ck('RASA','RASA points at the tile it talks about',pg.locator('#view .rasa-spot').count()>=1)
        ck('RASA','no script errors',not errs,errs[:2])
        pg.close()
    try:
        sec6()
    except Exception as ex:
        ck('F','section ran to the end',False,str(ex).split(chr(10))[0])
    def sec7():
        pg,errs=page(b)
        nd=pg.evaluate("DB.dprs.length");pg.evaluate("localStorage.setItem('protrack-demo-v1',JSON.stringify(DB))")
        pg.evaluate("go('admin');state.adminTab='system';render()");pg.wait_for_timeout(500)
        ck('Date switch','System tab shows demo mode and its date','Demo' in pg.inner_text('#view') and '22 Sept 2026' in pg.inner_text('#view'))
        pg.click('[data-datemode="live"]');cfm(pg);pg.wait_for_timeout(1500)
        if pg.is_visible('#loginForm'):
            pg.fill('#lgId','asarudeen@company.com');pg.fill('#lgPw',PW);pg.click('#lgBtn');pg.wait_for_timeout(1400)
        ck('Date switch','after switching, the app runs on today\'s date',pg.evaluate("DATE_MODE")=='live' and pg.evaluate("TODAY===localISO()"),pg.evaluate("DATE_MODE+' '+TODAY"))
        ck('Date switch','live mode uses its own storage',pg.evaluate("KEY")=='protrack-live-v1')
        ck('Date switch','demo data left untouched',pg.evaluate("JSON.parse(localStorage.getItem('protrack-demo-v1')).dprs.length")==nd)
        ck('Date switch','sidebar shows the date basis','live date' in pg.inner_text('#sideVer'))
        pg.evaluate("go('admin');state.adminTab='system';render()");pg.wait_for_timeout(400);pg.click('[data-datemode="demo"]');cfm(pg);pg.wait_for_timeout(1500)
        if pg.is_visible('#loginForm'):
            pg.fill('#lgId','asarudeen@company.com');pg.fill('#lgPw',PW);pg.click('#lgBtn');pg.wait_for_timeout(1400)
        ck('Date switch','switching back restores demo mode and its data',pg.evaluate("DATE_MODE")=='demo' and pg.evaluate("DB.dprs.length")==nd)
        ck('Date switch','no script errors',not errs,errs[:2])
        pg.close()
    try:
        sec7()
    except Exception as ex:
        ck('G','section ran to the end',False,str(ex).split(chr(10))[0])
    def sec8():
        pg,errs=page(b)
        pg.evaluate("go('rep');state.report='prod';render()");pg.wait_for_timeout(600)
        cols=pg.evaluate("REPORTS.prod.build().cols.map(c=>c.label||c.h||c[0]||'')")
        pg.evaluate("loadLib(LIBS.xlsx).then(()=>{window.__xl.sheets=[]})");pg.wait_for_timeout(500)
        btn=pg.locator('[data-export="xlsx"],[data-export="excel"],[data-export]').first
        if btn.count():btn.click();pg.wait_for_timeout(1200)
        sheets=pg.evaluate("window.__xl.sheets.length")
        ck('Exports','Excel export builds a sheet from the report',sheets>0,sheets)
        ck('Exports','no script errors',not errs,errs[:2])
        pg.close()
    try:
        sec8()
    except Exception as ex:
        ck('H','section ran to the end',False,str(ex).split(chr(10))[0])
    b.close()
out={'run_at':time.strftime('%Y-%m-%d %H:%M'),'app':APP,'results':R,'summary':{k:sum(1 for r in R if r['result']==k) for k in ['PASS','FAIL','SKIPPED']}}
print(json.dumps(out,indent=1))
