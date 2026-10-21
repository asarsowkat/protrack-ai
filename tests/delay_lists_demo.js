/* ProTrackAI v3.19.1, the delay events register's drop-down lists. Acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},err=f=>{try{f();return ''}catch(x){return x.message}};
  const wait=ms=>new Promise(r=>setTimeout(r,ms)),sa=DB.master.users.find(u=>u.role==='sa'&&u.active!==false),conf=window.confirm;window.confirm=()=>true;
  try{
    as(sa.id);const pid=PROJECTS[0].id,f0={name:'List check',start_date:addDays(TODAY,-10),time_bar:28};
    ok('0. The demo events (and those seeded with v3.19) use the lists',dlyRows().length>0&&dlyRows().every(x=>['identification','entitlement','liability','concurrency','mitigation','owner'].every(k=>!x[k]||dlyInList(k,x[k]))));
    /* 1-3: the lists, word for word */
    ok('1. Seven lists, as in the workbook',DLY_LISTS.map(x=>x[1]).join('|')==='Event Status List|Entitlement List|Liability List|Concurrency List|Owner List|Mitigation List|Claim Identification List');
    ok('2. The items, word for word',dlyList('entitlement').join('|')==='EOT Only|EOT + Cost|V.O (Cost Only)|V.O (Time & Cost)|To Be Determined'&&dlyList('liability').includes('Neutral / Force Majeure')
      &&dlyList('concurrency').length===4&&dlyList('owner').join('|')==='Regional Manager|Portfolio Manager|Project Manager'&&dlyList('mitigation').length===5&&dlyList('identification').length===12);
    ok('3. Seven columns of the register are drop-downs',DLY_COLS.filter(c=>c[3]==='list'||c[3]==='status').map(c=>c[0]).sort().join(',')==='concurrency,entitlement,identification,liability,mitigation,owner,status');
    /* 4-6: the window and the rules */
    go('dly');await wait(200);openDly(dlyRows().find(e=>e.project_id===pid).id);await wait(200);
    const sel=$('#dlyForm').elements.liability;
    ok('4. The window offers the list as a drop-down',sel&&sel.tagName==='SELECT'&&[...sel.options].map(o=>o.value).filter(Boolean).join('|')===dlyList('liability').join('|'));
    closeDrawer();
    ok('5. A value outside the list is refused, with what to do',/not in the list\. A super admin can add it/.test(err(()=>delayActLocal({action:'save',project_id:pid,fields:{...f0,liability:'The client'}}))));
    const e=delayActLocal({action:'save',project_id:pid,fields:{...f0,liability:'engineer / pmc',owner:'project manager'}});
    ok('6. Values match the list whatever the case, and keep its spelling',e.liability==='Engineer / PMC'&&e.owner==='Project Manager');
    /* 7-11: the super admin changes the lists */
    as(sa.id);state.adminTab='dlylists';go('admin');await wait(300);
    ok('7. Settings → Delay register lists shows the seven lists; status is fixed',/Delay register lists/.test($('#view').innerText)&&document.querySelectorAll('.dlylist').length===7&&!document.querySelector('[data-dlyladd="status"]'));
    $('#dlyl_liability').value='Utility Company';document.querySelector('[data-dlyladd="liability"]').click();await wait(200);
    ok('8. Adding an item puts it at the end, and the register accepts it',dlyList('liability').at(-1)==='Utility Company'&&err(()=>delayActLocal({action:'save',id:e.id,fields:{liability:'Utility Company'}}))==='');
    ok('9. A duplicate, an empty item and the status list are refused',/already in the list/.test(dlyListCheck('liability',[...dlyList('liability'),'employer']))&&/empty/.test(dlyListCheck('owner',['', 'x']))&&/fixed/.test(dlyListCheck('status',['Open'])));
    await dlyListSet('liability',dlyList('liability').filter(x=>x!=='Utility Company'),'"Utility Company" removed');
    ok('10. Removing an item: the event keeps its value, shown as not in the list, and can still be saved',dlyRows().find(x=>x.id===e.id).liability==='Utility Company'
      &&(openDly(e.id),/Utility Company \(not in the list\)/.test($('#dlyForm').elements.liability.innerHTML))&&err(()=>delayActLocal({action:'save',id:e.id,fields:{liability:'Utility Company',owner:'Regional Manager'}}))==='');
    closeDrawer();
    const before=dlyList('owner').join('|');document.querySelector('[data-dlyli="owner:down:0"]').click();await wait(200);
    ok('11. Reordering, the change log, and back to the workbook\'s list',dlyList('owner')[1]==='Regional Manager'&&DB.master.log[0].text.startsWith('Delay register lists: Owner List')
      &&(await dlyListSet('owner',[...DLY_LISTS.find(x=>x[0]==='owner')[2]],"back to the workbook's list"),dlyList('owner').join('|')===before));
    const pl=DB.master.users.find(u=>u.role==='plan'&&u.active!==false);as(pl.id);
    ok('12. Only a super admin changes the lists',!(await dlyListSet('owner',['A'],'x'))&&dlyList('owner').join('|')===before);as(sa.id);
    /* 13-14: Excel */
    await loadLib(LIBS.xlsx);const aoa=[[],DLY_COLS.map(c=>c[1]),[]],row=Array(27).fill(null),col=k=>DLY_COLS.findIndex(c=>c[0]===k);
    row[col('event_no')]='Event 40';row[col('name')]='From Excel';row[col('start_date')]='2026-08-01';row[col('entitlement')]='Extra payment';aoa.push(row);
    const P=dlyParse(aoa,pid);
    ok('13. Upload: a value outside a list refuses the row with the reason',P.rows[0].err.includes('Entitlement type: "Extra payment" is not in the list'),P.rows[0].err);
    let names=null;const keep=saveFile;window.saveFile=async(n,b)=>{const wb=XLSX.read(await b.arrayBuffer(),{type:'array'});names={n,sheets:wb.SheetNames,head:XLSX.utils.sheet_to_json(wb.Sheets.Lists,{header:1})[0]}};
    try{saveFile=window.saveFile}catch(x){}await dlyTemplate(pid);try{saveFile=keep}catch(x){}window.saveFile=keep;
    ok('14. The template has the Lists sheet in the workbook\'s layout',names&&names.sheets.includes('Lists')&&names.head.join('|')===DLY_LISTS.map(x=>x[1]).join('|'),names&&names.sheets);
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{window.confirm=conf;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Delay register lists: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__dlChecks=res;try{sessionStorage.setItem('dlChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
