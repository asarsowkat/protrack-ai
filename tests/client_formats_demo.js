/* ProTrackAI v3.45: client report formats (Settings → Client report formats), the pages the planning engineer enters in the
   client report, the review before an export, and the client report as PowerPoint, Word and PDF. Acceptance checks for the
   demo page. How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste
   this whole file. It saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms)),keep=saveFile,keepToast=toast,toasts=[];
  const set=(el,v)=>{el.value=v;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))};
  const files={};const grab=()=>{saveFile=async(n,b)=>{files[n]=b}};
  try{
    const sa=me().id,U=DB.master.users,r=relRows().find(x=>x.kind==='client'),pid=r.project_id,t=r.period_type,per=r.period,pl=teamOf(pid,'plan')[0],pmU=U.find(u=>u.role==='pm'&&u.active!==false&&onProject(u,pid));window.toast=m=>toasts.push(m);
    await loadLib(LIBS.zip);
    ok('1. Version 3.45 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=45,APP_VERSION);
    // 2-6: the formats
    state.adminTab='crf';state.crfEdit=null;go('admin');await wait(80);const adm=$('#view').innerText,sec=crfRows().find(x=>x.sample);
    ok('2. Settings → Client report formats: the built-in standard format and the SAMPLE SEC weekly format (pages and headings only)',/Client report formats/.test(adm)&&/ProTrack standard client report/.test(adm)&&!!sec&&/SAMPLE/.test(sec.name)&&sec.customer===projById(pid).client&&sec.sections.some(s=>s.src==='manual:table'&&/HSE/.test(s.title)),sec&&sec.name);
    const auto0=crfFor(pid,t),rmx=crfFor('RMX','week');await crfPick('RMX',sec.id);const picked=crfFor('RMX','week');await crfPick('RMX',null);
    ok('3. A report uses its project\'s chosen format, else its customer\'s, else the standard one',auto0===sec&&rmx===CRF_STD&&picked===sec&&crfFor('RMX','week')===CRF_STD);
    const bad=[crfCheck(Object.assign({},sec,{style:Object.assign({},sec.style,{c1:'green'})})),crfCheck(Object.assign({},sec,{sections:[{key:'a',title:'X',src:'manual:table',cols:[]}]})),crfCheck(Object.assign({},sec,{sections:[{key:'a',title:'X',src:'auto:nothing'}]}))];
    as(pl.id);const ns=await crfSave(crfBlank());const nsMsg=toasts.pop()||'';as(sa);
    ok('4. The checks: colours, table columns, sources; only the super admin keeps formats',/hex codes/.test(bad[0])&&/column headings/.test(bad[1])&&/unknown source/.test(bad[2])&&!ns&&/Only the super admin/.test(nsMsg),bad);
    const nf=crfBlank();nf.name='Monthly report for Saudi Aramco (SAMPLE)';nf.customer='Saudi Aramco';nf.periods=['month'];await crfSave(nf);
    ok('5. A format for another customer applies to its projects, for its reports only',crfFor('JWP','month').name===nf.name&&crfFor('JWP','week')===CRF_STD);
    /* a client's PowerPoint drawn here: cover, a table page, a pictures page, thank you */
    await loadLib(LIBS.pptx);const PP=new PptxGenJS();PP.layout='LAYOUT_WIDE';PP.defineSlideMaster({title:'M',objects:[{rect:{x:0,y:0,w:13.3,h:0.3,fill:{color:'40916C'}}},{text:{text:'Classified as Public (sample)',options:{x:0.3,y:7,w:6,h:0.3}}}]});
    let s1=PP.addSlide({masterName:'M'});s1.addText('Sample project (SAMPLE)',{x:1,y:2,w:8,h:1});s1=PP.addSlide({masterName:'M'});s1.addText('HSE Summary',{x:0.4,y:0.3,w:8,h:0.6});s1.addTable([[{text:'Classification'},{text:'This week'},{text:'Project to date'}],[{text:'Fatalities'},{text:'0'},{text:'0'}]],{x:0.4,y:1.2,w:8});
    s1=PP.addSlide({masterName:'M'});s1.addText('Site Pictures',{x:0.4,y:0.3,w:8,h:0.6});s1=PP.addSlide({masterName:'M'});s1.addText('Thank you',{x:0.4,y:3,w:8,h:1});
    const deck=await PP.write({outputType:'blob'}),DF=await crfFromPptx(new File([deck],'Client weekly report 12-Oct-26.pptx')),hs=DF.sections.find(x=>x.title==='HSE Summary');
    ok('6. A format drafted from a client\'s PowerPoint: the pages in order, table headings as columns, pictures and closing pages, the footer',
      DF.sections.map(x=>x.src).join()==='auto:cover,auto:contents,manual:table,auto:photos,auto:thanks'&&!!hs&&hs.cols.join('|')==='Classification|This week|Project to date'&&/Classified as Public/.test(DF.style.footer)&&!crfCheck(DF),DF.sections.map(x=>x.title+'→'+x.src));
    // 7-11: the pages in the client report
    as(pl.id);state.clTab='fmt';openClientRelease(pid,t,per);await wait(200);const P0=$('#crPanel').innerText;
    ok('7. The client report has a Client format and export tab: every page with its source and state, and the count of pages not updated',/Client format: SEC weekly progress report \(SAMPLE format\)/.test(P0)&&/not updated/.test(P0)&&document.querySelectorAll('#crPanel .crpg').length===sec.sections.length);
    const hse=sec.sections.find(x=>/HSE/.test(x.title)),ds=sec.sections.find(x=>x.title==='Design Status'),ou=sec.sections.find(x=>/Outage/.test(x.title)),ex=sec.sections.find(x=>x.src==='auto:info');
    set($(`[data-crpc="${hse.key}|0|1"]`),'0');set($(`[data-crpc="${hse.key}|7|1"]`),'0.12 (sample)');set($(`[data-crpt="${ds.key}"]`),'# Engineering\nAll design works completed (sample)');
    const na=$(`[data-crpna="${ou.key}"]`);na.checked=true;na.dispatchEvent(new Event('change',{bubbles:true}));const rv=$(`[data-crprev="${ex.key}"]`);rv.checked=true;rv.dispatchEvent(new Event('change',{bubbles:true}));
    [...document.querySelectorAll('#sheet button')].find(b=>/^Save draft$/i.test(b.textContent.trim())).click();await wait(700);
    const R=relRows().find(x=>x.kind==='client'&&x.project_id===pid&&x.period===per),PG=R.narrative.pages||{};
    ok('8. Entered pages are saved with the report: the HSE table (its rows listed by the format), the text, not applicable, and the reviewed ticks',PG[hse.key]&&PG[hse.key].rows[0].join('|')==='Fatalities|0|'&&PG[hse.key].rows.length===8&&/All design works completed/.test(PG[ds.key].text)&&PG[ou.key].st==='na'&&R.narrative.review[ex.key]===true,Object.keys(PG));
    const doc=await crDoc(pid,t,per),st=k=>doc.pages.find(x=>x.s.key===k).state.s;
    ok('9. Each page\'s state: from ProTrack, entered, not applicable, and not updated (nothing entered, no data in ProTrack)',st(ex.key)==='auto'&&st(hse.key)==='manual'&&st(ou.key)==='na'&&st(sec.sections.find(x=>/Correspondence/.test(x.title)).key)==='empty'&&doc.bad.length>0&&doc.bad.every(x=>['empty','nodata','carried'].includes(x.state.s)),doc.bad.map(x=>x.s.title));
    R.status='Released';const nxt=recentWeeks(1)[0]>per?recentWeeks(1)[0]:'2026-W42',C=crPagesOf(pid,t,nxt,null),cs=crState(hse,C.pages[hse.key],true);R.status='Draft';
    ok('10. The next period starts from the last released report\'s pages, marked carried (not updated) until changed',C.pages[hse.key]&&C.pages[hse.key].carried&&cs.s==='carried'&&/carried from/.test(cs.l),cs.l);
    as(pmU.id);openClientRelease(pid,t,per);await wait(100);const dis=$(`[data-crpt="${ds.key}"]`).disabled,pk=await crfPick(pid,null);const pkMsg=toasts.pop()||'';as(pl.id);
    ok('11. Someone who does not prepare the client report cannot change its pages or its format',dis&&!pk&&/Only those who prepare/.test(pkMsg));
    // 12-17: review and the files
    openClientRelease(pid,t,per);await wait(100);$('[data-crxopen]').click();await wait(400);const dlg=$('#crxDlg').innerText;
    ok('12. Before an export: the disclaimer to review and validate the complete report, every page\'s state, and the pages not updated by name',/Disclaimer/.test(dlg)&&/review and validate the complete report/.test(dlg)&&/not updated/.test(dlg)&&/List of Correspondence/.test(dlg)&&/marked DRAFT/.test(dlg));
    $('#crxCopy').value='client';$('[data-crxgo]').click();await wait(100);const refused=/Tick that you reviewed and validated/.test(toasts.pop()||'');$('#crxDlg').remove();
    ok('13. A client copy needs the confirmation',refused);
    grab();await crExport(pid,t,per,'pptx','review',false);await crExport(pid,t,per,'docx','client',true);await crExport(pid,t,per,'pdf','client',true);saveFile=keep;
    const nm=Object.keys(files),pp=files[nm.find(n=>/\.pptx$/.test(n))],z=await JSZip.loadAsync(await pp.arrayBuffer()),sl=Object.keys(z.files).filter(k=>/^ppt\/slides\/slide\d+\.xml$/.test(k)).sort((a,b)=>+a.match(/\d+/)[0]-+b.match(/\d+/)[0]);
    const tx=[];for(const k of sl)tx.push([...(await z.file(k).async('string')).matchAll(/<a:t>([^<]*)<\/a:t>/g)].map(m=>m[1]).join(' '));
    ok('14. PowerPoint: a slide a page in the format\'s order, the review copy marks the pages not updated, DRAFT while not approved',sl.length>=sec.sections.length&&/Content/.test(tx[1])&&/Project Main Highlights/.test(tx[2])&&tx.some(x=>/NOT UPDATED/.test(x))&&tx.some(x=>/DRAFT/.test(x))&&/Thank you/.test(tx[tx.length-1])&&/\(review copy\)\.pptx$/.test(nm.find(n=>/\.pptx$/.test(n))),{slides:sl.length});
    const dz=await JSZip.loadAsync(await files[nm.find(n=>/\.docx$/.test(n))].arrayBuffer()),dx=await dz.file('word/document.xml').async('string'),ft=(await Promise.all(Object.keys(dz.files).filter(k=>/word\/footer\d*\.xml$/.test(k)).map(k=>dz.file(k).async('string')))).join('');
    ok('15. Word: the pages as numbered headings, the HSE table with its columns, the footer of the format; a client copy has no NOT UPDATED marks',/HSE \(Health, Safety and Environment\) Summary/.test(dx)&&/Classification/.test(dx)&&/This week/.test(dx)&&/Classification footer as required by the client/.test(ft)&&!/NOT UPDATED/.test(dx));
    const lib=await pvPdfLib(),pdf=await lib.getDocument({data:new Uint8Array(await files[nm.find(n=>/\.pdf$/.test(n))].arrayBuffer())}).promise;
    ok('16. PDF: the cover and a page or more per page of the format',pdf.numPages>=sec.sections.length,pdf.numPages);
    const L=(DB.crExports||[]).filter(x=>x.project_id===pid&&x.period===per);openClientRelease(pid,t,per);await wait(100);
    ok('17. Every export is logged (who, file, review or client copy, the pages not updated) and listed in the tab',L.length===3&&L[0].copy==='review'&&L[1].copy==='client'&&L[1].pages_not_updated.length===doc.bad.length&&/Client copy, Word/.test($('#crPanel').innerText),L.map(x=>x.file+'/'+x.copy));
    {const x=document.querySelector('#sheet [data-close]');if(x)x.click()}
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keep;window.toast=keepToast;{const o=document.getElementById('crxDlg');if(o)o.remove()}try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Client report formats and exports: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__cfChecks=res;try{sessionStorage.setItem('cfChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
