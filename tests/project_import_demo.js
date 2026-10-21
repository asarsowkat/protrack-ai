/* ProTrackAI v3.13, importing many projects from Excel: acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. It needs an internet connection (SheetJS loads from cdnjs). */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const wait=ms=>new Promise(r=>setTimeout(r,ms));
  try{
    state.uid='U28';state.role='sa';state.scope='ALL';SCOPE=scopeIds();state.adminTab='projects';go('admin');await wait(200);await loadLib(LIBS.xlsx);
    ok('Settings → Projects has Import projects from Excel for the super admin',!!document.querySelector('[data-pjimp]'));
    let blob=null;const of=saveFile;saveFile=async(n,b)=>{blob={n,b}};await pjTemplate(false);saveFile=of;
    const wb=XLSX.read(await blob.b.arrayBuffer(),{type:'array'}),head=XLSX.utils.sheet_to_json(wb.Sheets.Projects,{header:1})[3];
    ok('The template has Projects, How to fill and Lists sheets, with every column',blob.n==='ProTrack_projects_template.xlsx'&&['Projects','How to fill','Lists'].every(s=>wb.SheetNames.includes(s))&&head.length===PJ_COLS.length,wb.SheetNames);
    const m=DB.master,C=m.cities,R=m.regions,S=m.sectors,pm=m.users.find(u=>u.role==='pm'),pl=m.users.find(u=>u.role==='plan'),rows=[];
    for(let i=0;i<120;i++){const c=C[i%C.length],r=R.find(x=>x.id===c.region)||R[0],pre=i%10===0;
      rows.push([pre?'':'PE-'+(500+i),`Sample project ${i+1}`,'',pre?'Pre-award':'Active',r.name,S[i%S.length].name,c.name,'Substation',pre?'':'2026-01-01',pre?'':'2027-12-31',pre?'':50+i,'SEC',c.name,'TE'+(7000+i),pre&&i%20===0?'L2':'L1',40,'2025-12-01',pre?'':'2025-12-20','',pm.email,'',pl.name,i===3?'nobody@x.com':''])}
    rows.push(['PE-900','Bad region','','Active','Mars',S[0].name,C[0].name,'','2026-01-01','2027-01-01',10]);
    rows.push(['PE-901','Bad dates','','Active',R[0].name,S[0].name,C[0].name,'','2026-05-01','2026-01-01',10]);
    rows.push(['PE-505','Duplicate PE','','Active',R[0].name,S[0].name,C[0].name,'','2026-01-01','2027-01-01',10]);
    rows.push([pcode(PROJECTS[0]),'Already there','','Active',R[0].name,S[0].name,C[0].name,'','2026-01-01','2027-01-01',10]);
    rows.push(['PE-902','Pre-award with NOA','','Pre-award',R[0].name,'','','','','','','','','TE9999','L1','','2026-01-01','2026-02-01']);
    const w2=XLSX.utils.book_new();XLSX.utils.book_append_sheet(w2,XLSX.utils.aoa_to_sheet([['x'],['y'],[],head,...rows]),'Projects');
    const file=new File([XLSX.write(w2,{bookType:'xlsx',type:'array'})],'portfolio.xlsx'),before=PROJECTS.length;
    openProjImport();ok('The import opens as a full window',$('#sheet').classList.contains('full'));
    await pjFile(file);const U=state.pjUp,rf=U.rows.filter(r=>r.err&&!r.skip);
    ok('125 rows checked: 120 ready, 1 already in ProTrackAI, 4 refused',U.rows.length===125&&U.rows.filter(r=>!r.err).length===120&&U.rows.filter(r=>r.skip).length===1&&rf.length===4,{n:U.rows.length,refused:rf.map(r=>r.err)});
    ok('Refused rows say why (unknown region, dates, duplicate PE, NOA on a pre-award tender)',/unknown region Mars/.test(rf[0].err)&&/finish date/.test(rf[1].err)&&/appears twice/.test(rf[2].err)&&/pre-award tender has no NOA/.test(rf[3].err));
    ok('A person not found is a warning, not a refusal',U.rows.some(r=>!r.err&&r.warn.some(w=>/nobody@x.com not found/.test(w))));
    document.querySelector('[data-pjgo]').click();await wait(300);ok('Refused rows must be confirmed before anything is created',PROJECTS.length===before);
    $('#pjAck').checked=true;document.querySelector('[data-pjgo]').click();await wait(800);
    ok('120 projects are created in one go',PROJECTS.length-before===120,PROJECTS.length-before);
    const p=projById('PE-501');ok('A project keeps its PE number, status, dates, value, city and tender details',p&&p.status==='Active'&&p.start==='2026-01-01'&&p.value===51&&!!p.city&&p.te==='TE7001'&&p.rank==='L1',p);
    ok('The NOA date also releases the finance WBS on the same date',p.award==='2025-12-20'&&p.fwbs==='2025-12-20');
    ok('The named project manager and planning engineer get access',pm.projects.includes('PE-501')&&pl.projects.includes('PE-501')&&p.pm===pm.name);
    const pre=PROJECTS.find(x=>x.name==='Sample project 1');ok('A pre-award tender without a PE number gets the next number, with its bid position',pre&&isPE(pcode(pre))&&pre.status==='Pre-award'&&pre.rank==='L2',pre&&pcode(pre));
    ok('The upload is a numbered batch in the Import centre',DB.batches.some(b=>b.kind==='projects'&&b.rows_accepted===120&&b.rows_rejected===4)&&IMPORT_KINDS.projects==='Project list');
    ok('The Tender register history records the imported tenders',DB.regAudit.some(a=>a.project_id==='PE-501'&&a.action==='Registered'&&a.note==='From the project list'));
    await pjFile(file);ok('The same list again changes nothing: every row is already in ProTrackAI or refused',state.pjUp.rows.filter(r=>!r.err).length===0);
    blob=null;saveFile=async(n,b)=>{blob={n,b}};await pjTemplate(true);saveFile=of;await pjFile(new File([blob.b],blob.n));
    ok('The current project list downloads in the same layout and uploads back unchanged',state.pjUp.rows.length===PROJECTS.filter(x=>x.status!=='Cancelled').length&&state.pjUp.rows.every(r=>r.skip),{rows:state.pjUp.rows.length});
    const pmU=DB.master.users.find(u=>u.role==='pm');state.uid=pmU.id;state.role='pm';ok('Only a super admin sees the import',(()=>{go('admin');return !document.querySelector('[data-pjimp]')})());
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Project import: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__pjChecks=res;try{sessionStorage.setItem('pjChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
