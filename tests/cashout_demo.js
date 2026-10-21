/* ProTrackAI v3.20, Invoices & Cash Flow → Cash-out forecast. Acceptance checks for the demo page: the 12 acceptance tests
   of the specification, then the workflows (Finance import, payment terms, versions, scenarios, reports, access).
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},err=f=>{try{f();return ''}catch(x){return x.message}};
  const M=v=>Math.round(v*1e6*100),U=DB.master.users,sa=U.find(u=>u.role==='sa'&&u.active!==false),co=U.find(u=>isCoord(u)),hd=pccHeads()[0];
  const keepSave=window.saveFile;let saved=[];window.saveFile=async(n,b)=>{saved.push({n,b})};
  const file=(rows,name)=>{const ws=XLSX.utils.aoa_to_sheet([['Project ID / code','Project name','Reporting period','Cumulative actual cash-out','Currency','Source / remarks'],...rows]),wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,ws,'Cash-out');
    return new File([XLSX.write(wb,{type:'array',bookType:'xlsx'})],name||'finance.xlsx')};
  try{
    as(sa.id);await loadLib(LIBS.xlsx);
    /* the 12 acceptance tests of the specification */
    const t1=coReconcile({budgetH:M(200),actualH:M(66),remainingH:M(125)});
    ok('Test 1. Within budget: FAC 191M, headroom 9M, utilization 95.5%, Within Budget',t1.fac===M(191)&&t1.headroom===M(9)&&t1.utilF===95.5&&t1.status==='ok',t1);
    const t2=coReconcile({budgetH:M(200),actualH:M(66),remainingH:M(140)});
    ok('Test 2. Overrun: FAC 206M, overrun 6M, utilization 103%, Forecast Overrun, not reduced to 134M',t2.fac===M(206)&&t2.overrun===M(6)&&t2.utilF===103&&t2.status==='fover'&&t2.fac!==M(200),t2);
    const jdc=coForecast('JDC');as(hd.id);go('cout');state.impPid='JDC';state.coTab='overview';render();
    ok('Test 2. ... and management action is required',jdc.status==='fover'&&/Management action required/.test($('#view').innerText));as(sa.id);
    const t3=coReconcile({budgetH:M(200),actualH:M(205),remainingH:0});
    ok('Test 3. Actual 205M stays 205M: actual overrun 5M, Actual Overrun',t3.fac===M(205)&&t3.actualOver===M(5)&&t3.status==='aover'&&t3.utilA===102.5,t3);
    const B=coBudget('RMX','2026-08'),cr=lastCostRel('RMX'),F4=coForecast('RMX'),poTot=coPos('RMX').reduce((t,x)=>t+coH(x.o.value),0);
    ok('Test 4. PO commitments are not added to the budget; outstanding PO payments count once',B.amount===coH(cr.figures.budget_current)&&F4.budget.amount===B.amount&&F4.fac===F4.actualH+F4.remainingH&&F4.remainingH===F4.outSub+F4.outMat+F4.outCost+F4.outUnord+F4.outOther+F4.payable&&F4.fac!==F4.actualH+F4.remainingH+poTot,{budget:B.amount,poTot});
    const ms=[10,20,20,40,10].map(p=>({basis:'pct',pct:p})),amt=ms.map(m=>coMsAmount(coH(1000000),m));
    ok('Test 5. Milestones 10/20/20/40/10 of SAR 1,000,000',amt.join()===[100000,200000,200000,400000,100000].map(v=>v*100).join()&&amt.reduce((a,b)=>a+b,0)===coH(1000000),amt.map(v=>v/100));
    const L6=[['2026-01',20e6],['2026-02',35e6],['2026-03',53e6],['2026-04',66e6]].map(([period,cum])=>({period,cum})),m6=coMovesOf(L6,true),o6=coMovesOf(L6,false);
    ok('Test 6. Cumulative 20/35/53/66M → monthly 20/15/18/13M (zero opening verified); else the first is an opening balance',m6.map(r=>r.move/100/1e6).join()==='20,15,18,13'&&o6[0].kind==='opening'&&o6[0].move==null&&o6[1].move===M(15));
    /* Test 7: the same file twice, the same period twice (as the super admin: RTT is not in the coordinator's access) */
    as(sa.id);const before=DB.coAct.length,f7=file([['RTT','Ras Tanura TF','2026-04',39000000,'SAR','Back-filled April']],'april.xlsx');
    state.coUp={projects:['RTT'],cutoff:'2026-08'};await coFinFile(f7);const b7=coFinCommitLocal(state.coUp,{});
    ok('Test 7. An import adds the missing month',b7.added===1&&DB.coAct.length===before+1);
    await coFinFile(f7);const e7=err(()=>coFinCommitLocal(state.coUp,{}));await coFinFile(file([['RTT','Ras Tanura TF','2026-04',39000000,'SAR','again']],'april-copy.xlsx'));const e7b=err(()=>coFinCommitLocal(state.coUp,{}));
    ok('Test 7. The same file, or the same period and amount, again adds nothing',/already imported/.test(e7)&&/Nothing new/.test(e7b)&&DB.coAct.length===before+1,[e7,e7b]);
    /* Test 8: a correction keeps the original */
    const orig=coActActive('RTT').find(r=>r.period==='2026-08');await coFinFile(file([['RTT','Ras Tanura TF','2026-08',coH(orig.cum)/100+1500000,'SAR','Finance restatement']],'restate.xlsx'));
    const k8=state.coUp.rows[0].kind,e8=err(()=>coFinCommitLocal(state.coUp,{}));coFinCommitLocal(state.coUp,{correct:true,reason:'Finance added a late bank charge for August'});
    const now8=coActActive('RTT').find(r=>r.period==='2026-08');
    ok('Test 8. A correction needs the workflow; the original is kept, the reason and author recorded, the actual recalculated',k8==='restate'&&/corrections/.test(e8)&&orig.superseded_by===now8.id&&now8.supersedes===orig.id&&now8.reason&&now8.created_by===sa.id
      &&coForecast('RTT').actualH===coH(orig.cum)+coH(1500000)&&DB.coAudit.some(a=>a.project_id==='RTT'&&a.action==='Actual restated'));
    as(sa.id);
    /* Test 9 */
    const t9=coReconcile({budgetH:null,actualH:M(50),remainingH:M(60)}),b9=coBudget('NOPROJECT');
    ok('Test 9. No approved budget: Budget Not Configured; the PO value is not used as a budget',t9.status==='bnc'&&t9.headroom==null&&t9.utilF==null&&!b9.ok&&b9.amount==null);
    /* Test 10 and 11 */
    const paidBefore=coPos('RTT').reduce((t,x)=>t+(x.s.milestones||[]).filter(m=>m.status==='Paid').length,0),F10=coForecast('RTT');
    ok('Test 10. Project-level actuals are not shared out to POs: no milestone is marked paid by an import; the difference is shown in the reconciliation',
      coPos('RTT').reduce((t,x)=>t+(x.s.milestones||[]).filter(m=>m.status==='Paid').length,0)===paidBefore&&F10.diff===F10.actualH-F10.paidPo-F10.booked-F10.paidOther&&F10.recon.some(t=>/Unexplained actual cash-out/.test(t)));
    /* Test 11: Finance pays a milestone (its cumulative rises) and it is marked paid: it leaves the remaining forecast once; the forecast at completion does not move */
    const x11=coPos('JBS')[0],m11=x11.s.milestones.find(m=>m.status!=='Paid'),F11a=coForecast('JBS'),net=coMsNet(coH(x11.o.value),m11),lastA=coActActive('JBS').pop();
    coPoSaveLocal(x11.o.id,{status:'Open',milestones:x11.s.milestones.map(m=>m.id===m11.id?{...m,status:'Paid',paid_date:'2026-08-20',evidence:'PV-TEST',paid_amount:''}:m)},'');lastA.cum=(coH(lastA.cum)+net)/100;
    const F11b=coForecast('JBS');
    ok('Test 11. A paid milestone counts once: the actual rises by it, the remaining forecast falls by it, the forecast at completion and the budget do not move',F11b.remainingH===F11a.remainingH-net&&F11b.actualH===F11a.actualH+net&&F11b.fac===F11a.fac&&F11b.budget.amount===F11a.budget.amount&&F11b.paidPo===F11a.paidPo+net);
    /* Test 12: access */
    const pm=U.find(u=>u.role==='pm'&&accessIds(u).length<PROJECTS.length),other=PROJECTS.find(p=>!accessIds(pm).includes(p.id));as(pm.id);saved=[];
    state.impPid=other.id;state.coTab='overview';go('cout');await new Promise(r=>setTimeout(r,100));await coExcel(other.id);await coPdf(other.id);
    ok('Test 12. Another project\'s figures: not shown, not exported, not changed, whatever the project id',!coSees(other.id)&&state.impPid!==other.id&&!saved.length&&!$('#view').innerText.includes(other.short+' (')
      &&/costing engineers of this project/.test(err(()=>coPoSaveLocal(coPos(other.id)[0].o.id,{milestones:[]},'')))&&/Only the super admin/.test(err(()=>coFinCommitLocal({rows:[]},{}))));
    as(sa.id);
    /* workflows */
    const pl=U.find(u=>u.role==='plan'),cst=U.find(u=>u.role==='costing'&&!isCoord(u)&&accessIds(u).includes('RTT'));as(pl.id);const ePl=err(()=>coFinCommitLocal({rows:[]},{}));as(sa.id);
    ok('13. Only the super admin and the Head Office cost control coordinator import Finance actuals',/Only the super admin/.test(ePl)&&canCoUpload()&&(as(co.id),canCoUpload()));as(sa.id);
    state.coUp={projects:['RMX'],cutoff:'2026-08'};await coFinFile(file([['RMX','x','2026-09',1,'SAR'],['RMX','x','2026-07',-5,'SAR'],['ZZZ','x','2026-07',5,'SAR'],['QOT','x','2026-07',5,'SAR'],['RMX','x','2026-05',5,'USD'],['RMX','x','Q3',5,'SAR']]));
    const R=state.coUp.rows.map(r=>r.err.join(';'));
    ok('14. Row checks: after the cutoff, negative, unknown project, project not chosen, other currency, not a month',/after the reporting cutoff/.test(R[0])&&/negative/.test(R[1])&&/unknown project/.test(R[2])&&/not one of the projects chosen/.test(R[3])&&/USD/.test(R[4])&&/not a month/.test(R[5]),R);
    const odd=XLSX.utils.aoa_to_sheet([['Proj','Mon','Cum Paid SAR'],['RMX','2026-08',1]]),wbo=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wbo,odd,'S');
    state.coUp={projects:['RMX'],cutoff:'2026-08'};await coFinFile(new File([XLSX.write(wbo,{type:'array',bookType:'xlsx'})],'odd.xlsx'));const needMap=!!state.coUp.error;
    state.coUp.map={project:'Proj',period:'Mon',cum:'Cum Paid SAR'};coFinRemap();
    ok('15. Another layout: the columns are mapped by hand, then read',needMap&&state.coUp.rows&&state.coUp.rows[0].kind==='restate');state.coUp=null;
    as(cst.id);const x16=coPos('RTT')[0],ret=x16.s.milestones.find(m=>m.status!=='Paid'),eSum=err(()=>coPoSaveLocal(x16.o.id,{status:'Open',milestones:x16.s.milestones.map(m=>m.id===ret.id?{...m,pct:5}:m)},''));
    const c16=coPoCheck('RTT',{...x16,s:coPoState(x16.o)});
    ok('16. Payment terms: a total other than 100% is flagged as Forecast Incomplete',eSum===''&&c16.issues.some(t=>/must total 100%/.test(t))&&coForecast('RTT').flags.includes('inc'));
    const ePaid=err(()=>coPoSaveLocal(x16.o.id,{status:'Open',milestones:[{name:'Advance',kind:'Advance payment',basis:'pct',pct:100,planned_date:'2026-08-01',pay_days:0,status:'Paid',paid_date:'2026-08-05'}]},''));
    ok('17. A paid milestone needs its Finance evidence',/evidence/.test(ePaid));
    as(sa.id);const x18=coPos('JWP')[0],pm18=x18.s.milestones.find(m=>m.status==='Paid');as(cst.id);
    const e18=err(()=>coPoSaveLocal(x18.o.id,{status:'Open',milestones:x18.s.milestones.map(m=>m.id===pm18.id?{...m,pct:5}:m)},''));
    ok('18. What was paid cannot be changed by changing future assumptions',/is paid: what was paid cannot be changed/.test(e18));as(sa.id);
    /* versions */
    as(co.id);const v=coVerActLocal({action:'create',project_id:'JDC',comments:'September forecast'});const eSelf=err(()=>coVerActLocal({action:'review',id:v.id}));as(sa.id);coVerActLocal({action:'review',id:v.id,note:'Checked'});
    as(hd.id);const ePub=err(()=>coVerActLocal({action:'publish',id:v.id}));coReviewLocal({project_id:'JDC',version_id:v.id,decision:CO_DECISIONS[0],action:'Re-tender the cable supply; owner PM, by 30 Oct 2026'});coVerActLocal({action:'publish',id:v.id});
    ok('19. Versions: draft → reviewed by someone else → published; an overrun is published only after the management review',v.state==='Published'&&/someone else/.test(eSelf)&&/management review/.test(ePub)&&v.fac===coForecast('JDC').fac);
    const v2=coVerActLocal({action:'create',project_id:'JDC'});
    ok('20. A later forecast is a new version; the published one is kept',v2.no===v.no+1&&coVers('JDC').find(x=>x.id===v.id).state==='Published');as(sa.id);
    const Fb=coForecast('RMX'),Fs=coForecast('RMX',{scenario:CO_SCEN_BUILTIN[1]}),Fa=coForecast('RMX');
    ok('21. Scenarios are simulations: the pessimistic one is higher; the official forecast, actuals and budget do not change',Fs.fac>Fb.fac&&Fs.actualH===Fb.actualH&&Fa.fac===Fb.fac&&Fs.budget.amount===Fb.budget.amount);
    /* reports */
    saved=[];await coExcel('RMX');const wb=XLSX.read(await saved[0].b.arrayBuffer(),{type:'array'}),Sm=XLSX.utils.sheet_to_json(wb.Sheets.Summary,{header:1}),fac=Sm.find(r=>r[0]==='Forecast at completion');
    ok('22. The Excel report has every sheet, its header, and the same figures as the screen',['Summary','Monthly cash-out','Actual vs plan','Reconciliation','Budget','PO payment schedule','Uploads and corrections','Version comparison'].every(n=>wb.SheetNames.includes(n))
      &&/Reporting cutoff .* currency SAR .* approved current budget .* forecast version/.test(Sm[1][0])&&fac[1]===Fa.fac/100,fac);
    saved=[];await coPdf('RMX');ok('23. The PDF report is built',saved.length===1&&saved[0].n.endsWith('.pdf')&&saved[0].b.size>2000);
    ok('24. The menu, the right and the screen',DOMAINS.find(d=>d.k==='invoices').items.some(i=>i.v==='cout')&&RIGHTS.some(r=>r[0]==='cashout.keep')&&SCREENS.includes('cout'));
    /* v3.28.2: the sample July version is taken on the v3.21 records, so it no longer counts the other line and the cost report heads both */
    const J=coVers('RMX').find(x=>x.id==='CVRMX1'),FJ=coForecast('RMX',{cutoff:'2026-07'});
    ok('25. Riyadh Metro\'s published July version is within budget, as the July forecast is (v3.28.2)',J&&J.state==='Published'&&J.status==='ok'&&J.fac<=J.budget&&J.fac===FJ.fac,J&&{fac:J.fac,budget:J.budget,status:J.status});
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.saveFile=keepSave;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Cash-out forecast: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__coChecks=res;try{sessionStorage.setItem('coChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
