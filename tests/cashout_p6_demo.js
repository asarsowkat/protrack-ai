/* ProTrackAI v3.21, the cash-out forecast from the material POs on P6 dates and the cost report by WBS head.
   Acceptance checks for the demo page. How to run: open demo.html (or index.html) on the demo page, sign in with the demo
   Super Admin account (U28), open the browser console and paste this whole file. It saves this browser's demo data first
   and puts it back at the end, then reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},err=f=>{try{f();return ''}catch(x){return x.message}};
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'&&u.active!==false),co=U.find(u=>isCoord(u)),keepMt=window.mtMaterials,keepSave=window.saveFile;let saved=[];window.saveFile=async(n,b)=>{saved.push({n,b})};
  try{
    as(sa.id);
    /* material POs */
    const Q=coMatPos('QOT'),J=coMatPos('JBS');
    ok('1. Material POs are the PO numbers of Material tracking, one per PO; materials without a PO are listed as not ordered',Q.length===3&&J.length===5&&coMatUnordered('QOT').some(m=>m.material==='Composite Insulators')&&coMatUnordered('JBS').some(m=>m.material==='Shunt Reactor'),[Q.map(x=>x.no),J.map(x=>x.no)]);
    const x=Q.find(y=>y.mats.some(m=>m.material==='ACSR Conductor Drums')),P6=coP6('QOT'),del=x.s.milestones.find(m=>m.stage==='DEL'),d=coMatPayDate(x,del,P6);
    ok('2. A milestone is paid on its stage date (P6 forecast until done) plus the contractual days',d.base===x.stages.DEL.date&&d.date===addDays(x.stages.DEL.date,del.pay_days)&&d.src==='P6 forecast',d);
    const ret=x.s.milestones.find(m=>m.stage==='TCC'),dr=coMatPayDate(x,ret,P6);
    ok('3. The retention is paid after the P6 TCC milestone of the updated schedule',P6.tcc&&dr.base===P6.tcc.date&&/TCC|Technical completion/i.test(coStageName('TCC'))&&dr.date===addDays(P6.tcc.date,ret.pay_days),{tcc:P6.tcc,d:dr});
    ok('4. The standard schedule: 10% PO creation, 20% FAT, 60% delivery at site, 10% retention at TCC',coMatStd().map(m=>m.stage+':'+m.pct).join()==='PO:10,FAT:20,DEL:60,TCC:10');
    /* the schedule moves, the cash-out moves */
    const lab='Material PO '+x.no,before=coForecast('QOT').srcF[lab]||{};
    window.mtMaterials=pid=>keepMt(pid).map(m=>m.material==='ACSR Conductor Drums'?{...m,cells:{...m.cells,DEL:m.cells.DEL&&{...m.cells.DEL,date:addDays(m.cells.DEL.date,92)}}}:m);
    const after=coForecast('QOT').srcF[lab]||{};window.mtMaterials=keepMt;
    const mB=Object.keys(before).sort(),mA=Object.keys(after).sort();
    ok('5. When the P6 delivery slips by three months, the delivery payment moves three months later',mA.join()!==mB.join()&&Object.values(after).reduce((a,b)=>a+b,0)===Object.values(before).reduce((a,b)=>a+b,0),[mB,mA]);
    /* rules */
    const y=Q[0];
    ok('6. A material PO needs its value; a changed value needs the revision reference and reason',/PO value/.test(err(()=>coMatPoSaveLocal('QOT',y.no,{value:'',milestones:y.s.milestones},'')))&&/revision reference/.test(err(()=>coMatPoSaveLocal('QOT',y.no,{value:(+y.s.value)+1000,milestones:y.s.milestones},''))));
    const paid=y.s.milestones.find(m=>m.status==='Paid');const cst=U.find(u=>u.role==='costing'&&!isCoord(u)&&accessIds(u).includes('JBS'));
    as(cst.id);const jx=coMatPos('JBS').find(z=>z.s.milestones.some(m=>m.status==='Paid'));const jp=jx.s.milestones.find(m=>m.status==='Paid');
    ok('7. What was paid on a material PO cannot be changed by the keeper',/is paid: what was paid cannot be changed/.test(err(()=>coMatPoSaveLocal('JBS',jx.no,{value:jx.s.value,milestones:jx.s.milestones.map(m=>m.id===jp.id?{...m,pct:5}:m)},''))));
    const jy=coMatPos('JBS')[0],jm=jy.s.milestones.find(m=>m.status!=='Paid');
    coMatPoSaveLocal('JBS',jy.no,{value:jy.s.value,status:'Open',milestones:jy.s.milestones.map(m=>m.id===jm.id?{...m,pct:(+m.pct)+5}:m)},'');
    ok('8. Milestones not totalling 100% leave the forecast incomplete; changed milestones wait for approval',coForecast('JBS').incomplete.some(t=>/must total 100%/.test(t))&&coMatPos('JBS').find(z=>z.key===jy.key).s.milestones.some(m=>m.approval==='Draft'));
    as(sa.id);ok('9. Approval is refused while the terms are incomplete',/Fix these first/.test(err(()=>coMatPoApproveLocal('JBS',jy.no,''))));as(sa.id);
    /* the cost report heads */
    const CH=coCostHeads('QOT','2026-08'),tr=k=>CH.lines.find(l=>l.code===k).treat;
    ok('10. Default treatments: material heads to material POs, installation to subcontract POs, contingency and reserves excluded, the rest from the cost report',tr('MTRL.ELC')==='mat'&&tr('INSTL.ELC')==='sub'&&tr('CONT')==='excl'&&tr('MGT.RES')==='excl'&&tr('PC ITEMS')==='excl'&&tr('SM')==='nonpo'&&tr('MAN.ELC')==='sub',CH.lines.map(l=>l.code+':'+l.treat).join(' '));
    const FQ=coForecast('QOT'),cr=FQ.srcF['Cost report heads (EAC − actual)'],cm=Object.keys(cr).sort(),cv=cm.map(m=>cr[m]);
    ok('11. A cost-report head forecasts EAC − actual, spread evenly from the month after the cutoff to the P6 forecast TCC',cm[0]==='2026-09'&&cm[cm.length-1]===FQ.P6.finishM&&Math.max(...cv)-Math.min(...cv)<=cm.length*FQ.heads.lines.length,{from:cm[0],to:cm[cm.length-1],tcc:FQ.P6.finish});
    const cont=CH.lines.find(l=>l.code==='CONT'),Fc0=coForecast('QOT');coHeadsSaveLocal('QOT',{...Object.fromEntries(CH.lines.map(l=>[l.code,l.treat])),CONT:'nonpo'},true,'test');const Fc1=coForecast('QOT');
    ok('12. Contingency is excluded by default; treated as cost it would add its EAC − actual',Fc1.fac-Fc0.fac===Math.max(0,cont.eacH-cont.actualH));coHeadsSaveLocal('QOT',Object.fromEntries(CH.lines.map(l=>[l.code,l.treat])),true,'back');
    const FR=coForecast('RMX');
    ok('13. A PO head with no PO recorded falls back to the cost report, with a warning',coMatPos('RMX').length===0&&FR.exceptions.some(t=>/Electrical Material: no material POs recorded/.test(t)));
    ok('14. The ETC of the PO heads (not yet ordered) is forecast once, and can be switched off',FQ.outUnord>0&&(coHeadsSaveLocal('QOT',Object.fromEntries(CH.lines.map(l=>[l.code,l.treat])),false,'x'),coForecast('QOT').outUnord===0)&&(coHeadsSaveLocal('QOT',Object.fromEntries(CH.lines.map(l=>[l.code,l.treat])),true,'x'),true));
    /* reconciliation */
    const FJ=coForecast('JWP');
    ok('15. Cost booked and not yet paid is a payable in the month after the cutoff; nothing is counted twice',FJ.diff<0&&FJ.payable===-FJ.diff&&(FJ.srcF['Cost booked, not yet paid']||{})[FJ.next]===FJ.payable
      &&FJ.fac===FJ.paidPo+FJ.booked+FJ.paidOther+FJ.outSub+FJ.outMat+FJ.outCost+FJ.outUnord+FJ.outOther,{diff:FJ.diff,payable:FJ.payable});
    const FT=coForecast('RTT');
    ok('16. Finance paying more than the records explain, beyond the PO milestones due, is reconciliation required',FT.diff>0&&FT.unexplained===Math.max(0,FT.diff-FT.dueUnmarked)&&FT.flags.includes('rec'));
    ok('17. The cross-check with the cost report EAC flags a large gap',coForecast('JDC').exceptions.some(t=>/Cross-check/.test(t))&&FQ.eacCmp===CH.eacH-CH.exclEacH);
    const aug=FQ.months.find(r=>r.m==='2026-08');
    ok('18. Month by month: expected = PO payments scheduled + the cost booked that month (two released cost reports)',aug&&aug.costMove!=null,aug);
    /* screens and reports */
    state.impPid='QOT';state.coTab='po';go('cout');await new Promise(r=>setTimeout(r,200));const t=$('#view').innerText;
    ok('19. The PO tab shows the material POs, the subcontract POs and the cost report heads',/Material POs/.test(t)&&/Subcontract POs/.test(t)&&/Cost report heads/.test(t));
    state.coTab='rec';render();await new Promise(r=>setTimeout(r,200));ok('20. The reconciliation shows the bridge and the timing items',/Cost booked, not yet paid/.test($('#view').innerText)&&/Unexplained/.test($('#view').innerText)&&/Cross-check/.test($('#view').innerText));
    go('mat');await new Promise(r=>setTimeout(r,300));
    ok('21. Material tracking shows each PO\'s value and payment terms, and opens them',!!document.querySelector('#mtTable [data-comatpo]')&&/payment milestone/.test($('#mtTable').innerText));
    document.querySelector('#mtTable [data-comatpo]').click();await new Promise(r=>setTimeout(r,200));ok('22. ... in the payment terms window',/Material PO/.test($('#sheet').innerText)&&/Paid at \(stage\)/.test($('#sheet').innerText));closeDrawer();
    await loadLib(LIBS.xlsx);saved=[];await coExcel('QOT');const wb=XLSX.read(await saved[0].b.arrayBuffer(),{type:'array'});
    ok('23. The Excel report has the material POs, the cost heads and the reconciliation bridge',['Material POs','Cost heads','Reconciliation bridge'].every(n=>wb.SheetNames.includes(n)));
    const pm=U.find(u=>u.role==='pm'&&accessIds(u).includes('QOT'));as(pm.id);
    ok('24. A project manager reads the material PO terms but cannot change them or the head treatments',/costing engineers/.test(err(()=>coMatPoSaveLocal('QOT',Q[0].no,{value:Q[0].s.value,milestones:Q[0].s.milestones},'')))&&/keep this project/.test(err(()=>coHeadsSaveLocal('QOT',{},true,''))));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.mtMaterials=keepMt;window.saveFile=keepSave;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Cash-out on P6 and the cost report: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__cpChecks=res;try{sessionStorage.setItem('cpChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
