/* ProTrackAI v3.49: Client Invoice Builder, the Schedule-C item from the WBS and the "Schedule C Invoicing" weight. Acceptance
   checks for the demo page: reading a P6 XER (the WBS field "Schedule C" inherited down the WBS, a child WBS with its own value,
   the activity code taking precedence, the code value rather than its description, the invoicing resource's budgeted units);
   the mapping rows and what is shown before saving; progress from the weighted activities only; the stored weight and source;
   the warning for a mapped item without the weight; the SAMPLE item of the demo; the mapping audit screen.
   How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this whole
   file. It saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';state.sector='ALL';SCOPE=scopeIds()},keepToast=toast,toasts=[],keepCib=JSON.stringify(DB.cib||null);
  const SA='U28',PLAN='U31',COST='U41';
  try{
    window.toast=m=>toasts.push(m);as(SA);
    ok('1. Version 3.49 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=49,APP_VERSION);
    /* a SAMPLE XER: Equipment > Main station > GIS (Schedule C on the WBS) > GIS bay (no value: inherits); GIB (its own value) > connectors (own value) */
    const tb=(name,f,rows)=>[`%T\t${name}`,`%F\t${f.join('\t')}`,...rows.map(r=>`%R\t${r.join('\t')}`)].join('\n');
    const T=a=>[a[0],'P1',a[1],a[0],a[2],'TK_Active','CP_Phys',a[3],'80','40','TT_Task','2026-06-08 08:00','2027-05-19 17:00'];
    const xer=['ERMHDR\t19.12',
      tb('PROJECT',['proj_id','proj_short_name','last_recalc_date'],[['P1','SAMPLE-308','2026-10-31 00:00']]),
      tb('PROJWBS',['wbs_id','proj_id','parent_wbs_id','proj_node_flag','wbs_short_name','wbs_name'],[['W0','P1','','Y','SAMPLE','SAMPLE'],['W1','P1','W0','N','EM','Equipment & Materials'],['W2','P1','W1','N','EM.1','Main Station'],
        ['W3','P1','W2','N','GIS','110kV GIS'],['W4','P1','W3','N','GIS-2','110kV GIS bay'],['W5','P1','W2','N','GIB','110kV GIB'],['W6','P1','W5','N','GIB-C','110kV GIB connectors'],['W7','P1','W2','N','TR','Power transformers']]),
      tb('TASK',['task_id','proj_id','wbs_id','task_code','task_name','status_code','complete_pct_type','phys_complete_pct','target_drtn_hr_cnt','remain_drtn_hr_cnt','task_type','target_start_date','target_end_date'],
        [['T1','W4','PR Issuance [GIS]','100'],['T2','W4','Manufacturing [GIS]','60'],['T3','W4','Delivery [GIS]','0'],['T4','W4','Material inspection at site [GIS]','0'],['T5','W5','Delivery [GIB]','50'],['T6','W6','Delivery [GIB connectors]','25'],
         ['T7','W5','Inspection [GIB]','30'],['T8','W7','Transformer inspection','10'],['T9','W1','General procurement','40']].map(T)),
      tb('UDFTYPE',['udf_type_id','table_name','udf_type_name','udf_type_label','logical_data_type'],[['U1','PROJWBS','user_field_1','SCHEDULE C','FT_TEXT'],['U2','TASK','user_field_2','Remarks','FT_TEXT']]),
      tb('UDFVALUE',['udf_type_id','fk_id','proj_id','udf_text'],[['U1','W3','P1','A.SS.3.1.1.1.1.1'],['U1','W5','P1','A.SS.3.1.2.1.1'],['U1','W6','P1','A.SS.3.1.2.2.1.2'],['U2','T1','P1','not a WBS field']]),
      tb('ACTVTYPE',['actv_code_type_id','actv_code_type'],[['C1','Schedule C'],['C2','Discipline']]),
      tb('ACTVCODE',['actv_code_id','actv_code_type_id','short_name','actv_code_name'],[['V1','C1','A.SS.3.1.9','Power transformers supply'],['V2','C2','EL','Electrical']]),
      tb('TASKACTV',['task_id','actv_code_type_id','actv_code_id'],[['T8','C1','V1'],['T1','C2','V2']]),
      tb('RSRC',['rsrc_id','rsrc_short_name','rsrc_name','rsrc_type','unit_id'],[['R1','PE-308-INT','INTERNAL WEIGHTAGE','RT_Equip',''],['R2','PE-308 SCH','Schedule C Invoicing','RT_Equip',''],['R3','PE-308-SEC','SEC weightage','RT_Equip','']]),
      tb('TASKRSRC',['task_id','rsrc_id','target_qty'],[['T1','R1','100'],['T2','R1','300'],['T4','R1','50'],['T4','R2','5427901'],['T4','R3','288500'],['T5','R2','1000'],['T7','R2','3000'],['T9','R2','700']]),
      '%E'].join('\n');
    const P=parseSchedXER(xer),row=id=>P.rows.find(r=>r.id===id);
    ok('2. The XER: the WBS field "SCHEDULE C" is found (an activity user field is not); the invoicing resource is found by its name, the internal and SEC weightages are not',
      P.wbsFields.join()==='SCHEDULE C'&&P.invRes.map(x=>x.name).join()==='Schedule C Invoicing'&&P.invRes[0].total===5427901+1000+3000+700,{wf:P.wbsFields,res:P.invRes});
    ok('3. The WBS value is inherited down: the GIS bay activities take A.SS.3.1.1.1.1.1 from the GIS WBS above; the connectors keep their own WBS value; an activity under a WBS with no value above it has none',
      row('T1').wf['SCHEDULE C']==='A.SS.3.1.1.1.1.1'&&row('T4').wf['SCHEDULE C']==='A.SS.3.1.1.1.1.1'&&row('T5').wf['SCHEDULE C']==='A.SS.3.1.2.1.1'&&row('T6').wf['SCHEDULE C']==='A.SS.3.1.2.2.1.2'&&!row('T8').wf['SCHEDULE C']&&!row('T9').wf['SCHEDULE C'],P.rows.map(r=>[r.id,r.wf]));
    ok('4. The invoicing weight per activity is the budgeted units of "Schedule C Invoicing" only',row('T4').iw['Schedule C Invoicing']===5427901&&!row('T1').iw['Schedule C Invoicing']&&row('T7').iw['Schedule C Invoicing']===3000,P.rows.map(r=>[r.id,r.iw]));
    const o=cibSrcOf(P),m=cibMapRows(P,o),mr=id=>m.find(x=>x.act===id);
    ok('5. The source is chosen by itself: the WBS field, the activity code and the resource',o.wf==='SCHEDULE C'&&o.ct==='Schedule C'&&o.res==='Schedule C Invoicing',o);
    ok('6. The mapping rows: from the WBS for the GIS and GIB activities; the activity code (its value, not its description) for the transformer inspection; the weight where the resource is assigned; nothing for an activity without an item',
      mr('T1').item==='A.SS.3.1.1.1.1.1'&&mr('T1').via==='wbs'&&mr('T1').w===null&&mr('T4').w===5427901&&mr('T8').item==='A.SS.3.1.9'&&mr('T8').via==='code'&&!mr('T9')&&m.length===8,m);
    const L=cibLooseW(P,o);ok('7. An activity with the invoicing weight but no item is pointed out',L.length===1&&L[0].id==='T9',L.map(r=>r.id));
    ok('8. Older files: an activity code alone still works (a text type name as before)',cibMapRows(P,'Schedule C').length===1&&cibMapRows(P,{wf:'SCHEDULE C'}).length===7);
    /* the SAMPLE item of the demo: every activity of the ACSR conductor drums package mapped from the WBS, the delivery alone weighted */
    const QS=cibAppr('QOT'),it=QS.items.find(i=>i.no==='S.3.2'),X=cibCtx('QOT',null,ASOF),A=X.byItem['S.3.2']||[],dl=A.find(a=>/delivery/i.test(a.name)),g=cibProg('QOT',QS,it,X);
    const all=A.reduce((t,a)=>t+(+a.pct||0),0)/(A.length||1)/100;
    ok('9. Demo: S.3.2 (SAMPLE) earns on the delivery activity only, not on PR, PO, manufacturing or shipment',!!it&&/SAMPLE/.test(it.desc)&&A.length===9&&!!dl&&g.iw&&g.n===1&&g.nx===8&&Math.abs(g.p-dl.pct/100)<1e-9&&g.p<all,{p:g.p,all,dl:dl&&dl.pct,n:g.n});
    const QA=cibAudit('QOT');ok('10. Demo: the price schedule still adds up to the contract value; two items missing and one unknown code as before; no mapped item without the weight',
      Math.abs(cibBill(QS).reduce((t,i)=>t+i.value,0)-QS.head.value)<1&&QA.miss.length===2&&QA.unknown.length===1&&QA.useW&&!QA.noW.length,{miss:QA.miss.length,unk:QA.unknown.length,noW:QA.noW.map(x=>x.i.no)});
    const C0=cibCompute('QOT',{to:X.U.data_date,seq:99,sch:QS.id,prev:null}),l2=C0.lines.find(l=>l.no==='S.3.2');
    ok('11. Demo: the invoice line says it is invoicing-weighted, from one activity',l2.iw===true&&l2.acts===1&&Math.abs(l2.prog-g.p)<1e-6,l2);
    /* the store */
    as((teamOf('QOT','plan')[0]||{}).id||PLAN);const MP=cibMapOf('QOT'),pk=A.map(a=>({act:a.id,name:a.name,item:'S.3.2',src:'p6',via:'wbs',w:MP[a.id].w}));
    const r0=await cibAct('map_save',{pid:'QOT',rows:pk});const r1=await cibAct('map_save',{pid:'QOT',rows:pk.map(x=>x.act===dl.id?{...x,w:x.w*2}:x)});
    const r2=await cibAct('map_save',{pid:'QOT',rows:[{act:A[0].id,item:'S.3.2',src:'manual',w:500,via:'wbs'}]});
    ok('12. The mapping store: the same rows change nothing; a new weight is a change; a mapping by hand carries no weight and no P6 source',
      r0.changed===0&&r1.changed===1&&cibMapOf('QOT')[dl.id].w===pk.find(x=>x.act===dl.id).w*2&&r2.changed===1&&cibMapOf('QOT')[A[0].id].w===null&&cibMapOf('QOT')[A[0].id].src==='manual',{r0,r1,r2});
    /* the warning: an item mapped without the weight in a project that uses it */
    const one=QA.rows.find(x=>x.st==='Mapped'&&x.rule.t==='pct'&&x.i.no!=='S.3.2'),acts1=X.byItem[one.i.no]||[];acts1.forEach(a=>{cibMapOf('QOT')[a.id].w=null});
    const QA2=cibAudit('QOT'),C1=cibCompute('QOT',{to:X.U.data_date,seq:99,sch:QS.id,prev:null}),E=cibExc('QOT',{id:'TEST',seq:99,from:addDays(X.U.data_date,-30),to:X.U.data_date},C1);
    ok('13. A mapped item without the invoicing weight is named in the audit and warned on the invoice (not blocking); its progress uses the schedule weight',
      QA2.noW.length===1&&QA2.noW[0].i.no===one.i.no&&E.some(e=>e.k==='weight'&&e.sev==='warn'&&e.items.includes(one.i.no))&&C1.lines.find(l=>l.no===one.i.no).iw===false,{noW:QA2.noW.map(x=>x.i.no),E:E.filter(e=>e.k==='weight')});
    /* the screen */
    as(SA);state.cib={pid:'QOT',tab:'map',mapOpen:'S.3.2',px:{pid:'QOT',file:'SAMPLE.xer',parsed:P,...o}};go('cib');const v=$('#view').innerText;
    ok('14. The mapping audit: the three choices for the XER, what will be read, the invoicing weight of each activity and the activities not invoiced on',
      !!document.querySelector('[data-cibxwf]')&&!!document.querySelector('[data-cibxtype]')&&!!document.querySelector('[data-cibxres]')&&/7 from the WBS/.test(v)&&/carry the invoicing weight but no item|carries the invoicing weight but no item/.test(v)&&/Invoicing weight/.test(v)&&/not invoiced on/.test(v)&&/P6 WBS/.test(v),v.slice(0,300));
    state.cib.mapOpen=null;state.cib.px=null;
  }catch(e){ok('Unexpected error',false,e.stack||e.message)}
  finally{window.toast=keepToast;try{DB.cib=JSON.parse(keepCib)}catch(x){}
    try{if(KEYDATA!=null)localStorage.setItem(KEY,KEYDATA)}catch(x){}
    console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Client Invoice Builder, WBS and invoicing weight: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
    window.__cibwChecks=res;try{sessionStorage.setItem('cibwChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500)}
})();
