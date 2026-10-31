/* ProTrackAI v3.42 and v3.43, Cost Control -> Cost plan: the cost plan upload (COST PLAN (I), COST PLAN (F), ACTUAL TO LAST YEAR,
   once or twice a year) and the monthly actual POC upload (its own file, one month each), by a super admin or the costing
   coordinator. Acceptance checks for the demo page. How to run: open demo.html, sign in with the demo Super Admin account (U28),
   open the browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms)),keep=saveFile,keepToast=toast,toasts=[];
  const cell=(ws,r,c,v)=>{ws[XLSX.utils.encode_cell({r,c})]=v},rowOf=(ws,code)=>XLSX.utils.sheet_to_json(ws,{header:1,blankrows:true}).findIndex(r=>r[0]===code);
  const grab=async fn=>{let out=null;saveFile=async(n,b)=>{out={n,b}};await fn();saveFile=keep;return {n:out.n,wb:XLSX.read(new Uint8Array(await out.b.arrayBuffer()),{type:'array',cellNF:true})}};
  const reread=wb=>XLSX.read(XLSX.write(wb,{bookType:'xlsx',type:'array'}),{type:'array'});
  const upload=async(id,wb,name,key)=>{const dt=new DataTransfer();dt.items.add(new File([XLSX.write(wb,{bookType:'xlsx',type:'array'})],name));const inp=$('#'+id);inp.files=dt.files;inp.dispatchEvent(new Event('change',{bubbles:true}));
    for(let i=0;i<25&&!state[key];i++)await wait(200);await wait(80);return state[key]};
  try{
    const sa=me().id,y=cpState().y,coord=userById('U40'),U=DB.master.users,coOnly=U.find(u=>u.role==='costing'&&u.active!==false&&!isCoord(u)),pmU=U.find(u=>u.role==='pm'&&u.active!==false);
    await loadLib(LIBS.xlsx);window.toast=m=>toasts.push(m);
    ok('1. Version 3.43 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=43,APP_VERSION);
    // 2: who uploads, and the two uploads
    const card={};[['sa',sa],['coord',coord.id],['costing',coOnly&&coOnly.id],['pm',pmU&&pmU.id]].forEach(([k,id])=>{if(!id)return;as(id);go('cplan');const t=$('#view').innerText;card[k]=/Cost plan upload \(Excel\)/.test(t)&&/Actual POC upload \(Excel\)/.test(t)&&canCpBulk()});as(sa);
    ok('2. Two uploads, the cost plan and the monthly actual POC, for the super admin and the costing coordinator only',card.sa&&card.coord&&card.costing===false&&card.pm===false,card);
    // 3-5: the cost plan file
    as(coord.id);go('cplan');const T=await grab(cpExport),wb=T.wb,fin=wb.Sheets['COST PLAN (F)'],I=wb.Sheets['COST PLAN (I)'],B=wb.Sheets['ACTUAL TO LAST YEAR'],pcF=fin[XLSX.utils.encode_cell({r:1,c:4})];
    const bh=XLSX.utils.sheet_to_json(B,{header:1})[0]||[];
    ok('3. The cost plan template: COST PLAN (I), COST PLAN (F) and ACTUAL TO LAST YEAR (actual POC, budget and contract value at December), no actual POC of the year',
      wb.SheetNames.join()==='COST PLAN (I),COST PLAN (F),ACTUAL TO LAST YEAR'&&/%/.test((pcF||{}).z||'')&&bh.includes('Actual POC end of last year')&&bh.includes('Budget at December of last year')&&bh.includes('Contract value at December of last year'),wb.SheetNames);
    const r0=cpParseBook(reread(wb),y);
    ok('4. The cost plan template uploaded untouched: every row says No change',r0.length>0&&r0.every(r=>r.same&&!r.err),r0.filter(r=>!r.same||r.err).map(r=>r.code+' '+r.part+' '+(r.err||'')));
    cell(I,rowOf(I,'RMX'),6,{t:'n',v:12345678});cell(fin,rowOf(fin,'JDC'),4,{t:'s',v:'55%'});const bq=rowOf(B,'QOT');cell(B,bq,4,{t:'n',v:370000000});
    const wbA=reread(wb);XLSX.utils.book_append_sheet(wbA,XLSX.utils.aoa_to_sheet([['Proj. ID',...MON.map(m=>m+' %')],['RMX',...Array(12).fill(1)]]),'ACTUAL POC');
    let rows=cpParseBook(wbA,y),ch=rows.filter(r=>!r.same&&!r.err),bqr=ch.find(r=>r.code==='QOT'&&r.part==='base');
    ok('5. Only the changed rows: an internal month, a finance target typed as 55%, a year-start budget (its POC and contract value kept); an ACTUAL POC sheet is not read',
      ch.length===3&&ch.some(r=>r.code==='RMX'&&r.part==='int'&&r.data.months[0]===12345678)&&ch.some(r=>r.code==='JDC'&&r.part==='fin'&&r.data.target===55)&&!!bqr&&bqr.data.budget===370000000&&bqr.data.poc===+cpOf('QOT',y).base.poc.toFixed(4)
      &&rows.some(r=>r.sheet==='ACTUAL POC'&&r.same&&/each month in its own file/.test(r.info||'')),ch.map(r=>r.code+' '+r.part));
    // 6-8: refusals
    const ri=XLSX.utils.sheet_to_json(I,{header:1}),n=ri.length;
    cell(I,n,0,{t:'s',v:'ZZZ'});cell(I,n,5,{t:'n',v:1000});cell(I,n+1,0,{t:'s',v:'JBS'});cell(I,n+1,5,{t:'n',v:1000});cell(I,n+2,0,{t:'s',v:'QOT'});cell(I,n+2,5,{t:'n',v:1000});
    cell(I,rowOf(I,'JDC'),8,{t:'s',v:'abc'});I['!ref']=XLSX.utils.encode_range({s:{r:0,c:0},e:{r:n+2,c:XLSX.utils.decode_range(I['!ref']).e.c}});
    const fq=rowOf(fin,'QOT');cell(fin,fq,4,{t:'n',v:0.7});for(let c=6;c<18;c++)cell(fin,fq,c,{t:'n',v:0.01});
    rows=cpParseBook(reread(wb),y);const err=c=>(rows.find(r=>r.code===c[0]&&r.part===c[1]&&r.err)||{}).err||'';
    ok('6. An unknown project and a project outside the coordinator\'s projects are refused; so is a project twice in a sheet',/Unknown project ZZZ/.test(err(['ZZZ','int']))&&/Not one of your projects/.test(err(['JBS','int']))&&/appears twice/.test(err(['QOT','int'])));
    ok('7. A month that is not a number, and finance percentages that lost their percent format, are refused',/is not a number/.test(err(['JDC','int']))&&/look like fractions/.test(err(['QOT','fin'])),[err(['JDC','int']),err(['QOT','fin'])]);
    const w2=XLSX.utils.book_new();XLSX.utils.book_append_sheet(w2,XLSX.utils.aoa_to_sheet([['Proj. ID','Budget',...MON.map(m=>`${m}-${String(y-1).slice(2)}`)],['RMX',100,...Array(12).fill(1)]]),'COST PLAN (I)');
    const ry=cpParseBook(w2,y);
    ok('8. Months of another year are refused for the whole sheet',ry.length===1&&new RegExp(`for ${y-1}, not ${y}`).test(ry[0].err||''),ry[0]);
    // 9-10: through the screen
    const bk=cpOf('RMX',y).int.status;cell(fin,fq,4,{t:'s',v:''});for(let c=6;c<18;c++)delete fin[XLSX.utils.encode_cell({r:fq,c})];
    await upload('cpBulkFile',wb,'plans-oct.xlsx','cpImp');const btn=$('[data-cpbulksave]');
    ok('9. The cost plan preview lists every row with New, Change, No change or the reason, and counts what will be saved',/plans-oct\.xlsx/.test($('#view').innerText)&&/Unknown project ZZZ/.test($('#view').innerText)&&!!btn&&/Save the 3 new or changed plans/.test(btn.textContent),btn&&btn.textContent);
    $('#cpbulkNote').value='October re-plan';btn.click();for(let i=0;i<25&&state.cpImp;i++)await wait(200);
    const rm=cpOf('RMX',y),jd=cpOf('JDC',y),qo=cpOf('QOT',y);
    ok('10. Saved together: the plans return to draft with "Bulk upload: plans-oct.xlsx" in their history; the year start saved; refused rows not saved',
      !state.cpImp&&bk==='Agreed'&&rm.int.status==='Draft'&&rm.int.months[0]===12345678&&jd.fin.target===55&&jd.fin.status==='Draft'&&qo.base.budget===370000000&&rm.hist.slice(-1)[0].note==='Bulk upload: plans-oct.xlsx · October re-plan'&&!cpOf('JBS',y)?.hist?.some(h=>/plans-oct/.test(h.note||'')),{st:rm.int.status});
    // 11-17: the monthly actual POC file
    const jan=`${y}-01`,feb=`${y}-02`;cpActState().per=jan;go('cplan');const AT=await grab(()=>cpActExport(jan)),aws=AT.wb.Sheets['ACTUAL POC'],ar=XLSX.utils.sheet_to_json(aws,{header:1,blankrows:true});
    const hRow=ar.findIndex(r=>r[0]==='Proj. ID'),rmx=ar.findIndex(r=>r[0]==='RMX');
    ok('11. The monthly template: one sheet for the month (cell Month), each project with the POC in the month, the cumulative from start and last month\'s cumulative',
      AT.n===`Actual POC ${jan}.xlsx`&&AT.wb.SheetNames.join()==='ACTUAL POC'&&ar[1][0]==='Month'&&ar[1][1]===jan&&ar[hRow].includes('Actual POC in the month (%)')&&ar[hRow].includes('Cumulative actual POC from start (%)')&&Math.abs(ar[rmx][5]*100-merBase('RMX',y).poc)<1e-6,ar[hRow]);
    const qr=ar.findIndex(r=>r[0]==='QOT'),jr=ar.findIndex(r=>r[0]==='JDC');
    cell(aws,rmx,3,{t:'n',v:1.5});cell(aws,qr,4,{t:'s',v:(merBase('QOT',y).poc+2).toFixed(2)+'%'});cell(aws,jr,3,{t:'n',v:1});cell(aws,jr,4,{t:'n',v:merBase('JDC',y).poc+5});
    cpActState().per=`${y}-05`;const A1=await upload('cpActFile',AT.wb,'actual-jan.xlsx','cpActImp');const g=c=>A1.rows.find(r=>r.code===c)||{};
    ok('12. The month written in the file is the one read (the page showed May)',A1.per===jan&&new RegExp(perLabel('month',jan)).test($('#view').innerText),A1.per);
    ok('13. The POC in the month as given; a cumulative from start becomes cumulative − last month\'s; the two that disagree are refused',
      g('RMX').val===1.5&&Math.abs(g('QOT').val-2)<1e-9&&/do not agree/.test(g('JDC').err||''),[g('RMX').val,g('QOT').val,g('JDC').err]);
    const sb=$('[data-cpactsave]');ok('14. The save button names the month and the projects',!!sb&&new RegExp(`Save the actual POC of ${perLabel('month',jan)} for 2 projects`).test(sb.textContent),sb&&sb.textContent);
    const intBefore=JSON.stringify(cpOf('RMX',y).int);sb.click();for(let i=0;i<25&&state.cpActImp;i++)await wait(200);
    const am=cp12(cpOf('RMX',y).act.months);
    ok('15. Saved: January\'s actual in the plans, the cost plans untouched, the history says "Actual POC Jan …"',!state.cpActImp&&am[0]===1.5&&JSON.stringify(cpOf('RMX',y).int)===intBefore&&/Actual POC/.test(cpOf('RMX',y).hist.slice(-1)[0].note||''),am.slice(0,3));
    const F2=await grab(()=>cpActExport(feb)),fws=F2.wb.Sheets['ACTUAL POC'],fr=XLSX.utils.sheet_to_json(fws,{header:1,blankrows:true}),fx=fr.findIndex(r=>r[0]==='RMX');
    const prevFeb=merBase('RMX',y).poc+1.5;cell(fws,fx,4,{t:'n',v:(prevFeb+2.25)/100,z:'0.00%'});
    const A2=await upload('cpActFile',F2.wb,'actual-feb.xlsx','cpActImp');const rf=A2.rows.find(r=>r.code==='RMX')||{};
    ok('16. Next month: last month\'s cumulative includes the uploaded January, so a cumulative-only figure works',A2.per===feb&&Math.abs(fr[fx][5]*100-prevFeb)<1e-6&&Math.abs(rf.val-2.25)<1e-6,[rf.val,rf.err]);
    $('[data-cpactsave]').click();for(let i=0;i<25&&state.cpActImp;i++)await wait(200);const am2=cp12(cpOf('RMX',y).act.months);
    ok('17. Each month is added: January is kept when February is saved',am2[0]===1.5&&Math.abs(am2[1]-2.25)<1e-6,am2.slice(0,3));
    if(coOnly){as(coOnly.id);const z=await cpBulkSave([{pid:'RMX',code:'RMX',part:'act',data:{months:Array(12).fill(1)}}],y,'x.xlsx');as(coord.id);
      ok('18. A costing engineer who is not the coordinator cannot upload',z===false&&/costing coordinator/.test(toasts.slice(-1)[0]||''))}
    // 19-21: in the MER
    as(sa);const per=merDefaultPer(),pm=+per.slice(5,7),Am=merActual('RMX',y,per,merBase('RMX',y).poc);
    ok('19. The cost plan and the MER use the uploaded actual for a month without a released cost report',Am.src[0]==='up'&&Am.inc[0]===1.5&&Am.src[pm-1]==='cr',Am.src);
    const crM=ym(merRel('RMX','cost',per).period),X=await grab(()=>cpActExport(crM)),xw=X.wb.Sheets['ACTUAL POC'],xr=XLSX.utils.sheet_to_json(xw,{header:1,blankrows:true}),xi=xr.findIndex(r=>r[0]==='RMX');
    cell(xw,xi,3,{t:'n',v:9});const A3=cpParseAct(reread(X.wb),crM),r3=A3.rows.find(r=>r.code==='RMX')||{};
    ok('20. A month with a released cost report: the preview says the cost report comes first',/released cost report of this month comes first/.test(r3.info||'')&&/Yes, POC/.test(String(xr[xi][6])),r3.info);
    const pe=PROJECTS.find(p=>!relRows().some(r=>r.project_id===p.id&&r.kind==='cost'&&r.status==='Released')&&accessIds().includes(p.id));
    if(pe){await cpSave(pe.id,y,'base',{poc:10,budget:null,cv:null});await cpSave(pe.id,y,'act',{months:[1,2,3,4,5,6,7,8,9,10,11,12]});const m=merProject(pe,per,'int');
      ok('21. A project without a released cost report: actual POC from the year start and the uploaded months',Math.abs(m.poc-(10+pm*(pm+1)/2))<1e-9&&Math.abs(m.t_act-pm*(pm+1)/2)<1e-9&&m.notes.includes('actual POC partly from the upload'),{poc:m.poc,u:m.t_act})}
    else ok('21. A project without a released cost report (none in this demo)',true,'skipped');
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keep;window.toast=keepToast;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Cost plan and actual POC uploads: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__cpiChecks=res;try{sessionStorage.setItem('cpiChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
