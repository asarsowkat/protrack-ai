/* ProTrackAI v3.23 (v3.27.1: monthly reports), intermediate milestones from the P6 schedule and progress by phase. Acceptance checks for the demo
   page. How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28),
   open the browser console and paste this whole file. It saves this browser's demo data first and puts it back at the
   end, then reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms));
  const err=fn=>{try{fn();return ''}catch(e){return e.message}},near=(a,b)=>a!=null&&b!=null&&Math.abs(a-b)<=0.06;
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'),P='QOT',pl=teamOf(P,'plan')[0],eng=U.find(u=>u.role==='eng'),other=U.find(u=>u.role==='plan'&&!accessIds(u).includes(P));
  const T='week',PER='2026-W39',CPER='2026-W41',okConfirm=window.confirm,pm0=U.find(u=>u.role==='pm'&&accessIds(u).includes(P))||sa;
  try{
    ok('1. Every phase is listed, energization on its own',RPH.map(x=>x[0]).join()==='GEN,DES,MAT,CON,INS,TC,EN,CLO'&&phaseSuggest('Energization of the 380 kV line')==='EN'&&phaseSuggest('Testing and commissioning')==='TC');
    ok('2. The demo has intermediate milestones on QOT and JBS; an internal-only one is not in the client report',kmsOf('QOT').length>=5&&kmsOf('JBS').length===5
      &&kmsFor(P,'planning',T,PER).some(x=>x.name==='Material delivery complete')&&!kmsFor(P,'client',T,PER).some(x=>x.name==='Material delivery complete'));
    as(pl.id);
    const rows=schedRowsOf(schedAt(P,periodEnd(PER,T))),mx=a=>a.filter(Boolean).sort().pop(),mn=a=>a.filter(Boolean).sort()[0];
    const G=rows.filter(r=>!r.ms&&r.wbs===DEMO_WBS.DES),K=kmsFor(P,'planning',T,PER).find(x=>x.name==='Design completion'),ePlan=mx(G.map(r=>r.bf)),eFc=mx(G.map(r=>r.af||r.ef||r.bf));
    ok('3. A WBS finish: baseline = last baseline finish, forecast = last forecast finish of its activities',K.plan===ePlan&&K.fc===eFc&&K.delay===diffDays(ePlan,eFc)&&kmsLight(K).t==='Delayed',[K.plan,K.fc,K.delay]);
    const C=rows.filter(r=>!r.ms&&r.wbs===DEMO_WBS.CON),K2=kmsFor(P,'planning',T,PER).find(x=>x.name==='Civil works start');
    ok('4. A WBS start: actual = the first actual start of its activities, achieved',K2.act===mn(C.map(r=>r.as))&&K2.plan===mn(C.map(r=>r.bs))&&kmsLight(K2).t==='Achieved',[K2.plan,K2.act]);
    const a=kmsActLocal({action:'add',project_id:P,item:{name:'Right of way complete',req:'client',use:'both',src:'act',ref:'QOT-MS02',ev:'start'}});
    const K3=kmsFor(P,'planning',T,PER).find(x=>x.name==='Right of way complete');
    ok('5. A P6 milestone picked by ID: baseline and actual from the schedule (42 days late, achieved late)',a.ms&&a.ev==='finish'&&K3.plan==='2026-03-31'&&K3.act==='2026-05-12'&&K3.delay===42&&kmsLight(K3).t==='Achieved late',[K3.plan,K3.act,K3.delay]);
    const add=(o)=>err(()=>kmsActLocal({action:'add',project_id:P,item:Object.assign({name:'X',req:'pm',use:'both',src:'wbs',ref:DEMO_WBS.INS,ev:'start'},o)}));
    const E=[add({name:' '}),add({name:'design COMPLETION'}),add({src:'act',ref:'QOT-NOPE'}),add({ref:'NOPE'}),add({ref:''}),add({req:'x'}),add({ev:'mid'})];
    ok('6. Wrong entries are refused with a message',/Give the milestone a name/.test(E[0])&&/already a milestone named/.test(E[1])&&/QOT-NOPE is not in the updated schedule/.test(E[2])&&/not a WBS element/.test(E[3])&&/Choose a WBS element/.test(E[4])&&/who asked/.test(E[5])&&/start or the finish/.test(E[6]),E);
    as(eng.id);const e1=add({name:'Y'});as(other.id);const e2=add({name:'Y'});as(pl.id);
    ok('7. Only the planning engineers of the project (or a super admin) keep them',/Only a planning engineer|do not have access/.test(e1)&&/do not have access/.test(e2),[e1,e2]);
    const I=phaseTbl(P,'planning',T,PER),S=schedAt(P,periodEnd(PER,T)).summary,W=phaseSetupOf(P).weights,sum=k=>I.phases.reduce((t,x)=>t+(+x[k]||0),0);
    ok('8. Internal: every phase with its internal weight; the weighted phases add up to the internal progress',I.phases.length===8&&I.phases.every(x=>x.wt===(+W[x.phase]||0))&&near(sum('c_plan'),I.plan)&&near(sum('c_act'),I.act)&&I.plan===S.int_plan&&/start of the project/.test(I.basis),[sum('c_plan'),I.plan,sum('c_act'),I.act]);
    const con=I.phases.find(x=>x.phase==='CON');
    ok('9. Only the site phases are compared with the daily reports',['GEN','DES','MAT','CLO'].every(k=>!I.phases.find(x=>x.phase===k).dpr)&&con.dpr.n>0&&near(con.dpr.diff,con.dpr.dpr-con.dpr.p6)&&con.dpr.diff<0,con.dpr);
    const Cl=phaseTbl(P,'client',T,PER),cs=schedAt(P,periodEnd(PER,T),'client').summary;
    ok('10. Client: weights are the schedule\'s own shares, the overall is the client progress, no daily reports',Cl.own&&near(Cl.phases.reduce((t,x)=>t+x.wt,0),100)&&Cl.plan===cs.client_plan&&Cl.act===cs.client_act&&Cl.phases.every(x=>!x.dpr));
    const fig=Object.assign({},relPlanSnapshot(P),relDashDefaults(P)),r=relActLocal({action:'save',project_id:P,kind:'planning',period_type:T,period:PER,figures:fig,overrides:[],narrative:{},data_date:ASOF});
    ok('11. Saving an internal report keeps its intermediate milestones and progress by phase',r.figures.key_ms.length===kmsFor(P,'planning',T,PER).length&&r.figures.key_ms.some(x=>x.name==='Right of way complete')&&r.figures.phase_tbl.phases.length===8);
    relActLocal({action:'submit',id:r.id});as(sa.id);relActLocal({action:'approve',id:r.id,validated:true,validation_note:'checked'});
    const n0=JSON.stringify(r.figures.key_ms);kmsActLocal({action:'remove',project_id:P,id:a.id});
    state.rdTab='ms';openPlanRelease(P,T,PER);await wait(150);const card=$('#kmsCard').innerText;
    ok('12. Approved: frozen; removing a milestone later does not change it',r.status==='Released'&&JSON.stringify(r.figures.key_ms)===n0&&/Right of way complete/.test(card)&&/As frozen when this report was approved/.test(card)&&!$('#kmsCard [data-kmsdel]'),card.slice(0,160));
    const xr=xrDashHTML(r.figures);ok('13. The executive report (project view) shows them as released',xr.includes('id="xrKms"')&&xr.includes('Progress by phase')&&xr.includes('Design completion'));
    as(pl.id);const c=relActLocal({action:'save',project_id:P,kind:'client',period_type:T,period:CPER,figures:{plan_pct:cs.client_plan,act_pct:cs.client_act},overrides:[],narrative:{},data_date:ASOF});
    ok('14. A client report keeps only the milestones for the client, and the client weightage table',!c.figures.key_ms.some(x=>x.name==='Material delivery complete')&&c.figures.key_ms.some(x=>x.name==='Design completion')&&c.figures.phase_tbl.own&&c.figures.phase_tbl.plan===cs.client_plan);
    const old=relReleased(P,'planning','week','2026-W38');
    ok('15. A version saved before v3.23 says so',!!old&&/saved before intermediate milestones/.test(kmsCardHTML(P,'planning','week','2026-W38',old.figures,old))&&phaseTblHTML(phaseTblOf(P,'planning','week','2026-W38',old.figures,old),'planning').includes('saved before progress by phase'));
    state.rdTab='prog';openPlanRelease(P,T,'2026-W42');await wait(150);const pay=relFormPayload();
    ok('16. A new draft sends them with the save, and the Progress tab shows the table',Array.isArray(pay.figures.key_ms)&&pay.figures.phase_tbl&&pay.figures.phase_tbl.phases.length===8&&!!$('#sheet .phtbl [data-ph="EN"]')&&/Daily reports − P6/.test($('#sheet .phtbl').innerText));
    window.confirm=()=>true;state.rdTab='ms';openPlanRelease(P,T,'2026-W42');await wait(150);const nb=kmsOf(P).length;$('#kmsCard [data-kmsdel]').click();await wait(200);
    ok('17. Remove from the card (draft)',kmsOf(P).length===nb-1&&!!$('#kmsCard'));
    // v3.27.1: monthly reports, as weekly
    const mo=relOpen(P,'planning','month','2026-09')||relReleased(P,'planning','month','2026-09'),MT=phaseTblOf(P,'planning','month','2026-09',mo.figures,mo);
    state.rdTab='prog';openPlanRelease(P,'month','2026-09');await wait(150);
    ok('18. A monthly report saved before v3.23 shows progress by phase too, worked out from the schedule in force at the month end, and says so',mo.figures.phase_tbl===undefined&&MT&&MT.late&&MT.update_id===schedAt(P,'2026-09-30').id&&!!$('#sheet [data-rdp="prog"] .phtbl [data-ph="CON"]')&&/worked out from the updated schedule in force at the end of the period/.test($('#sheet [data-rdp="prog"]').innerText));
    const mo8=relReleased(P,'planning','month','2026-08');ok('19. Without a schedule up to the month end, nothing is invented',!!mo8&&phaseTblOf(P,'planning','month','2026-08',mo8.figures,mo8)==='old');
    if(mo.status==='Submitted'){as(sa.id);if(relSettings().pm_review&&!mo.reviewed_by)mo.reviewed_by=pm0.id;relActLocal({action:'approve',id:mo.id,validated:true,validation_note:'checked'});}
    ok('20. Approved: the monthly report keeps the table it was approved with, and the executive report shows it',!!mo.figures.phase_tbl&&mo.figures.phase_tbl.late===true&&xrDashHTML(mo.figures).includes('Progress by phase'));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.confirm=okConfirm;$('#drawer').hidden=true;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Intermediate milestones and progress by phase: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__kmChecks=res;try{sessionStorage.setItem('kmChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
