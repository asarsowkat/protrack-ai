/* ProTrackAI v3.54: the Daily Productivity Report (preview while preparing, reviewing and approving, and the approval email to
   the Approval email list) and the preview of the weekly and monthly internal reports before they are submitted. Acceptance
   checks for the demo page. How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser
   console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then reloads. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms)),keepToast=toast,toasts=[];
  const set=(sel,v)=>{const e=document.querySelector(sel);e.value=v;e.dispatchEvent(new Event('input',{bubbles:true}))};
  const view=async()=>{await wait(1200);const v=$('#docView'),d=v&&v.querySelector('iframe').contentDocument;return {v,d,tx:d?d.body.innerText:''}};
  const close=()=>{const x=document.querySelector('#docView [data-docx]');if(x)x.click()};
  try{
    window.toast=m=>toasts.push(m);const sa=me().id;
    ok('1. Version 3.54 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=54,APP_VERSION);
    ok('2. The productivity index guide: over 110% Excellent, 100–110% Good, 90–100% Acceptable, 80–90% Needs Improvement, under 80% Critical',
      [1.2,1.1,1.0,0.95,0.9,0.85,0.8,0.5].map(x=>piBand(x)[1]).join()==='Excellent,Good,Good,Acceptable,Acceptable,Needs Improvement,Needs Improvement,Critical');
    /* 3-6: the foreman prepares, with the new fields, and previews before submitting */
    const P=PROJECTS.find(p=>p.status==='Active'&&p.foremen.length&&ACTS.some(a=>a.p===p.id&&isCon(a))),fm=DB.master.users.find(u=>u.role==='foreman'&&u.active!==false&&P.foremen.includes(u.name));
    as(fm.id);state.form=null;state.editing=null;go('new');await wait(300);state.form.p=P.id;state.form.foreman=fm.name;state.form.lines=[blankLine(P.id)];renderForm();await wait(200);
    ok('3. The form asks for the weather, major constraints / issues and recovery actions / next steps, and has Preview report',!!document.querySelector('[data-k=weather]')&&!!document.querySelector('[data-k=issues]')&&!!document.querySelector('[data-k=recovery]')&&!!document.querySelector('[data-formprev]'));
    set('[data-k=weather]','Windy, 38 °C');set('[data-k=issues]','Material delivery late by 3 hours (SAMPLE)');set('[data-k=recovery]','Night shift to recover (SAMPLE)');set('[data-k=remarks]','Zone A works continued (SAMPLE)');set('[data-lk=qty]','6');
    document.querySelector('[data-formprev]').click();let V=await view();
    const heads=['DAILY PRODUCTIVITY REPORT','PROTRACK AI ENABLED DAILY PRODUCTIVITY REPORT','ACTIVITY PROGRESS & PRODUCTIVITY TRACKING','SUMMARY (TOTALS)','PRODUCTIVITY INDEX GUIDE','Remarks / Comments','Major Constraints / Issues','Recovery Actions / Next Steps','Prepared By (Initiator)','Reviewed By','Approved By','Powered by ProTrack AI'];
    ok('4. Preview while preparing: the report in the company layout, before it is saved, with Print or save as PDF',!!V.v&&!!V.v.querySelector('[data-docprint]')&&heads.every(h=>V.tx.includes(h))&&/preview before submitting/.test($('#docView .docttl').innerText)&&/not saved yet/.test(V.tx),heads.filter(h=>!V.tx.includes(h)));
    const kv=['Initiator Name','Project Name','Project Number','Contract Number','Client','Reporting Discipline','Date','Day (Week)','Weather'];
    const cols=['S.No.','Work Location','Activity Name','UOM','Scope','Completed','Today','Cumulative','Balance','Planned MP','Actual','Avg OT Hrs','Normal Hrs','OT Hrs','Productivity'];
    ok('5. The report details and the activity columns of the template, with what was typed',kv.every(k=>V.tx.includes(k))&&cols.every(c=>V.tx.includes(c))&&/Windy, 38/.test(V.tx)&&/Material delivery late/.test(V.tx)&&/Night shift to recover/.test(V.tx)&&/Zone A works continued/.test(V.tx)&&!!V.d.querySelector('img[alt="alfanar Projects"]')&&!!V.d.querySelector('img[alt="ProTrack"]'),[kv.filter(k=>!V.tx.includes(k)),cols.filter(c=>!V.tx.includes(c))]);
    const R=dprDocRows({id:null,date:state.form.date,p:P.id,lines:[{...state.form.lines[0],qty:6}]})[0],a=actById(state.form.lines[0].act);
    ok('6. The figures: today, cumulative = up to yesterday + today, balance = scope − cumulative, planned MP = quantity ÷ planned rate ÷ 8 h, PI = earned ÷ worked manhours',
      R.today===6&&Math.abs(R.cum-(R.before+6))<1e-9&&Math.abs(R.bal-Math.max(0,R.scope-R.cum))<1e-9&&Math.abs(R.plan-6/a.pp/8)<1e-9&&Math.abs(R.pi-lpi({...state.form.lines[0],qty:6}))<1e-9,R);
    close();document.querySelector('[data-save=submit]').click();await wait(1500);const d=DB.dprs[DB.dprs.length-1];
    ok('7. The weather, constraints and recovery actions are kept with the report',d.weather==='Windy, 38 °C'&&/Material delivery/.test(d.issues)&&/Night shift/.test(d.recovery),[d.weather,d.issues,d.recovery]);
    /* 8-9: review and approval preview the report */
    as(sa);openDpr(d.id);await wait(200);const pb=document.querySelector(`[data-dprprev="${d.id}"]`);
    ok('8. The report shows the weather, constraints and recovery actions, and Preview report beside the review actions',!!pb&&!!document.querySelector('[data-do=review]')&&/Weather: Windy/.test($('#sheet').innerText)&&/Major constraints/.test($('#sheet').innerText));
    pb.click();V=await view();
    ok('9. Preview while reviewing: the saved report, prepared and signed by the foreman, review and approval pending',/is submitted/.test(V.tx)&&/Prepared By[\s\S]{0,120}Signed in ProTrack/.test(V.tx)&&/Reviewed By[\s\S]{0,80}\(pending\)/.test(V.tx));
    const kd=new KeyboardEvent('keydown',{key:'Escape',bubbles:true});document.activeElement.dispatchEvent(kd);await wait(100);
    ok('10. Escape closes the preview and leaves the report open',!$('#docView')&&!$('#drawer').hidden);
    /* 11-13: approval sends the report to the Approval email list */
    const c=mailCfg(),keepOn=c.on;c.on=true;const n0=(DB.outbox||[]).length;
    doAction('review');await wait(300);openDpr(d.id);doAction('approve');await wait(1500);const m=(DB.outbox||[])[0],want=mailRecipients(d).length;
    ok('11. Once approved, the report is sent to everyone on the Approval email list',d.status==='Approved'&&(DB.outbox||[]).length===n0+1&&m.dpr===d.id&&m.to.length===want&&want>0,[m&&m.to.length,want]);
    ok('12. The email is the Daily Productivity Report, approved and signed, with a link and no embedded pictures (mail programs block them)',/DAILY PRODUCTIVITY REPORT/.test(m.html)&&/Approved By[\s\S]{0,400}Signed in ProTrack/.test(m.html)&&m.html.includes(dprLink(d))&&!/src="data:/.test(m.html)&&!/Preview ·/.test(m.html));
    c.on=false;const n1=(DB.outbox||[]).length;await sendApprovalMail(d);
    ok('13. With the Approval email switched off, nothing is sent',(DB.outbox||[]).length===n1);c.on=keepOn;
    openDpr(d.id);document.querySelector(`[data-dprprev="${d.id}"]`).click();V=await view();
    ok('14. After approval the preview has no preview note, and all three have signed',!/Preview ·/.test(V.tx)&&(V.tx.match(/Signed in ProTrack/g)||[]).length===3);close();closeDrawer();
    /* 15-17: weekly and monthly reports preview before submitting */
    const pid=PROJECTS.find(p=>{const pl=teamOf(p.id,'plan')[0];if(!pl)return false;as(pl.id);return rmCanEdit(p.id,'planning','week',curWeek())&&rmCanEdit(p.id,'planning','month',TODAY.slice(0,7))})?.id;
    for(const [t,per,i] of [['week',curWeek(),15],['month',TODAY.slice(0,7),16]]){state.rdTab='notes';openPlanRelease(pid,t,per);$('#drawer').hidden=false;await wait(300);
      const n=document.querySelector('#relForm [name=n_summary]');n.value=`Typed ${t} summary (SAMPLE)`;
      const b=document.querySelector(`[data-relprev="${pid}|${t}|${per}"]`),sub=!!document.querySelector('[data-reldo=submit]');b.click();V=await view();
      ok(`${i}. The ${t==='week'?'weekly':'monthly'} report: Preview report beside Submit shows the report as typed, before saving`,sub&&V.tx.includes(t==='week'?'WEEKLY PROGRESS REPORT':'MONTHLY PROGRESS REPORT')&&V.tx.includes(`Typed ${t} summary`)&&['PROGRESS SUMMARY','MILESTONES','MANPOWER','REPORT NOTES'].every(s=>V.tx.includes(s))&&/before saving/.test($('#docView .docttl').innerText)&&/what will be submitted/.test(V.tx));close()}
    const sub=relRows().find(r=>r.kind==='planning'&&r.status==='Submitted');
    if(sub){as(sa);openPlanRelease(sub.project_id,sub.period_type,sub.period);await wait(300);document.querySelector(`[data-relprev="${sub.project_id}|${sub.period_type}|${sub.period}"]`).click();V=await view();
      ok('17. The approver previews a submitted report, as submitted',/awaiting/.test(V.tx)&&/as submitted|submitted, rev/.test($('#docView .docttl').innerText));close()}
    else ok('17. The approver previews a submitted report (none in the sample data; skipped)',true);
    closeDrawer();
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.toast=keepToast;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Report previews: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__rpvChecks=res;try{sessionStorage.setItem('rpvChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
