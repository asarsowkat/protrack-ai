/* ProTrackAI v3.11, internal and client contract value: acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. The Excel check needs an internet connection (SheetJS
   loads from cdnjs). */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},co=DB.master.users.find(u=>u.role==='costing');
  try{
    as('U28');const P='RMX',L=voLatest(P,'9999-12'),R=L.rows,row=ref=>R.find(r=>r.ref_no===ref),p=projById(P),orig=Math.round(+p.value*1e6);
    ok('Sample: VO-001 approved by the client at a client approved price',voHas(row('VO-001').client_price)&&/approved/i.test(row('VO-001').client_status),row('VO-001').client_price);
    ok('Sample: VO-002 considered internally in full and CL-001 in part, each with a WF number and date',voBasis(row('VO-002'))==='Full'&&voBasis(row('CL-001'))==='Partial'&&R.filter(r=>voHas(r.internal_price)).every(r=>r.wf_no&&r.wf_date));
    let c=contractOf(P);const sub=R.filter(voSubmitted).reduce((t,r)=>t+(+r.est_price||0),0),appr=R.filter(r=>!voRejected(r)&&voHas(r.client_price)).reduce((t,r)=>t+ +r.client_price,0);
    const int=R.reduce((t,r)=>t+(voRejected(r)?0:voHas(r.client_price)?+r.client_price:voHas(r.internal_price)&&r.wf_no&&r.wf_date?+r.internal_price:0),0);
    ok('Original contract value = project value',c.orig===orig,{orig:c.orig});
    ok('Change orders submitted = Σ estimated price of the submitted items',Math.abs(c.sub-sub)<1e-6,{sub:c.sub});
    ok('Change orders approved = Σ client approved price',Math.abs(c.appr-appr)<1e-6,{appr:c.appr});
    ok('Considered internally = client approved price, else the WF-approved internal price',Math.abs(c.int-int)<1e-6&&Math.abs(c.int-c.appr-c.wf)<1e-6,{int:c.int,wf:c.wf});
    ok('Revised contract value (internal) = original + considered internally',c.rev_int===c.orig+c.int,c.rev_int);
    ok('Revised contract value (client) = original + approved by the client',c.rev_client===c.orig+c.appr,c.rev_client);
    // rules
    const cl=row('CL-001'),e=v=>{try{voUpdate(cl.id,{client_status:cl.client_status,client_price:cl.client_price??'',internal_price:cl.internal_price??'',wf_no:cl.wf_no||'',wf_date:cl.wf_date||'',remarks:cl.remarks||'',...v});return ''}catch(x){return x.message}};
    as(co.id);
    ok('Refused: a price considered internally without a WF number',/WF number and WF date/.test(e({wf_no:''})));
    ok('Refused: a price considered internally above the estimated price',/more than the estimated price/.test(e({internal_price:String(+cl.est_price+1)})));
    ok('Refused: a client approved price while the client has not approved',/needs the client approval status/.test(e({client_status:'Pending',client_price:'1000'})));
    ok('Refused: a WF date in the future',/in the future/.test(e({wf_date:'2099-01-01'})));
    e({client_status:'Pending',client_price:''});const before=contractOf(P),relPl=relReleased(P,'planning','month',L.b.source_period),frozen=relPl?JSON.stringify(relContract(relPl)):null;
    ok('The costing engineer updates the client approved price; the internal value follows',e({client_status:'Partially approved',client_price:'5000000'})===''&&contractOf(P).appr===before.appr+5000000&&contractOf(P).int===before.int-(+cl.internal_price)+5000000);
    ok('Each update is kept in the log history with who and when',DB.coAudit[0].ref==='CL-001'&&DB.coAudit[0].by===co.name&&DB.coAudit[0].changes.some(x=>x[0]==='client_price'));
    ok('A released report keeps the contract value frozen at approval',!relPl||JSON.stringify(relContract(relPl))===frozen);
    ok('A project manager cannot update the log',(()=>{as(teamOf(P,'pm')[0].id);const m=e({remarks:'x'});as(co.id);return /Only the costing engineer/.test(m)})());
    e({client_status:'Rejected',client_price:''});ok('A rejected item counts nowhere',contractOf(P).int===before.int-(+cl.internal_price)&&contractOf(P).appr===before.appr);
    // reports
    as('U28');
    const f=relPlanCalc(P,{planned_pct:40,actual_pct:35},curMonth());
    ok('Internal report amounts use the internal revised contract value',f.int_plan_amt===Math.round(contractOf(P,curMonth()).rev_int*0.4),{amt:f.int_plan_amt});
    const cf=crCompute(P,curMonth(),crDefaults(P,curMonth()));ok('Monthly cost report: contract value = internal revised; margin on it',cf.contract_value===contractOf(P,curMonth()).rev_int);
    const cc=contractClient(contractOf(P));ok('Client report: only the client-approved value, never the internal consideration',cc.rev_client===contractOf(P).rev_client&&!('int' in cc)&&!('rev_int' in cc)&&!('wf' in cc));
    const xr=xrRows('month',L.b.source_period).find(x=>x.p.id===P);ok('Executive report weights progress by the internal revised contract value',xr&&Math.abs(xr.w-(xr.cc.rev_int/1e6))<1e-9,xr&&xr.w);
    // the approval freezes the breakdown
    const sub2=relRows().find(r=>r.project_id==='JBS'&&r.kind==='planning'&&r.period_type==='month'&&['Draft','Submitted'].includes(r.status));
    if(sub2){const base={project_id:'JBS',kind:'planning',period_type:'month',period:sub2.period};if(sub2.status==='Draft'){as(teamOf('JBS','plan')[0].id);await relAct({...base,action:'submit',note:''})}as('U28');
      const ap=await relAct({...base,action:'approve',note:'',validated:true,validation_note:'checked'});ok('Approving an internal report freezes the contract breakdown into it',!!(ap&&ap.contract_snapshot&&ap.contract_snapshot.rev_int===contractOf('JBS',sub2.period).rev_int))}
    // the Excel template and an upload of the new columns
    await loadLib(LIBS.xlsx);const head=['Ref no','Type (VO or Claim)','Description','Submission status','Submission date','Client approval status','Estimated price','Estimated cost','Expected price to be approved','Client approved price','Price considered internally (SAR)','Internal WF no','Internal WF date','Cost considered internally','Change in Rev-0 budget','Internal WF status','Overall approval status with client','Remarks'];
    const pr=logParse([head,['VO-9','VO','x','Submitted','2026-08-10','Approved',100,50,90,90,'','','','Yes',0,'','Approved',''],['CL-9','Claim','y','Submitted','2026-08-10','Pending',100,'',80,'',60,'WF-1','2026-08-20','','','','',''],['CL-8','Claim','z','Submitted','2026-08-10','Pending',100,'',80,'',60,'','','','','','','']],true);
    ok('Upload reads the client approved price, the price considered internally, WF no and WF date',pr.rows[0].client_price===90&&pr.rows[1].internal_price===60&&pr.rows[1].wf_no==='WF-1'&&pr.rows[1].wf_date==='2026-08-20'&&pr.rows[1].price_internal==='Partial',pr.rows.slice(0,2).map(r=>({cp:r.client_price,ip:r.internal_price,wf:r.wf_no})));
    ok('Upload refuses a row considered internally without its WF number and date',/WF number and WF date/.test(pr.rows[2].err),pr.rows[2].err);
    const old=logParse([['Ref no','Type','Description','Submission status','Submission date','Client approval status','Estimated price','Estimated cost','Expected price to be approved','Price considered internally','Cost considered internally'],['VO-7','VO','x','Submitted','2026-08-10','Pending',100,50,90,'Yes','No']],true);
    ok('A log in the earlier layout (Yes / No / Partial) still loads, its text kept',!old.rows[0].err&&old.rows[0].price_internal==='Yes'&&old.rows[0].internal_price==null,old.rows[0]);
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Contract value: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__cvChecks=res;try{sessionStorage.setItem('cvChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
