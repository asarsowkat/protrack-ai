"""Reference cases for the Finance formula sign-off. Injects one synthetic project with round numbers
into the running app (nothing is saved) and compares every formula with a hand calculation.
The same cases are written out in the 'Formula reference for Finance' document."""
import sys,json,time
from playwright.sync_api import sync_playwright
APP=sys.argv[1] if len(sys.argv)>1 else 'index.html';R=[]
def ck(case,name,got,exp,tol=0.005):
    ok=(got is None and exp is None) or (got is not None and exp is not None and abs(got-exp)<=tol*max(1,abs(exp)))
    R.append({'area':case,'check':name,'result':'PASS' if ok else 'FAIL','expected':exp,'actual':got})
SETUP="""(()=>{
  const p={id:'REF',name:'Reference project',short:'REF',sector:PROJECTS[0].sector,region:PROJECTS[0].region,city:PROJECTS[0].city,
    start:'2026-09-01',finish:'2026-09-30',value:0.1,status:'Active',pm:'Ref PM',eng:'Ref Eng',foremen:['Ref Foreman'],
    milestones:[{n:'TCC',t:'TCC',plan:'2026-09-15',act:'2026-09-15'}]};
  PROJECTS.push(p);
  ACTS.push({id:'REF-A',p:'REF',cls:'CON',disc:'Civil',area:'Zone R',wbs:'Ref works',name:'Concrete pour',uom:'m3',
    qty:1000,bmh:2000,pp:0.5,pw:100000,priorQty:0,bs:'2026-09-01',bf:'2026-09-30',crew:[['Carpenter',10]],equip:[],pace:1,dailyPlan:1000/26});
  DB.dprs.push({id:'REF-1',p:'REF',date:'2026-09-10',foreman:'Ref Foreman',status:'Approved',audit:[],
    lines:[{act:'REF-A',qty:50,labour:[{cat:'Carpenter',count:10,reg:8,ot:2}],subs:[],equip:[]}]});
  _lines=null;return rateAt('Carpenter','2026-09-10');
})()"""
with sync_playwright() as p:
    b=p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg=b.new_page();pg.route('**/*',lambda r:r.abort() if r.request.url.startswith('http') else r.continue_())
    pg.goto('file://'+APP);pg.wait_for_timeout(800)
    pg.fill('#lgId','asarudeen@company.com');pg.fill('#lgPw','ProTrack@2026');pg.click('#lgBtn');pg.wait_for_timeout(1300)
    rate=pg.evaluate(SETUP)
    L="DB.dprs.find(d=>d.id==='REF-1').lines[0]"
    a="ACTS.filter(a=>a.p==='REF')"
    # 1 manhours, earned, productivity
    ck('C1 Productivity','manhours = 10 x (8 + 2)',pg.evaluate(f"mhOf({L})"),100)
    ck('C1 Productivity','earned manhours = 50 / 0.5',pg.evaluate(f"earnedOf({L})"),100)
    ck('C1 Productivity','productivity index = 100 / 100',pg.evaluate(f"lpi({L})"),1.0)
    # 2 cost
    ck('C2 Labour cost','cost = 10 x rate x (8 + 1.5 x 2)',pg.evaluate(f"costOf({L})"),10*rate*11)
    # 3 earned value at a date inside the window
    e=pg.evaluate(f"evm({a},'2026-09-21')")
    ck('C3 Earned value','BAC = price weight 100,000',e['bac'],100000)
    ck('C3 Earned value','PV = 100,000 x 20/29 days',e['pv'],100000*20/29)
    ck('C3 Earned value','EV = 100,000 x 50/1000',e['ev'],5000)
    ck('C3 Earned value','AC = cost of the one report',e['ac'],10*rate*11)
    ck('C3 Earned value','SPI = EV / PV',e['spi'],5000/(100000*20/29))
    ck('C3 Earned value','CPI = EV / AC',e['cpi'],5000/(10*rate*11))
    x=pg.evaluate(f"eacOf(evm({a},'2026-09-21'))")
    ck('C3 Earned value','EAC = BAC / CPI',x['eac1'],100000/(5000/(10*rate*11)))
    # 4 zero denominators
    z=pg.evaluate(f"evm({a},'2026-08-31')")
    ck('C4 Edge cases','before the baseline starts PV = 0',z['pv'],0)
    ck('C4 Edge cases','with PV = 0 the app shows SPI = 0 (Finance: should be "not applicable")',z['spi'],0)
    ck('C4 Edge cases','with AC = 0 the app shows CPI = 0 (Finance: should be "not applicable")',z['cpi'],0)
    # 5 billing: progress beyond cap, TCC achieved, retention capped, advance recovery
    pg.evaluate(f"(()=>{{{L}.qty=900;_lines=null;const p=PROJECTS.find(x=>x.id==='REF');p.billing={{v:2,adv:{{pct:10,recover:10}},ret:{{pct:10,cap:5,tcc:50,fac:50}},phases:{{ENG:{{cap:90,rel1:'TCC',pct1:10,rel2:'',pct2:0}},PRC:{{cap:90,rel1:'TCC',pct1:10,rel2:'',pct2:0}},CON:{{cap:80,rel1:'TCC',pct1:10,rel2:'FAC',pct2:10}},TC:{{cap:80,rel1:'TCC',pct1:10,rel2:'FAC',pct2:10}}}}}}}})()")
    bl=pg.evaluate("(()=>{const r=billing(PROJECTS.find(x=>x.id==='REF'),'2026-09-21');return {contract:r.contract,billable:r.billable,held:r.held,released:r.released,recovered:r.recovered,net:r.net}})()")
    ck('C5 Billing','contract (sum of price weights) = 100,000',bl['contract'],100000)
    ck('C5 Billing','billable = min(earned 90,000, cap 80,000) + TCC release 10,000',bl['billable'],90000)
    ck('C5 Billing','retention held = min(10% x 90,000, 5% x 100,000)',bl['held'],5000)
    ck('C5 Billing','retention released at TCC = 50% x 5,000',bl['released'],2500)
    ck('C5 Billing','advance recovered = min(10,000, 10% x 90,000)',bl['recovered'],9000)
    ck('C5 Billing','invoiceable = 90,000 - 5,000 + 2,500 - 9,000',bl['net'],78500)
    # 6 cap of 0% (v2.4 rule)
    pg.evaluate("PROJECTS.find(x=>x.id==='REF').billing.phases.CON.cap=0")
    ck('C6 Zero cap','0% cap: billable = TCC release only, 10,000',pg.evaluate("billing(PROJECTS.find(x=>x.id==='REF'),'2026-09-21').billable"),10000)
    # 7 submitted reports count
    pg.evaluate(f"(()=>{{DB.dprs.find(d=>d.id==='REF-1').status='Submitted';{L}.qty=50;_lines=null}})()")
    ck('C7 Report status','a Submitted (not yet approved) report already counts in EV',pg.evaluate(f"evm({a},'2026-09-21').ev"),5000)
    pg.evaluate("(()=>{DB.dprs.find(d=>d.id==='REF-1').status='Draft';_lines=null})()")
    ck('C7 Report status','a Draft report does not count',pg.evaluate(f"evm({a},'2026-09-21').ev"),0)
    b.close()
out={'run_at':time.strftime('%Y-%m-%d %H:%M'),'carpenter_rate':rate,'results':R,'summary':{k:sum(1 for r in R if r['result']==k) for k in ['PASS','FAIL']}}
print(json.dumps(out,indent=1))
