/* ProTrackAI v3.15, invoice register dates and phases, and the cash-inflow forecast: acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. It needs an internet connection (SheetJS loads from cdnjs). */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const wait=ms=>new Promise(r=>setTimeout(r,ms)),near=(a,b,t=1)=>Math.abs(a-b)<=t;
  try{
    state.uid='U28';state.role='sa';state.scope='ALL';SCOPE=scopeIds();await loadLib(LIBS.xlsx);seedHistories();invSampleDates();
    const P='RMX',p=projById(P);state.impPid=P;
    // the template
    let blob=null;const of=saveFile;saveFile=async(n,b)=>{blob=b};await invoiceTemplate();saveFile=of;
    const head=XLSX.utils.sheet_to_json(XLSX.read(await blob.arrayBuffer(),{type:'array'}).Sheets.Invoices,{header:1})[4];
    ok('The template has the phase and the actual submission, approval and collection dates',['Phase','Submission date','Approval date','Collection date'].every(h=>head.includes(h)),head);
    // reading a register
    const rows=[['INV-1','2026-03-01','Progress',PHASES[0][1],100,100,'2026-03-02',90,'2026-03-20',90,'2026-04-25',''],
      ['INV-2','2026-04-01','Progress','Construction',200,200,'2026-04-02',150,'',0,'',''],
      ['INV-3','2026-04-01','Progress',PHASES[2][1],200,200,'2026-04-10',150,'2026-04-05',0,'',''],
      ['INV-4','2026-04-01','Progress','Painting',50,50,'2026-04-02',0,'',0,'',''],
      ['INV-5','2026-04-01','Progress',PHASES[1][1],50,50,'2099-01-01',0,'',0,'',''],
      ['INV-6','2026-02-01','Advance','',300,300,'2026-02-01',300,'2026-02-05',300,'2026-03-01','']];
    const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.aoa_to_sheet([['x'],['y'],['z'],[],head,...rows]),'Invoices');
    document.body.insertAdjacentHTML('beforeend','<div id="invBox" hidden></div>');await handleInvFile(new File([XLSX.write(wb,{bookType:'xlsx',type:'array'})],'reg.xlsx'));
    const I=state.inv,e=no=>(I.rows.find(r=>r.no===no)||{}).err||'';
    ok('A valid row keeps its phase and its three actual dates',!e('INV-1')&&I.rows[0].phase===PHASES[0][0]&&I.rows[0].sub_date==='2026-03-02'&&I.rows[0].appr_date==='2026-03-20'&&I.rows[0].coll_date==='2026-04-25');
    ok('Refused: an approved amount without its approval date',/Approval date missing/.test(e('INV-2')),e('INV-2'));
    ok('Refused: approved before it was submitted',/Approved before it was submitted/.test(e('INV-3')),e('INV-3'));
    ok('Refused: a phase that is not in the payment terms',/is not one of/.test(e('INV-4')),e('INV-4'));
    ok('Refused: an actual date in the future',/in the future/.test(e('INV-5')),e('INV-5'));
    ok('An advance needs no phase',!e('INV-6')&&invBucket(I.rows.find(r=>r.no==='INV-6'))==='ADV');
    const old=XLSX.utils.book_new();XLSX.utils.book_append_sheet(old,XLSX.utils.aoa_to_sheet([['Invoice number','Invoice date','Type','Invoice amount (SAR)','Submitted amount (SAR)','Approved amount (SAR)','Collected amount (SAR)'],['O-1','2026-03-01','Progress',100,100,100,100]]),'Invoices');
    await handleInvFile(new File([XLSX.write(old,{bookType:'xlsx',type:'array'})],'old.xlsx'));
    ok('A register in the earlier layout still loads, with a note that the invoice date is used',!state.inv.rows[0].err&&/invoice date is used/.test(state.inv.rows[0].warn||''));
    state.inv=null;document.querySelector('#invBox')?.remove();
    // status by phase
    const S=invPhaseStatus(P),R=invOf(P),tot=k=>S.reduce((t,x)=>t+(+x[k]||0),0);
    ok('Invoicing status by phase adds up to the register (submitted, approved, collected)',near(tot('sub'),R.reduce((t,r)=>t+(+r.sub||+r.amount||0),0))&&near(tot('appr'),R.reduce((t,r)=>t+(+r.appr||0),0))&&near(tot('coll'),R.reduce((t,r)=>t+(+r.coll||0),0)));
    const PV=phaseValues(P);ok('Phase values add up to the client contract value (original + approved by the client)',near(PHASES.reduce((t,[k])=>t+PV.val[k],0),contractOf(P).rev_client,2));
    // the running forecast
    const F=cashForecast(P),Rw=cashRows(F),actByM={};R.forEach(r=>{if(+r.coll>0){const m=ym(r.coll_date||r.date);actByM[m]=(actByM[m]||0)+(+r.coll)}});
    ok('Running project: actual collections by month come from the register\'s collection dates',F.mode==='running'&&Object.entries(actByM).every(([m,v])=>near(F.actual[m]||0,v)));
    const due=R.reduce((t,r)=>t+Math.max(0,(+r.appr>0?+r.appr:(+r.sub||+r.amount||0))-(+r.coll||0)),0);
    ok('Invoices not yet collected are forecast after the payment period',near(Object.values(F.outstanding).reduce((a,b)=>a+b,0),due)&&Object.keys(F.outstanding).every(m=>m>=ym(ASOF)));
    ok('The balance of each phase is invoiced from this month on, never in the past',Object.keys(F.fc.inv).every(m=>m>=ym(ASOF))&&F.fc.left<1);
    ok('The baseline plan collects the whole client contract value (no retention held at the end)',near(Rw[Rw.length-1].cumPlan,F.contract,F.contract*(+billOf(p).ret.pct||0)/100+2));
    const qF=cashForecast('QOT');ok('With an updated schedule the balance follows it, and says so',/updated schedule of/.test(qF.basis));
    // the payment period
    const b0=JSON.parse(JSON.stringify(p.billing||{}));p.billing=Object.assign({},p.billing||{},{pay:{days:15}});const F15=cashForecast(P);p.billing=Object.assign({},p.billing,{pay:{days:120}});const F120=cashForecast(P);p.billing=b0;
    const firstCol=G=>Object.keys(G.fc.col).sort()[0];ok('A longer payment period moves the collections later',firstCol(F120)>firstCol(F15),[firstCol(F15),firstCol(F120)]);
    // a new project: nothing invoiced
    const keep=DB.invoices[P];DB.invoices[P]=[];const N=cashForecast(P);DB.invoices[P]=keep;
    ok('New project: the whole inflow from the client baseline and the payment terms',N.mode==='new'&&/client baseline/.test(N.basis)&&near(Object.values(N.fc.col).reduce((a,b)=>a+b,0),N.contract,N.contract*(+billOf(p).ret.pct||0)/100+2));
    // the page
    state.scope=P;SCOPE=scopeIds();go('cash');await wait(400);
    ok('Invoices & Cash Flow → Cash-inflow forecast opens with its chart, phases and months',/Cash-inflow forecast/.test($('#view').innerText)&&!!$('#cashChart')&&/Invoicing status by phase/.test($('#view').innerText)&&/month by month/i.test($('#view').innerText));
    blob=null;saveFile=async(n,b)=>{blob=b};await cashExport(P);saveFile=of;const xw=XLSX.read(await blob.arrayBuffer(),{type:'array'});
    ok('Export: Monthly invoicing, Cash inflow and Phases sheets',xw.SheetNames.join()==='Monthly invoicing,Cash inflow,Phases');
    const mi=XLSX.utils.sheet_to_json(xw.Sheets['Monthly invoicing'],{header:1})[3];ok('The Monthly invoicing sheet has planned, invoiceable, submitted and approved columns',['Planned invoice (original baseline)','Invoiceable (actual progress)','Submitted (register)','Approved (register)'].every(h=>mi.includes(h)),mi);
    const M=invMonthly(P,cashForecast(P)),subR=R.reduce((t,r)=>t+((r.sub_date||r.date)<=ASOF?(+r.sub||+r.amount||0):0),0),apR=R.reduce((t,r)=>t+(+r.appr||0),0);
    ok('Monthly invoicing: submitted and approved to date equal the register',Math.abs(M.subToDate-subR)<1&&Math.abs(M.apprToDate-apR)<1,{sub:M.subToDate,subR});
    ok('Monthly invoicing: planned to date follows the baseline plan and invoiceable never goes negative',M.rows.every(r=>r.plan>=0&&(r.ivb==null||r.ivb>=0))&&Math.abs(M.planToDate-Object.entries(cashForecast(P).plan.inv).filter(([m])=>m<=ym(ASOF)).reduce((t,[,v])=>t+v,0))<1);
    ok('Months invoiced counts the past months with invoiceable value that had an invoice',M.monthsHit<=M.months&&M.missed.length===M.months-M.monthsHit);
    ok('The page shows Monthly invoicing with its chart and a download button',/Monthly invoicing/.test($('#view').innerText)&&!!$('#invChart'));
    go('inv');await wait(300);ok('The invoice register page shows the status by phase and the dates',/Invoicing status by phase/.test($('#view').innerText)&&/Type and phase/.test($('#view').innerText));
    ok('The menu has Cash-inflow forecast under Invoices & Cash Flow (no longer planned)',NAV_ALL.includes('cash')&&SCREENS.includes('cash')&&navOn('cash'));
    const fm=DB.master.users.find(u=>u.role==='foreman');state.uid=fm.id;state.role='foreman';ok('A foreman does not see it',!navOn('cash'));state.uid='U28';state.role='sa';
    state.adm={type:'projects',id:P};state.impPid=P;ok('Payment terms take the client\'s payment period',/Client pays within/.test(billingEditor(p)));
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Invoices and cash inflow: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__ciChecks=res;try{sessionStorage.setItem('ciChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
