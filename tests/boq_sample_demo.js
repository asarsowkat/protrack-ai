/* ProTrackAI v3.25.1, BOQ Engine sample data (demo page). Checks that the sample OHTL (QOT) and substation (JBS) data
   loads complete and that its quantities are the ones the engine works out from the sample dimensions. How to run: open
   demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this whole file.
   It reads only; nothing is changed. */
(async()=>{
  const res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  try{
    const B=boqDB(),pq=B.pkgs.find(p=>p.project_id==='QOT'&&p.sample),pj=B.pkgs.find(p=>p.project_id==='JBS'&&p.sample);
    ok('1. A sample package on the OHTL project (QOT) and on the substation (JBS), labelled sample',!!pq&&!!pj&&/sample/i.test(pq.name)&&/sample/i.test(pj.name));
    const q=(pkg,code)=>{for(const c of boqCalcsOf(pkg.id))for(const o of (c.outputs||[]))if(o.item_code===code)return dqRound(o.est,3);return null};
    const Q={'EXC-001':'322.560','BLD-001':'5.292','RCC-001':'51.489','BKF-001':'265.779','DSP-001':'56.781','FWK-001':'81.000','RFT-001':'3962.706','EXC-002':'1800.000','IMP-001':'2880.000','EXC-003':'432.640'};
    const gq=Object.fromEntries(Object.keys(Q).map(k=>[k,q(pq,k)]));ok('2. OHTL quantities: T-101 excavation, blinding, concrete, backfill, disposal, formwork, steel; AR-2 stripping and subbase; T-105 provisional',Object.keys(Q).every(k=>gq[k]===Q[k]),gq);
    const J={'EXC-001':'90.000','BLD-001':'5.850','RCC-001':'54.000','RCC-002':'3.600','BKF-001':'30.150','DSP-001':'59.850','FWK-001':'33.800','RFT-001':'2944.407','EXC-002':'381.600','SND-001':'56.863','DCT-001':'1290.000','PTS-001':'370.000','WTP-001':'550.000','BKF-002':'298.800'};
    const gj=Object.fromEntries(Object.keys(J).map(k=>[k,q(pj,k)]));ok('3. Substation quantities: T1 foundation (with the 2.5 % steel wastage from the specification) and cable trench CT-1 on its rev 3',Object.keys(J).every(k=>gj[k]===J[k]),gj);
    const eq=boqEstsOf(pq.id),ej=boqEstsOf(pj.id);ok('4. Estimates: OHTL rev 0 released and handed off; substation rev 0 released, rev 1 ready for review',eq.map(e=>e.status).join()==='Released'&&ej.map(e=>e.status).join()==='Released,Ready for Review'&&B.handoffs.some(h=>h.est_id===eq[0].id));
    ok('5. Released revisions were reviewed and approved by someone other than the preparer',[eq[0],ej[0]].every(e=>e.approved_by&&e.approved_by!==e.prepared_by&&e.approved_by!==e.submitted_by));
    const cmp=boqCompare(ej[0].lines,ej[1].lines,ej[0].snap_at,ej[1].snap_at),bk=cmp.find(x=>x.item_code==='BKF-002');
    ok('6. Revision comparison shows the trench change and its cause',!!bk&&bk.state==='Modified'&&dqRound(bk.var,2)==='21.60'&&bk.why.some(w=>/Changed geometry/.test(w)),bk);
    ok('7. Rates only on the substation, from the costing engineer, marked as demo samples',ej[0].lines.some(l=>l.rate!=null)&&Object.values(ej[0].rates).every(r=>/DEMO sample rate/.test(r.note))&&eq[0].lines.every(l=>l.rate==null));
    const R=a=>boqReadiness(boqAssetsOf(pj.id).find(x=>x.name===a)).level;ok('8. Completeness: T1 foundation and trench ready; GIS building partial (sections not issued)',R('Power Transformer T1 Foundation')==='Ready'&&R('Cable Trench CT-1 (transformer yard to GIS building)')==='Ready'&&R('GIS Building')==='Partial estimate only');
    ok('9. The GIS building excavation stays incomplete (depth awaited), with no quantity',boqCalcsOf(pj.id).some(c=>/GIS building/.test(c.desc)&&c.status==='Incomplete'&&!(c.outputs||[]).length));
    ok('10. A real conflict is flagged (structural concrete C40/50 against C35/45), blinding C15 is not a conflict',boqSpecConflicts('JBS').length===1&&boqSpecConflicts('JBS')[0].scope==='structural concrete');
    const pend=B.dwgs.filter(d=>d.project_id==='JBS'&&!d.reg&&!d.discarded);ok('11. One upload waits for registration, with its proposals and evidence',pend.length===1&&pend[0].ext.cls.st&&pend[0].ext.no==='JBS-SS-CIV-501');
    ok('12. Status awaiting confirmation (GIS building GA) and a newer OHTL revision not yet the basis',B.dwgs.some(d=>d.no==='JBS-SS-ARC-101'&&!d.status_ok)&&B.dwgs.some(d=>d.no==='QOT-TL-CIV-101'&&d.rev==='C'&&!d.basis));
    const d=B.dwgs.find(x=>x.no==='JBS-SS-CIV-201'),b=await boqFileGet(d),t=new TextDecoder().decode(new Uint8Array((await b.arrayBuffer()).slice(0,5)));ok('13. Sample drawings open as generated PDFs',t==='%PDF-');
    const S=boqSummary(ej[0].lines);ok('14. Estimated amounts are kept apart from budgets and labelled estimates',S.some(s=>s.amt!=null)&&ej[0].lines.every(l=>l.qty==null||l.amount==null||l.amount===dqStr(dqMul(dq(l.qty),dq(l.rate)))));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`BOQ Engine sample data: ${res.length-f} passed, ${f} failed.`);window.__bsChecks=res;
})();
