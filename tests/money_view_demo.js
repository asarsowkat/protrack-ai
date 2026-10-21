/* ProTrackAI v3.28.3, cost and billing figures only with the right to see them (money.view). Acceptance checks for the demo
   page. How to run: open demo.html (or index.html), sign in with the demo Super Admin account (U28), open the browser
   console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then reloads the
   page. It needs an internet connection (SheetJS, PptxGenJS and JSZip). */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const wait=ms=>new Promise(r=>setTimeout(r,ms)),as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';state.execProj=null;state.report=null;SCOPE=scopeIds()};
  const U=DB.master.users,on=(r,p)=>U.find(u=>u.role===r&&u.active!==false&&(u.projects||[]).includes(p));
  const sm=on('sm','RMX'),eng=on('eng','RMX'),fm=on('foreman','RMX'),pm=on('pm','RMX');
  const MONEY=/SAR|\bCPI\b|\bEAC\b|\bVAC\b|Labour cost|Contract value|Earned value/;
  const view=()=>$('#view').innerText,hits=t=>(t.match(/.{0,40}(SAR|\bCPI\b|\bEAC\b|\bVAC\b|Labour cost|Contract value).{0,30}/g)||[]);
  const keepSave=saveFile;let got=null;
  const capture=async fn=>{got=null;saveFile=async(name,blob)=>{got={name,blob}};try{await fn()}finally{saveFile=keepSave}return got};
  const COSTREP=['eac','unitrate','invoice','cash'];
  try{
    ok('0. The demo has a site manager, site engineer, foreman and project manager on Riyadh Metro',!!(sm&&eng&&fm&&pm),[sm&&sm.id,eng&&eng.id,fm&&fm.id,pm&&pm.id]);
    as(sm.id);ok('0a. The site manager has no right to see cost and billing figures; the project manager has it',!can('money.view')&&(as(pm.id),can('money.view')));

    /* 1. All reports and the Full report pack */
    as(sm.id);const C=roleCfg(),keepRep=C.reports.sm.slice();C.reports.sm=[...new Set(keepRep.concat(COSTREP))];
    ok('1. A cost or billing report cannot be opened without the right, even when ticked for the role',COSTREP.every(k=>!reportAllowed(k)),COSTREP.filter(reportAllowed));
    go('rep');await wait(200);ok('1a. The report list leaves them out',COSTREP.every(k=>!document.querySelector(`[data-rep="${k}"]`)));
    C.reports.sm=keepRep;
    await loadLib(LIBS.xlsx);
    let f=await capture(()=>exportRep('pack')),wb=XLSX.read(await f.blob.arrayBuffer());
    const allowed=Object.keys(REPORTS).filter(reportAllowed).map(k=>REPORTS[k].sheet);
    ok('1b. The Full report pack holds only the reports the site manager may open',JSON.stringify(wb.SheetNames)===JSON.stringify(allowed),{pack:wb.SheetNames,allowed});
    const packTxt=wb.SheetNames.map(n=>XLSX.utils.sheet_to_csv(wb.Sheets[n])).join('\n');
    ok('1c. No sheet of the pack has a cost or billing column',!/SAR|Labour budget|,CPI,|Contract value/.test(packTxt),hits(packTxt));
    const pp=REPORTS.projprog.build(),rg=REPORTS.regprog.build(),pl=REPORTS.projlist.build();
    ok('1d. Progress by project, by region and the Project list are built without BAC, CPI, contract and expected value',![pp,rg,pl].some(r=>r.cols.some(c=>/BAC|CPI|value/i.test(c.h))),[pp,rg,pl].map(r=>r.cols.filter(c=>/BAC|CPI|value/i.test(c.h)).map(c=>c.h)));
    ok('1e. A cost report gives RASA nothing without the right',repSnapshot('eac')===null&&repSnapshot('projprog')&&!JSON.stringify(repSnapshot('projprog')).match(/CPI|BAC/));
    as(pm.id);f=await capture(()=>exportRep('pack'));wb=XLSX.read(await f.blob.arrayBuffer());
    ok('1f. With the right: every report in the pack, with its cost columns',wb.SheetNames.length===Object.keys(REPORTS).length&&REPORTS.projprog.build().cols.some(c=>c.h==='CPI')&&repSnapshot('eac')!==null,wb.SheetNames.length);

    /* 2. Live summary */
    for(const u of [sm,eng]){as(u.id);state.execProj='RMX';state.execTab='proj';go('exec');await wait(300);
      ok(`2. Live summary, project view (${ROLES[u.role]}): no Cost (CPI) gauge, EAC, VAC or contract value`,!MONEY.test(view()),hits(view()));
      state.execProj=null;go('exec');await wait(300);ok(`2a. Live summary list and critical projects (${ROLES[u.role]}): no CPI or SAR`,!MONEY.test(view()),hits(view()))}
    as(pm.id);state.execProj='RMX';state.execTab='proj';go('exec');await wait(300);
    ok('2b. With the right: the project view keeps the CPI gauge, EAC, VAC and contract value',/Cost \(CPI\)/.test(view())&&/EAC SAR/.test(view())&&/Contract value SAR/.test(view()));

    /* 3. Dashboard */
    as(sm.id);go('dash');await wait(300);ok('3. Dashboard (site manager): no EV or PV in SAR, no CPI column, no regional contract value',!/SAR/.test(view())&&!/>CPI</.test($('#view').innerHTML),hits(view()));
    as(pm.id);go('dash');await wait(300);ok('3a. With the right: the dashboard keeps EV, PV and CPI',/EV SAR/.test(view())&&/CPI/.test(view()));

    /* 4. Early warnings, bottlenecks and project flags, with a CPI under 0.95 */
    const keepFc=forecast;forecast=p=>({...keepFc(p),cpi:0.85});
    try{as(sm.id);const w=warnings(),k=projKPI(projById('RMX'));
      ok('4. Without the right: no cost warning, no cost bottleneck, CPI does not flag a project',!w.some(x=>/CPI/.test(x.ind)||/SAR/.test(x.act))&&!bottlenecks(projById('RMX')).some(b=>/CPI/.test(b.h)),w.filter(x=>/CPI/.test(x.ind)));
      const c0=k.crit;as(pm.id);ok('4a. With the right: the cost warning, with its overrun in SAR, and the flag',warnings().some(x=>/CPI/.test(x.ind)&&/SAR/.test(x.act))&&projKPI(projById('RMX')).crit===c0+1)}
    finally{forecast=keepFc}

    /* 5. Presentation */
    as(sm.id);state.deck=null;go('deck');await wait(300);
    ok('5. The site manager is not offered the Unit rate, EAC or Invoiceable value slides',['unitrate','eac','invoice'].every(k=>!document.querySelector(`[data-dslide="${k}"]`)&&!deckSlideOk(k))&&!!document.querySelector('[data-dslide="kpi"]'));
    const D=deckState();DECK_SLIDES.forEach(([k])=>D.pick[k]=1);D.charts=false;
    f=await capture(()=>buildDeck());await loadLib(LIBS.zip);
    const z=await JSZip.loadAsync(await f.blob.arrayBuffer()),sl=Object.keys(z.files).filter(n=>/ppt\/slides\/slide\d+\.xml$/.test(n));
    let deckTxt='';for(const n of sl)deckTxt+=((await z.file(n).async('string')).match(/<a:t>([^<]*)<\/a:t>/g)||[]).join(' ');
    ok('5a. Every slide ticked, charts off: 11 slides (the S-curve needs charts) plus the cover and closing, none with SAR, CPI, EAC or VAC',sl.length===13&&!/SAR|CPI|EAC|VAC/.test(deckTxt),{slides:sl.length,hits:hits(deckTxt.replace(/<[^>]+>/g,' '))});
    as(pm.id);state.deck=null;go('deck');await wait(300);ok('5b. With the right: all 15 slides offered',DECK_SLIDES.every(([k])=>!!document.querySelector(`[data-dslide="${k}"]`)));

    /* 6. Daily reports: the new report form and a report's subcontractor line */
    const d=DB.dprs.find(x=>x.p==='RMX'&&x.lines.some(l=>subFlat(l).some(u=>u.count||u.qty)));
    for(const u of [fm,eng]){as(u.id);state.form=null;go('new');await wait(300);
      ok(`6. New report form (${ROLES[u.role]}): no labour cost`,!/Labour cost|SAR/.test(view()),hits(view()));
      const h=d.lines.map((l,i)=>lineHTML(l,i,d.lines.length,d)).join('');
      ok(`6a. A report's subcontractor line (${ROLES[u.role]}): the PO number, no rate or cost`,!/SAR/.test(h)&&/PO-/.test(h),h.match(/.{0,60}PO-.{0,40}/))}
    as(pm.id);const h2=d.lines.map((l,i)=>lineHTML(l,i,d.lines.length,d)).join('');
    ok('6b. With the right: the subcontractor line keeps its PO rate and cost',/per .{1,12} = SAR/.test(h2));
    /* only foremen and site engineers create reports, so the site engineer is given the right for this check */
    const keepRight=rightOf;rightOf=(k,...x)=>k==='money.view'?true:keepRight(k,...x);
    try{as(eng.id);state.form=null;go('new');await wait(300);ok('6c. A site engineer given the right sees the labour cost on the new report form',/Labour cost/.test(view()))}
    finally{rightOf=keepRight}

    /* 7. Settings → Role access names the cost and billing reports */
    as('U28');ok('7. Role access marks the four cost and billing reports as needing the right',(roleAccessHTML().match(/only for people given the right to see cost and billing figures/g)||[]).length===COSTREP.length*SITE_ROLES.length);
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keepSave;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const fl=res.filter(r=>r.result==='FAIL').length;console.log(`Cost and billing figures by right: ${res.length-fl} passed, ${fl} failed. Restoring the demo data and reloading…`);
  window.__mvChecks=res;try{sessionStorage.setItem('mvChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
