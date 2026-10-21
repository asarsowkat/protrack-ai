/* ProTrackAI v3.19, Claims & Variations: the delay events register. Acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},err=f=>{try{f();return ''}catch(x){return x.message}};
  const wait=ms=>new Promise(r=>setTimeout(r,ms)),sa=DB.master.users.find(u=>u.role==='sa'&&u.active!==false);
  try{
    as(sa.id);
    /* 1-3: menu, screen, seed */
    const claims=DOMAINS.find(d=>d.k==='claims');
    ok('1. Claims & Variations lists the Delay events register first',claims.items[0].v==='dly'&&claims.items[0].label==='Delay events register',claims.items.map(i=>i.label));
    go('dly');await wait(300);
    ok('2. The screen opens with its KPIs, the by-project table and the register',/Delay events register/.test($('#view').innerText)&&/Notice not served/.test($('#view').innerText)&&/Delay events by project/.test($('#view').innerText));
    ok('3. The demo holds sample events on four projects',dlyRows().length>=12&&new Set(dlyRows().map(e=>e.project_id)).size===4,{events:dlyRows().length});
    /* 4-6: the worked-out columns */
    const t=TODAY,e1={start_date:addDays(t,-30),status:'Ongoing',time_bar:28,notice_date:addDays(t,-25)},c1=dlyCalc(e1);
    ok('4. Duration till today, notice days used and days against the time bar',c1.duration===30&&c1.used===5&&c1.vs===-23&&c1.left==='served',c1);
    const c2=dlyCalc({start_date:addDays(t,-40),status:'Closed',closed_on:addDays(t,-10),time_bar:14,notice_date:addDays(t,-20)});
    ok('5. A closed event counts to its closing date; a notice after the time bar is late',c2.duration===30&&c2.vs===6&&dlyNotice({start_date:addDays(t,-40),time_bar:14,notice_date:addDays(t,-20)}).k==='late',c2);
    const n1=dlyNotice({start_date:addDays(t,-24),time_bar:28}),n2=dlyNotice({start_date:addDays(t,-40),time_bar:28}),n3=dlyNotice({start_date:addDays(t,-5),time_bar:28});
    ok('6. Days to the notice deadline: 1 to 7 amber, passed red, more green',n1.k==='due'&&n1.c==='a'&&n2.k==='passed'&&n2.c==='r'&&n3.k==='open'&&n3.c==='g',[n1,n2,n3]);
    /* 7-11: the rules */
    const pid=PROJECTS[0].id,f0={name:'Check event',start_date:addDays(t,-10),time_bar:28};
    ok('7. The event name and start date are required',/event name/.test(err(()=>delayActLocal({action:'save',project_id:pid,fields:{start_date:addDays(t,-3)}})))&&/start date/.test(err(()=>delayActLocal({action:'save',project_id:pid,fields:{name:'x'}}))));
    ok('8. Dates in the future are refused',/future/.test(err(()=>delayActLocal({action:'save',project_id:pid,fields:{...f0,notice_date:addDays(t,3)}}))));
    ok('9. A closed event needs its closing date; a closing date needs Closed',/closing date of a closed/.test(err(()=>delayActLocal({action:'save',project_id:pid,fields:{...f0,status:'Closed'}})))&&/only when the event is closed/.test(err(()=>delayActLocal({action:'save',project_id:pid,fields:{...f0,status:'Ongoing',closed_on:addDays(t,-2)}}))));
    ok('10. Negative costs and a bad time bar are refused',/positive/.test(err(()=>delayActLocal({action:'save',project_id:pid,fields:{...f0,vo_add:'-5'}})))&&/whole number/.test(err(()=>delayActLocal({action:'save',project_id:pid,fields:{...f0,time_bar:'2.5'}}))));
    const nextNo=dlyNextNo(pid),nextRef=dlyRows().filter(x=>x.project_id===pid).reduce((m,x)=>Math.max(m,+x.ref||0),0)+1;
    const e=delayActLocal({action:'save',project_id:pid,fields:{...f0,vo_add:'1,250,000',sched_impact:'Not calculated yet'}});
    ok('11. A new event gets the next event number and Ref.; amounts read as numbers, notes kept',e.event_no===nextNo&&e.ref===nextRef&&e.vo_add===1250000&&e.sched_impact==='Not calculated yet',{no:e.event_no,ref:e.ref});
    ok('12. An event number already used on the project is refused',/already used/.test(err(()=>delayActLocal({action:'save',project_id:pid,fields:{...f0,name:'Other',event_no:'event 1'}}))));
    delayActLocal({action:'save',id:e.id,fields:{mitigation:'EOT Claim Approved'},note:'Weekly update'});
    ok('13. Changes are kept in the history with the fields changed',dlyAuditOf(e.id).some(a=>a.action==='Updated'&&a.note==='Weekly update'&&a.detail.changes.includes('mitigation')));
    ok('14. Deleting needs a reason and is kept in the history',/why/.test(err(()=>delayActLocal({action:'delete',id:e.id})))&&(delayActLocal({action:'delete',id:e.id,note:'Entered twice'}),!dlyRows().some(x=>x.id===e.id)&&(DB.dlyAudit||[]).some(a=>a.event_id===e.id&&a.action==='Deleted')));
    /* 15-19: who sees and who keeps */
    ok('15. The right "Keep the delay events register" goes to planning engineers, and to the Head by position',RIGHTS.some(r=>r[0]==='delay.keep'&&r[3].includes('plan'))&&/Head of Planning/.test(RIGHT_POS['delay.keep']||''));
    const pl=DB.master.users.find(u=>u.role==='plan'&&u.active!==false&&!isHead(u)&&accessIds(u).length<PROJECTS.length&&accessIds(u).length);
    if(pl){as(pl.id);const mine=new Set(accessIds()),other=PROJECTS.find(p=>!mine.has(p.id));
      ok('16. A planning engineer sees only the events of the projects in their access',dlyVisible().length>0&&dlyVisible().every(x=>mine.has(x.project_id))&&dlyRows().some(x=>!mine.has(x.project_id)),{access:[...mine]});
      ok('17. ... keeps their own projects and is refused on another',canDlyEdit([...mine][0])&&(!other||/access to this project/.test(err(()=>delayActLocal({action:'save',project_id:other.id,fields:f0})))));
      go('dly');await wait(200);const opts=[...document.querySelectorAll('[data-dlyf=pid] option')].map(o=>o.value).filter(Boolean);
      ok('18. ... and the screen offers only those projects',opts.every(v=>mine.has(v)),opts)}
    else ok('16-18. A planning engineer with part of the portfolio',false,'no such demo user');
    const pm=DB.master.users.find(u=>u.role==='pm'&&u.active!==false);as(pm.id);
    ok('19. A project manager reads the register but cannot change it',canDlyView()&&!canDlyEdit(accessIds()[0])&&/planning engineers of this project/.test(err(()=>delayActLocal({action:'save',project_id:accessIds()[0],fields:f0}))));
    const fm=DB.master.users.find(u=>u.role==='foreman'),en=DB.master.users.find(u=>u.role==='eng'),ro=DB.master.users.find(u=>u.role==='ro');
    as(fm.id);const fmOk=canDlyView();as(en.id);const enOk=canDlyView();as(ro.id);const roOk=canDlyView()&&!canDlyEdit(accessIds()[0]);
    ok('20. Foremen and site engineers do not see it; read-only users read it',!fmOk&&!enOk&&roOk);
    as(sa.id);
    /* 21-26: Excel */
    await loadLib(LIBS.xlsx);const L=dlyRows().filter(x=>x.project_id===pid).sort((a,b)=>a.ref-b.ref),ws=dlySheet(L),hd=DLY_COLS.map((c,i)=>(ws[XLSX.utils.encode_col(i)+'2']||{}).v);
    ok('21. The download keeps the register layout: four groups and the 27 headers over two rows',ws.A1.v==='Claim Contractual Data'&&ws.J1.v==='NOTICE OF CLAIM  DATA'&&ws.P1.v==='Schedule Impact Data'&&ws.V1.v==='Cost Impact Data'&&hd.length===27&&hd[2]==='Claim Event Name'&&hd[26]==='Claim Owner'&&ws['!merges'].length===31);
    ok('22. Dates are Excel dates; the worked-out columns carry working formulas',ws.E4.t==='n'&&ws.E4.z==='dd-mmm-yy'&&/TODAY\(\)/.test(ws.H4.f)&&/K4-E4/.test(ws.M4.f)&&/M4-J4/.test(ws.N4.f)&&/Notice served/.test(ws.O4.f));
    const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,ws,'X');const aoa=XLSX.utils.sheet_to_json(XLSX.read(XLSX.write(wb,{type:'array',bookType:'xlsx'}),{type:'array',cellDates:true}).Sheets.X,{header:1,blankrows:true,raw:true,defval:null});
    const col=k=>DLY_COLS.findIndex(c=>c[0]===k),row=k=>{const r=Array(27).fill(null);Object.entries(k).forEach(([a,b])=>r[col(a)]=b);return r};
    aoa[3][col('mitigation')]='EOT Claim Approved';
    aoa.push(row({event_no:'Event 30',name:'From the workbook',start_date:'15/08/2026',status:'ongoing',time_bar:28,prolong_cost:500000}));
    aoa.push(row({event_no:'Event 31',name:'Bad date',start_date:'31/02/2026'}));
    aoa.push(row({event_no:'Event 30',name:'Same number',start_date:'2026-08-20'}));
    const ex=row({name:'skip me'});ex[0]='Example';aoa.push(ex);
    const P=dlyParse(aoa,pid),bad=P.rows.filter(r=>r.err);
    ok('23. Upload: events matched by number, new ones added, the Example row skipped',P.rows.filter(r=>r.match&&!r.err).length===L.length&&P.rows.some(r=>r.event_no==='Event 30'&&!r.match&&!r.err)&&!P.rows.some(r=>r.name==='skip me'));
    ok('24. Upload: a bad date and a number used twice are refused with their sheet rows',bad.length===2&&bad.some(r=>/not a date/.test(r.err)&&r.row===L.length+5)&&bad.some(r=>/appears twice/.test(r.err)),bad.map(r=>[r.row,r.err]));
    const ws3=XLSX.utils.aoa_to_sheet(aoa),wb3=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb3,ws3,pcode(projById(pid)));const file=new File([XLSX.write(wb3,{type:'array',bookType:'xlsx'})],'delays.xlsx');
    go('dly');await wait(200);await handleDlyFile(file,pid);await wait(200);$('#dlyAck').checked=true;await dlyUploadGo(document.querySelector('[data-dlyupgo]'));await wait(200);
    const b=(DB.batches||[]).filter(x=>x.kind==='delays').slice(-1)[0];
    ok('25. Saving updates and adds the events and logs the upload in the import history',dlyRows().find(x=>x.project_id===pid&&x.ref===1).mitigation==='EOT Claim Approved'&&dlyRows().some(x=>x.name==='From the workbook'&&x.status==='Ongoing'&&x.start_date==='2026-08-15')&&b&&b.rows_rejected===2&&IMPORT_KINDS.delays==='Delay events register');
    await handleDlyFile(file,pid);await wait(200);$('#dlyAck').checked=true;const before=dlyRows().length;await dlyUploadGo(document.querySelector('[data-dlyupgo]'));
    ok('26. The same file again changes nothing',dlyRows().length===before);
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Delay events register: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__dlyChecks=res;try{sessionStorage.setItem('dlyChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
