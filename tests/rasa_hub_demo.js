/* ProTrackAI v3.47: RASA Intelligence, the central knowledge and learning hub. Acceptance checks for the demo page: the module
   registry and its honest states, indexing with change detection (idempotent, versions, removals, no half-published sync),
   permission-aware search (projects, cost figures, the document rack's rows), answers with checked citations, knowledge gaps,
   teaching and the review workflow (own proposals, company-wide approvers, two approvals and a regression check for a financial
   formula, conflicts, publish and roll back), feedback, settings, the evaluation set and the screen.
   How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this whole
   file. It saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';state.sector='ALL';SCOPE=scopeIds()},keepToast=toast,toasts=[],thr=async f=>{try{await f();return null}catch(e){return e.message}};
  const hadRk=!!DB.rk;
  try{
    window.toast=m=>toasts.push(m);as('U28');
    ok('1. Version 3.47 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=47,APP_VERSION);
    /* a fresh index */
    DB.rk=null;RK.ch={};RK.first=true;RK.dirty.clear();for(const m of RK_MODS)try{await DOCIDB.del('rk:'+m.k)}catch(e){}
    const st0=Object.fromEntries(RK_MODS.map(m=>[m.k,rkModState(m).st]));
    ok('2. Registry: every module has an honest state; nothing is "Connected" before it is indexed; no connector means Not connected; SAP is Disabled',
      RK_MODS.every(m=>RK_ST.includes(st0[m.k]))&&!Object.values(st0).includes('Connected')&&st0.pv==='Not connected'&&st0.bcm==='Not connected'&&st0.sap==='Disabled'&&st0.sched==='Configuring',st0);
    const D=DOMAINS.find(d=>d.k==='rasa');
    ok('3. Menu: RASA Intelligence with its eight tabs and the assistant; RASA Settings only for the super admin',!!D&&D.label==='RASA Intelligence'&&D.items.filter(i=>i.v==='rasa').map(i=>i.tab).join()==='ov,ask,src,teach,act,rev,ana,set'&&D.items.some(i=>i.action==='rasa')
      &&navItemOk(D.items[7],NAV_ALL)&&(as('U30'),!navItemOk(D.items[7],NAV_ALL)&&navOn('rasa'))&&(as('U28'),true));
    const runs=await rkSyncAll('first'),R=rkDB(),S=Object.values(R.src),by=k=>S.filter(s=>s.mod===k&&s.st==='Indexed');
    const C=await DOCIDB.get('rk:docs'),one=by('docs')[0];
    ok('4. First index: each connected module read without errors; sources keep project, record, revision, approval, hash, version and access class; passages are in the file store',
      runs.length>=10&&runs.every(r=>!r.err)&&['sched','cost','docs','prod','exec','claims','proj','cash'].every(k=>by(k).length>0)&&S.every(s=>s.mod&&s.rec&&s.hash&&s.ver===1&&s.cls&&s.appr&&'pid' in s)&&!!C&&!!one&&Array.isArray(C[one.id])&&C[one.id].length>0,runs.map(r=>r.mod+':'+r.added+(r.err?'!':'')));
    const again=await rkSync('sched','manual');
    ok('5. Syncing again changes nothing (idempotent)',again.added===0&&again.changed===0&&again.removed===0&&again.same===by('sched').length,again);
    const p=projById('RMX'),ms=msOf(p)[0],keepFc=ms.fc;ms.fc=addDays(ms.fc||ms.plan||TODAY,21);save();
    const ch=await rkSync('sched','manual'),src=R.src['sched:ms:RMX:0'];
    ok('6. A changed record is indexed again as a new version with its history; the activity log says so',ch.changed>=1&&src.ver===2&&src.hist.length===1&&R.act.some(a=>a.k==='updated'&&/Milestone/.test(a.text)),{ch,ver:src&&src.ver});
    ms.fc=keepFc;save();await rkSync('sched','manual');
    const iss=issRows().find(i=>SCOPE.has(i.project_id)),keepIss=DB.issues.slice();DB.issues=DB.issues.filter(i=>i!==iss);save();
    const rm=await rkSync('proj','manual'),gone=R.src['proj:iss:'+(iss.id||iss.issue_no)],Cp=await DOCIDB.get('rk:proj');
    ok('7. A removed record is marked deleted and its passages leave the index',rm.removed===1&&gone.st==='Deleted'&&!Cp[gone.id],rm);
    DB.issues=keepIss;save();await rkSync('proj','manual');
    const mP=rkMod('proj'),keepConn=mP.conn,before=JSON.stringify(Object.values(R.src).filter(s=>s.mod==='proj').map(s=>[s.id,s.st,s.hash]));
    mP.conn=pids=>{throw new Error('Simulated read failure')};const bad=await rkSync('proj','manual');const after=JSON.stringify(Object.values(R.src).filter(s=>s.mod==='proj').map(s=>[s.id,s.st,s.hash]));
    const stBad=rkModState(mP).st;mP.conn=keepConn;const good=await rkSync('proj','manual');
    ok('8. A failed sync publishes nothing, shows "Attention required" and is retried safely',!!bad.err&&before===after&&stBad==='Attention required'&&!good.err&&rkModState(mP).st==='Connected',{err:bad.err,stBad});
    /* permissions */
    as('U16');const f1=await rkSearch('EAC budget cost report actual',{});
    ok('9. A foreman sees only their project and no cost figures; the hidden matches are only counted',f1.hits.every(h=>h.s.pid==='RMX'||!h.s.pid)&&f1.hits.every(h=>h.s.cls!=='money')&&f1.hidden>0,{hits:f1.hits.map(h=>h.s.id),hidden:f1.hidden});
    const g0=rkDB().gaps.length,a1=await rkAsk('What is the EAC in the cost report?',{});
    ok('10. A question about records the person may not open is not a knowledge gap and does not reveal them',!a1.answered&&rkDB().gaps.length===g0&&!/rk-cite/.test(a1.html));
    as('U07');const f2=await rkSearch('schedule status activities',{});
    ok('11. A project manager of JDC finds nothing of other projects',f2.hits.length>0&&f2.hits.every(h=>!h.s.pid||h.s.pid==='JDC'),f2.hits.map(h=>h.s.pid));
    as('U28');
    const a2=await rkAsk('What notice period does the contract give for a claim on RMX?',{}),dv=document.createElement('div');dv.innerHTML=a2.html;const q2=rkDB().qlog[0];
    ok('12. An answer quotes the contract clause with its document, project, revision and status, and every citation is checked',a2.answered&&/Clause 20\.1|28 days/.test(dv.textContent)&&dv.querySelectorAll('.rk-cite').length>0&&q2.valid===q2.cites&&q2.cites>0&&/Document Rack|Contracts/.test(dv.textContent),{cites:q2.cites,valid:q2.valid});
    const w1=await rkAsk('What will the weather be like on site tomorrow?',{}),w2=await rkAsk('What will the weather be like on site tomorrow?',{}),gw=rkDB().gaps.find(g=>/weather/.test(g.q));
    ok('13. A question nobody can answer is said so, recorded once as a knowledge gap and counted when asked again',!w1.answered&&/No evidence/.test(w1.html)&&gw&&gw.n===2&&gw.st==='Open',gw);
    const cl=await rkAsk('What is the critical path of the project?',{});
    ok('14. An ambiguous question with several projects in scope asks which project',cl.clarify===true&&/Which project/.test(cl.html));
    /* teaching and review */
    as('U30');const k1=await rkPropSave({kind:'correction',title:'Riyadh Metro handover milestone forecast',old:'The handover milestone is on track',text:'The handover milestone is forecast 21 days late after the access delay; see delay event Event 01.',why:'The forecast was not updated after the access delay',scope:'project',pid:'RMX',mod:'sched',ref:'Delay event Event 01',ids:'Event 01'},true);
    const e0=await thr(()=>rkPropAct(k1.id,'take'));rightsDB().user.U30={'rasa.review':true};const e00=await thr(()=>rkPropAct(k1.id,'take'));delete rightsDB().user.U30;
    ok('15. A planning engineer teaches a correction and submits it; without the reviewer right they cannot review, and nobody reviews their own',k1.st==='Submitted'&&/knowledge reviewer/.test(e0||'')&&/own/.test(e00||'')&&k1.hist.length===2,{st:k1.st,e0,e00});
    as('U28');rkPropAct(k1.id,'take');const e1=await thr(()=>rkPropAct(k1.id,'revise',''));rkPropAct(k1.id,'approve');await rkPropAct(k1.id,'publish');
    const t1=R.src['taught:kp:'+k1.id],a3=await rkAsk('Is the Riyadh Metro handover milestone forecast on track?',{pid:'RMX'});
    ok('16. A reviewer takes, approves and publishes it (a return needs a comment); it is indexed and answers the next question as approved knowledge',/Say why/.test(e1||'')&&k1.st==='Published'&&k1.pubVer>=1&&t1&&t1.st==='Indexed'&&/Approved knowledge applies/.test(a3.html),{st:k1.st,t1:!!t1});
    as('U30');const k2=await rkPropSave({kind:'rule',title:'Delay notices within 28 days',text:'A delay notice is sent to the Engineer within 28 days of the event, as Clause 20.1 requires.',purpose:'Protect the extension-of-time entitlement',scope:'company',mod:'claims',ref:'Contract Clause 20.1'},true);
    as('U28');rightsDB().user.U48={'rasa.review':true};as('U48');const e2=await thr(()=>rkPropAct(k2.id,'take'));
    as('U28');rkPropAct(k2.id,'take');rkPropAct(k2.id,'approve');await rkPropAct(k2.id,'publish');
    ok('17. Company-wide knowledge needs a designated approver: a project reviewer cannot take it, the super admin can',/designated approvers/.test(e2||'')&&k2.st==='Published'&&!k2.pid,e2);
    as('U30');const k3=await rkPropSave({kind:'rule',title:'Contingency drawdown threshold',text:'Contingency drawdown above 10% of the remaining contingency needs the Head of Planning and Cost Control.',purpose:'Control of contingency',scope:'project',pid:'RMX',mod:'cost',formula:'drawdown / remaining contingency > 0.10',fin:true},true);
    as('U28');rkPropAct(k3.id,'take');const e3=await thr(()=>rkPropAct(k3.id,'approve',''));rkPropAct(k3.id,'approve','',{regress:true});const mid=k3.st;
    const e4=await thr(()=>rkPropAct(k3.id,'approve','',{regress:true}));as('U29');rkPropAct(k3.id,'approve','',{regress:true});
    ok('18. A high-impact financial formula needs the regression check and two different approvers',/regression/.test(e3||'')&&mid==='Under Review'&&/another approver/.test(e4||'')&&k3.st==='Approved'&&k3.approvals.length===2,{e3,mid,st:k3.st});
    as('U30');const k4=await rkPropSave({kind:'correction',title:'Riyadh Metro handover milestone forecast',old:'21 days late',text:'The handover milestone is now forecast 35 days late after the second access delay.',why:'A second access delay',scope:'project',pid:'RMX',mod:'sched'},true);
    as('U28');rkPropAct(k4.id,'take');const e5=await thr(()=>rkPropAct(k4.id,'approve'));rkPropAct(k4.id,'resolve','replace');rkPropAct(k4.id,'approve');await rkPropAct(k4.id,'publish');const sup=k1.st;
    await rkPropAct(k4.id,'unpublish','Wrong forecast date');
    ok('19. A conflict with published knowledge is resolved before approval; publishing replaces it, rolling back restores it; both are in the version log',k4.conflicts.some(c=>c.id===k1.id)&&/Resolve the conflict/.test(e5||'')&&sup==='Superseded'&&k1.st==='Published'&&k4.st==='Withdrawn'&&R.pub.some(x=>x.prop===k4.id&&x.op==='publish')&&R.pub.some(x=>x.prop===k4.id&&x.op==='rollback')&&!R.src['taught:kp:'+k4.id]?.st?.startsWith('Index'),{sup,k1:k1.st,k4:k4.st});
    const gp=rkDB().gaps.find(g=>/weather/.test(g.q));as('U30');const k5=await rkPropSave({kind:'gap',gap:gp.id,title:'Weather on site',text:'ProTrackAI does not record weather; the site engineer notes it in the daily report remarks.',scope:'company',mod:'prod'},true);
    as('U28');rkPropAct(k5.id,'take');rkPropAct(k5.id,'approve');await rkPropAct(k5.id,'publish');
    ok('20. Knowledge submitted for a gap resolves the gap when it is published',gp.st==='Resolved'&&/Answered by published knowledge/.test(gp.res),gp.st);
    await rkFeedback(q2.id,-1,'Quote the clause number');
    ok('21. Negative feedback is kept with the answer and appears in the learning activity',rkDB().fb.some(f=>f.qid===q2.id&&f.v===-1)&&rkDB().act.some(a=>a.k==='feedback'));
    R.cfg.mods.cost={on:false,sync:'event'};const offHits=(await rkSearch('EAC current budget cost report',{})).hits.filter(h=>h.s.mod==='cost').length,offSt=rkModState(rkMod('cost')).st;R.cfg.mods.cost={on:true,sync:'event'};
    ok('22. Switching a module off in RASA Settings takes its knowledge out of every answer at once',offHits===0&&offSt==='Disabled'&&(await rkSearch('EAC current budget cost report',{})).hits.some(h=>h.s.mod==='cost'));
    RK.dirty.clear();rkDirty();const dirty=RK.dirty.has('sched');clearTimeout(RK.t);await rkCatchUp();
    ok('23. Saving a record marks the modules set to "on change" and they refresh by themselves',dirty&&RK.dirty.size===0&&R.runs[0].kind==='event');
    const ev=await rkEvalRun();
    ok('24. The evaluation set finds the expected module in the top 3 for most questions, with valid citations and no permission leak',ev.hit>=7&&ev.iso&&ev.valid===ev.cites,{hit:ev.hit,n:ev.n,valid:ev.valid,cites:ev.cites});
    const errs=[];for(const t of ['ov','ask','src','teach','act','rev','ana','set']){try{state.rkTab=t;state.view='rasa';render();if(!$('#view .rk'))errs.push(t)}catch(e){errs.push(t+': '+e.message)}}
    state.rkTab='ov';render();const v=$('#view');
    ok('25. Every tab renders; the overview shows the eight measures, all registered modules and the learning progress',!errs.length&&v.querySelectorAll('.rk-kpi').length===8&&v.querySelectorAll('.rk-mc').length===RK_MODS.length&&/Welcome to RASA Intelligence/.test(v.innerText)&&!!v.querySelector('.rk-dn'),errs);
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.toast=keepToast;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}if(!hadRk)for(const m of RK_MODS)try{await DOCIDB.del('rk:'+m.k)}catch(e){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`RASA Intelligence: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__rkChecks=res;try{sessionStorage.setItem('rkChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
