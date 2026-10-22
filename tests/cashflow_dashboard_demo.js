/* ProTrackAI v3.32, the Cashflow Dashboard. Acceptance checks for the demo page. How to run: open demo.html, sign in with the
   demo Super Admin account (U28), open the browser console and paste this whole file. It saves this browser's demo data first
   and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms)),near=(a,b)=>Math.abs(a-b)<1;
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'),pm=U.find(u=>u.role==='pm'&&u.active),fm=U.find(u=>u.role==='foreman'&&u.active),eng=U.find(u=>u.role==='eng'&&u.active);
  const now=ym(ASOF);
  try{
    as(sa.id);state.cfd=null;renderNav();
    const items=[...document.querySelectorAll('#nav button')].map(b=>b.innerText.trim());const iv=items.indexOf('Invoice register'),ic=items.indexOf('Cashflow Dashboard');
    ok('1. Invoices & Cash Flow -> Cashflow Dashboard, right below the Invoice register',ic>0&&ic===iv+1,items.slice(iv,iv+3));
    const R=cfdCompute(),P=R.P.find(x=>x.p.id==='RMX');
    // inflow and outflow, as the two forecast pages work them out
    const F=cashForecast('RMX'),rows=cashRows(F),C=coForecast('RMX');
    const inAll=rows.reduce((t,r)=>t+r.act+r.fcCol,0),outAll=C.months.reduce((t,r)=>t+(r.actual||0)+(r.forecast||0),0)/100;
    ok('2. Inflow: the invoice register\'s collections (actual) and the cash-inflow forecast, month by month',near(P.rows.reduce((t,r)=>t+r.in,0),inAll)&&rows.every(r=>{const y=P.rows.find(z=>z.m===r.m);return !(r.act+r.fcCol)||(y&&near(y.inA,r.act)&&near(y.inF,r.fcCol))}));
    ok('3. Outflow: Finance\'s cash-out (actual, to the last import) and the cash-out forecast after it',near(P.rows.reduce((t,r)=>t+r.out,0),outAll)&&C.months.every(r=>{const y=P.rows.find(z=>z.m===r.m);return !((r.actual||0)+(r.forecast||0))||(y&&near(y.outA*100,r.actual||0)&&near(y.outF*100,r.forecast||0))}));
    ok('4. Net = inflow - outflow; the cash position is the running total from the project\'s first month',P.rows.every((r,i)=>near(r.net,r.in-r.out)&&near(r.cum,(i?P.rows[i-1].cum:0)+r.net)));
    // finance cost
    const c=cfCfg(),d=P.rows.find(r=>r.net<-1&&r.rate!=null);
    ok('5. Finance cost of a deficit month = deficit x rate / 100 / 12; a surplus month costs nothing',!!d&&near(d.fc,-d.net*d.rate/1200)&&P.rows.filter(r=>r.net>=0).every(r=>r.fc===0),d&&[d.m,d.net,d.rate,d.fc]);
    ok('6. Worked out project by project: one project\'s surplus never lowers another\'s cost',R.M.every(m=>near(m.fc,R.P.reduce((t,x)=>{const y=x.rows.find(z=>z.m===m.m);return t+(y&&y.fc?y.fc:0)},0))));
    ok('7. The demo page has SAMPLE rates: one per actual month and a forecast average',c.sample&&c.fc_avg!=null&&Object.keys(c.rates).length>=6&&R.M.filter(r=>r.m>=now).every(r=>r.rate!=null));
    ok('8. A month from this one onward without its own rate uses the forecast average; an earlier month without one has none',cfRate(cfMAdd(now,3)).src==='avg'&&cfRate('2020-01').src==='none');
    await cfRatesSave({rates:{[cfMAdd(now,1)]:9},fc_avg:7,basis:'month'},'check 9');const R9=cfdCompute(),m9=R9.M.find(r=>r.m===cfMAdd(now,1)),m10=R9.M.find(r=>r.m===cfMAdd(now,2));
    ok('9. The super admin sets a month\'s rate and the forecast average; both apply at once',m9.rate===9&&m9.rsrc==='month'&&m10.rate===7&&m10.rsrc==='avg');
    await cfRatesSave({rates:{},fc_avg:7,basis:'cum'},'check 10');const Rc=cfdCompute(),Pc=Rc.P.find(x=>x.p.id==='RMX');
    ok('10. On the cumulative deficit: interest runs on a negative cash position, nothing on a positive one',Pc.rows.every(r=>r.cum>=0?r.fc===0:(r.rate==null?r.fc==null:near(r.fc,-r.cum*r.rate/1200))));
    ok('11. Every change is recorded with who and what',cfAudit()[0].changes.some(x=>/basis month → cum/.test(x))&&cfAudit()[0].by===sa.name);
    ok('12. The checks: a rate from 0 to 100 % per annum, a month like 2026-09',/0 to 100/.test(cfCheck({rates:{'2026-09':120},fc_avg:null,basis:'month'}))&&/2026-09/.test(cfCheck({rates:{'26-9':5},fc_avg:null,basis:'month'})));
    await cfRatesSave({rates:{[cfMAdd(now,1)]:null},fc_avg:c.fc_avg,basis:'month'},'back');
    // filters
    const reg=projById('RMX').region;state.cfd={reg};const Rr=cfdCompute();
    ok('13. Region filter',Rr.P.length>0&&Rr.P.every(x=>x.p.region===reg));
    state.cfd={sec:projById('JBS').sector};ok('14. Sector filter',cfdCompute().P.every(x=>x.p.sector===projById('JBS').sector));
    state.cfd={pid:'QOT'};ok('15. One project',cfdCompute().P.map(x=>x.p.id).join()==='QOT');
    state.cfd={st:'Active'};ok('16. Project status filter',cfdCompute().P.every(x=>x.p.status==='Active'));
    state.cfd={from:'2026-06',to:'2026-08'};const Rp=cfdCompute();ok('17. Period: only the months chosen, the cash position still from the first month',Rp.M.map(r=>r.m).join()==='2026-06,2026-07,2026-08'&&Rp.P.every(x=>x.win.every(r=>r.m>='2026-06'&&r.m<='2026-08')));
    state.cfd={mode:'actual'};const Ra=cfdCompute();state.cfd={mode:'forecast'};const Rf=cfdCompute();
    ok('18. Actual only and forecast only',Ra.M.every(r=>!r.inF&&!r.outF&&near(r.net,r.inA-r.outA))&&Rf.M.every(r=>!r.inA&&!r.outA&&near(r.net,r.inF-r.outF)));
    state.cfd={both:false};const Rb=cfdCompute();state.cfd=null;const Rd=cfdCompute();
    ok('19. By default only projects with both inflow and outflow; the others are named as left out',Rd.P.every(x=>x.d.inOk&&x.d.outOk)&&Rd.skipped.length>0&&Rb.P.length+Rb.skipped.length>=Rd.P.length);
    ok('20. By project, by sector and by region add up to the total',near(Rd.bySec.reduce((t,g)=>t+g.net,0),Rd.T.net)&&near(Rd.byReg.reduce((t,g)=>t+g.fc,0),Rd.T.fc)&&near(Rd.P.reduce((t,x)=>t+x.in,0),Rd.T.in));
    // the screen
    go('cfd');await wait(400);const v=$('#view').innerText;
    ok('21. The screen: figures, net with surplus or deficit, finance cost, the tables',/Cashflow Dashboard/.test(v)&&/Net cash flow: (surplus|deficit)/.test(v)&&/Finance cost/.test(v)&&/By project/.test(v)&&/By sector/.test(v)&&/By region/.test(v)&&/Month by month/.test(v)&&!!$('#cfdChart'));
    ok('22. A super admin sees the rate fields and Save; the history is there',!!$('[data-cfsave]')&&!!$('#cfAvg')&&/History of the rates/.test(v));
    $('[data-cfdpid="QOT"]').click();await wait(300);ok('23. Tapping a project shows only it',state.cfd&&state.cfd.pid==='QOT'&&cfdCompute().P.length===1);state.cfd=null;
    let saved=null;const keep=saveFile;saveFile=async(n,b)=>{saved={n,b}};await cfdExport();saveFile=keep;
    const wb=saved&&XLSX.read(new Uint8Array(await saved.b.arrayBuffer()),{type:'array'});
    ok('24. Export to Excel: monthly, by project, by sector, by region, project x month, the rates',!!wb&&['Monthly','By project','By sector','By region','Project x month','Interest rates'].every(n=>wb.SheetNames.includes(n)),wb&&wb.SheetNames);
    // who
    as(pm.id);go('cfd');await wait(300);ok('25. A project manager sees it for his projects, read only',canCfdView()&&!$('[data-cfsave]')&&cfdCompute().P.every(x=>accessIds().includes(x.p.id))&&(await cfRatesSave({rates:{},fc_avg:1,basis:'month'}))===false);
    as(fm.id);renderNav();ok('26. Foremen and site engineers do not see it',!canCfdView()&&![...document.querySelectorAll('#nav [data-go="cfd"]')].length&&(as(eng.id),!canCfdView()));
    // RASA
    as(sa.id);const h=String(answer('What is the finance cost on our cash flow?')).replace(/<[^>]+>/g,' ');const R12=cfdCompute(Object.assign(cfdFilter(),{reg:'ALL',sec:'ALL',st:'ALL',pid:'ALL',from:now,to:cfMAdd(now,11),mode:'both',both:true}));
    ok('27. RASA: net cash flow, deficit months and finance cost, as the dashboard',h.includes(sar(R12.T.net))&&h.includes(sar(R12.T.fc))&&/Open the Cashflow Dashboard/.test(h));
    ok('28. RASA still answers "cash flow forecast" with inflow, outflow and the net',/Net over the next 3 months/.test(String(answer('Give me the cash flow forecast'))));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{as(sa.id);state.cfd=null;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Cashflow Dashboard: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__cfdChecks=res;try{sessionStorage.setItem('cfdChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
