/* ProTrackAI v3.44: the company logo and the customers with their logos (Settings → Logos and customers), the MER's Project
   wise page in the PLAN-006-FORM-01 layout with its Excel and PDF exports, and the progress photos and videos of the internal and
   client reports. Acceptance checks for the demo page. How to run: open demo.html, sign in with the demo Super Admin account
   (U28), open the browser console and paste this whole file. It saves this browser's demo data first and puts it back at the
   end, then reloads the page. The logos and photos are drawn here and labelled SAMPLE. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms)),keep=saveFile,keepToast=toast,toasts=[];
  const mk=(w,h,txt,col)=>{const c=document.createElement('canvas');c.width=w;c.height=h;const g=c.getContext('2d');g.fillStyle=col;g.fillRect(0,0,w,h);g.fillStyle='#fff';g.font='bold '+Math.round(h/5)+'px sans-serif';g.fillText(txt,20,h/2);return c};
  const file=async(c,name,type,q)=>new File([await new Promise(r=>c.toBlob(r,type,q))],name,{type,lastModified:Date.parse('2026-09-10T10:00:00Z')});
  const grab=async fn=>{let out=null;saveFile=async(n,b)=>{out={n,b}};await fn();saveFile=keep;return out};
  try{
    const sa=me().id,U=DB.master.users,pl=teamOf('RMX','plan')[0],pmU=U.find(u=>u.role==='pm'&&u.active!==false&&onProject(u,'RMX'));window.toast=m=>toasts.push(m);
    ok('1. Version 3.44 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=44,APP_VERSION);
    // 2-5: logos and customers
    state.adminTab='brand';go('admin');await wait(80);const adm=$('#view').innerText;
    as(pl.id);const nsa=await brandSet({name:'x',logo:null});as(sa);
    ok('2. Settings → Logos and customers, for the super admin only',/Logos and customers/.test(adm)&&/Company logo/.test(adm)&&/Customers/.test(adm)&&nsa===false&&/Only the super admin/.test(toasts.pop()||''));
    const big=await logoFromFile(await file(mk(2400,1600,'SAMPLE LOGO','#0b5394'),'logo.png','image/png')),bi=await rmLoadImg(big);
    let svgErr='';try{await logoFromFile(new File(['<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'],'x.svg',{type:'image/svg+xml'}))}catch(e){svgErr=e.message}
    ok('3. A logo is made web-sized (at most 800 × 400); an SVG with a script and a non-image are refused',bi.naturalWidth<=800&&bi.naturalHeight<=400&&/scripts/.test(svgErr)&&/must be a PNG/.test(brCheckLogo('data:text/html;base64,AAAA')||''),[bi.naturalWidth,bi.naturalHeight]);
    await brandSet({name:'alfanar',logo:big});
    const cl=await logoFromFile(await file(mk(600,300,'SAMPLE CLIENT','#38761d'),'c.png','image/png')),client=projById('RMX').client;
    const c1=await custAct('create',{name:client,logo:cl,active:true}),dup=await custAct('create',{name:client.toUpperCase(),logo:null});const dupMsg=toasts.pop()||'';
    const cu=custOf(client),del=await custAct('delete',{id:cu.id});const delMsg=toasts.pop()||'';
    await custAct('create',{name:'Old Name Utility (SAMPLE)',active:false});
    ok('4. A customer with its logo; the same name twice and deleting a customer that is a client are refused; an inactive one is not suggested',
      c1&&!dup&&/already exists/.test(dupMsg)&&!del&&/make it inactive/.test(delMsg)&&!!custLogo(client)&&!/Old Name Utility/.test(custDatalist()),[dupMsg,delMsg]);
    await custAct('update',{id:cu.id,name:client+' (renamed SAMPLE)',logo:cl,active:true});const renamed=projById('RMX').client;await custAct('update',{id:cu.id,name:client,logo:cl,active:true});
    const lists=[...document.scripts].map(x=>x.textContent).join('').split('list="custList"').length-1;
    ok('5. Renaming a customer renames the client of its projects; the tender forms suggest the customers',renamed===client+' (renamed SAMPLE)'&&projById('RMX').client===client&&lists>=2&&/<datalist id="custList">/.test(custDatalist()),{renamed,lists});
    // 6-9: Project wise in the PLAN-006 layout, Excel and PDF
    go('mer');Object.assign(merState(),{tab:'proj',pid:'RMX',basis:'int'});render();await wait(300);
    const secs=[...document.querySelectorAll('.pf .pftbl tr.pfsec td')].map(t=>t.textContent);
    ok('6. Project wise: the PLAN-006-FORM-01 sections in the PE sheet\'s order, the company and client logos, four charts, the footer',
      secs.join()==='PROJECT INFORMATION,PROGRESS PERCENTAGE,SCHEDULE STATUS,CLAIM STATUS,COMMERCIAL STATUS,BUDGET STATUS,MANPOWER,AREAS OF CONCERN'&&document.querySelectorAll('.pflogos img.brlogo').length===2&&MER_CH.length===4&&/PLAN-006-FORM-01/.test($('.pffoot').innerText),secs);
    const F=merForm(merData(merState()).rows.find(r=>r.p.id==='RMX'));
    ok('7. The form\'s rows: 8 information rows, 16 commercial rows, the budget by WBS head (GP %, overall, 18 heads, potential risks), schedule Var. = revised (else contract) − forecast',
      F.info.length===8&&F.comm.length===16&&F.budget.length>=21&&F.budget[20][0]==='Potential Risks'&&F.sched.slice(2).every(x=>x[4]==null||x[4]===diffDays(x[3],x[2]||x[1])),F.budget.length);
    await loadLib(LIBS.xlsx);const X=await grab(()=>merExport()),wb=XLSX.read(new Uint8Array(await X.b.arrayBuffer()),{type:'array',bookFiles:true}),ws=wb.Sheets['RMX'],media=Object.keys(wb.files||{}).filter(k=>/^xl\/media\//.test(k));
    const mg=(ws['!merges']||[]).map(m=>XLSX.utils.encode_range(m));
    ok('8. Excel: COST, DASHBOARD and a PE-layout sheet per project (same cells and merges), with the logos and the chart pictures; print area A1:P103',
      wb.SheetNames[0]==='COST(I)'&&wb.SheetNames[1]==='DASHBOARD'&&ws.B1.v==='PROJECT INFORMATION'&&ws.B74.v==='MANPOWER'&&ws.B82.v==='DESIGN / ENGINEERING'&&ws.N102.v==='PLAN-006-FORM-01'&&ws.B111.v==='Planned'&&['B2:D2','E2:I2','G36:I36','C53:D53','K83:P83'].every(r=>mg.includes(r))&&media.length>=5,{media:media.length});
    const P1=await grab(()=>merPdf('RMX')),Pa=await grab(()=>merPdf()),lib=await pvPdfLib(),n1=(await lib.getDocument({data:new Uint8Array(await P1.b.arrayBuffer())}).promise).numPages,na=(await lib.getDocument({data:new Uint8Array(await Pa.b.arrayBuffer())}).promise).numPages,nr=merData(merState()).rows.length;
    ok('9. PDF: one A4 page for a project; the whole MER is Cost and Dashboard (A3) then a page per project; a sensible size',n1===1&&na>=2+nr&&P1.b.size<1.5e6&&Pa.b.size<12e6&&/\.pdf$/.test(Pa.n),{n1,na,nr,one:P1.b.size,all:Pa.b.size});
    // 10-16: photos and videos
    const per=ym(ASOF),ctx={pid:'RMX',kind:'planning',t:'month',per};as(pl.id);
    const n=await rmAdd([await file(mk(3000,2000,'SITE PHOTO SAMPLE','#7f6000'),'IMG_1.jpg','image/jpeg',0.9),await file(mk(800,600,'SAMPLE 2','#134f5c'),'IMG_2.png','image/png')],ctx);let L=rmOf('RMX','planning','month',per);
    const big1=await rmLoadImg(URL.createObjectURL(await rmBlob(L[0])));
    ok('10. The planning engineer adds photos to the monthly internal report: resized to 1920 pixels, a preview, the date taken from the file',n===2&&L.length===2&&Math.max(big1.naturalWidth,big1.naturalHeight)===1920&&L.every(m=>m.thumb&&m.mime==='image/jpeg'&&m.taken_on==='2026-09-10'),[big1.naturalWidth,big1.naturalHeight]);
    await rmAct('update',L[0].id,{caption:'Cable pulling, Zone A (SAMPLE)'});let bad='';const tooLong=await rmAct('update',L[1].id,{caption:'x'.repeat(301)});bad=toasts.pop()||'';
    ok('11. A caption is kept (300 characters at most)',rmOf('RMX','planning','month',per)[0].caption==='Cable pulling, Zone A (SAMPLE)'&&!tooLong&&/300 characters/.test(bad));
    let vid=null;try{const c=mk(320,240,'VIDEO','#444'),stv=c.captureStream(10),rec=new MediaRecorder(stv,{mimeType:'video/webm'}),ch=[];rec.ondataavailable=e=>ch.push(e.data);rec.start();for(let i=0;i<8;i++){c.getContext('2d').fillRect(i*30,0,20,20);await wait(100)}rec.stop();await new Promise(r=>rec.onstop=r);vid=new File(ch,'clip.webm',{type:'video/webm'})}catch(e){}
    if(vid){await rmAdd([vid],ctx);const v=rmOf('RMX','planning','month',per).find(m=>m.mime==='video/webm');ok('12. A video is kept as it is, with a preview frame and its length',!!v&&v.size===vid.size&&!!v.thumb&&v.duration!=null)}else ok('12. A video (this browser cannot record one; skipped)',true,'skipped');
    let ex='';try{await rmPrepare(new File(['x'],'doc.pdf',{type:'application/pdf'}))}catch(e){ex=e.message}
    ok('13. Other files are refused',/use JPG, PNG or WEBP photos, or MP4, WEBM or MOV videos/.test(ex),ex);
    const relM=recentMonths(3)[1],lockN=await rmAdd([await file(mk(400,300,'X','#000'),'x.jpg','image/jpeg')],{pid:'RMX',kind:'planning',t:'month',per:relM});const lockMsg=toasts.pop()||'';
    as(pmU.id);const pmN=rmCanEdit('RMX','planning','month',per);as(pl.id);
    ok('14. Locked once the report is approved; someone who does not prepare reports cannot add',!rmCanEdit('RMX','planning','month',relM)&&lockN===0&&/locked/.test(lockMsg)&&pmN===false,lockMsg);
    as(sa);const cp=await rmCopyInternal('RMX','month',per),cp2=await rmCopyInternal('RMX','month',per),C=rmOf('RMX','client','month',per);
    ok('15. The client report copies the internal report\'s photos and videos once; each report keeps its own',cp===rmOf('RMX','planning','month',per).length&&cp2===0&&C.length===cp&&C.every(m=>m.from&&m.id!==m.from),{cp,cp2});
    const ph=await rmPrintHTML('RMX','client','month',per);
    ok('16. The client report\'s Print or save as PDF prints the photos with their captions and lists the videos',/<h2>Progress photos<\/h2>/.test(ph)&&/Cable pulling, Zone A \(SAMPLE\)/.test(ph)&&(!vid||/<h2>Progress videos<\/h2>/.test(ph)));
    state.clTab='media';openClientRelease('RMX','month',per);await wait(100);const ctab=[...document.querySelectorAll('#sheet [data-cltab]')].map(b=>b.dataset.cltab);
    state.rdTab='media';openPlanRelease('RMX','week',recentWeeks(1)[0]);await wait(100);const wtab=[...document.querySelectorAll('#sheet [data-rdtab]')].map(b=>b.dataset.rdtab);
    ok('17. The Photos & videos tab is in the client report and the weekly internal report too',ctab.includes('media')&&wtab.includes('media')&&!!$('#rmPanel'),{ctab,wtab});
    const d0=rmOf('RMX','client','month',per)[0];await rmAct('delete',d0.id);const gone=await DOCIDB.get('rm:'+d0.id);
    ok('18. Deleting removes the record and the stored file; the internal report keeps its own',!rmRows().some(m=>m.id===d0.id)&&gone==null&&rmOf('RMX','planning','month',per).length>=2);
    {const x=document.querySelector('#sheet [data-close]');if(x)x.click()}
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keep;window.toast=keepToast;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Logos, PLAN-006 exports, photos and videos: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__lmChecks=res;try{sessionStorage.setItem('lmChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
