/* ProTrackAI v3.42, Cost Control -> Cost plan -> Bulk upload (Excel): the internal and finance plans and the actual POC of many
   projects at once, by a super admin or the costing coordinator. Acceptance checks for the demo page. How to run: open demo.html,
   sign in with the demo Super Admin account (U28), open the browser console and paste this whole file. It saves this browser's
   demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms)),keep=saveFile,keepToast=toast,toasts=[];
  const cell=(ws,r,c,v)=>{ws[XLSX.utils.encode_cell({r,c})]=v},rowOf=(ws,code)=>XLSX.utils.sheet_to_json(ws,{header:1}).findIndex(r=>r[0]===code);
  try{
    const sa=me().id,y=cpState().y,coord=userById('U40'),U=DB.master.users,coOnly=U.find(u=>u.role==='costing'&&u.active!==false&&!isCoord(u)),pmU=U.find(u=>u.role==='pm'&&u.active!==false);
    await loadLib(LIBS.xlsx);window.toast=m=>toasts.push(m);
    ok('1. Version 3.42 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=42,APP_VERSION);
    // 2: who uploads
    const card={};[['sa',sa],['coord',coord.id],['costing',coOnly&&coOnly.id],['pm',pmU&&pmU.id]].forEach(([k,id])=>{if(!id)return;as(id);go('cplan');card[k]=/Bulk upload \(Excel\)/.test($('#view').innerText)&&canCpBulk()});as(sa);
    ok('2. The bulk upload is for the super admin and the costing coordinator, not a costing engineer or a project manager',card.sa&&card.coord&&card.costing===false&&card.pm===false,card);
    // 3: the template is the export, and reads back unchanged
    as(coord.id);go('cplan');let out=null;saveFile=async(n,b)=>{out={n,b}};await cpExport();saveFile=keep;
    const buf=new Uint8Array(await out.b.arrayBuffer()),wb=XLSX.read(buf,{type:'array',cellNF:true}),fin=wb.Sheets['COST PLAN (F)'],pcF=fin[XLSX.utils.encode_cell({r:1,c:4})];
    const r0=cpParseBook(XLSX.read(buf,{type:'array'}),y);
    ok('3. The template: COST PLAN (I), COST PLAN (F) and ACTUAL POC, percent cells formatted as percent',wb.SheetNames.join()==='COST PLAN (I),COST PLAN (F),ACTUAL POC'&&!!pcF&&/%/.test(pcF.z||''),wb.SheetNames);
    ok('4. The template uploaded untouched: every row says No change',r0.length>0&&r0.every(r=>r.same&&!r.err),r0.filter(r=>!r.same||r.err).map(r=>r.code+' '+r.part+' '+(r.err||'')));
    // 5: changes
    const I=wb.Sheets['COST PLAN (I)'],A=wb.Sheets['ACTUAL POC'];
    cell(I,rowOf(I,'RMX'),6,{t:'n',v:12345678});cell(fin,rowOf(fin,'JDC'),4,{t:'s',v:'55%'});
    const aq=rowOf(A,'QOT');cell(A,aq,3,{t:'n',v:2.5});cell(A,aq,4,{t:'s',v:'3'});cell(A,aq,5,{t:'n',v:0.04,z:'0.00%'});cell(A,aq,10,{t:'n',v:1.2});
    let rows=cpParseBook(XLSX.read(XLSX.write(wb,{bookType:'xlsx',type:'array'}),{type:'array'}),y),ch=rows.filter(r=>!r.same&&!r.err);
    const q=ch.find(r=>r.code==='QOT'&&r.part==='act');
    ok('5. Only the changed rows are proposed: an internal month, a finance target typed as 55%, and actual POC (a number, a text, a percent cell)',
      ch.length===3&&ch.some(r=>r.code==='RMX'&&r.part==='int'&&r.data.months[0]===12345678)&&ch.some(r=>r.code==='JDC'&&r.part==='fin'&&r.data.target===55)&&!!q&&JSON.stringify(q.data.months.slice(0,8))==='[2.5,3,4,null,null,null,null,1.2]',ch.map(r=>r.code+' '+r.part));
    // 6-9: refusals
    const ri=XLSX.utils.sheet_to_json(I,{header:1}),n=ri.length;
    cell(I,n,0,{t:'s',v:'ZZZ'});cell(I,n,5,{t:'n',v:1000});cell(I,n+1,0,{t:'s',v:'JBS'});cell(I,n+1,5,{t:'n',v:1000});cell(I,n+2,0,{t:'s',v:'QOT'});cell(I,n+2,5,{t:'n',v:1000});
    cell(I,rowOf(I,'JDC'),8,{t:'s',v:'abc'});I['!ref']=XLSX.utils.encode_range({s:{r:0,c:0},e:{r:n+2,c:XLSX.utils.decode_range(I['!ref']).e.c}});
    const fq=rowOf(fin,'QOT');cell(fin,fq,4,{t:'n',v:0.7});for(let c=6;c<18;c++)cell(fin,fq,c,{t:'n',v:0.01});
    rows=cpParseBook(XLSX.read(XLSX.write(wb,{bookType:'xlsx',type:'array'}),{type:'array'}),y);const err=c=>(rows.find(r=>r.code===c[0]&&r.part===c[1]&&r.err)||{}).err||'';
    ok('6. An unknown project and a project outside the coordinator\'s projects are refused',/Unknown project ZZZ/.test(err(['ZZZ','int']))&&/Not one of your projects/.test(err(['JBS','int'])),[err(['ZZZ','int']),err(['JBS','int'])]);
    ok('7. A project twice in a sheet, and a month that is not a number, are refused',/appears twice/.test(err(['QOT','int']))&&/is not a number/.test(err(['JDC','int'])),[err(['QOT','int']),err(['JDC','int'])]);
    ok('8. Finance percentages that lost their percent format (0.7 for 70 %) are refused',/look like fractions/.test(err(['QOT','fin'])),err(['QOT','fin']));
    const w2=XLSX.utils.book_new();XLSX.utils.book_append_sheet(w2,XLSX.utils.aoa_to_sheet([['Proj. ID',...MON.map(m=>`${m}-${String(y-1).slice(2)} %`)],['RMX',...Array(12).fill(1)]]),'ACTUAL POC');
    const ry=cpParseBook(w2,y);
    ok('9. Months of another year are refused for the whole sheet',ry.length===1&&new RegExp(`for ${y-1}, not ${y}`).test(ry[0].err||''),ry[0]);
    // 10-12: through the screen, as the coordinator
    const bk=cpOf('RMX',y).int.status;cell(fin,fq,4,{t:'s',v:''});for(let c=6;c<18;c++)delete fin[XLSX.utils.encode_cell({r:fq,c})];
    const file=new File([XLSX.write(wb,{bookType:'xlsx',type:'array'})],'plans-oct.xlsx'),inp=$('#cpBulkFile'),dt=new DataTransfer();dt.items.add(file);inp.files=dt.files;inp.dispatchEvent(new Event('change',{bubbles:true}));
    for(let i=0;i<25&&!state.cpImp;i++)await wait(200);await wait(80);const tv=$('#view').innerText,btn=$('[data-cpbulksave]');
    ok('10. The preview lists every row with New, Change, No change or the reason, and counts what will be saved',/plans-oct\.xlsx/.test(tv)&&/Change/.test(tv)&&/No change/.test(tv)&&/Unknown project ZZZ/.test(tv)&&!!btn&&/Save the 3 new or changed plans/.test(btn.textContent),btn&&btn.textContent);
    $('#cpBulkNote').value='October re-plan';btn.click();for(let i=0;i<25&&state.cpImp;i++)await wait(200);
    const rm=cpOf('RMX',y),jd=cpOf('JDC',y),qo=cpOf('QOT',y);
    ok('11. Saved together: the changed plans return to draft, each with "Bulk upload: plans-oct.xlsx" in its history; the refused rows are not saved',
      !state.cpImp&&bk==='Agreed'&&rm.int.status==='Draft'&&rm.int.months[0]===12345678&&jd.fin.target===55&&jd.fin.status==='Draft'&&qo.act.months[1]===3&&rm.hist.slice(-1)[0].note==='Bulk upload: plans-oct.xlsx · October re-plan'&&!cpOf('JBS',y)?.hist?.some(h=>/plans-oct/.test(h.note||'')),{st:rm.int.status});
    if(coOnly){as(coOnly.id);const z=await cpBulkSave([{pid:'RMX',code:'RMX',part:'act',data:{months:Array(12).fill(1)}}],y,'x.xlsx');as(coord.id);
      ok('12. A costing engineer who is not the coordinator cannot save in bulk',z===false&&/costing coordinator/.test(toasts.slice(-1)[0]||''))}
    // 13-15: the uploaded actual POC in the MER
    as(sa);const per=merDefaultPer(),Aq=merActual('QOT',y,per,merBase('QOT',y).poc),pm=+per.slice(5,7);
    ok('13. The cost plan and the MER use the uploaded actual POC for a month without a released cost report',Aq.src[0]==='up'&&Aq.inc[0]===2.5&&Aq.inc[2]===4&&Aq.src[pm-1]==='cr',Aq.src);
    await cpSave('QOT',y,'act',{months:Object.assign(Array(12).fill(null),{[pm-1]:99})});const Aq2=merActual('QOT',y,per,merBase('QOT',y).poc);
    ok('14. A released cost report comes before an uploaded actual of the same month',Aq2.src[pm-1]==='cr'&&Aq2.inc[pm-1]!==99,Aq2.inc[pm-1]);
    const pe=PROJECTS.find(p=>!relRows().some(r=>r.project_id===p.id&&r.kind==='cost'&&r.status==='Released')&&accessIds().includes(p.id));
    if(pe){await cpSave(pe.id,y,'base',{poc:10,budget:null,cv:null});await cpSave(pe.id,y,'act',{months:[1,2,3,4,5,6,7,8,9,10,11,12]});const m=merProject(pe,per,'int');
      ok('15. A project without a released cost report: actual POC and this year\'s actual from the year start and the uploaded months',Math.abs(m.poc-(10+pm*(pm+1)/2))<1e-9&&Math.abs(m.t_act-pm*(pm+1)/2)<1e-9&&m.notes.includes('actual POC partly from the upload'),{poc:m.poc,u:m.t_act})}
    else ok('15. A project without a released cost report (none in this demo)',true,'skipped');
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keep;window.toast=keepToast;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Cost plan bulk upload: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__cpiChecks=res;try{sessionStorage.setItem('cpiChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
