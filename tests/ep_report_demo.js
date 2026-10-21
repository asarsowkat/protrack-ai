/* ProTrackAI v3.26, E&P progress inside the internal and client reports. Acceptance checks for the demo page. How to run:
   open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this whole file. It
   saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms));
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'),P='QOT',pl=teamOf(P,'plan')[0],T='week',PER='2026-W39',keepSave=saveFile;let saved=null;
  try{
    as(pl.id);renderNav();ok('1. No separate E&P progress screen in the menu',![...document.querySelectorAll('#nav button')].some(b=>/E&P progress/.test(b.innerText))&&!NAV_ALL.includes('upd'));
    state.view='upd';render();await wait(100);ok('2. The old address opens Internal Reporting',state.view==='rel'&&state.relTab==='planning');
    const E=epReportStats(P,'planning',T,PER),u=schedAt(P,periodEnd(PER,T)),row=schedRowsOf(u).find(r=>r.id==='QOT-E1020');
    ok('3. From the updated schedule the report uses (in force at the end of the period), activity by activity',E.update_id===u.id&&E.rows.find(r=>r.id==='QOT-E1020').pct===r2(+row.pct)&&E.rows.find(r=>r.id==='QOT-E1020').ff===(row.af||row.ef||null),[E.dd,row.pct]);
    ok('4. Engineering and procurement weighted, with plan, actual and late counts',E.ENG.n+E.PRC.n===E.all.n&&E.all.pct!=null&&E.all.plan!=null);
    const old=epReportStats(P,'planning','week','2025-W10');ok('5. A period before any updated schedule: no figures invented, the baseline plan only',!old.update_id&&old.rows.every(r=>r.pct==null)&&old.all.pct==null);
    const C=epReportStats(P,'client',T,PER);ok('6. The client report uses the schedule with client weightage',!C.update_id||schedUps(P).find(x=>x.id===C.update_id).weightage==='client');
    state.rdTab='ep';openPlanRelease(P,T,PER);await wait(150);ok('7. The internal report has an E&P progress tab showing the activities',!!$('#sheet [data-rdtab="ep"]')&&/the same schedule this report uses/.test($('#sheet [data-rdp="ep"]').innerText)&&document.querySelectorAll('#sheet #epTbl tbody tr').length===E.rows.length);
    const fig=Object.assign({},relPlanSnapshot(P),relDashDefaults(P)),r=relActLocal({action:'save',project_id:P,kind:'planning',period_type:T,period:PER,figures:fig,overrides:[],narrative:{},data_date:ASOF});
    ok('8. Saved with the report',!!r.figures.ep&&r.figures.ep.rows.length===E.rows.length&&r.figures.ep.all.pct===E.all.pct);
    relActLocal({action:'submit',id:r.id});as(sa.id);relActLocal({action:'approve',id:r.id,validated:true,validation_note:'checked'});const frozen=JSON.stringify(r.figures.ep);
    row.pct=Math.min(100,+row.pct+10);ok('9. Approved: frozen even when the schedule rows change later',JSON.stringify(r.figures.ep)===frozen&&epReportStats(P,'planning',T,PER).all.pct!==r.figures.ep.all.pct);
    ok('10. The executive report (project view) shows it as released',xrDashHTML(r.figures).includes('Engineering and procurement progress'));
    const was=relReleased(P,'planning','week','2026-W38');ok('11. A version saved before v3.26 says so',/saved before engineering and procurement/.test(epHTML(epOf(P,'planning','week','2026-W38',was.figures,was),'planning')));
    as(pl.id);const cs=schedAt(P,periodEnd('2026-W41','week'),'client').summary,c=relActLocal({action:'save',project_id:P,kind:'client',period_type:'week',period:'2026-W41',figures:{plan_pct:cs.client_plan,act_pct:cs.client_act},overrides:[],narrative:{},data_date:ASOF});
    state.clTab='ep';openClientRelease(P,'week','2026-W41');await wait(150);ok('12. The client report has the tab and keeps the figures',!!c.figures.ep&&!!$('#sheet [data-cltab="ep"]')&&/client weightage/.test($('#sheet [data-clp="ep"]').innerText));
    saveFile=async(n,b)=>{saved={n,b}};await clientExport('xlsx',P,'week','2026-W41');saveFile=keepSave;const wb=XLSX.read(new Uint8Array(await saved.b.arrayBuffer()),{type:'array'});
    ok('13. The client report Excel has an E&P progress sheet',wb.SheetNames.includes('E&P progress'),wb.SheetNames);
    ok('14. Monthly reports use the schedule in force at the end of the month',epReportStats(P,'planning','month','2026-09').update_id===(schedAt(P,'2026-09-30')||{}).id);
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keepSave;$('#drawer').hidden=true;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`E&P progress in reports: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__epChecks=res;try{sessionStorage.setItem('epChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
