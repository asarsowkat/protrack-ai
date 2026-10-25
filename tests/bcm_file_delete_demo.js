/* ProTrackAI v3.40, Budget & Cost Management -> Tender File Intake: delete an uploaded tender costing file. Acceptance checks for the
   demo page. How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this
   whole file. It saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms));
  const err=fn=>{try{fn();return ''}catch(e){return e.message}};
  const U0=DB.master.users,sa=U0.find(u=>u.role==='sa'),co=U0.find(u=>u.role==='costing'&&u.active!==false&&u.id!==sa.id),fm=U0.find(u=>u.role==='foreman'&&u.active!==false);
  try{
    as(sa.id);await loadLib(LIBS.xlsx);go('bcm');const U=bcmUi();U.pid='RMX';U.sec='intake';
    // a batch of its own with two small workbooks
    const r=await bcmCall('batch_save',{project_id:'RMX',tender_ref:'T-DEL-CHECK',tender_rev:'0',currency:'SAR',ptype:'132 kV substation',title:'Delete check'});U.bid=r.id;const bid=r.id;
    const mk=rows=>XLSX.write((()=>{const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.aoa_to_sheet([['Item','Description','Qty','Unit','Rate','Amount'],...rows]),'Summary');return wb})(),{type:'array',bookType:'xlsx'});
    const bytesA=new Uint8Array(mk([['A1','Site staff salaries',1,'LS',100000,100000],['A2','Site villa rent',12,'month',15000,180000]])),bytesB=new Uint8Array(mk([['B1','Excavation for cable trench',100,'cu.m',40,4000]]));
    const file=(b,n)=>new File([b],n,{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
    await bcmUpload(bid,[file(bytesA,'Check A.xlsx'),file(bytesB,'Check B.xlsx')]);
    const fa=()=>bcmFilesOf(bid).find(f=>f.name==='Check A.xlsx'),fb=()=>bcmFilesOf(bid).find(f=>f.name==='Check B.xlsx');
    U.sec='intake';render();await wait(200);
    ok('1. Version 3.40; each file of an open batch has Delete for its uploader',APP_VERSION==='3.40'&&!!fa()&&!!fb()&&!!$(`[data-bcmfdel="${fa().id}"]`)&&!!$(`[data-bcmfdel="${fb().id}"]`));
    ok('2. The batch says a file uploaded by mistake can be deleted and uploaded again',/can be deleted \(Delete, with a reason\) and uploaded again/.test($('#view').innerText));
    // refusals
    ok('3. A reason of 3 characters at least',/Give the reason/.test(err(()=>BCML.file_delete({file_id:fa().id,reason:'x'}))));
    const S=bcmS3(),fakeV={id:'BV-CHECK',project_id:'RMX',kind:'Tender estimate',rev_no:99,status:'Draft',batch_id:bid};S.versions.push(fakeV);
    const m4=err(()=>BCML.file_delete({file_id:fa().id,reason:'Wrong file',confirm:true}));fakeV.status='Cancelled';const m4b=err(()=>BCML.file_delete({file_id:'none',reason:'Wrong file'}));
    ok('4. Refused while a budget version prepared from the batch is not rejected or cancelled',/Budget version Tender estimate rev 99 \(Draft\) was prepared from this batch. Reject or cancel it first; the file stays/.test(m4)&&!!fa()&&/Unknown file/.test(m4b),m4);
    S.versions.splice(S.versions.indexOf(fakeV),1);
    fb().status='Extracting';ok('5. Refused while the file is being read, and no Delete button then',/being read/.test(err(()=>BCML.file_delete({file_id:fb().id,reason:'Wrong file'})))&&!bcmCanDel(fb(),bcmBatch(bid)));fb().status='Extracted';
    // someone who uploads on this project but is not a reviewer and did not upload the file
    // (the demo's costing engineers are also reviewers, so the review right is switched off for this person, for this check only)
    const RU=rightsDB().user,keepRU=RU[co.id];RU[co.id]=Object.assign({},keepRU||{},{'bcm.review':false});as(co.id);
    const up=bcmCan('bcm.upload','RMX'),m6=err(()=>BCML.file_delete({file_id:fa().id,reason:'Not mine'})),cd6=bcmCanDel(fa(),bcmBatch(bid));
    if(keepRU===undefined)delete RU[co.id];else RU[co.id]=keepRU;
    ok('6. Someone who uploads on the project but did not upload the file (and is not a reviewer) cannot delete it',up&&/Only the person who uploaded the file, or a reviewer, deletes it/.test(m6)&&!cd6&&!!fa(),{up,m6});as(sa.id);
    as(sa.id);const FA=fa(),BA=bcmBatch(bid);as(fm.id);
    ok('7. A foreman cannot delete it',!bcmCanDel(FA,BA)&&/Only the person|Unknown file/.test(err(()=>BCML.file_delete({file_id:FA.id,reason:'Not mine'})))&&!!bcmDB().files.find(f=>f.id===FA.id));as(sa.id);
    // decided lines: a confirmation first, and the decisions go with the file; the history stays
    const LA=bcmDB().lines.filter(l=>l.file_id===fa().id),l0=LA.find(l=>bcmKind(l)==='item');const c0=bcmCls(l0.id)||{};
    bcmDB().cls[l0.id]=Object.assign({},c0,{status:'Confirmed',decided_by_name:sa.name});bcmDB().chist.push({line_id:l0.id,action:'Confirmed',status:'Confirmed',by_name:sa.name,at_time:new Date().toISOString()});
    S.dups.push({id:'DUP-CHECK',batch_id:bid,project_id:'RMX',kind:'exact',lines:[l0.id],status:'Decided'});S.allocs.push({id:'AL-CHECK',line_id:l0.id,status:'Proposed'});S.roles.push({file_id:fa().id,run:fa().run,sheet:'Summary',project_id:'RMX',batch_id:bid,role:'summary',status:'Confirmed'});
    ok('8. With decided lines, a confirmation first',/People have decided 1 line of this file\. Deleting it removes those decisions too \(their history is kept\)\. Confirm to go on\./.test(err(()=>BCML.file_delete({file_id:fa().id,reason:'Wrong revision'})))&&!!fa());
    // through the screen: Delete, the reason, the confirmation
    const fA=fa(),path=fA.path,had=!!(await DOCIDB.get('bcm:'+path)),nL=LA.length;U.sec='intake';render();await wait(150);
    $(`[data-bcmfdel="${fA.id}"]`).click();await wait(300);const q=$('#sheet h2').textContent;$('#bcmAskV').value='Wrong revision';$('#bcmAskOk').click();await wait(250);
    const cf=($('.cfm')||{}).innerText||'';$('[data-cfm="1"]').click();await wait(700);
    ok('9. Delete asks why, then confirms with the number of rows and the decided lines',/Why is Check A\.xlsx deleted\?/.test(q)&&/Delete Check A\.xlsx\?/.test(cf)&&new RegExp('Its '+nL+' rows read').test(cf)&&/decided 1 line of this file: those decisions go too/.test(cf),{q,cf});
    const B=bcmDB();ok('10. The file, its lines, their classification and the stored workbook are gone',had&&!bcmFile(fA.id)&&!B.lines.some(l=>l.file_id===fA.id)&&!B.cls[l0.id]&&!(await DOCIDB.get('bcm:'+path)));
    ok('11. Its splits and sheet roles go with it; a duplicate group that used its lines becomes obsolete',!S.allocs.some(a=>a.id==='AL-CHECK')&&!S.roles.some(r=>r.file_id===fA.id)&&S.dups.find(d=>d.id==='DUP-CHECK').status==='Obsolete');
    const a=B.audit[0];ok('12. The audit log keeps who, the file (name, SHA-256, size), its lines, the decisions and the reason; the classification history stays',a.action==='File deleted'&&a.ref===fA.id&&a.by_name===sa.name&&a.detail.name==='Check A.xlsx'&&a.detail.sha256===fA.sha256&&a.detail.lines===nL&&a.detail.decided===1&&a.detail.reason==='Wrong revision'&&B.chist.some(h=>h.line_id===l0.id),a.detail);
    ok('13. The other file and the batch are untouched',!!fb()&&B.lines.some(l=>l.file_id===fb().id)&&bcmBatch(bid).status==='Open');
    // the same file can be uploaded again
    await bcmUpload(bid,[file(bytesA,'Check A.xlsx')]);const again=fa();
    ok('14. The same workbook can be uploaded again (it is read again as a new file)',!!again&&again.id!==fA.id&&again.sha256===fA.sha256&&again.status==='Extracted'&&B.lines.some(l=>l.file_id===again.id));
    // a withdrawn batch keeps its files
    await bcmCall('batch_save',{action:'withdraw',id:bid,reason:'Check done'});U.sec='intake';render();await wait(150);
    ok('15. A withdrawn batch keeps its files: no Delete, and the server rule refuses',!$('[data-bcmfdel]')&&/The batch is withdrawn: its files are kept with it/.test(err(()=>BCML.file_delete({file_id:fb().id,reason:'Too late'}))));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{as(sa.id);try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Delete a tender file: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__bfdChecks=res;try{sessionStorage.setItem('bfdChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
