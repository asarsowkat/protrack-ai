/* ProTrackAI v3.28 (v3.28.1: tender stages), the Project list report. Acceptance checks for the demo page. How to run: open demo.html, sign in with
   the demo Super Admin account (U28), open the browser console and paste this whole file. It saves this browser's demo data
   first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms));
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'),pm=U.find(u=>u.role==='pm'&&u.active),eng=U.find(u=>u.role==='eng'&&u.active),keepSave=saveFile;let got=[];
  const B=()=>REPORTS.projlist.build(),reset=()=>{state.plReg=state.plSec=state.plSt=state.plTen='ALL'};
  try{
    as(sa.id);reset();const R=B(),p=projById('JBS'),r=R.rows.find(x=>x.proj===p.short);
    ok('1. One row per project in the scope, any status',R.rows.length===scopeProjects().length,R.rows.length);
    ok('2. Tender no, PE number, short name, status, region, sector',r.te===p.te&&r.pe===pcode(p)&&r.status===p.status&&r.region===regName(p)&&r.sector===secById(p.sector).name);
    ok('3. Project manager, scheduling engineers and costing engineers of the project',r.pm===p.pm&&r.plan===teamOf('JBS','plan').map(u=>u.name).join(', ')&&r.cost===teamOf('JBS','costing').map(u=>u.name).join(', '));
    const P=progIds(['JBS'],projEvm(['JBS']));ok('4. Latest progress as the project-wise report: planned, actual, variance, SPI, and where it comes from',r.pp===P.plan&&r.ap===P.act&&Math.abs(r.vp-(P.act-P.plan))<1e-9&&/Updated schedule of/.test(r.src),[r.pp,P.plan]);
    const nx=msOf(p).filter(m=>!m.act).sort((a,b)=>String(a.fc||a.plan).localeCompare(String(b.fc||b.plan)))[0];ok('5. The next key milestone not yet achieved, with plan, forecast and status',!!nx&&r.ms.startsWith(nx.n)&&r.msp===nx.plan&&r.msf===(nx.fc||null)&&r.mss===msState(nx).t,[r.ms,nx&&nx.n]);
    const dd=DB.dprs.filter(d=>d.p==='JBS'&&d.status!=='Draft').map(d=>d.date).sort().pop();ok('6. Last daily report: the latest one submitted, and days since',r.dpr===dd&&r.dprAge===diffDays(dd,TODAY));
    const w=relRows().filter(x=>x.project_id==='JBS'&&x.kind==='planning'&&x.period_type==='week'&&x.status==='Released').sort((a,b)=>b.period.localeCompare(a.period))[0];
    ok('7. Last weekly, monthly and monthly cost reports: the latest released, with the release date',r.wk.startsWith(perLabel('week',w.period))&&/released/.test(r.wk)&&/released|None released/.test(r.mo)&&/released|None released/.test(r.co),[r.wk,r.mo,r.co]);
    // filters
    state.plReg=p.region;const fr=B();ok('8. Region filter',fr.rows.length===scopeProjects().filter(x=>x.region===p.region).length&&fr.rows.every(x=>x.region===regName(p)));
    reset();state.plSec=p.sector;const fs=B();ok('9. Sector filter',fs.rows.length===scopeProjects().filter(x=>x.sector===p.sector).length);
    reset();state.plSt='On hold';const fh=B();state.plSt='Active';const fa=B();ok('10. Status filter, with every status offered',fh.rows.length===scopeProjects().filter(x=>x.status==='On hold').length&&fa.rows.length===scopeProjects().filter(x=>x.status==='Active').length&&['Pre-award','Active','On hold','Completed','Cancelled'].every(x=>fa.controls.includes(`>${x}<`)));
    state.plReg=p.region;state.plSt='Active';const both=B();ok('11. Filters combine',both.rows.every(x=>x.region===regName(p)&&x.status==='Active'));reset();
    // the screen and the menu
    renderNav();ok('12. In the menu under Projects & Handover',!!document.querySelector('#nav [data-navrep="projlist"]'));
    state.report='projlist';go('rep');await wait(200);const sel=$('[data-repctl="plReg"]');sel.value=p.region;sel.dispatchEvent(new Event('change',{bubbles:true}));await wait(200);
    ok('13. The region filter works on the screen',$('#view table tbody').querySelectorAll('tr').length===scopeProjects().filter(x=>x.region===p.region).length&&/of \d+ project/.test($('.repctl').innerText));reset();render();
    // exports
    saveFile=async(n,b)=>{got.push({n,b})};await exportRep('xlsx');await exportRep('pdf');saveFile=keepSave;
    const wb=XLSX.read(new Uint8Array(await got[0].b.arrayBuffer()),{type:'array'}),aoa=XLSX.utils.sheet_to_json(wb.Sheets['Project list'],{header:1});
    ok('14. Excel: one sheet with every column',!!wb.Sheets['Project list']&&aoa[5].length===29&&aoa[5].includes('Last monthly cost report')&&aoa.length>=6+R.rows.length);
    const lib=await pvPdfLib(),pdf=await lib.getDocument({data:new Uint8Array(await got[1].b.arrayBuffer())}).promise,pg=await pdf.getPage(1);
    ok('15. PDF on an A3 page, so the 29 columns are readable',Math.round(pg.view[2])===1191&&Math.round(pg.view[3])===842);
    // roles
    as(pm.id);ok('16. A project manager sees only the projects in his access',B().rows.length===accessIds().length&&B().rows.every(x=>accessIds().includes(PROJECTS.find(q=>q.short===x.proj).id)));
    as(eng.id);ok('17. Site roles do not get it unless the super admin adds it in Role access',!reportAllowed('projlist'));
    // RASA
    as(sa.id);const h=String(answer('Show me the project list')).replace(/<[^>]+>/g,' ');ok('18. RASA answers "project list" with the counts and each project, and opens the report',new RegExp(`${R.rows.length} projects`).test(h)&&/Open the Project list/.test(h));
    const he=String(answer(`project list for the ${regById(p.region).name} region`)).replace(/<[^>]+>/g,' ');ok('19. RASA applies a region named in the question',he.includes(`${regById(p.region).name} Region`)&&he.includes(p.short));
    ok('20. RASA still answers "which projects are behind" as before',!/Open the Project list/.test(String(answer('which projects are behind'))));
    // v3.28.1: tender stages
    reset();const tp=te=>PROJECTS.find(p=>p.te===te),t1=tp('TE2501'),t2=tp('TE2502'),t3=tp('TE2503'),t4=tp('TE2504');
    ok('21. Sample tenders on the demo page, marked SAMPLE: L1 and L2 awaiting the NOA, one NOA received (active), one cancelled',!!(t1&&t2&&t3&&t4)&&t1.status==='Pre-award'&&rankOf(t1)==='L1'&&t2.status==='Pre-award'&&rankOf(t2)==='L2'&&!!t3.award&&t3.status==='Active'&&t4.status==='Cancelled'&&[t1,t2,t3,t4].every(p=>/SAMPLE/.test(p.name)));
    const row=te=>B().rows.find(x=>x.te===te),r1=row('TE2501'),r3=row('TE2503');
    ok('22. Bid position, tender stage, NOA date, client and expected value',r1.bid==='L1'&&r1.ten==='L1, awaiting NOA'&&r1.noa===null&&r1.client===t1.client&&r1.exp===+t1.expected&&r3.ten.startsWith('NOA received')&&r3.noa===t3.award&&row('TE2502').ten==='L2, awaiting NOA'&&row('TE2504').ten.startsWith('Cancelled'));
    state.plTen='pre';const pre=B().rows;state.plTen='pre-L1';const l1=B().rows;state.plTen='pre-L2';const l2=B().rows;state.plTen='noa';const nr=B().rows;state.plTen='none';const nn=B().rows;
    ok('23. Tender stage filter: pre-award (L1 and L2), L1, L2, NOA received, not from the Tender list',pre.length===scopeProjects().filter(p=>p.te&&p.status==='Pre-award').length&&l1.every(x=>x.ten==='L1, awaiting NOA')&&l2.every(x=>x.ten==='L2, awaiting NOA')&&nr.every(x=>x.ten.startsWith('NOA received'))&&nn.every(x=>x.te==='—')&&l1.length+l2.length===pre.length);
    reset();state.plSt='Pre-award';ok('24. The status filter Pre-award gives the same projects',B().rows.map(x=>x.pe).join()===pre.map(x=>x.pe).join());reset();
    const n0=tenderActLocal('register',null,{te_number:'TE2599',name:'Test tender (test)',bid_rank:'L2',rank_note:'test',region:PROJECTS[0].region,sector:PROJECTS[0].sector});
    SCOPE=scopeIds();const a0=row('TE2599');tenderActLocal('noa',n0.id,{award_on:addDays(TODAY,-1)});const b0=row('TE2599');
    ok('25. A tender registered in the Tender register shows at once as L2 awaiting NOA; recording the NOA makes it NOA received and active',a0&&a0.ten==='L2, awaiting NOA'&&a0.status==='Pre-award'&&b0.ten.startsWith('NOA received')&&b0.status==='Active');
    const hr=String(answer('project list of L2 projects')).replace(/<[^>]+>/g,' ');ok('26. RASA: "project list of L2 projects"',/L2, awaiting NOA/.test(hr)&&hr.includes(t2.short)&&!hr.includes(t1.short));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keepSave;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Project list: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__plChecks=res;try{sessionStorage.setItem('plChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
