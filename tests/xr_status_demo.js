/* ProTrackAI v3.22.2, which projects the executive report (released) lists, by project status. Acceptance checks for
   the demo page. How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account
   (U28), open the browser console and paste this whole file. It saves this browser's demo data first and puts it back
   at the end, then reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms));
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'),ex=U.find(u=>u.role==='exec'),P=id=>projById(id),keep=Object.fromEntries(PROJECTS.map(p=>[p.id,p.status]));
  const listed=(t,per)=>xrProjects(t,per).map(p=>p.id),row=id=>[...document.querySelectorAll('#view table tbody tr')].find(tr=>tr.textContent.includes(P(id).short));
  try{
    as(ex.id);
    ok('1. Active projects are listed whether they released or not',['RTT','JWP'].every(id=>listed('week','2026-W38').includes(id)));
    P('JWP').status='Completed';
    ok('2. A completed project is listed in a period it released (week 37) and not in one it did not (week 38)',listed('week','2026-W37').includes('JWP')&&!listed('week','2026-W38').includes('JWP'));
    ok('3. A completed project never holds the report',!rsPeriod('week','2026-W38').rows.some(r=>r.p.id==='JWP'));
    P('JWP').status='On hold';const r=xrRel('JWP','planning','week','2026-W38');
    ok('4. An on-hold project is listed with its last released figures',listed('week','2026-W38').includes('JWP')&&r&&r.period==='2026-W37'&&!relReleased('JWP','planning','week','2026-W38'));
    ok('5. An on-hold project does not hold the report',!rsPeriod('week','2026-W38').rows.some(x=>x.p.id==='JWP'));
    P('RTT').status='On hold';
    ok('6. With both outstanding projects on hold, week 38 is complete and the executive report opens',rsPeriod('week','2026-W38').complete);
    state.xrPt='week';state.xrPer='2026-W38';state.xrTab='sum';go('xr');await wait(250);
    const tr=row('JWP');ok('7. The progress table marks it On hold, with the period of its figures',!/Held:/.test($('#view').innerText)&&tr&&/On hold · figures of Week 37/.test(tr.textContent),tr&&tr.textContent.slice(0,120));
    const X=xrRows('week','2026-W38');ok('8. Its last released figures count in the summary',X.some(x=>x.p.id==='JWP'&&x.pr&&x.pr.period==='2026-W37'));
    P('QOT').status='Pre-award';
    ok('9. A pre-award project is neither listed nor required',!listed('week','2026-W38').includes('QOT')&&!rsPeriod('week','2026-W38').rows.some(x=>x.p.id==='QOT'));
    state.xrTab='proj';go('xr');await wait(200);
    ok('10. The project view offers the same projects',!$('#view').innerHTML.includes(`value="QOT"`)&&listed('week','2026-W38').length===xrProjects('week','2026-W38').length);
    Object.entries(keep).forEach(([id,s])=>{P(id).status=s});
    ok('11. Back to active: week 38 is held again by the outstanding projects',!rsPeriod('week','2026-W38').complete);
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{Object.entries(keep).forEach(([id,s])=>{if(P(id))P(id).status=s});try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Executive report by project status: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__xsChecks=res;try{sessionStorage.setItem('xsChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
