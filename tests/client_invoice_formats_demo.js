/* ProTrackAI v3.50: Client Invoice Builder, client invoice formats. Acceptance checks for the demo page: the formula engine (references
   moved and kept, rows inserted and deleted as Excel does, the formulas worked out); the SAMPLE format and what ProTrack reads from it
   (breakdown tables per component, header cells, TCC and FAC, the forecast, the invoice number in a title, the totals checked); an
   invoice exported in it (rows rebuilt from the Schedule-C, the format's totals equal to ProTrack's, header cells, forecast); a
   format whose payment formula differs from the rules; matching rows only; a sheet taken out; upload, map, rename and delete; rights;
   the audit trail; the screens.
   How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this whole
   file. It saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';state.sector='ALL';SCOPE=scopeIds()},keepToast=toast,keepSave=window.saveFile,keepConfirm=window.confirm,keepCib=JSON.stringify(DB.cib||null);
  const SA='U28',pid='QOT',COST=(teamOf(pid,'costing')[0]||{}).id,PM=(teamOf(pid,'pm')[0]||{}).id,FORE='U21',files=[];
  const thr=async f=>{try{await f();return null}catch(e){return e.message}};
  try{
    window.toast=()=>{};window.saveFile=(n,b)=>files.push({n,b});window.confirm=()=>true;as(SA);
    ok('1. Version 3.50 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=50,APP_VERSION);
    ok('2. The Invoice formats tab; the SAMPLE format kept for any client',CIB_TABS.some(t=>t[0]==='fmt')&&cibFmts().some(f=>f.sample&&!f.client&&/SAMPLE/.test(f.name)),cibFmts().map(f=>f.name));
    /* the engine: references */
    const sh=xlShiftF("SUM(K14:K87)+'MATERIAL TAB'!G89-MATERIAL!$A$1&\"K20 stays\"+[1]MATERIAL!K20",'MATERIAL','SUMMARY',20,3).f,own=xlShiftF('SUM(K14:K87)+K10+K90','MATERIAL','MATERIAL',20,3).f,del=xlShiftF('K21+SUM(K14:K30)','MATERIAL','MATERIAL',20,-5);
    ok('3. Rows inserted: ranges that span them grow, references below move, strings and other workbooks are left alone; rows deleted: ranges shrink and a reference into them becomes #REF!',
      sh==="SUM(K14:K87)+'MATERIAL TAB'!G89-MATERIAL!$A$1&\"K20 stays\"+[1]MATERIAL!K20"&&own==='SUM(K14:K90)+K10+K93'&&del.f==='#REF!+SUM(K14:K25)'&&del.bad===1&&xlMove('I14*$E$14+SUM(A1:B2)',3,1)==='J17*$E$14+SUM(B4:C5)',{sh,own,del});
    /* the evaluator, on a small workbook */
    await loadLib(LIBS.exceljs);const wb0=new ExcelJS.Workbook(),a=wb0.addWorksheet('A'),b=wb0.addWorksheet('B 2');a.getCell('A1').value=10;a.getCell('A2').value=20;a.getCell('A3').value=0;b.getCell('A1').value=5;
    const fx=[['B1','SUM(A1:A3)*2'],['B2',"IF(A1>5,\"big\",\"small\")"],['B3','IFERROR(A1/A3,-1)'],['B4','ROUND(A2/3,2)'],['B5',"'B 2'!A1*13%"],['B6','MAX(A1:A3)-MIN(A1:A3)+ABS(-2)'],['B7','A1&"-"&A2'],['B8','AND(A1>0,OR(A3>0,TRUE))']];
    fx.forEach(([c,f])=>a.getCell(c).value={formula:f});const BK=await xlOpen(await wb0.xlsx.writeBuffer()),CK=xlCalc(BK),gv=c=>CK.val('A',c);
    ok('4. The formulas worked out: sums, IF, IFERROR, ROUND, percent, another sheet, MIN/MAX/ABS, joining text, AND/OR',gv('B1')===60&&gv('B2')==='big'&&gv('B3')===-1&&gv('B4')===6.67&&Math.abs(gv('B5')-0.65)<1e-9&&gv('B6')===22&&gv('B7')==='10-20'&&gv('B8')===true,fx.map(([c])=>gv(c)));
    /* the SAMPLE format, as ProTrack reads it */
    const SF=cibFmts().find(f=>f.sample),sbuf=await (await cibFmtBlob(SF)).arrayBuffer(),SB0=await xlOpen(sbuf),M=cibfScan(SB0,cibAppr(pid));
    const comps=M.tables.map(t=>t.comp).sort().join(),fl=new Set(M.fields.map(f=>f.field));
    ok('5. The SAMPLE format: a breakdown table per component, typed progress and payment columns, amounts as formulas',M.tables.length===7&&comps==='CLO,CON,ENG,GEN,INS,MAT,TC'&&M.tables.every(t=>t.mode==='rebuild'&&['prog_prev_pct','prog_this_pct','pay_prev_pct','pay_this_pct'].every(r=>t.cols.some(c=>c.role===r&&!c.f))&&t.cols.some(c=>c.role==='pay_this_amt'&&c.f)),M.tables.map(t=>[t.sheet,t.comp,t.mode]));
    ok('6. Header cells (invoice number, date, due date, period, contract, deductions, VAT %), TCC and FAC, the forecast, the number in the certificate title, the totals to check',
      ['inv_no','inv_date','due_date','from','to','contract_no','title','cv','ret_this','rel_this','adv_this','vat_pct','inv_ref','client','contractor'].every(k=>fl.has(k))&&M.ms.length===4&&M.fc&&M.fc.rows.length===24&&M.tnum.length===1&&['gross_this','net','vat','total'].every(k=>M.calc.some(c=>c.field===k)),
      {miss:['inv_no','inv_date','due_date','from','to','contract_no','title','cv','ret_this','rel_this','adv_this','vat_pct','inv_ref','client','contractor'].filter(k=>!fl.has(k)),ms:M.ms.length,fc:M.fc&&M.fc.rows.length,tnum:M.tnum.length,calc:M.calc.map(c=>c.field)});
    /* an invoice exported in it */
    as(COST);let I=cibInvOf(pid).find(x=>x.st==='Draft');if(!I){const r=await cibAct('inv_save',{pid,to:schedUps(pid)[0].data_date});I=cibInvOf(pid).find(x=>x.id===r.id)}
    const rep=await cibExportFmt(pid,I,SF.id),f1=files.pop(),OB=await xlOpen(await f1.b.arrayBuffer()),OC=xlCalc(OB),S=cibAppr(pid);
    const sum=xlSheet(OB,'INVOICE SUMMARY'),tr=[...sum.cells.keys()].map(a=>xlP(a)).find(p=>p.c===1&&/TOTAL LUMP/.test(xlTxt(OB,sum,xlA(1,p.r)))).r,near=(x,y)=>Math.abs(x-y)<0.05;
    const want=k=>cibBill(S).filter(i=>i.comp===k).length,mat=xlSheet(OB,'MATERIAL'),matNos=[...mat.cells.keys()].filter(a=>/^A\d+$/.test(a)&&CIB_ITEMRE.test(cibNo(xlTxt(OB,mat,a)))).map(a=>cibNo(xlTxt(OB,mat,a)));
    ok('7. Exported: each breakdown sheet rebuilt to the Schedule-C items of its component, in order; no difference and no warning',
      /\.xlsx$/.test(f1.n)&&rep.rebuilt.length===7&&rep.rebuilt.every(x=>x.to===want({'GENERAL':'GEN','ENGINEERING':'ENG','MATERIAL':'MAT','CONSTRUCTION':'CON','INSTALLATION':'INS','TESTING & COMM':'TC','CLOSE-OUT':'CLO'}[x.sheet]))
      &&matNos.join()===cibBill(S).filter(i=>i.comp==='MAT').map(i=>i.no).join()&&!rep.checks.length&&rep.calc.u===0,{rebuilt:rep.rebuilt,checks:rep.checks});
    const tax=xlSheet(OB,'TAX INVOICE'),rowOf=(sh,l)=>[...sh.cells.keys()].map(a=>xlP(a)).find(p=>p.c===1&&xlTxt(OB,sh,xlA(1,p.r))===l).r;
    ok("8. The format's own totals equal ProTrack's: this period, previously, to date, net payable, VAT and the total with VAT",
      near(OC.val('INVOICE SUMMARY','K'+tr),I.tot.gross_this)&&near(OC.val('INVOICE SUMMARY','I'+tr),I.tot.gross_prev)&&near(OC.val('INVOICE SUMMARY','M'+tr),I.tot.gross_cum)
      &&near(OC.val('TAX INVOICE','C'+rowOf(tax,'Net Payable')),I.tot.net)&&near(OC.val('TAX INVOICE','C'+rowOf(tax,'VAT amount')),I.tot.vat)&&near(OC.val('TAX INVOICE','C'+rowOf(tax,'Grand Total with VAT')),I.tot.total),
      {fmt:[OC.val('INVOICE SUMMARY','K'+tr),OC.val('INVOICE SUMMARY','M'+tr)],pt:[I.tot.gross_this,I.tot.gross_cum]});
    const ser=d=>xlSerial(d);
    ok('9. Header cells: invoice number, period from and to, due date after the payment days, contract number, the certificate title numbered; the forecast row of this invoice',
      xlGet(OB,tax,'B19').v===I.seq&&xlGet(OB,tax,'C21').v===ser(I.from)&&xlGet(OB,tax,'B21').v===ser(I.to)&&xlGet(OB,tax,'B18').v-xlGet(OB,tax,'B17').v===(+S.head.pay_days||0)&&xlGet(OB,tax,'B22').v===S.head.contract_no
      &&xlTxt(OB,sum,'F9')===`PAYMENT CERTIFICATE # ${pad(I.seq)}`&&near(xlGet(OB,xlSheet(OB,'FORECAST'),'F'+(11+I.seq)).v,I.tot.gross_this)&&xlTxt(OB,xlSheet(OB,'FORECAST'),'I'+(11+I.seq))==='Draft',
      {no:xlGet(OB,tax,'B19').v,title:xlTxt(OB,sum,'F9')});
    ok('10. The export is in the audit trail with the format and what was found',cibDB().audit.some(a=>a.pid===pid&&a.act==='Invoice exported'&&/SAMPLE/.test(a.ref)&&/0 differences/.test(a.note||'')),cibDB().audit.filter(a=>a.act==='Invoice exported').slice(0,1));
    /* a format whose payment is a formula of progress at 80% (as many clients' are): the difference with the approved rules is shown */
    const B80=await xlOpen(sbuf),m80=xlSheet(B80,'MATERIAL');[14,15].forEach(r=>{xlSetF(B80,m80,'S'+r,`I${r}*0.8`);xlSetF(B80,m80,'U'+r,`L${r}*0.8`)});
    const b80=await xlSave(B80);await DOCIDB.put('cibf:CFtest80pct',b80);cibFmts().push({id:'CFtest80pct',name:'Test 80% on progress',client:null,file:'t.xlsx',map:null});as(COST);
    const rep80=await cibExportFmt(pid,I,'CFtest80pct');files.pop();const d80=rep80.checks.filter(c=>c.sev==='diff');
    ok("11. A format paying 80% on progress against the approved 90% split: the difference is named on MATERIAL, and on the format's net and totals",d80.some(c=>c.sheet==='MATERIAL'&&/payment this period/.test(c.msg))&&d80.some(c=>/net payable/.test(c.msg)),d80.map(c=>c.msg.slice(0,90)));
    /* matching rows only, and a sheet taken out */
    const M2=JSON.parse(JSON.stringify(cibfMapClean(M)));M2.tables.forEach(t=>t.mode='match');M2.sheets.find(s=>s.name==='FORECAST').act='drop';M2.sheets.find(s=>s.name==='COVER PAGE').act='drop';
    cibFmts().push({id:'CFtestmatch',name:'Test match',client:null,file:'t.xlsx',map:M2});await DOCIDB.put('cibf:CFtestmatch',new Blob([sbuf]));
    const repM=await cibExportFmt(pid,I,'CFtestmatch'),fM=files.pop(),BM=await xlOpen(await fM.b.arrayBuffer());
    ok('12. Matching rows only: no row added or taken out, the items missing from the format are named; a sheet nobody refers to is taken out',
      !repM.rebuilt.length&&repM.checks.some(c=>/not in the format/.test(c.msg))&&!xlSheet(BM,'FORECAST')&&repM.dropped.includes('FORECAST'),{rebuilt:repM.rebuilt,dropped:repM.dropped});
    ok('13. A sheet that other sheets refer to is not taken out (the cover page reads nothing from others here, but the summary does)',(()=>{return repM.dropped.includes('COVER PAGE')})()&&!!xlSheet(BM,'INVOICE SUMMARY'),repM.dropped);
    const M3=JSON.parse(JSON.stringify(M2));M3.sheets.find(s=>s.name==='TAX INVOICE').act='drop';cibFmts().push({id:'CFtestdrop',name:'Test drop',client:null,file:'t.xlsx',map:M3});await DOCIDB.put('cibf:CFtestdrop',new Blob([sbuf]));
    const repD=await cibExportFmt(pid,I,'CFtestdrop');files.pop();
    ok('14. Taking out the tax invoice, which the summary refers to, is refused with a warning and the sheet stays',!repD.dropped.includes('TAX INVOICE')&&repD.checks.some(c=>/TAX INVOICE.*cannot be taken out/.test(c.msg)),repD.checks.map(c=>c.msg.slice(0,80)));
    /* upload, map, rename, delete; rights */
    as(COST);const file=new File([sbuf],'Client X invoice.xlsx',{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}),fx1=await cibFmtRead(file,pid);fx1.client='SAMPLE client X';
    const r1=await cibFmtSave(fx1),F1=cibFmts().find(f=>f.id===r1.id),blob1=await DOCIDB.get('cibf:'+r1.id);
    const eDup=await thr(()=>cibFmtSave(Object.assign({},fx1,{id:null}))),eBad=await thr(()=>cibFmtRead(new File(['x'],'macro.xlsm'),pid));
    ok('15. Upload: the workbook is read and kept with its map, its file in this browser; the same name for the same client is refused; a workbook with macros is refused',
      !!F1&&F1.client==='SAMPLE client X'&&F1.map.tables.length===7&&!!blob1&&F1.hash&&F1.hash.length===64&&/already kept/.test(eDup||'')&&/macros/.test(eBad||''),{eDup,eBad});
    F1.map.tables[0].comp='GEN';await cibFmtAct('fmt_map',{id:F1.id,name:'Client X layout',client:F1.client,map:F1.map});
    ok('16. The map is checked and saved under a new name, with its history',cibFmts().find(f=>f.id===F1.id).name==='Client X layout'&&(F1.hist||[]).length===2,F1.hist);
    const keepClient=projById(pid).client;projById(pid).client='SAMPLE client X';
    ok("17. A project's own client's formats are offered first, then those for any client",cibFmtsFor(pid)[0].id===F1.id&&cibFmtsFor(pid).some(f=>f.sample),cibFmtsFor(pid).map(f=>f.name));projById(pid).client=keepClient;
    as(PM);const ePm=await thr(()=>cibFmtAct('fmt_map',{id:F1.id,name:'x y',map:F1.map}));const xPm=await thr(()=>cibExportFmt(pid,I,SF.id));files.pop();as(FORE);const eFo=await thr(()=>cibAct('inv_export',{pid,id:I.id,fmt:'x'}));
    ok('18. Rights: the project manager exports but does not keep formats; a foreman does not export',/keep the invoice formats/.test(ePm||'')&&!xPm&&/not open to you|access/.test(eFo||''),{ePm,xPm,eFo});
    as(COST);await cibFmtAct('fmt_del',{id:F1.id});ok('19. Delete: the format and its workbook in this browser are gone',!cibFmts().some(f=>f.id===F1.id)&&!(await DOCIDB.get('cibf:'+F1.id)));
    /* the screens */
    as(SA);state.cib={pid,tab:'fmt'};go('cib');let v=$('#view').innerText;const s=cibUiOf();s.fx=Object.assign({pid},fx1,{map:cibfMapClean(M)});render();const v2=$('#view').innerText;
    ok('20. The Invoice formats tab lists the formats; the map shows sheets, breakdown tables with their component and rows, header cells and the totals checked',
      /Client invoice formats/.test(v)&&/Utility client layout \(SAMPLE\)/.test(v)&&/Breakdown tables/.test(v2)&&/Invoice header cells/.test(v2)&&/Checked against ProTrack/.test(v2)&&document.querySelectorAll('[data-cibfx^="table|"]').length===14,v2.slice(0,200));
    s.fx=null;as(COST);state.cib={pid,tab:'inv',inv:I.id,xrep:{inv:I.id,name:SF.name,rep}};go('cib');v=$('#view').innerText;
    ok('21. The invoice offers its formats beside the Excel invoice, and shows what the last export found',!!document.querySelector('[data-cibxf]')&&[...document.querySelector('[data-cibxf]').options].some(o=>o.value==='std')&&/Exported in “Utility client layout \(SAMPLE\)”/.test(v)&&/agree with ProTrack/.test(v),v.slice(0,200));
    state.cib={pid,tab:'dash'};
  }catch(e){ok('Unexpected error',false,e.stack||e.message)}
  finally{window.toast=keepToast;window.saveFile=keepSave;window.confirm=keepConfirm;try{DB.cib=JSON.parse(keepCib)}catch(x){}
    try{for(const k of ['CFtest80pct','CFtestmatch','CFtestdrop'])await DOCIDB.del('cibf:'+k)}catch(x){}
    try{if(KEYDATA!=null)localStorage.setItem(KEY,KEYDATA)}catch(x){}
    console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Client invoice formats: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
    window.__cibfChecks=res;try{sessionStorage.setItem('cibfChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500)}
})();
