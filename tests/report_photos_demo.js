/* ProTrackAI v3.53: site photos on the daily report (prepare, review, approve), the weekly report picking from that week's daily
   photos, the monthly report picking from the weekly and daily reports of the month, uploads from a computer or a phone, and the
   photo viewer in every report. Acceptance checks for the demo page. How to run: open demo.html, sign in with the demo Super Admin
   account (U28), open the browser console and paste this whole file. It saves this browser's demo data first and puts it back at
   the end, then reloads the page. The photos are drawn here and labelled SAMPLE. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms)),keepToast=toast,toasts=[],ids0=new Set(rmRows().map(m=>m.id));
  const mk=async(txt,col,type)=>{const c=document.createElement('canvas');c.width=2400;c.height=1800;const g=c.getContext('2d');g.fillStyle=col;g.fillRect(0,0,2400,1800);g.fillStyle='#fff';g.font='bold 150px sans-serif';g.fillText(txt,100,900);
    return new File([await new Promise(r=>c.toBlob(r,type,0.9))],txt.replace(/\W+/g,'_')+(type==='image/png'?'.png':'.jpg'),{type})};
  const put=async(inp,files)=>{const dt=new DataTransfer();files.forEach(f=>dt.items.add(f));inp.files=dt.files;inp.dispatchEvent(new Event('change',{bubbles:true}));await wait(2500)};
  const key=k=>document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:k,bubbles:true}));
  try{
    window.toast=m=>toasts.push(m);const sa=me().id,wk=curWeek(),mo=TODAY.slice(0,7);
    ok('1. Version 3.53 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=53,APP_VERSION);
    /* a project whose weekly and monthly internal reports can still be prepared, with a foreman who reports on it */
    const P=PROJECTS.filter(p=>p.status==='Active'&&p.foremen.length&&teamOf(p.id,'plan')[0]&&ACTS.some(a=>a.p===p.id&&isCon(a))).find(p=>{const pl=teamOf(p.id,'plan')[0];as(pl.id);return rmCanEdit(p.id,'planning','week',wk)&&rmCanEdit(p.id,'planning','month',mo)});
    if(!P)throw new Error('No project with this week\'s and this month\'s internal reports open to prepare');
    const pid=P.id,pl=teamOf(pid,'plan')[0],fm=DB.master.users.find(u=>u.role==='foreman'&&u.active!==false&&P.foremen.includes(u.name));
    if(!fm)throw new Error('No foreman user on '+pid);
    /* 2-5: the foreman prepares a daily report with photos */
    as(fm.id);state.form=null;state.editing=null;go('new');await wait(300);state.form.p=pid;state.form.foreman=fm.name;state.form.lines=[blankLine(pid)];renderForm();await wait(200);
    const cam=$('#dpCam');ok('2. The form has Site photos, with Add photos (this computer) and Take a photo (the phone camera, shown on touch screens)',!!$('#dpPhotos')&&!!$('#dpPick')&&cam&&cam.getAttribute('capture')==='environment'&&/^image\//.test(cam.accept)&&getComputedStyle(document.querySelector('label[for=dpCam]')).display===(matchMedia('(pointer:coarse)').matches?'inline-block':'none'));
    await put($('#dpPick'),[await mk('SAMPLE photo A','#2a6f97','image/jpeg'),await mk('SAMPLE photo B','#6a994e','image/png'),new File(['x'],'notes.txt',{type:'text/plain'})]);
    const im=new Image();im.src=URL.createObjectURL(DPF.add[0].blob);await im.decode();
    ok('3. Two photos wait in the form, resized to 1920 pixels; a text file is refused',DPF.add.length===2&&Math.max(im.naturalWidth,im.naturalHeight)===1920&&toasts.some(t=>/notes\.txt: use JPG, PNG or WEBP/.test(t))&&document.querySelectorAll('#dpSet .phcard').length===2,[DPF.add.length,im.naturalWidth]);
    {const c=document.querySelector('[data-dpcapt]');c.value='Zone A slab pour (SAMPLE)';c.dispatchEvent(new Event('input',{bubbles:true}))}
    document.querySelector('[data-pvtmp]').click();await wait(400);
    ok('4. Preview while preparing: an unsaved photo opens in the viewer, with its caption, "Not saved yet" and 1 of 2',!!document.querySelector('.rmview #pvBody img')&&/Zone A slab pour/.test($('#pvCap').innerText)&&/Not saved yet/.test($('#pvCap').innerText)&&$('#pvCnt').textContent==='1 of 2');
    document.querySelector('.rmview [data-pvx]').click();
    const q=document.querySelector('[data-lk=qty]');q.value='5';q.dispatchEvent(new Event('input',{bubbles:true}));
    const nD=DB.dprs.length;document.querySelector('[data-save=draft]').click();await wait(1500);
    const d=DB.dprs[DB.dprs.length-1],L1=dprPhotos(d),b1=await DOCIDB.get('rm:'+(L1[0]||{}).id);
    ok('5. Saving the draft stores the photos with the report: its id, its date, the caption, the file in this browser',DB.dprs.length===nD+1&&L1.length===2&&L1.every(m=>m.kind==='dpr'&&m.period===d.id&&m.taken_on===d.date&&m.path.startsWith(`${pid}/dpr/dpr-${d.id}/`))&&L1.some(m=>m.caption==='Zone A slab pour (SAMPLE)')&&!!b1,L1.map(m=>m.path));
    /* 6-7: editing keeps photos only when saved; the limit */
    openDpr(d.id);doAction('edit');await wait(300);document.querySelectorAll('[data-dpdel]')[0].click();go('dpr');await wait(200);
    ok('6. Leaving the form without saving changes nothing',dprPhotos(d).length===2);
    openDpr(d.id);doAction('edit');await wait(300);
    DPF.add=Array.from({length:DPR_PH_MAX-2},(_,i)=>({tmp:'t'+i,blob:new Blob(['x']),mime:'image/jpeg',name:'x.jpg',size:1,thumb:'',caption:''}));toasts.length=0;
    await dpAddFiles([await mk('SAMPLE one too many','#999','image/jpeg')]);
    ok(`7. A daily report holds ${DPR_PH_MAX} photos at most`,DPF.add.length===DPR_PH_MAX-2&&toasts.some(t=>new RegExp(`At most ${DPR_PH_MAX} photos`).test(t)));
    DPF.add=[];dpRedraw();
    const keepId=dprPhotos(d).find(m=>m.caption)?.id||dprPhotos(d)[0].id;document.querySelector(`[data-dpdel]:not([data-dpdel="${keepId}"])`).click();
    {const c=document.querySelector(`[data-dpcap="${keepId}"]`);c.value='Zone A slab pour, east bay (SAMPLE)';c.dispatchEvent(new Event('input',{bubbles:true}))}
    await put($('#dpCam'),[await mk('SAMPLE camera','#9c6644','image/jpeg')]);
    document.querySelector('[data-save=submit]').click();await wait(1800);const L2=dprPhotos(d);
    ok('8. Edit and submit: a removed photo is gone (record and file), the caption changed, the camera photo added',d.status==='Submitted'&&L2.length===2&&L2.some(m=>m.caption==='Zone A slab pour, east bay (SAMPLE)')&&!L1.filter(m=>m.id!==keepId).some(m=>rmRows().includes(m)),L2.map(m=>m.caption));
    /* 9-10: review and approval see the photos */
    go('dpr');await wait(200);const row=[...document.querySelectorAll('tr.click')].find(r=>r.dataset.open===d.id);
    ok('9. The list shows how many photos a report has',!!row&&/2 photos/.test(row.innerText));
    as(sa);openDpr(d.id);await wait(200);
    ok('10. Review and approval: the report shows its site photos, with Preview all, beside the review actions',document.querySelectorAll('#dpvSet .phcard').length===2&&!!document.querySelector('[data-pvall=dpvSet]')&&!!document.querySelector('[data-do=review]'));
    document.querySelector('[data-pvall=dpvSet]').click();await wait(500);const c0=$('#pvCnt').textContent;key('ArrowRight');await wait(300);const c1=$('#pvCnt').textContent;key('ArrowRight');await wait(200);const c2=$('#pvCnt').textContent;
    const o=document.querySelector('.rmview');o.dispatchEvent(new PointerEvent('pointerdown',{clientX:300,bubbles:true}));o.dispatchEvent(new PointerEvent('pointerup',{clientX:100,bubbles:true}));await wait(200);const c3=$('#pvCnt').textContent;
    key('Escape');await wait(100);
    ok('11. The viewer steps with → (round to the first), a swipe, and Escape closes only the viewer',c0==='1 of 2'&&c1==='2 of 2'&&c2==='1 of 2'&&c3==='2 of 2'&&!document.querySelector('.rmview')&&!$('#drawer').hidden,[c0,c1,c2,c3]);
    closeDrawer();
    /* 12-15: the weekly report picks from the week's daily photos */
    const other=DB.dprs.find(x=>x.p===pid&&isoWeekOf(x.date)===wk&&x.id!==d.id&&x.status!=='Rejected');
    let draftOk=true;if(other){const keepSt=other.status;other.status='Draft';const ph={id:rmUuid(),project_id:pid,kind:'dpr',period_type:'dpr',period:other.id,path:`${pid}/dpr/dpr-${other.id}/x.jpg`,name:'x.jpg',mime:'image/jpeg',size:1,thumb:null,taken_on:other.date,caption:'draft photo'};rmRows().push(ph);
      draftOk=!rmCands(pid,'week',wk).daily.some(x=>x.m.id===ph.id);other.status='Rejected';draftOk=draftOk&&!rmCands(pid,'week',wk).daily.some(x=>x.m.id===ph.id);rmRows().splice(rmRows().indexOf(ph),1);other.status=keepSt}
    as(pl.id);state.rdTab='media';openPlanRelease(pid,'week',wk);$('#drawer').hidden=false;await wait(300);
    const mine=[...document.querySelectorAll('#rmPkD [data-rmsel]')].filter(c=>L2.some(m=>m.id===c.dataset.rmsel));
    ok('12. The weekly report offers the daily photos of its week (not drafts or rejected reports), each with its report and date',mine.length===2&&draftOk&&/Pick from the daily reports of this week/.test($('.phsrc summary').innerText)&&[...document.querySelectorAll('#rmPkD .t2')].some(t=>t.textContent.includes(d.id)));
    mine.forEach(c=>{c.checked=true;c.dispatchEvent(new Event('change',{bubbles:true}))});
    ok('13. Ticking photos counts them on the add button',$('#rmSelN').textContent==='2'&&!document.querySelector('[data-rmadd]').disabled);
    document.querySelector('[data-rmadd]').click();await wait(1500);const W=rmOf(pid,'planning','week',wk);
    ok('14. Add selected copies them into the weekly report (its own copies), shown there as "In this report"',W.filter(m=>L2.some(s=>s.id===m.from)).length===2&&[...document.querySelectorAll('#rmPkD .phpick.done')].length>=2&&!!(await DOCIDB.get('rm:'+W[W.length-1].id)));
    const again=await rmCopyFrom({pid,kind:'planning',t:'week',per:wk},L2);
    ok('15. Adding the same photos again adds nothing',again===0&&rmOf(pid,'planning','week',wk).length===W.length);
    await put($('#rmFile'),[await mk('SAMPLE weekly own','#5e548e','image/jpeg')]);
    ok('16. The planning engineer can still add photos from this computer or phone (Add photos or videos, Take a photo)',rmOf(pid,'planning','week',wk).length===W.length+1&&!!$('#rmCam')&&$('#rmCam').getAttribute('capture')==='environment');
    /* 17-19: the monthly report picks from the weekly and daily reports of the month */
    state.rdTab='media';openPlanRelease(pid,'month',mo);await wait(300);const C=rmCands(pid,'month',mo);
    ok('17. The monthly report offers the weekly reports\' photos and the daily photos of the month, in two groups',/Pick from the weekly and daily reports of this month/.test($('.phsrc summary').innerText)&&C.weekly.length>=3&&document.querySelectorAll('#rmPkW .phcard').length===C.weekly.length&&document.querySelectorAll('#rmPkD .phcard').length===C.daily.length,[C.weekly.length,C.daily.length]);
    ok('18. A daily photo already in a weekly report is offered once, with the weekly report',!C.daily.some(x=>L2.some(m=>m.id===x.m.id))&&C.shown>=2&&/shown once, with the weekly report/.test($('.phsrc').innerText));
    const m0=rmOf(pid,'planning','month',mo).length,free=rmPickFree(pid,'month',mo).length;
    document.querySelector('[data-rmall]').click();await wait(200);document.querySelector('[data-rmadd]').click();await wait(4000);
    const M=rmOf(pid,'planning','month',mo),root=m=>{const s=rmRows().find(x=>x.id===m.from);return s&&s.from?s.from:m.from},R=M.map(root);
    ok('19. Select all and add: every photo once, none twice',M.length===Math.min(RM_MAX_N,m0+free)&&R.length===new Set(R).size&&(M.length===RM_MAX_N||/^0 to pick from/.test($('.phsrc summary .muted').innerText)),[m0,free,M.length,new Set(R).size]);
    /* 20-21: approval and locked reports */
    state.rdTab='appr';openPlanRelease(pid,'month',mo);await wait(300);const ar=[...document.querySelectorAll('.tbl.kv tr')].find(r=>/Photos and videos/.test(r.innerText));
    ar.querySelector('[data-pvall]').click();await wait(500);const vc=$('#pvCnt').textContent;document.querySelector('.rmview [data-pvx]').click();
    ok('20. The Approval tab says how many photos the report has and previews them all',new RegExp(`${M.length} photos`).test(ar.innerText)&&vc===`1 of ${M.length}`,[ar.innerText,vc]);
    const sub=relRows().find(r=>r.kind==='planning'&&r.status==='Submitted');
    if(sub){as(teamOf(sub.project_id,'plan')[0]?.id||pl.id);state.rdTab='media';openPlanRelease(sub.project_id,sub.period_type,sub.period);await wait(300);
      ok('21. A report with the approver is locked: no picking or adding, and it says why',!document.querySelector('.phsrc')&&!$('#rmFile')&&/Locked while the report is with the reviewer or approver/.test($('#rmPanel').innerText))}
    else ok('21. A report with the approver is locked (no submitted report in the sample data to try)',true);
    closeDrawer();
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.toast=keepToast;for(const m of rmRows())if(!ids0.has(m.id))try{await DOCIDB.del('rm:'+m.id)}catch(e){}try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Report photos: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__rpChecks=res;try{sessionStorage.setItem('rpChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
