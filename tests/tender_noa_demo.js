/* ProTrackAI v3.12, Tender register: L1 / L2 and the notice of award (NOA). Acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},err=f=>{try{f();return ''}catch(x){return x.message}};
  const wait=ms=>new Promise(r=>setTimeout(r,ms));
  try{
    const co=DB.master.users.find(u=>isCoord(u));as(co.id);go('tender');await wait(200);
    ok('The button says L1 or L2',/Register an L1 or L2 project/.test(document.querySelector('[data-tenreg]').textContent));
    document.querySelector('[data-tenreg]').click();await wait(400);
    ok('The registration opens as a full window',$('#sheet').classList.contains('full')&&!$('#drawer').hidden);
    const f=$('#tenForm');f.elements.te_number.value='TE9901';f.elements.name.value='Sample L2 tender';f.elements.notified_on.value='2026-10-01';
    f.querySelector('[type=submit]').click();await wait(300);
    ok('The bid position must be chosen',/Choose whether we are L1 or L2/.test($('#tenErr').textContent));
    const r2=f.querySelector('input[name=bid_rank][value=L2]');r2.checked=true;r2.dispatchEvent(new Event('change',{bubbles:true}));
    ok('Choosing L2 shows the reason field',!$('#tenRankNote').hidden);
    f.elements.rank_note.value='Client prefers our past performance';f.querySelector('[type=submit]').click();await wait(600);
    const p=DB.master.projects.find(x=>x.te==='TE9901');
    ok('An L2 project is registered with its reason, pre-award, awaiting NOA',p&&p.rank==='L2'&&p.rankNote==='Client prefers our past performance'&&p.status==='Pre-award'&&!p.award,p&&{rank:p.rank,status:p.status});
    const p1=tenderActLocal('register',null,{te_number:'TE9902',name:'Sample L1 tender',bid_rank:'L1'});
    ok('An L1 project is registered as L1',projById(p1.id).rank==='L1');
    ok('Projects registered before v3.12 count as L1',rankOf(PROJECTS.find(x=>!x.rank&&x.id!==p.id)||{})==='L1');
    ok('A bid position other than L1 or L2 is refused',/L1 or L2/.test(err(()=>tenderActLocal('register',null,{te_number:'TE9903',name:'x',bid_rank:'L3'}))));
    go('tender');await wait(200);const row=[...document.querySelectorAll('#view tbody tr[data-tenopen]')].find(t=>t.textContent.includes('TE9901'));
    ok('The register shows the bid position and Awaiting NOA',row&&/L2/.test(row.textContent)&&/Awaiting NOA/.test(row.textContent));
    ok('The award date is no longer typed in the Tender details',/Record NOA received/.test(err(()=>tenderActLocal('update',p.id,{award_on:'2026-10-05'}))));
    const pm=DB.master.users.find(u=>u.role==='pm'&&accessIds&&teamOf(PROJECTS[0].id,'pm').some(x=>x.id===u.id));
    if(pm){as(pm.id);ok('A project manager cannot record the NOA',/costing coordinator or a super admin/.test(err(()=>tenderActLocal('noa',PROJECTS[0].id,{award_on:'2026-09-01'}))));as(co.id)}
    ok('The NOA date cannot be in the future',/future/.test(err(()=>tenderActLocal('noa',p.id,{award_on:'2099-01-01'}))));
    ok('The NOA date cannot be before Tender notified',/before the date Tender notified/.test(err(()=>tenderActLocal('noa',p.id,{award_on:'2026-09-15'}))));
    openTender(p.id);await wait(200);$('#tenNoaOn').value='2026-10-12';document.querySelector('[data-tennoa]').click();await wait(400);
    const cf=document.querySelector('[data-cfm="1"]');if(cf)cf.click();await wait(500);
    const q=projById(p.id);
    ok('The coordinator records the NOA with its actual date; the project becomes Active',q.award==='2026-10-12'&&q.status==='Active'&&q.noaBy===co.name,{award:q.award,status:q.status});
    ok('The finance WBS is released on the same date for the PBG cost',q.fwbs==='2026-10-12'&&DB.regAudit.some(a=>a.project_id===p.id&&a.action==='Finance WBS released'&&/PBG/.test(a.note||'')));
    ok('The history, stage 3 and a notification record it',DB.regAudit.some(a=>a.project_id===p.id&&a.action==='NOA received')&&(DB.lcAudit||[]).some(a=>a.project_id===p.id&&a.stage_no===3&&/finance WBS/.test(a.note||''))&&/PBG/.test(DB.notes[0].text));
    ok('Stage 3 shows the NOA and the finance WBS as evidence',lcEvidence(q,'loa').st==='ok'&&lcEvidence(q,'fwbs').st==='ok'&&/PBG/.test(lcDef(3).items.find(i=>i[0]==='fwbs')[1]));
    ok('Correcting the NOA date needs a reason',/reason/.test(err(()=>tenderActLocal('noa',p.id,{award_on:'2026-10-11'}))));
    tenderActLocal('noa',p.id,{award_on:'2026-10-11'},'Date on the NOA letter');
    ok('A correction moves the finance WBS date too and is kept in the history',projById(p.id).fwbs==='2026-10-11'&&DB.regAudit.some(a=>a.project_id===p.id&&a.action==='NOA date corrected'&&a.note==='Date on the NOA letter'));
    ok('The bid position is fixed once the NOA is received',/cannot change once the NOA/.test(err(()=>tenderActLocal('update',p.id,{bid_rank:'L1'}))));
    as('U28');ok('A super admin can record the NOA too',err(()=>tenderActLocal('noa',p1.id,{award_on:localISO()}))===''&&projById(p1.id).fwbs===localISO());
    ok('Settings: the NOA right goes to the costing coordinator',RIGHTS.some(r=>r[0]==='tender.noa')&&/costing coordinator/.test(RIGHT_POS['tender.noa']||''));
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Tender L1 / L2 and NOA: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__tnChecks=res;try{sessionStorage.setItem('tnChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
