/* ProTrackAI v3.29 and v3.29.1, Cost Control → Budget supplements: the log by user field and category. Acceptance checks for the
   demo page. How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28),
   open the browser console and paste this whole file. It saves this browser's demo data first and puts it back at the
   end, then reloads the page. It prints one line per check and a total; the results are also in sessionStorage
   ('suppChecks'). */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},err=f=>{try{f();return ''}catch(x){return x.message}};
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'&&u.active!==false),co=U.find(u=>isCoord(u)),cst=U.find(u=>u.role==='costing'&&!isCoord(u)),pl=U.find(u=>u.role==='plan'),sm=U.find(u=>u.role==='sm');
  const keepSave=window.saveFile,keepConfirm=window.confirm,keepPrompt=window.prompt;let saved=[];window.saveFile=async(n,b)=>{saved.push({n,b})};window.confirm=()=>true;
  const book=(rows,head)=>{const ws=XLSX.utils.aoa_to_sheet([['ProTrack budget supplement log'],[],head||['Supplement no','Version (MMM-YY)','WF date','User field','Category','Description','Amount (SAR)','WBS Group','WBS ID','WBS Description','Linked VO / claim','Remarks'],...rows]),wb=XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb,ws,'Supplements');return XLSX.utils.sheet_to_json(wb.Sheets.Supplements,{header:1,blankrows:false})};
  try{
    as(sa.id);await loadLib(LIBS.xlsx);
    /* the lists */
    const L=suppLists();
    ok('1. The standard lists: 19 user fields and 24 categories, each category with its unified category, as in the company sheet',L.uf.length===19&&L.cats.length===24&&suppUni('Cont-SZN')==='Saudization'&&suppUni('Client/External')==='External Factors'&&suppUfDesc('INSTL.CVL')==='Civil Equip',[L.uf.length,L.cats.length]);
    ok('2. A value is matched as the list writes it, case aside',suppUF('man.elc')==='MAN.ELC'&&suppCat('cont-claim')==='Cont-Claim'&&suppCat('CHANGE ORDER')==='CHANGE ORDER'&&suppCat('change order')==='Change Order'&&suppUF('XYZ')===null);
    /* the four columns */
    const v=(uf,cat,amount)=>suppView({user_field:uf,category:cat,unified_category:suppUni(cat),amount});
    const s1=v('MAN.ELC','Under Estimation',-250000),s2=v('SM','Savings',80000),s3=v('INSTL.ELC','Change Order',-300000),s4=v('Cont. Value','CHANGE ORDER',420000);
    ok('3. A negative amount is a Supplement, a positive one Savings',s1.supp===-250000&&s1.sav===0&&s2.sav===80000&&s2.supp===0);
    ok('4. A change order is a VO Cost, or a VO Price when the user field is Cont. Value',s3.vocost===-300000&&s3.supp===0&&s4.voprice===420000&&s4.sav===0);
    ok('5. Net value = Supplement + Savings + VO Cost + VO Price (the impact on the gross margin)',[s1,s2,s3,s4].every(r=>r.net===r.supp+r.sav+r.vocost+r.voprice&&r.net===r.amt));
    ok('6. Budget change = −(the rows that are not Cont. Value): supplements and VO costs add, savings take away, a VO price is not budget',s1.budget===250000&&s2.budget===-80000&&s3.budget===300000&&s4.budget===0);
    const old=suppView({category:'Change order',amount:1000,approval_status:'Approved'}),oldP=suppView({category:'Under estimate',amount:500,approval_status:'Pending'});
    ok('7. A log from before v3.29: its approved amounts are added to the budget, as before; pending ones are not',old.old&&old.budget===1000&&old.uni==='Change Order'&&oldP.budget===0&&old.vocost===-1000);
    /* the demo data, in today's layout */
    const D0=suppData();
    ok('8. The demo logs are in the new layout: user field, WBS, signed amounts, a VO price and a saving on each sample project',DB.v329Seeded&&D0.rows.length>0&&D0.rows.every(r=>!r.old&&r.uf)&&D0.rows.some(r=>r.voprice>0)&&D0.rows.some(r=>r.sav>0),D0.rows.length);
    const R0=D0.rows.filter(r=>r.p.id==='RMX');
    ok('9. The cost report uses the budget change of the log (Riyadh Metro)',Math.abs(suppApproved('RMX',D0.per)-R0.reduce((t,r)=>t+r.budget,0))<1&&suppApproved('RMX',D0.per)>0,suppApproved('RMX',D0.per));
    /* many projects, the version, the filters */
    state.suppF=null;state.logTab='supp';go('logs');await new Promise(r=>setTimeout(r,200));
    const t=$('#view').innerText;
    ok('10. Super admin: all projects in scope, the version as MMM-YY, every column',/All projects in scope/.test(t)&&new RegExp(MMMYY(D0.per)).test(t)&&['User field','Unified category','Supplement','Savings','VO Cost','VO Price','Net value','WBS Group','WBS ID','WBS Description','Remarks'].every(h=>[...document.querySelectorAll('.supptbl th')].some(th=>th.textContent===h)));
    const f=suppState();f.uni='Change Order';let D=suppData();
    ok('11. Filter by unified category',D.rows.length>0&&D.rows.every(r=>r.uni==='Change Order'));
    f.uni='';f.uf='SM';D=suppData();ok('12. Filter by user field',D.rows.length>0&&D.rows.every(r=>r.uf==='SM'));
    f.uf='';f.cat='Saudization';D=suppData();ok('13. Filter by category',D.rows.length>0&&D.rows.every(r=>r.cat==='Saudization'));
    f.cat='';const reg=PROJECTS.find(p=>p.id==='RMX').region;f.reg=reg;D=suppData();ok('14. Filter by region',D.rows.length>0&&D.rows.every(r=>r.p.region===reg));
    f.reg='';const sec=PROJECTS.find(p=>p.id==='QOT').sector;f.sec=sec;D=suppData();ok('15. Filter by sector',D.rows.every(r=>r.p.sector===sec));
    f.sec='';f.pt='OHTL';D=suppData();ok('16. Filter by project type',D.rows.length>0&&D.rows.every(r=>r.p.ptype==='OHTL'));
    f.pt='';f.pid='RMX';D=suppData();ok('17. One project',D.rows.length>0&&D.rows.every(r=>r.p.id==='RMX'));
    {const lb=suppLatest('RMX',D.per).b,n0=D.rows.length,x={id:999999,batch_id:lb.id,project_id:'RMX',period:lb.source_period,supp_no:'BS-OLD',supp_date:lb.source_period+'-03',category:'Finance',amount:7000,approval_status:'Pending'};
      DB.suppLog.push(x);const D2=suppData();DB.suppLog=DB.suppLog.filter(r=>r!==x);
      ok('17a. Only WF-approved rows: a pending row of a log from before v3.29 is left out of the rows and tiles, and counted',D2.rows.length===n0&&!D2.rows.some(r=>r.supp_no==='BS-OLD')&&D2.hid===1,{n0,n:D2.rows.length,hid:D2.hid})}
    /* the template, an upload */
    state.logPid='RMX';saved=[];await suppTemplate();const tw=XLSX.read(await saved[0].b.arrayBuffer(),{type:'array'});
    ok('18. The template has the columns and a Lists sheet with the user fields and the categories',tw.SheetNames.join()==='Supplements,Lists'&&XLSX.utils.sheet_to_json(tw.Sheets.Lists,{header:1}).length>=25);
    const per=curMonth(),M=MMMYY(per),aoa=book([['bs-01',M,per+'-02','man.elc','under estimation','Extra manpower',-250000,'Electrical','WBS-E2','Electrical manpower','',''],['BS-02',M,per+'-03','SM','Savings','',80000,'','','','',''],
      ['BS-03',M,per+'-04','INSTL.ELC','Change Order','VO-009 cost',-300000,'','','','VO-009',''],['BS-04',M,per+'-04','Cont. Value','CHANGE ORDER','VO-009 price',420000,'','','','VO-009',''],
      ['BS-05',M,per+'-04','XYZ','Savings','',1,'','','','',''],['BS-06',M,'','SM','Savings','',1,'','','','',''],['BS-07','Jan-20',per+'-04','SM','Savings','',1,'','','','',''],['BS-08',M,per+'-04','SM','Nope','',1,'','','','','']]);
    const P=logParse(aoa,false),why=Object.fromEntries(P.rows.map(r=>[r.supp_no,r.err]));
    ok('19. Row checks: user field and category from the lists, the WF date required, the version is a month',!why['BS-01']&&!why['BS-04']&&/user field "XYZ"/.test(why['BS-05'])&&/WF date is missing/.test(why['BS-06'])&&/category "Nope"/.test(why['BS-08'])&&P.rows.find(r=>r.supp_no==='BS-07')._ver==='2020-01',why);
    const r1=P.rows.find(r=>r.supp_no==='BS-01');
    ok('20. A row is stored as the lists write it, with its unified category and WBS, approved',r1.user_field==='MAN.ELC'&&r1.category==='Under Estimation'&&r1.unified_category==='Under Estimation'&&r1.wbs_id==='WBS-E2'&&r1.approval_status==='Approved'&&!('v_supp' in r1));
    const P4=logParse(book([['BS-01',M,per+'-02','SM','Savings','',0,0,0,500,'']],['Supplement no','Version','WF date','User field','Category','Description','Supplement','Savings','VO Cost','VO Price','Remarks']),false);
    ok('21. A file with the four columns instead of one amount: their sum is the amount',P4.rows[0].amount===500&&!P4.rows[0].err,P4.rows[0]);
    as(cst.id);state.logPid=PROJECTS.find(p=>accessIds(cst).includes(p.id)).id;state.logUp={file:'test.xlsx',rows:P.rows,period:per,hash:'t-'+Date.now(),ack:true};
    go('logs');await new Promise(r=>setTimeout(r,150));$('#logMonth').value=per;$('#logAck')&&($('#logAck').checked=true);await logGo(document.createElement('button'));
    /* the row of another version is refused at Save: it is shown with the others, and the refused rows are confirmed again */
    const vRef=(state.logUp?.rows||[]).find(r=>r.supp_no==='BS-07');
    ok('22a. A row of another version than the month is refused, and shown before anything is saved',!!vRef&&/version Jan-20 is not the month/.test(vRef.err||'')&&/is not the month/.test($('#view').innerText),vRef&&vRef.err);
    $('#logMonth').value=per;$('#logAck')&&($('#logAck').checked=true);await logGo(document.createElement('button'));
    const nb=suppLatestAny(state.logPid);
    ok('22. A costing engineer uploads the month: the refused rows (another version too) are left out',nb.b&&nb.b.source_period===per&&nb.rows.length===4&&!nb.rows.some(r=>r.supp_no==='BS-07'),nb.rows.map(r=>r.supp_no));
    /* changes on the screen */
    const pid=state.logPid,n0=nb.rows.length;
    const a1=suppActLocal({action:'add',project_id:pid,values:{supp_no:'bs-10',supp_date:per+'-05',user_field:'DE',category:'Project Execution',amount:-10000,remarks:'design'}});
    ok('23. Add a row on the screen',a1.row.supp_no==='BS-10'&&suppLatestAny(pid).rows.length===n0+1);
    ok('24. A number already in the log, a missing WF date: refused',/already in the log/.test(err(()=>suppActLocal({action:'add',project_id:pid,values:{supp_no:'BS-10',supp_date:per+'-05',user_field:'DE',category:'Finance',amount:1}})))
      &&/WF date is missing/.test(err(()=>suppActLocal({action:'add',project_id:pid,values:{supp_no:'BS-11',user_field:'DE',category:'Finance',amount:1}}))));
    const e1=suppActLocal({action:'edit',project_id:pid,id:a1.row.id,values:{...a1.row,amount:-12000}});
    ok('25. Change a row: the change is in the history',e1.changed&&e1.row.amount===-12000&&DB.suppAudit[0].action==='changed'&&DB.suppAudit[0].changes.some(c=>c[0]==='amount'));
    ok('26. Remove needs a reason, and is in the history',/reason/.test(err(()=>suppActLocal({action:'remove',project_id:pid,id:a1.row.id,reason:''})))&&suppActLocal({action:'remove',project_id:pid,id:a1.row.id,reason:'Entered twice'}).removed&&DB.suppAudit[0].action==='removed');
    as(pl.id);ok('27. A planning engineer cannot change the log',/Only the costing engineer/.test(err(()=>suppActLocal({action:'add',project_id:pid,values:{supp_no:'BS-12',supp_date:per+'-05',user_field:'DE',category:'Finance',amount:1}}))));
    as(sm.id);state.logTab='supp';go('logs');await new Promise(r=>setTimeout(r,150));
    ok('28. A site manager does not see the log (no cost figures)',!canLogsView()&&!/Budget supplement log/.test($('#view').innerText));
    /* Settings → Supplement lists */
    as(sa.id);const L1=suppLists();await suppListsSet({uf:[...L1.uf,['NEW.CODE','A new head']],cats:[...L1.cats,['Cont-New','Savings']]},'test');
    ok('29. The super admin adds a user field and a category; they are used at once',suppUF('new.code')==='NEW.CODE'&&suppUni('Cont-New')==='Savings'&&!suppNormalize({supp_no:'X1',supp_date:'2026-09-01',user_field:'NEW.CODE',category:'Cont-New',amount:1},null).err);
    ok('30. Cont. Value cannot leave the user fields; a category twice is refused',/Cont\. Value stays/.test(suppListCheck({uf:L1.uf.filter(x=>x[0]!=='Cont. Value'),cats:L1.cats}))&&/twice/.test(suppListCheck({uf:L1.uf,cats:[...L1.cats,L1.cats[0]]})));
    as(cst.id);const before=JSON.stringify(DB.suppLists);await suppListsSet({uf:SUPP_UF_DEF,cats:SUPP_CAT_DEF},'not allowed');
    ok('31. Only a super admin changes the lists',JSON.stringify(DB.suppLists)===before);
    as(sa.id);go('admin');state.adminTab='supplists';render();await new Promise(r=>setTimeout(r,100));
    ok('32. Settings → Supplement lists shows both lists',/User fields/.test($('#view').innerText)&&/Categories and their unified category/.test($('#view').innerText)&&DOMAINS.find(d=>d.k==='admin').items.some(i=>i.tab==='supplists'));
    /* a version, the export, the executive report */
    const pv=(PROJECTS.find(p=>{const b=suppLatestAny(p.id).b;return b&&b.source_period<curMonth()})||{}).id,lb=pv&&suppLatestAny(pv).b;
    if(lb){const r=suppActLocal({action:'version',project_id:pv,period:curMonth()});ok('33. A new version is started as a copy of the latest log',r.batch.source_period===curMonth()&&suppLatestAny(pv).rows.length===suppLatest(pv,lb.source_period).rows.length
      &&/already/.test(err(()=>suppActLocal({action:'version',project_id:pv,period:curMonth()}))))}
    else ok('33. A new version is started as a copy of the latest log',false,'no project with a log before this month');
    state.suppF=null;saved=[];await suppExport();const xw=XLSX.read(await saved[0].b.arrayBuffer(),{type:'array'}),xs=XLSX.utils.sheet_to_json(xw.Sheets.Supplements,{header:1});
    ok('34. Export to Excel: the rows shown, with project, region, sector, type and every column',saved[0].n.startsWith('ProTrack_budget_supplements_')&&xs[3].includes('Unified category')&&xs[3].includes('Net value')&&xs[3].includes('Project type')&&xs.length>5);
    ok('35. The executive report shows the supplements by unified category',(XR_SECS.find(x=>x[0]==='supp')||[])[1]==='Budget supplements by unified category');
    /* v3.29.1: the exported file, changed in Excel, uploaded again for the same version */
    as(co.id);const xp='RMX',xper=suppLatestAny(xp).b.source_period,sheet=async b=>XLSX.utils.sheet_to_json(XLSX.read(await b.arrayBuffer(),{type:'array'}).Sheets.Supplements,{header:1,blankrows:false});
    state.suppF=null;Object.assign(suppState(),{pid:xp,per:xper});const D5=suppData();saved=[];await suppExport();
    const aoa5=await sheet(saved[0].b),P5=logParse(aoa5,false);P5.rows.forEach(x=>{if(!x.err)x.err=suppProjErr(x,xp)});
    ok('36. An exported log reads back: every row with its number (not the PE number), description, user field and amount; the Total row is left out',accessIds().includes(xp)&&P5.rows.length===D5.rows.length&&P5.rows.every(x=>!x.err)
      &&D5.rows.every(r=>{const x=P5.rows.find(y=>y.supp_no===r.supp_no);return x&&x.amount===r.amt&&(x.description||null)===(r.description||null)&&x.user_field===r.uf}),{n:P5.rows.length,of:D5.rows.length,err:P5.rows.filter(x=>x.err).map(x=>x.err).slice(0,3)});
    const hi=aoa5.findIndex(r=>r.includes('Supplement no')),H5=aoa5[hi],ci=k=>H5.indexOf(k),body=aoa5.slice(hi+1).filter(r=>r[ci('Supplement no')]);
    const ch=body[0].slice(),ch0=ch[ci('Supplement no')],del=body[1][ci('Supplement no')],nw=ch.slice();ch[ci('Net value')]=-123000;nw[ci('Supplement no')]='BS-NEW';
    const wb5=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb5,XLSX.utils.aoa_to_sheet([...aoa5.slice(0,hi+1),ch,...body.slice(2),nw]),'Supplements');
    const file5=new File([xlsxBlob(wb5)],'changed.xlsx'),msgs=[];window.confirm=m=>{msgs.push(m);return true};
    const up=async()=>{state.logTab='supp';state.logPid=xp;go('logs');await new Promise(r=>setTimeout(r,150));$('#logMonth').value=xper;await handleLogFile(file5);$('#logMonth').value=xper;await logGo(document.createElement('button'))};
    await up();const L5=suppLatest(xp,xper);
    ok('37. Uploaded again for the same version, the changed file replaces that log: the changed amount, the deleted row and the new row',L5.b.source_period===xper&&L5.rows.length===body.length&&(L5.rows.find(r=>r.supp_no===ch0)||{}).amount===-123000&&!L5.rows.some(r=>r.supp_no===del)&&L5.rows.some(r=>r.supp_no==='BS-NEW'),L5.rows.map(r=>r.supp_no+' '+r.amount));
    ok('38. Before it is saved, the rows that leave the log are listed',msgs.some(m=>m.includes(del)&&/will leave the log/.test(m)),msgs);
    const nbat=DB.batches.length;await up();ok('39. The same file twice changes nothing',DB.batches.length===nbat&&suppLatest(xp,xper).b.id===L5.b.id);
    state.suppF=null;Object.assign(suppState(),{per:xper});saved=[];await suppExport();const PA=logParse(await sheet(saved[0].b),false);PA.rows.forEach(x=>{if(!x.err)x.err=suppProjErr(x,xp)});
    ok('40. In an export of many projects, the rows of another project are refused',PA.rows.some(x=>/is for project/.test(x.err||''))&&PA.rows.filter(x=>!x.err).every(x=>x._proj.includes(projById(xp).short)));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.saveFile=keepSave;window.confirm=keepConfirm;window.prompt=keepPrompt;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Budget supplements: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__suppChecks=res;try{sessionStorage.setItem('suppChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
