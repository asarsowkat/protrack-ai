/* ProTrackAI v3.19.2, correspondence and letters of a delay event. Acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},err=f=>{try{f();return ''}catch(x){return x.message}};
  const wait=ms=>new Promise(r=>setTimeout(r,ms)),sa=DB.master.users.find(u=>u.role==='sa'&&u.active!==false),conf=window.confirm,keepSave=window.saveFile;window.confirm=()=>true;
  let saved=null;window.saveFile=async(n,b)=>{saved={n,b}};
  try{
    as(sa.id);const p=PROJECTS[0],e1=dlyRows().find(e=>e.id==='DE'+p.id+'1'),e2=dlyRows().find(e=>e.id==='DE'+p.id+'2'),L1=dlyCorrOf(e1.id);
    ok('1. The demo event carries its letters in date order',L1.length===4&&L1.every((c,i)=>!i||L1[i-1].corr_date<=c.corr_date)&&dlyCorrOf(e2.id).length===1);
    go('dly');await wait(200);
    ok('2. The register shows how many letters an event has',/4 letters/.test($('#view').innerText));
    openDly(e1.id);await wait(200);
    ok('3. The window shows the section, its downloads and the form for a keeper',!!document.querySelector('[data-dlycsec]')&&!!document.querySelector('[data-dlycpack]')&&!!document.querySelector('[data-dlycadd]'));
    closeDrawer();
    /* 4-8: recording */
    const base={kind:'Letter',direction:'in',corr_date:addDays(TODAY,-3),ref_no:'ENG-LTR-0400',subject:'Further access restrictions',from_party:'The Engineer',to_party:'alfanar PM'};
    const c1=delayCorrActLocal({action:'add',event_id:e2.id,...base,link:true});
    ok('4. A received letter is recorded, and its reference added to Supporting documents ref.',c1&&/ENG-LTR-0400 \(/.test(dlyRows().find(e=>e.id===e2.id).support_docs||''));
    ok('5. Adding the same reference again does not repeat it in the register',(delayCorrActLocal({action:'add',event_id:e2.id,...base,subject:'Reminder',link:true}),(dlyRows().find(e=>e.id===e2.id).support_docs.match(/ENG-LTR-0400/g)||[]).length===1));
    const e5=dlyRows().find(e=>e.project_id===p.id&&!e.notice_date&&e.start_date);
    const noc={kind:'Notice of claim',direction:'out',corr_date:addDays(e5.start_date,2)>TODAY?TODAY:addDays(e5.start_date,2),ref_no:'ALF-NOC-0099',subject:'Notice of claim'};
    delayCorrActLocal({action:'add',event_id:e5.id,...noc,link:true});const e5b=dlyRows().find(e=>e.id===e5.id);
    ok('6. A sent notice of claim dates the notice and fills Notice of claim documents ref.',e5b.notice_date===noc.corr_date&&/ALF-NOC-0099/.test(e5b.notice_docs||'')&&dlyNotice(e5b).k!=='passed');
    const early={...noc,ref_no:'ALF-NOC-0100',corr_date:addDays(e1.start_date,-5)};
    ok('7. A link the register refuses says how to record the letter only',/before the event started.*untick/.test(err(()=>delayCorrActLocal({action:'add',event_id:dlyRows().find(e=>!e.notice_date&&e.start_date&&e.id!==e5.id).id,...early,link:true})))
      ||/untick/.test(err(()=>delayCorrActLocal({action:'add',event_id:e2.id,...early,kind:'Notice of claim',corr_date:addDays(e2.start_date,-5),link:true}))));
    ok('8. The rules: future date, no subject, unknown type',/future/.test(err(()=>delayCorrActLocal({action:'add',event_id:e2.id,...base,corr_date:addDays(TODAY,2)})))&&/subject/.test(err(()=>delayCorrActLocal({action:'add',event_id:e2.id,...base,subject:' '})))
      &&/type/.test(err(()=>delayCorrActLocal({action:'add',event_id:e2.id,...base,kind:'Fax'}))));
    /* 9-11: files */
    const f=new File(['Letter ENG-LTR-0401: access refused on 18 Sept.'],'ENG-LTR-0401.txt',{type:'text/plain'});
    const c2=await dlyCorrUpload(e2,f,{...base,ref_no:'ENG-LTR-0401',subject:'Access refused',link:false});
    ok('9. A file is kept with the record, and opens',c2&&c2.file_name==='ENG-LTR-0401.txt'&&/access refused/.test(await (await dlyCorrBlob(c2)).text()));
    ok('10. The same file twice on one event is refused',!(await dlyCorrUpload(e2,f,{...base,ref_no:'X',subject:'Again'}))&&/already attached/.test(delayCorrAct.err));
    ok('11. A file type outside the list is refused',!(await dlyCorrUpload(e2,new File(['x'],'tool.exe'),{...base,subject:'x'}))&&/not accepted/.test(delayCorrAct.err));
    /* 12-14: removing, deleting, rights */
    ok('12. Removing needs a reason; the record leaves the list and stays in the history',/why/.test(err(()=>delayCorrActLocal({action:'remove',id:c1.id})))
      &&(delayCorrActLocal({action:'remove',id:c1.id,note:'Recorded twice'}),!dlyCorrOf(e2.id).some(c=>c.id===c1.id)&&dlyCorrOf(e2.id,true).some(c=>c.id===c1.id)&&DB.dlyAudit.some(a=>a.event_id===e2.id&&a.action==='Correspondence removed')));
    ok('13. An event with letters cannot be deleted',/correspondence and letters first/.test(err(()=>delayActLocal({action:'delete',id:e1.id,note:'x'}))));
    const pm=DB.master.users.find(u=>u.role==='pm'&&accessIds(u).includes(p.id));as(pm.id);
    const pmErr=err(()=>delayCorrActLocal({action:'add',event_id:e1.id,...base}));go('dly');await wait(100);openDly(e1.id);await wait(150);
    ok('14. A project manager reads the letters but cannot add or remove them',/planning engineers of this project/.test(pmErr)&&!!document.querySelector('[data-dlycsec]')&&!document.querySelector('[data-dlycadd]')&&!document.querySelector('[data-dlycrm]'));
    closeDrawer();as(sa.id);
    /* 15-16: chronology and EOT pack */
    await loadLib(LIBS.xlsx);saved=null;await dlyCorrExcel(e1.id);const wb=XLSX.read(await saved.b.arrayBuffer(),{type:'array'}),A=XLSX.utils.sheet_to_json(wb.Sheets.Chronology,{header:1});
    ok('15. The chronology: the event, then every letter in date order, dates as Excel dates',wb.SheetNames.join()==='Chronology,Event'&&A[4][1]==='Date'&&A.length===5+4&&wb.Sheets.Chronology.B6.t==='n',A.slice(4,6));
    saved=null;await dlyCorrPack(e1.id);const z=await JSZip.loadAsync(await saved.b.arrayBuffer()),names=Object.keys(z.files).filter(n=>!n.endsWith('/'));
    ok('16. The EOT pack: the chronology and the files, numbered in date order',/^EOT_pack_/.test(saved.n)&&names.includes('00_Chronology.xlsx')&&names.filter(n=>n.startsWith('Correspondence/')).length===3&&names.some(n=>/^Correspondence\/01_.*ENG-LTR-0311\.txt$/.test(n)),names);
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{window.confirm=conf;window.saveFile=keepSave;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Delay event correspondence: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__dcChecks=res;try{sessionStorage.setItem('dcChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
