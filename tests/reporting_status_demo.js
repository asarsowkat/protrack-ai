/* ProTrackAI v3.22, Home → Reporting status, and the executive report held until every project has released.
   Acceptance checks for the demo page. How to run: open demo.html (or index.html) on the demo page, sign in with the demo
   Super Admin account (U28), open the browser console and paste this whole file. It saves this browser's demo data first
   and puts it back at the end, then reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},err=f=>{try{f();return ''}catch(x){return x.message}},wait=ms=>new Promise(r=>setTimeout(r,ms));
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'&&u.active!==false),ex=U.find(u=>u.role==='exec'),rm=U.find(u=>u.role==='rm'),pf=U.find(u=>u.role==='pf'),pmU=U.find(u=>u.role==='pm'),pl=U.find(u=>u.role==='plan'&&!(DB.relApprovers||[]).some(a=>a.user_id===u.id));
  const keepSave=window.saveFile;let saved=[];window.saveFile=async(n,b)=>{saved.push({n,b})};const conf=window.confirm,prm=window.prompt;window.confirm=()=>true;
  try{
    as(sa.id);
    ok('1. Home lists Reporting status after the executive report',DOMAINS.find(d=>d.k==='home').items[1].v==='rs'&&SCREENS.includes('rs'));
    ok('2. Deliverables: the internal report weekly; for a month also the cost report, the change order log, the supplement log and the invoice register',rsDels('week').map(d=>d[0]).join()==='int'&&rsDels('month').map(d=>d[0]).join()==='int,cost,vo,supp,inv');
    ok('3. Due dates: day 7 of the next month; two days after the week ends',rsDue('month','2026-08')==='2026-09-07'&&rsDue('week','2026-W38')===addDays(isoWeekMonday('2026-W38'),8));
    const M=rsPeriod('month','2026-08'),W=rsPeriod('week','2026-W38'),W7=rsPeriod('week','2026-W37');
    ok('4. August: every project released its internal and cost reports, so the monthly executive report is released',M.complete&&M.done===M.total&&M.req.join()==='int,cost');
    ok('5. The invoice register update is tracked, not required: two projects have not updated it',M.rows.filter(r=>r.items.inv.st==='Not updated').length===2&&M.rows.every(r=>r.complete));
    ok('6. Week 38 is held: 4 of 6, one awaiting approval and one draft',!W.complete&&W.done===4&&W.outstanding.map(r=>r.items.int.st).sort().join()==='Draft,Submitted');
    ok('7. Week 37: a returned report is overdue',!W7.complete&&W7.outstanding[0].items.int.st==='Returned'&&W7.outstanding[0].items.int.overdue);
    ok('8. Each item says who prepared and approved it, and whether it was on time',M.rows[0].items.int.by&&M.rows[0].items.int.appr&&M.rows[0].items.int.late===false);
    /* the executive report */
    as(ex.id);state.xrPt='week';state.xrPer='2026-W38';state.xrTab='sum';go('xr');await wait(200);const tx=$('#view').innerText;
    ok('9. An executive sees the weekly report held, without its figures',/Held: the weekly executive report for Week 38/.test(tx)&&!/Progress by project/.test(tx));
    state.xrPt='month';state.xrPer='2026-08';go('xr');await wait(200);
    ok('10. The August monthly executive report opens',!/Held:/.test($('#view').innerText)&&/Executive report · Aug 2026/.test($('#view').innerText));
    as(sa.id);state.xrPt='week';state.xrPer='2026-W38';go('xr');await wait(200);
    ok('11. The super admin sees a preview of the held report, marked held',/Held: the weekly/.test($('#view').innerText)&&/preview/.test($('#view').innerText));
    /* exemptions */
    const jwp=W.outstanding.find(r=>r.items.int.st==='Draft').p.id;
    ok('12. An exemption needs a reason',/reason/.test(err(()=>rsExemptLocal(jwp,'week','2026-W38','',false))));
    as(rm.id);ok('13. Only the super admin or the Head exempts',/Only the super admin or the Head/.test(err(()=>rsExemptLocal(jwp,'week','2026-W38','Site closed for Eid holidays this week',false))));as(sa.id);
    rsExemptLocal(jwp,'week','2026-W38','Site closed for Eid holidays this week',false);const Wx=rsPeriod('week','2026-W38');
    ok('14. The exempted project counts as complete, with its reason',Wx.done===5&&Wx.rows.find(r=>r.p.id===jwp).ex.reason.includes('Eid'));
    const rtt=relRows().find(r=>r.project_id===W.outstanding.find(o=>o.items.int.st==='Submitted').p.id&&r.kind==='planning'&&r.period==='2026-W38');Object.assign(rtt,{status:'Released',approved_by:sa.id,approved_at:'2026-09-22T09:00:00'});
    as(ex.id);go('xr');await wait(200);
    ok('15. Once every project has released (or is exempted), the weekly executive report opens',rsPeriod('week','2026-W38').complete&&!/Held:/.test($('#view').innerText));
    as(sa.id);rsExemptLocal(jwp,'week','2026-W38','',true);
    ok('16. Withdrawing the exemption holds the report again',!rsPeriod('week','2026-W38').complete);
    /* reminders */
    const before=(DB.rsRem||[]).length,ob=(DB.outbox||[]).length;as(rm.id);const regP=W.rows.map(r=>r.p.id).find(id=>accessIds().includes(id)&&!rsPeriod('week','2026-W38').rows.find(r=>r.p.id===id).complete);
    as(pl.id);const ePl=err(()=>rsRemindLocal(jwp,'week','2026-W38',null,''));as(pmU.id);const ePm=err(()=>rsRemindLocal(jwp,'week','2026-W38',null,''));
    ok('17. Planning engineers and project managers do not send reminders',/Only the super admin/.test(ePl)&&/Only the super admin|access/.test(ePm));
    as(sa.id);const r1=rsRemindLocal(jwp,'week','2026-W38',null,'Management meeting on Thursday');
    const plans=teamOf(jwp,'plan').map(u=>u.id),pms=teamOf(jwp,'pm').map(u=>u.id);
    ok('18. A reminder goes to the project\'s planning engineers and its project manager, in the notifications and as an email',r1.to.every(x=>plans.includes(x.id)||pms.includes(x.id))&&r1.to.some(x=>pms.includes(x.id))&&r1.to.some(x=>plans.includes(x.id))
      &&DB.rsRem.length===before+1&&DB.outbox.length===ob+1&&DB.outbox[0].status==='Demo: not sent'&&/reminded/.test(DB.notes[0].text));
    ok('19. Once a day per deliverable',/Already reminded today/.test(err(()=>rsRemindLocal(jwp,'week','2026-W38',null,''))));
    const cr=rsRemindLocal('RTT','month','2026-08',['inv'],''),cs=teamOf('RTT','costing').map(u=>u.id);
    ok('20. A cost-side reminder goes to the costing engineers and the project manager',cr.to.some(x=>cs.includes(x.id))&&!cr.to.some(x=>teamOf('RTT','plan').some(u=>u.id===x.id)));
    const sec=U.find(u=>(DB.relApprovers||[]).some(a=>a.user_id===u.id)),secP=PROJECTS.find(p=>(DB.relApprovers||[]).some(a=>a.user_id===sec.id&&a.region_id===p.region)),other=PROJECTS.find(p=>!(DB.relApprovers||[]).some(a=>a.user_id===sec.id&&a.region_id===p.region));
    as(sec.id);ok('21. The section planning manager reminds the projects of their region only',canRsRemind(secP.id)&&!canRsRemind(other.id));
    as(pf.id);ok('22. A portfolio manager reminds the projects in their access',accessIds().every(id=>canRsRemind(id))&&!PROJECTS.filter(p=>!accessIds().includes(p.id)).some(p=>canRsRemind(p.id)));
    /* rules */
    as(rm.id);ok('23. Only the super admin changes the reporting rules',/Only the super admin/.test(err(()=>rsCfgLocal({month_due_day:5,week_due_days:2,gate:{int:true}}))));as(sa.id);
    rsCfgLocal({month_due_day:7,week_due_days:2,gate:{int:true,cost:true,inv:true}});
    ok('24. Making the invoice register required holds August until it is updated',!rsPeriod('month','2026-08').complete&&rsPeriod('month','2026-08').outstanding.length===2);
    ok('25. The internal report is always required',/always holds/.test(err(()=>rsCfgLocal({month_due_day:7,week_due_days:2,gate:{int:false}}))));
    rsCfgLocal({month_due_day:7,week_due_days:2,gate:{int:true,cost:true}});
    /* screen, scope, export */
    state.rsF={t:'week',per:'2026-W38'};go('rs');await wait(200);const t=$('#view').innerText;
    ok('26. The screen shows the hold, the counts, the projects and the reminder log',/Weekly executive report, Week 38, 2026: held/.test(t)&&/Reminders sent/.test(t)&&document.querySelectorAll('.rstbl tbody tr').length===rsPeriod('week','2026-W38').total);
    as(rm.id);go('rs');await wait(200);ok('27. A regional manager sees the projects in their access only',[...document.querySelectorAll('.rstbl tbody tr')].length===rsPeriod('week','2026-W38').rows.filter(r=>accessIds().includes(r.p.id)).length);
    as(sa.id);saved=[];await rsExcel();await loadLib(LIBS.xlsx);const wb=XLSX.read(await saved[0].b.arrayBuffer(),{type:'array'}),A=XLSX.utils.sheet_to_json(wb.Sheets['Reporting status'],{header:1});
    ok('28. The Excel export lists every project with its deliverables and the executive report status',/Reporting status · weekly · Week 38/.test(A[0][0])&&A[2].includes('Executive report')&&A.length===3+rsPeriod('week','2026-W38').total);
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.saveFile=keepSave;window.confirm=conf;window.prompt=prm;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Reporting status: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__rsChecks=res;try{sessionStorage.setItem('rsChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
