/* ProTrackAI v3.27, the release strategy and RASA across every module. Acceptance checks for the demo page. How to run:
   open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this whole file. It
   saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms));
  const txt=h=>String(h||'').replace(/<[^>]+>/g,' ').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/\s+/g,' ').trim();
  const A=async q=>{let a=answer(q);if(a&&typeof a.then==='function')a=await a;return a||''};
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'),pm=U.find(u=>u.role==='pm'&&u.active),fm=U.find(u=>u.role==='foreman'&&u.active),
    eng=U.find(u=>u.role==='eng'&&u.active&&accessIds(u).includes('RMX')),co=U.find(u=>u.role==='costing'&&u.active&&accessIds(u).includes('RMX'));
  try{
    as(sa.id);
    // ---- the release strategy
    const c0=glCfg();ok('1. Defaults: four stages, every module live, nothing hidden (as before v3.27)',c0.stages.length===4&&c0.current===4&&GL_MODULES.every(m=>glLive(m.k))&&!c0.hide_menu,c0);
    const bad=[[{...c0,stages:[...c0.stages,...c0.stages]},'Between 1 and 6'],[{...c0,map:{...c0.map,boq:5}},'Each module needs a stage'],[{...c0,current:5},'Live up to'],
      [{...c0,stages:[{n:1,name:'A',date:'2027-03-01'},{n:2,name:'B',date:'2027-01-01'},{n:3,name:'C'},{n:4,name:'D'}]},'cannot go live before'],[{...c0,stages:[{n:1,name:' '},...c0.stages.slice(1)]},'needs a name']];
    ok('2. The checks: 1 to 6 stages, each module in a stage, live up to a stage, dates in order, named stages',bad.every(([c,m])=>glCheck(glClean(c)).includes(m)),bad.map(([c])=>glCheck(glClean(c))));
    as(pm.id);ok('3. Only a super admin changes the release strategy',(await glSave({...c0,current:3}))===false&&glCfg().current===4);as(sa.id);
    // ---- every module answers, with the screen's own figures
    const B=boqDB(),pk=B.pkgs.find(k=>k.code==='SS-CIV-01'),rel=B.estimates.find(e=>e.pkg_id===pk.id&&e.status==='Released');
    let rcc=0n;rel.lines.forEach(l=>{if(l.cat==='RCC'&&l.qty!=null)rcc+=dq(l.qty)});const hb=txt(await A('How much reinforced concrete is in the BOQ?'));
    ok('4. BOQ Engine: a quantity from the released estimate lines, per package',hb.includes('SS-CIV-01')&&hb.includes(`Reinforced concrete ${fmt(+dqStr(rcc),2)} m³`)&&/released estimate rev 0/.test(hb),hb);
    const ho=txt(await A('BOQ quantities'));ok('5. BOQ Engine: every package with its estimate, drawings and calculations',B.pkgs.every(k=>ho.includes(k.code))&&/calculations?:/.test(ho),ho);
    const L=dlyVisible(),hd=txt(await A('Delay events'));ok('6. Delay events register: the events of the scope, ongoing and closed, notices due',hd.includes(`${L.length} delay events`)&&hd.includes(`${L.filter(e=>e.status!=='Closed').length} ongoing`),hd);
    const now=ym(ASOF),F=scopeProjects().map(p=>{try{return coForecast(p.id)}catch(e){return null}}).filter(x=>x&&(x.budget.ok||x.moves.length)),hc=txt(await A('Cash-out forecast'));
    ok('7. Cash-out: actual and remaining as the cash-out forecast works them out',hc.includes(coSar(F.reduce((t,x)=>t+x.actualH,0)))&&hc.includes(coSar(F.reduce((t,x)=>t+x.remainingH,0))),hc);
    const n3=scopeProjects().reduce((t,p)=>{const f=cashForecast(p.id);if(!f||f.none)return t;return t+cashRows(f).filter(r=>r.m>=now&&r.m<rasaMAdd(now,3)).reduce((a,r)=>a+r.fcCol,0)},0),hi=txt(await A('Cash-inflow forecast'));
    ok('8. Cash-inflow: the next 3 months as on the cash-inflow forecast page',hi.includes(sar(n3)+' expected in the next 3 months'),[sar(n3),hi]);
    const hf=txt(await A('Give me the cash flow forecast'));ok('9. "Cash flow": inflow, outflow and the net, no longer "no evidence"',/Cash-out/.test(hf)&&/Cash-inflow/.test(hf)&&/Net over the next 3 months/.test(hf)&&!/No evidence/.test(hf));
    const late=scopeProjects().filter(p=>mtSetup(p.id)).reduce((t,p)=>t+mtActivities(p.id).rows.filter(r=>r.late).length,0),hm=txt(await A('Material deliveries'));
    ok('10. Materials: delayed activities as on material tracking',late>0&&(hm.match(/(\d+) activit(?:ies|y) delayed/g)||[]).reduce((t,x)=>t+ +x.match(/\d+/)[0],0)===late,hm);
    let poT=0;SUBS.forEach(sb=>scopeProjects().forEach(p=>posOf(sb,p.id).forEach(o=>poT+=+o.value||0)));const hp=txt(await A('Purchase orders'));ok('11. Subcontract purchase orders: total value',hp.includes(sar(poT)+' in all'),hp);
    const cv=scopeProjects().filter(p=>p.status!=='Cancelled').map(p=>contractOf(p.id,curMonth())).filter(c=>c.orig!=null),hv=txt(await A('What is the contract value?'));
    ok('12. Contract value: original and revised (client-approved change orders)',hv.includes(sar(cv.reduce((t,c)=>t+c.orig,0)))&&hv.includes(sar(cv.reduce((t,c)=>t+c.rev_client,0))),hv);
    const per=rsPeriods('week')[0],km=kmsFor('QOT','planning','week',per),hk=txt(await A('Intermediate milestones'));ok('13. Intermediate milestones as the internal report works them out',km.length>0&&km.every(m=>hk.includes(m.name)),hk);
    const T=phaseTbl('QOT','planning','week',per),hph=txt(await A('Progress by phase'));ok('14. Progress by phase, with the daily-report comparison for site phases',hph.includes(`overall ${fmt(T.act,1)}% actual against ${fmt(T.plan,1)}% plan`)&&/daily reports/.test(hph),hph);
    const E=epReportStats('QOT','planning','week',per),he=txt(await A('E&P progress'));ok('15. E&P progress from the same updated schedule',he.includes(`engineering ${fmt(E.ENG.pct,1)}%`),he);
    const R=rsPeriod('week',per,[...SCOPE]),hr=txt(await A('Reporting status'));ok('16. Reporting status for the last week that ended',hr.includes(`${R.done} of ${R.total}`),hr);
    // ---- documents
    const hl=txt(await A('Contract documents'));ok('17. Document rack: the current contract documents and how many have their text read',hl.includes(`${docsReadable().filter(d=>docRowOfKey(d.project_id,d.box_key)==='contract').length} current contract document`)&&/text read for RASA/.test(hl),hl);
    const ht=await A('What is the time bar for a notice of claim according to the contract?');ok('18. The contract text is quoted with the document and the page, words marked',/Clause 20\.1 Notice of Claim/.test(txt(ht))&&/C01/.test(ht)&&/page 3/.test(txt(ht))&&/<mark>/.test(ht)&&/does not interpret contract terms/.test(ht),txt(ht));
    const p0=projById('RMX'),b0=billOf(p0),hre=txt(await A('What does the contract say about retention?'));
    ok('19. The sample contract follows the project\'s own terms in Settings',/Clause 14\.9 Retention Money/.test(hre)&&(+b0.ret.pct?hre.includes(`Retention of ${b0.ret.pct}%`):/No retention money/.test(hre)),hre);
    as(co.id);const f=new File(['MINUTES OF MEETING (test file)\n\nItem 4. The Employer agreed to hand over the substation plot by 15 November 2026.\n\nItem 5. Site working hours during Ramadan are 08:00 to 14:00.'],'MOM 12.txt',{type:'text/plain'});
    const up=await docUpload('RMX','C10',f,{title:'Minutes of meeting 12 (test)',category:'Meeting minutes',status:'For information'});await wait(1200);
    const nd=(DB.docs||[]).find(d=>d.title==='Minutes of meeting 12 (test)'),m=nd&&docTextMeta(nd.id);ok('20. An uploaded file has its text read for RASA at once',!!up&&!!m&&m.status==='Read'&&m.pages===1&&m.unit==='part',m);
    const hw=txt(await A('When will the substation plot be handed over according to the documents?'));ok('21. RASA quotes the uploaded file',/Minutes of meeting 12 \(test\)/.test(hw)&&/15 November 2026/.test(hw)&&/part 1/.test(hw),hw);
    as(eng.id);let thrown='';try{await docIndex(nd)}catch(x){thrown=x.message}ok('22. Only the people who keep a box (or a super admin) read its text',/Only the people who keep this box/.test(thrown),thrown);
    ok('23. Who cannot read a box gets none of its text: a site engineer reads no contract document',docsReadable().every(d=>docRowOfKey(d.project_id,d.box_key)!=='contract')&&!/Clause 20\.1/.test(txt(await A('What is the time bar for a notice of claim according to the contract?'))));
    // ---- find
    as(sa.id);const hx=txt(await A('find QOT-TL-CIV-101'));ok('24. "find": a drawing by its number, with the screen that opens it',/Drawing QOT-TL-CIV-101 rev B/.test(hx)&&/Drawing QOT-TL-CIV-101 rev C/.test(hx),hx);
    const hz=txt(await A('find PO-2025-118'));ok('25. "find": a purchase order by its number',/PO-2025-118: /.test(hz),hz);
    ok('26. An unknown question: no answer and nothing found, so "no evidence" (or the language model on the demo page)',answer('What colour is the site office?')==null&&(await rasaFind('What colour is the site office?',false))==null);
    // ---- going live stage by stage
    const n0=glAudit().length;await glSave({...glCfg(),current:3,hide_menu:true},'Stage 3 live');
    ok('27. Saved and recorded: live up to stage 3, the BOQ Engine (stage 4) not live',glCfg().current===3&&!glLive('boq')&&glLive('claims')&&glAudit().length===n0+1&&glAudit()[0].note==='Stage 3 live');
    as(pm.id);const hn=txt(await A('BOQ quantities'));ok('28. Others get no answer about a module not live yet: its stage is named',/BOQ Engine is not live yet/.test(hn)&&/Stage 4/.test(hn)&&!/SS-CIV-01/.test(hn),hn);
    renderNav();ok('29. The menu hides it (the option is on)',![...document.querySelectorAll('#nav [data-go="boq"]')].length);
    rasaChips();ok('30. RASA\'s suggestions leave it out',![...document.querySelectorAll('#aiChips .chip')].some(b=>b.textContent==='BOQ quantities'));
    ok('31. "find" does not search it',!/QOT-TL-CIV-101/.test(txt(await A('find QOT-TL-CIV-101'))));
    ok('32. The help names what is live and what comes later',/BOQ Engine \(Stage 4\)/.test(txt(RASA_NOEV_HELP()))&&/Daily Reports/.test(txt(RASA_NOEV_HELP())));
    as(sa.id);renderNav();const hs=await A('BOQ quantities');ok('33. A super admin can still ask, to test it before go-live: the answer says so',/SS-CIV-01/.test(txt(hs))&&/data-rasagl="test"/.test(hs)&&!![...document.querySelectorAll('#nav [data-go="boq"]')].length);
    await glSave({...glCfg(),map:{...glCfg().map,invoices:4},current:3,hide_menu:false});ok('34. The language model on the demo page sees the live modules only',!('billing' in aiContextSafe('invoice'))&&aiContextSafe('x').modules.notLiveYet.some(x=>/Invoices/.test(x)));
    as(pm.id);ok('35. Questions of a module not live yet, answered before v3.27 too (invoicing), wait for it',/Invoices & Cash Flow is not live yet/.test(txt(await A('Invoicing and collection'))));
    // ---- unchanged
    as(sa.id);await glSave({...glCfg(),map:{...glCfg().map,invoices:3},current:4});
    ok('36. Live again: the earlier answers are unchanged (invoicing names the invoice register)',/invoice register/.test(await A('Invoicing and collection'))&&!/not live yet/.test(await A('Invoicing and collection')));
    as(fm.id);ok('37. Role limits stay: a foreman gets no cash, delay or document answers',/Not available for your role/.test(await A('Cash-out forecast'))&&/Not available for your role/.test(await A('Delay events'))&&/Not available for your role/.test(await A('What does the contract say about retention?')));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{as(sa.id);try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`RASA across modules and release strategy: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__rasaModChecks=res;try{sessionStorage.setItem('rasaModChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
