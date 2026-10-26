/* ProTrackAI v3.40.1, Budget & Cost Management -> WBS Mapping Master -> Excel import and export: download the WBS master, change it in
   Excel and import it back. Acceptance checks for the demo page. How to run: open demo.html, sign in with the demo Super Admin account
   (U28), open the browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end,
   then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const wait=ms=>new Promise(r=>setTimeout(r,ms));const keep=saveFile;
  try{
    go('bcm');const U=bcmUi();U.sec='master';U.mtab='io';render();await wait(200);await loadLib(LIBS.xlsx);
    // 1-3: the download goes through saveFile, like every other export (a host that offers its own downloads gets it too)
    let saved=null;saveFile=async(n,b)=>{saved={n,b}};$('[data-bcmexport="wbs"]').click();for(let i=0;i<25&&!saved;i++)await wait(200);saveFile=keep;
    ok('1. Version 3.40.1',APP_VERSION==='3.40.1');
    ok('2. Download the WBS master (Excel) hands an Excel workbook to saveFile',!!saved&&/^ProTrack WBS master .*\.xlsx$/.test(saved.n)&&saved.b.type==='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'&&saved.b.size>1000,saved&&{n:saved.n,t:saved.b.type,s:saved.b.size});
    ok('3. No export writes a file directly any more (the Budget & Cost Management and form workbooks included)',![...document.scripts].some(s=>/XLSX\.writeFile\(/.test(s.textContent)));
    const wb=XLSX.read(new Uint8Array(await saved.b.arrayBuffer()),{type:'array'}),rows=XLSX.utils.sheet_to_json(wb.Sheets['WBS master'],{header:1,defval:''}),W=bcmOf('wbs');
    ok('4. The workbook: the import columns first, then level, SAP WBS ID, user field description, status, version and id; one row per element',
      BCM_IO_COLS.every((c,i)=>rows[0][i]===c)&&rows[0].includes('Level')&&rows.length-1===W.length,{cols:rows[0].length,rows:rows.length-1,W:W.length});
    const up=async(aoa,name)=>{U.ioPrev=null;const w2=XLSX.utils.book_new();XLSX.utils.book_append_sheet(w2,XLSX.utils.aoa_to_sheet(aoa),'WBS master');
      const inp=$('#bcmWbsFile'),dt=new DataTransfer();dt.items.add(new File([XLSX.write(w2,{bookType:'xlsx',type:'array'})],name,{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}));
      inp.files=dt.files;inp.dispatchEvent(new Event('change',{bubbles:true}));for(let i=0;i<25&&!bcmUi().ioPrev;i++)await wait(200);await wait(100);return bcmUi().ioPrev};
    // 5: imported back unchanged: nothing to propose
    let P=await up(rows,'unchanged.xlsx');
    ok('5. The master imported back unchanged: every row says No change, and nothing is proposed',!!P&&P.rows.length===W.length&&P.rows.every(r=>r.same&&!r.err)&&/Nothing to propose: every valid row matches the master/.test($('#view').innerText)&&!$('[data-bcmioprop]'),P&&{n:P.rows.length,same:P.rows.filter(r=>r.same).length,err:P.rows.filter(r=>r.err).map(r=>r.row+' '+r.err).slice(0,3)});
    // 6-8: one description changed, one element added, one bad row
    const R2=rows.map(r=>r.slice()),iC=R2.findIndex(r=>r[1]==='SM3');R2[iC][3]=R2[iC][3]+' and stationery';
    R2.push([9990,'SM98','SM','Site drones and surveys','098','SM','drone survey','drone; survey','Overhead','','','','Yes','Yes','No'],[9991,'ZZ1','NOPE','Bad parent row','','','','','','','','','Yes','Yes','No']);
    P=await up(R2,'changed.xlsx');const ch=P.rows.filter(r=>!r.err&&!r.same);
    ok('6. Only the changed and the new rows are proposed; the others say No change',ch.length===2&&ch.some(r=>r.code==='SM3'&&r.id)&&ch.some(r=>r.code==='SM98'&&!r.id)&&P.rows.filter(r=>r.same).length===W.length-1,{ch:ch.map(r=>r.code)});
    ok('7. A row with an unknown parent is still refused with the reason',P.rows.some(r=>r.code==='ZZ1'&&/unknown parent NOPE/.test(r.err||'')));
    ok('8. The preview names them and the button counts them',/Change of/.test($('#view').innerText)&&/New element/.test($('#view').innerText)&&/No change/.test($('#view').innerText)&&/Propose the 2 new or changed rows/.test(($('[data-bcmioprop]')||{}).textContent||''));
    const pend0=bcmDB().master.filter(m=>m.pend).length;$('#bcmIoN').value='Checked in Excel';$('[data-bcmioprop]').click();for(let i=0;i<25&&bcmUi().ioPrev;i++)await wait(200);
    const M=bcmDB().master,sm3=M.find(m=>m.ent==='wbs'&&bcmData(m).code==='SM3'),sm98=M.find(m=>m.ent==='wbs'&&m.pend&&m.pend.data.code==='SM98');
    ok('9. Proposing makes exactly those 2 proposals, for someone else to approve',M.filter(m=>m.pend).length===pend0+2&&!!sm3.pend&&/and stationery/.test(sm3.pend.data.desc)&&!!sm98&&sm98.pend.note==='Checked in Excel');
    // 10: a row that matches a waiting proposal is not proposed again
    P=await up(R2.slice(0,-1),'again.xlsx');
    ok('10. Imported again: the rows that match the waiting proposals say No change too',P.rows.filter(r=>!r.err&&!r.same).length===0,P.rows.filter(r=>!r.err&&!r.same).map(r=>r.code));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keep;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`WBS master in Excel: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__wbsxChecks=res;try{sessionStorage.setItem('wbsxChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
