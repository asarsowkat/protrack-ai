/* ProTrackAI v3.18, reports in the presentation builder and the Excel download: acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. It needs an internet connection (PptxGenJS and SheetJS). */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const wait=ms=>new Promise(r=>setTimeout(r,ms)),as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()};
  try{
    as('U28');seedHistories();invSampleDates();state.scope='QOT';SCOPE=scopeIds();state.deck=null;go('deck');await wait(200);
    ok('Presentations has a Reports group with the six reports',/Reports/.test($('#view').innerText)&&DECK_REPORTS.every(([k])=>!!document.querySelector(`[data-drep="${k}"]`)));
    const D=deckState();deckRepState(D);const per=relRows().filter(r=>r.project_id==='QOT'&&r.kind==='planning'&&r.period_type==='month'&&r.status==='Released').map(r=>r.period).sort().pop();
    D.rper=per;D.rproj='QOT';const el=document.querySelector('[data-drep="rint"]');el.checked=true;el.dispatchEvent(new Event('change',{bubbles:true}));await wait(100);
    ok('Ticking a report shows its parts, all ticked',document.querySelectorAll('[data-dpart^="rint|"]').length===6&&[...document.querySelectorAll('[data-dpart^="rint|"]')].every(x=>x.checked));
    DECK_REPORTS.forEach(([k])=>D.rep[k]=1);
    let S=deckSections(D);const by=k=>S.find(s=>s.key===k),bt=(k,t)=>(by(k)||{blocks:[]}).blocks.find(b=>b.title===t);
    ok('One section per report for the chosen project (productivity for the scope)',S.length===6&&S.every(s=>s.key==='rprod'||(s.p&&s.p.id==='QOT')),S.map(s=>s.key));
    ok('Internal report: the released report with headline figures, milestones and manpower',/Released rev/.test(bt('rint','Report').lines[0])&&!!bt('rint','Headline figures')&&!!bt('rint','Contract milestones')&&bt('rint','Manpower').rows.length===4);
    ok('Client report section is built (or says there is none for the month)',!!by('rcli')&&by('rcli').blocks.length>0);
    ok('Invoicing and cash flow: KPIs, monthly invoicing, status by phase, cash inflow and charts',['Invoicing','Monthly invoicing','Invoicing status by phase','Cash inflow month by month','Cash inflow'].every(t=>by('rcash').blocks.some(b=>b.title===t)));
    const M=invMonthly('QOT',cashForecast('QOT'));ok('Monthly invoicing in the deck has one row per month of the page',bt('rcash','Monthly invoicing').rows.length===M.rows.length);
    const cs=by('rcost');ok('Cost report: by WBS head and the margin by column, or none for the month',/No cost report/.test(cs.blocks[0].lines?cs.blocks[0].lines[0]:'')||(!!bt('rcost','By WBS head')&&bt('rcost','Contract value and gross margin by column').rows.length===3));
    ok('Change order details: summary, every log row, contract breakdown',(()=>{const L=voLatest('QOT',per);return !L.b||(bt('rco','Change orders and claims').rows.length===L.rows.length&&!!bt('rco','Contract value breakdown'))})());
    ok('Productivity details: by activity and by foreman',!!bt('rprod','Productivity by activity')||!!bt('rprod','Productivity by foreman, last 30 days'));
    D.parts.rint.mp=0;D.parts.rint.ms=0;S=deckSections(D);ok('An unticked part is left out',!bt('rint','Manpower')&&!bt('rint','Contract milestones'));D.parts.rint.mp=1;D.parts.rint.ms=1;
    D.rproj='ALL';state.scope='ALL';SCOPE=scopeIds();S=deckSections(D);ok('Every project in the scope: one section per report and project',S.filter(s=>s.key==='rint').length===scopeProjects().filter(p=>p.status!=='Cancelled').length);
    state.scope='QOT';SCOPE=scopeIds();D.rproj='QOT';
    // the Excel download
    let blob=null,name='';const of=saveFile;saveFile=async(n,b)=>{blob=b;name=n};await deckExcel();saveFile=of;await loadLib(LIBS.xlsx);
    const wb=XLSX.read(await blob.arrayBuffer(),{type:'array'});ok('Excel: one sheet per report and project, named for them',wb.SheetNames.length===6&&wb.SheetNames.includes('Internal '+pcode(projById('QOT'))),wb.SheetNames);
    const a=XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames.find(n=>/^Invoicing/.test(n))],{header:1});ok('Excel: the sheet holds the tables with their headers',a.some(r=>r[0]==='Monthly invoicing')&&a.some(r=>r[0]==='Month'&&r[1]==='Planned invoice'));
    // the PowerPoint
    D.charts=false;Object.keys(D.pick).forEach(k=>D.pick[k]=0);DECK_REPORTS.forEach(([k])=>D.rep[k]=0);saveFile=async(n,b)=>{blob=b};await buildDeck();const size0=blob&&blob.size;
    DECK_REPORTS.forEach(([k])=>D.rep[k]=1);await buildDeck();saveFile=of;const size1=blob&&blob.size;
    ok('PowerPoint: the reports are added as slides',size1>size0*1.5,{without:size0,with:size1});
    // rights
    const eng=DB.master.users.find(u=>u.role==='eng');as(eng.id);ok('A role without cost figures gets no invoicing, cost or change order reports',!deckRepOk('rcash')&&!deckRepOk('rcost')&&!deckRepOk('rco')||rasaMoneyOk());as('U28');
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Presentation reports: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__dkChecks=res;try{sessionStorage.setItem('dkChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
