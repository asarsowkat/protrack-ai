/* ProTrackAI v3.48: Client Invoice Builder (Invoices & Cash Flow → Client Invoice Builder). Acceptance checks for the demo page:
   the menu, rights and screen; reading a Schedule-C (descriptions, priced items, "Not applicable", "Included in", duplicates,
   components); revisions and their approval (nobody approves their own); the five invoicing rules; weighted P6 progress;
   the mapping read from the "Schedule C" activity code when an updated schedule is loaded, the mapping audit and its review;
   loading the invoice history of a running project; preparing an invoice from P6 progress (previous, this period,
   cumulative; retention, advance recovery, VAT); every exception; the rules-based review; the workflow with its
   separation of duties; the client certificate with changes; the payment; the invoice register and cash pages; the next
   invoice continuing from the certified one; the forecast; the Excel invoice; the audit trail; every tab.
   How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this whole
   file. It saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';state.sector='ALL';SCOPE=scopeIds()},keepToast=toast,keepSave=saveFile,keepPrompt=window.prompt,toasts=[],thr=async f=>{try{await f();return null}catch(e){return e.message}};
  const pid='JBS',SA='U28',COST='U41',PM='U08',RM='U03',PLAN='U31',FORE='U21',ENG='U13';
  try{
    window.toast=m=>toasts.push(m);as(SA);
    ok('1. Version 3.48 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=48,APP_VERSION);
    const D=DOMAINS.find(d=>d.k==='invoices'),its=D.items.filter(i=>i.v==='cib');
    ok('2. Menu: Invoices & Cash Flow → Client Invoice Builder, Schedule-C mapping audit, Client invoices; the screen is in Role access; six rights',
      its.map(i=>i.tab).join()==='dash,map,inv'&&SCREENS.includes('cib')&&NAV_ALL.includes('cib')&&['cib.setup','cib.map','cib.prepare','cib.review','cib.approve','cib.certify'].every(k=>RIGHT_N[k])
      &&(as(FORE),!navOn('cib'))&&(as(ENG),!navOn('cib'))&&(as(COST),navOn('cib'))&&(as(SA),true));
    as(COST);ok('3. Default rights: costing sets up, prepares and certifies, not reviews or approves; planning maps; the project manager reviews; the regional manager approves',
      can('cib.setup')&&can('cib.prepare')&&can('cib.certify')&&!can('cib.review')&&!can('cib.approve')&&(as(PLAN),can('cib.map')&&can('cib.setup'))&&(as(PM),can('cib.review')&&!can('cib.approve'))&&(as(RM),can('cib.approve'))&&(as(SA),true));
    /* the demo sample */
    const QS=cibAppr('QOT'),QA=cibAudit('QOT');
    ok('4. Demo: QOT carries a SAMPLE Schedule-C (labelled, approved), its mapping with two items missing and one unknown code, and a loaded history #3',
      !!QS&&/SAMPLE/.test(QS.head.title)&&/SAMPLE/.test(QS.file)&&QA.miss.length===2&&QA.unknown.length===1&&cibInvOf('QOT').some(x=>x.kind==='Migrated'&&x.seq===3&&x.st==='Certified'),{miss:QA.miss.map(x=>x.i.no),unk:QA.unknown.length});
    /* reading a price schedule: the column layout of the client's Schedule-C, with made-up numbers */
    const aoa=[['BID FORM'],['CONTRACT PRICE BREAKDOWN'],[],['Item Number','Line Type','Short Description','Long Description','Qty','Unit','Unit Price','Total Cost'],['T.PART I'],
      ['T.1','Description','General'],['T.1.1','Breakdown','General','Site office',1,'LT',1000,1000],['T.1.2','Breakdown','General','Catering',1,'NA','','Not Applicable'],['','','','','Sub-Total "General"','','',1000],
      ['T.2','Description','Engineering & Design'],['T.2.1','Breakdown','Main','Phase I',1,'LT',3000,3000],['T.2.2','Breakdown','Main','Phase II',1,'LT',2000,2000],
      ['T.3','Description','Equipment & Materials'],['T.3.1','Description','GIS'],['T.3.1.1','Breakdown','GIS','Circuit breaker',2,'EA',5000,10000],['T.3.1.2','Breakdown','GIS','Panels',1,'LT',4000,4000],
      ['T.4','Description','Construction'],['T.4.1','Breakdown','Site','Site grading',1,'LT',6000,6000],['T.4.2','Breakdown','Site','Site development',1,'LT','','Included in tem T.4.1'],[' T.4.3','Breakdown','Building','Super-structure',1,'LT',8000,8000],
      ['T.5','Description','Installation'],['T.5.1','Breakdown','GIS','GIS installation',1,'LT',7000,7000],['T.6','Description','Testing & Commissioning'],['T.6.1','Breakdown','T&C','Final commissioning',1,'LT',2000,2000],['T.6.1','Breakdown','T&C','Duplicate row',1,'LT',99,99],
      ['','TOTAL PROJECT PRICE','','','','','',43000]];
    const P=cibParseRows(aoa),B=P.items.filter(i=>i.leaf&&i.st==='Active'&&i.value>0),by=k=>B.filter(i=>i.comp===k).map(i=>i.no).join();
    ok('5. Reading a Schedule-C: priced items and headings, "Not applicable", "Included in", a leading space, a duplicate kept once, the component of each item',
      B.length===9&&B.reduce((t,i)=>t+i.value,0)===43000&&P.items.find(i=>i.no==='T.1.2').st==='Not applicable'&&P.items.find(i=>i.no==='T.4.2').st==='Included'&&P.items.find(i=>i.no==='T.4.2').incl==='T.4.1'
      &&!!P.items.find(i=>i.no==='T.4.3')&&P.warn.some(w=>/appears again/.test(w))&&by('MAT')==='T.3.1.1,T.3.1.2'&&by('TC')==='T.6.1'&&by('ENG')==='T.2.1,T.2.2'&&!P.items.find(i=>i.no==='T.3.1').leaf,{n:B.length,warn:P.warn});
    /* the five rules */
    const r1={t:'pct',cap:80,tcc:10,fac:10},r2={t:'split',first:90},r5={t:'phase',cap:80,tcc:10,fac:10,steps:[{n:'Phase I',pct:40,act:'A'},{n:'Phase II',pct:60,act:'B'}]};
    ok('6. Rules: 1 percentage (cap, TCC, FAC), 2 split 90/10 at FAC, 3 at TCC, 4 at FAC; 5 phase steps; checks of the percentages',
      Math.abs(cibPay(r1,1000,0.5,false,false)-400)<1e-9&&Math.abs(cibPay(r1,1000,1,true,false)-900)<1e-9&&Math.abs(cibPay(r1,1000,1,true,true)-1000)<1e-9&&Math.abs(cibPay(r2,1000,1,false,false)-900)<1e-9&&Math.abs(cibPay(r2,1000,1,false,true)-1000)<1e-9
      &&cibPay({t:'tcc'},1000,1,false,false)===0&&cibPay({t:'tcc'},1000,0,true,false)===1000&&cibPay({t:'fac'},1000,1,true,false)===0&&cibPay({t:'fac'},1000,0,true,true)===1000
      &&/add up to 100/.test(cibRuleErr({t:'pct',cap:80,tcc:10,fac:0}))&&!!cibRuleErr({t:'split',first:100})&&/steps/.test(cibRuleErr({t:'phase',cap:100,tcc:0,fac:0,steps:[]}))&&!!cibRuleErr({...r5,steps:[{n:'I',pct:50,act:'A'}]})&&cibRuleErr(r5)===null);
    /* weighted progress: four activities at 40, 60, 30 and 20% with their weights */
    const X0={byItem:{'W.1':[{id:'a',pct:40,w:300},{id:'b',pct:60,w:400},{id:'c',pct:30,w:200},{id:'d',pct:20,w:100}]},byId:{},to:ASOF,M:{}},S0={rules:{CON:{t:'pct',cap:100,tcc:0,fac:0}},items:[]},i0={no:'W.1',comp:'CON',value:2595191};
    const g0=cibProg('ZZZ',S0,i0,X0),gE=cibProg('ZZZ',S0,i0,{...X0,byItem:{'W.1':X0.byItem['W.1'].map(a=>({...a,w:0}))}});
    ok('7. Progress is the weighted % complete of the mapped activities (equal weights when none carry one)',Math.abs(g0.p-0.44)<1e-9&&g0.src==='p6'&&g0.n===4&&Math.abs(gE.p-0.375)<1e-9,{p:g0.p,eq:gE.p});
    /* a new project: JBS. Upload, approve, map */
    const rows=DB.schedRows[schedUps(pid)[0].id].filter(r=>+r.w>0&&!r.ms),val=Math.round(projById(pid).value*1e6),items=[];let left=val;const tw=rows.reduce((t,r)=>t+r.w,0);
    const compOf={GEN:'GEN',DES:'ENG',MAT:'MAT',CON:'CON',INS:'INS',TC:'TC',CLO:'CLO'};
    rows.forEach((r,k)=>{const v=k===rows.length-1?left:Math.round(val*r.w/tw);left-=v;items.push({no:`J.${k+1}`,parent:null,lvl:0,desc:r.name,comp:compOf[r.phase]||'CON',unit:'LT',qty:1,rate:v,value:v,st:'Active',incl:null,leaf:true,line:'Breakdown',limit:100,rule:null})});
    items[items.length-1].limit=50;
    const keepCib=JSON.stringify(DB.cib);
    as(FORE);const eF=await thr(()=>cibAct('sch_save',{pid,head:{value:val},items}));as(ENG);const eE=await thr(()=>cibAct('sch_save',{pid,head:{value:val},items}));
    as(COST);const S1=await cibAct('sch_save',{pid,head:{value:val,vat:15,ret_pct:5,ret_cap:5,ret_tcc:50,ret_fac:50,adv_pct:10,adv_rec:10,pay_days:45,contract_no:'TEST-1'},items,file:'test.xlsx'});
    const eTwo=await thr(()=>cibAct('sch_save',{pid,head:{value:val},items}));const RU=rightsDB().user,keepRU=RU[COST];RU[COST]=Object.assign({},keepRU,{'cib.approve':true});const eOwn=await thr(()=>cibAct('sch_approve',{pid,sch:S1.id}));if(keepRU===undefined)delete RU[COST];else RU[COST]=keepRU;
    as(PM);const ePm=await thr(()=>cibAct('sch_approve',{pid,sch:S1.id}));as(RM);await cibAct('sch_approve',{pid,sch:S1.id});
    ok('8. Schedule-C revisions: foremen and site engineers cannot upload; one draft at a time; nobody approves their own; the approver approves',
      !!eF&&!!eE&&S1.st==='Approved'&&/draft revision is already/.test(eTwo)&&/Nobody approves/.test(eOwn)&&/approver/i.test(ePm)&&cibAppr(pid).id===S1.id,{eF,eE,eTwo,eOwn,ePm});
    as(COST);const eRule=await thr(()=>cibAct('sch_rules',{pid,sch:S1.id,rules:S1.rules}));const eHead=await thr(()=>cibActLocal('sch_save',{pid,head:{value:val,ret_tcc:70,ret_fac:40},items}));
    ok('9. An approved revision does not change (a new revision is uploaded); header checks (retention released adds up to at most 100%)',/Only a draft revision/.test(eRule)&&/more than 100/.test(eHead||''),{eRule,eHead});
    /* mapping from the "Schedule C" activity code when the updated schedule is loaded; one activity left without a code */
    as(PLAN);const parsed={codeTypes:['Discipline','Schedule C'],rows:rows.map((r,k)=>({id:r.id,name:r.name,codes:k===1?{}:{'Schedule C':`J.${k+1}`,Discipline:'X'}}))};parsed.rows.push({id:'JBS-XTRA',name:'Extra',codes:{'Schedule C':'J.99'}});
    await cibAfterSched(pid,parsed,'JBS_update.xer');const A1=cibAudit(pid);
    ok('10. Loading an updated schedule reads the "Schedule C" code: items mapped, the item without an activity is Missing, the notification says so',
      cibCodeType(parsed.codeTypes)==='Schedule C'&&A1.miss.length===1&&A1.miss[0].i.no==='J.2'&&A1.mapped===items.length-1&&(DB.notes[0]||{}).text.includes('not mapped to P6'),{miss:A1.miss.map(x=>x.i.no)});
    /* the history of a running project, then the first invoice here */
    as(COST);const prevLines=items.slice(0,3).map(i=>({no:i.no,cum:Math.round(i.value*0.2)}));const eMore=await thr(()=>cibAct('inv_migrate',{pid,seq:2,to:addDays(ASOF,-40),lines:[{no:'J.1',cum:items[0].value*2}]}));
    const H=await cibAct('inv_migrate',{pid,seq:2,to:monthEndOf(addDays(ASOF,-40).slice(0,7)),lines:prevLines,ret_cum:100,adv_cum:200,file:'latest_invoice.xlsx'});
    ok('11. Loading the latest certified invoice: amounts above an item value are refused; the history is a certified invoice #2',/more than its value/.test(eMore)&&H.kind==='Migrated'&&H.st==='Certified'&&H.seq===2&&H.tot.gross_cum===prevLines.reduce((t,l)=>t+l.cum,0),eMore);
    const eUnm=await thr(()=>cibAct('inv_save',{pid,to:ASOF}));const I1=cibInvOf(pid).find(x=>x.st==='Draft');
    ok('12. The invoice is prepared but blocked while an item is unmapped',!eUnm&&!!I1&&I1.seq===3&&cibBlocks(I1.exc).some(e=>e.k==='unmapped'),eUnm||I1.exc.map(e=>e.k));
    as(PLAN);const eRv=await thr(()=>cibAct('map_review',{pid,item:'J.2',d:'manual',pct:30,note:'no'}));await cibAct('map_review',{pid,item:'J.2',d:'manual',pct:30,note:'Progress per the approved site measurement sheet'});
    as(COST);await cibAct('inv_save',{pid,id:I1.id,to:I1.to,from:I1.from,ref:I1.ref});const I=cibInvOf(pid).find(x=>x.id===I1.id),T=JSON.parse(JSON.stringify(I.tot)),L2=I.lines.find(l=>l.no==='J.2');
    ok('13. Reviewing an unmapped item needs a reason; a stated % is billed and flagged; the block is gone',/reason/.test(eRv)&&L2.src==='manual'&&Math.abs(L2.prog-0.3)<1e-9&&!cibBlocks(I.exc).some(e=>e.k==='unmapped')&&I.exc.some(e=>e.k==='manual'),{eRv,blocks:cibBlocks(I.exc).map(e=>e.k)});
    const H0=S1.head,l1=I.lines.find(l=>l.no==='J.1'),last=I.lines[I.lines.length-1];
    ok('14. Previous certified, this period and cumulative per item; the item limit holds; retention, advance recovery and VAT follow the header',
      l1.prev_pay===prevLines[0].cum&&Math.abs(l1.this_pay-(l1.cum_pay-l1.prev_pay))<0.01&&last.cum_pay<=last.value*0.5+0.01&&Math.abs(T.gross_this-I.lines.reduce((t,l)=>t+l.this_pay,0))<0.05
      &&Math.abs(T.ret_this-Math.min(T.gross_this*0.05,val*0.05-100))<0.05&&Math.abs(T.adv_this-T.gross_this*0.1)<0.05&&Math.abs(T.net-(T.gross_this-T.ret_this-T.adv_this))<0.05&&Math.abs(T.vat-T.net*0.15)<0.05&&T.gross_prev===H.tot.gross_cum,T);
    /* exceptions */
    const fake=cibCompute(pid,{to:I.to,seq:I.seq,sch:S1.id});fake.lines[0].rev=true;fake.lines[1].over=true;fake.tot.gross_cum=val*2;
    const E=cibExc(pid,Object.assign({},I,{from:addDays(I.to,5)}),fake),Ek=E.map(e=>e.sev+':'+e.k);
    ok('15. Exceptions: schedule reversal, invoice limit, contract value exceeded, P6 update older than the period, unreleased progress report',
      Ek.includes('warn:reversal')&&Ek.includes('warn:over')&&Ek.includes('block:cv')&&Ek.includes('block:p6')&&Ek.includes('warn:release'),Ek);
    /* the review, then the workflow */
    const eNoAi=await thr(()=>cibAct('inv_submit',{pid,id:I.id}));const rv=cibReview(pid,I);await cibAct('inv_ai',{pid,id:I.id,score:rv.score,find:rv.find});
    const tam=JSON.parse(JSON.stringify(I));tam.lines[0].cum_pay+=5000;tam.lines[0].this_pay+=5000;const rvBad=cibReview(pid,tam);
    ok('16. "Review invoice": the arithmetic agrees with a fresh calculation; a tampered line is caught; checks of mapping, typed %, forecast; submitting needs the review first',
      /Run "Review invoice"/.test(eNoAi)&&rv.find.some(f=>f.k==='math'&&f.sev==='ok')&&rvBad.find.some(f=>f.k==='math'&&f.sev==='high')&&rv.find.some(f=>f.k==='progress'&&/typed/.test(f.msg))&&rv.find.some(f=>f.k==='forecast')&&rv.score>=0&&rv.score<=100,{eNoAi,score:rv.score});
    await cibAct('inv_submit',{pid,id:I.id});const eSelf=await thr(()=>cibAct('inv_review',{pid,id:I.id}));
    as(PM);await cibAct('inv_review',{pid,id:I.id});const eApPm=await thr(()=>cibAct('inv_approve',{pid,id:I.id}));
    as(RM);const eDocs=await thr(()=>cibAct('inv_approve',{pid,id:I.id}));
    ok('17. Submit, review by another person (not the preparer), approval needs the approver and every supporting document marked',/Only a reviewer|Nobody reviews/.test(eSelf)&&cibInvOf(pid).find(x=>x.id===I.id).hist.some(h=>h.st==='Reviewed')&&/approver/.test(eApPm)&&/supporting document/.test(eDocs),{eSelf,eApPm,eDocs});
    for(const [k] of CIB_DOCS)await cibAct('inv_docs',{pid,id:I.id,k,v:k==='spare'||k==='train'?'na':'yes'});
    const eRet=await thr(()=>cibAct('inv_return',{pid,id:I.id,note:'x'}));await cibAct('inv_approve',{pid,id:I.id});
    as(COST);const eIssF=await thr(()=>cibAct('inv_issue',{pid,id:I.id,date:addDays(TODAY,3)}));await cibAct('inv_issue',{pid,id:I.id,date:TODAY,ref:'JBS-INV-03'});
    const reg=invOf(pid).find(r=>r.cib&&r.no==='JBS-INV-03');
    ok('18. Approved, then issued (not in the future); the issued invoice joins the invoice register as a progress invoice',/Say why/.test(eRet)&&/not valid/.test(eIssF)&&!!reg&&reg.type==='Progress'&&Math.abs(reg.sub-T.gross_this)<0.05&&reg.sub_date===TODAY&&invTotals(pid).n>=1,{eRet,eIssF,reg});
    const cut=I.lines.find(l=>l.this_pay>0),ch={[cut.no]:cibR2(cut.this_pay/2)};const eOver=await thr(()=>cibAct('inv_certify',{pid,id:I.id,date:TODAY,lines:{[cut.no]:cut.this_pay*2}}));
    await cibAct('inv_certify',{pid,id:I.id,date:TODAY,ref:'CERT-3',lines:ch});const Ic=cibInvOf(pid).find(x=>x.id===I.id);
    ok('19. The client certificate: never more than claimed; changed amounts give the certified figures, retention and advance on them',/more than claimed/.test(eOver)&&Ic.st==='Certified'&&Ic.cert.changed&&Math.abs(Ic.cert.amt-(T.gross_this-cut.this_pay/2))<0.05&&Math.abs(Ic.tot.ret_this-Ic.cert.amt*0.05)<0.05&&Ic.lines.find(l=>l.no===cut.no).cert_cum===cibR2(cut.prev_pay+ch[cut.no]),Ic.cert);
    const ePayBig=await thr(()=>cibAct('inv_pay',{pid,id:I.id,date:TODAY,amt:Ic.tot.total*2}));await cibAct('inv_pay',{pid,id:I.id,date:TODAY,amt:Ic.tot.total});const reg2=invOf(pid).find(r=>r.cib&&r.no==='JBS-INV-03');
    ok('20. The payment: not more than the total with VAT; the register shows it certified and collected',/more than the invoice total/.test(ePayBig)&&reg2.appr===Ic.cert.amt&&Math.abs(reg2.coll-Ic.cert.amt)<0.05&&reg2.coll_date===TODAY,reg2);
    /* the next invoice continues from the certified one; duplicates refused */
    await cibAct('inv_save',{pid,to:ASOF,from:Ic.from});const I4=cibInvOf(pid).find(x=>x.st==='Draft'),lc=I4.lines.find(l=>l.no===cut.no);
    ok('21. The next invoice starts from the certified figures (not the claim) and its period overlaps nothing; a second draft is refused',
      I4.seq===4&&lc.prev_pay===Ic.lines.find(l=>l.no===cut.no).cert_cum&&I4.tot.gross_prev===Ic.tot.gross_cum&&I4.exc.some(e=>e.k==='dup')&&/already open/.test(await thr(()=>cibAct('inv_save',{pid,to:ASOF}))),{prev:lc.prev_pay,exc:I4.exc.map(e=>e.k)});
    await cibAct('inv_cancel',{pid,id:I4.id,note:'Test: duplicate period'});
    ok('22. Cancelling needs a reason; a cancelled invoice leaves the register and the chain',cibInvOf(pid).find(x=>x.id===I4.id).st==='Cancelled'&&!invOf(pid).some(r=>r.no===I4.ref));
    /* forecast */
    const fc=cibForecast(pid);
    ok('23. Forecast: monthly billing to the finish from P6 forecast dates and the rules, with retention, advance, VAT and the collection month; never above the contract',
      !!fc&&fc.rows.length>0&&fc.rows.every(r=>r.gross>=0&&r.coll>=r.m)&&fc.rows[fc.rows.length-1].cum<=val+1&&fc.rows.some(r=>r.adv>0),{n:fc&&fc.rows.length,last:fc&&fc.rows[fc.rows.length-1]});
    /* the Excel invoice */
    let blob=null,name='';window.saveFile=async(n,b)=>{name=n;blob=b};let sheets=[];try{await cibExcel(pid,Ic);const wb=new ExcelJS.Workbook();await wb.xlsx.load(await blob.arrayBuffer());sheets=wb.worksheets.map(w=>w.name)}catch(e){sheets=['ERR '+e.message]}window.saveFile=keepSave;
    ok('24. The Excel invoice: cover, summary, a breakdown sheet per component, retention, advance recovery, forecast, SAP upload, exceptions and review, audit',
      /client_invoice/.test(name)&&['Cover','Invoice summary','Retention','Advance recovery','Forecast','SAP upload','Exceptions & review','Audit'].every(n=>sheets.includes(n))&&sheets.some(n=>['Construction','Installation','Engineering','Material'].includes(n)),sheets);
    /* audit and permissions */
    const au=cibDB().audit.filter(a=>a.pid===pid),acts=new Set(au.map(a=>a.act));
    ok('25. Audit trail: who uploaded and approved the Schedule-C, changed the mapping, prepared, reviewed, approved, issued, certified, with before and after',
      ['Schedule-C uploaded','Schedule-C approved','Mapping read from P6','Mapping reviewed','Invoice prepared','Invoice recalculated','Invoice submitted','Invoice reviewed','Invoice approved','Invoice issued','Invoice certified','Invoice paid','Invoice history loaded'].every(a=>acts.has(a))
      &&au.some(a=>a.act==='Mapping read from P6'&&a.after&&a.before),[...acts]);
    as(FORE);const eFm=await thr(()=>cibAct('inv_save',{pid,to:ASOF}));as('U27');const eRo=await thr(()=>cibAct('inv_save',{pid,to:ASOF}));
    ok('26. Foremen never see billing; read-only people see but cannot prepare',/not open to you/.test(eFm)&&/prepare/.test(eRo),{eFm,eRo});
    /* every tab */
    as(SA);state.cib={pid,tab:'dash'};go('cib');let errs=[];for(const t of CIB_TABS.map(x=>x[0])){state.cib.tab=t;try{render();if(!document.querySelector('.cib'))errs.push(t)}catch(e){errs.push(t+': '+e.message)}}
    state.cib.tab='inv';state.cib.inv=Ic.id;try{render();if(!/Schedule-C breakdown/.test($('#view').innerText))errs.push('invoice')}catch(e){errs.push('invoice: '+e.message)}
    state.cib.tab='sch';state.cib.inv=null;state.cib.pid='QOT';state.cib.itemEd=QS.items.find(i=>i.leaf).no;try{render()}catch(e){errs.push('sch item: '+e.message)}
    ok('27. Every tab and an invoice draw without error',!errs.length,errs);
    DB.cib=JSON.parse(keepCib);
  }catch(e){ok('Unexpected error',false,e.stack||e.message)}
  finally{window.toast=keepToast;window.saveFile=keepSave;window.prompt=keepPrompt;
    try{if(KEYDATA!=null)localStorage.setItem(KEY,KEYDATA)}catch(x){}
    console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Client Invoice Builder: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
    window.__cibChecks=res;try{sessionStorage.setItem('cibChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500)}
})();
