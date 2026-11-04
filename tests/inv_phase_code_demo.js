/* ProTrackAI v3.57: the invoicing phase from a P6 activity code. Acceptance checks for the demo page: reading the activity codes
   of a baseline XER, the code named for invoicing chosen by default, a phase suggested for each value and changed by hand,
   the phase kept on each activity and used by the invoiceable calculation over the WBS wording, values without a phase left to
   the WBS wording, the project's choice kept for the next import, a changed mapping not taken as the same file, going back to
   the WBS wording, and the note on Invoicing status by phase.
   How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this whole
   file. It saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const keepToast=toast,toasts=[];
  try{
    window.toast=m=>toasts.push(m);state.uid='U28';state.role='sa';state.scope='ALL';SCOPE=scopeIds();
    ok('1. Version 3.57 or later',+APP_VERSION.split('.')[1]>=57,APP_VERSION);
    /* a SAMPLE XER: four activities under a construction WBS, each with an "Invoice Phase" code value, and a Discipline code */
    const tb=(name,f,rows)=>[`%T\t${name}`,`%F\t${f.join('\t')}`,...rows.map(r=>`%R\t${r.join('\t')}`)].join('\n');
    const T=a=>[a[0],'P1','W2',a[1],a[2],'TK_NotStart','CP_Phys','0','80','80','TT_Task','2026-10-01 08:00','2027-03-31 17:00'];
    const xer=['ERMHDR\t19.12',
      tb('PROJECT',['proj_id','proj_short_name','last_recalc_date'],[['P1','SAMPLE-IPH','2026-09-22 00:00']]),
      tb('PROJWBS',['wbs_id','proj_id','parent_wbs_id','proj_node_flag','wbs_short_name','wbs_name'],[['W0','P1','','Y','SAMPLE','SAMPLE'],['W1','P1','W0','N','CON','Construction Works'],['W2','P1','W1','N','CON.1','Substation Area']]),
      tb('TASK',['task_id','proj_id','wbs_id','task_code','task_name','status_code','complete_pct_type','phys_complete_pct','target_drtn_hr_cnt','remain_drtn_hr_cnt','task_type','target_start_date','target_end_date'],
        [['T1','IPH-1010','Foundation layout package'],['T2','IPH-1020','Transformer foundation'],['T3','IPH-1030','Protection panel checks'],['T4','IPH-1040','Cable trench works'],['T5','IPH-1050','Fencing']].map(T)),
      tb('ACTVTYPE',['actv_code_type_id','actv_code_type'],[['C1','Discipline'],['C2','Invoice Phase']]),
      tb('ACTVCODE',['actv_code_id','actv_code_type_id','short_name','actv_code_name'],[['V1','C2','ENG','Engineering design'],['V2','C2','SUP','Equipment supply'],['V3','C2','TC','Testing and commissioning'],['V4','C2','OTH','Other works'],['V9','C1','EL','Electrical']]),
      tb('TASKACTV',['task_id','actv_code_type_id','actv_code_id'],[['T1','C2','V1'],['T2','C2','V2'],['T3','C2','V3'],['T4','C2','V4'],['T1','C1','V9']]),
      tb('RSRC',['rsrc_id','rsrc_short_name','rsrc_name','rsrc_type','unit_id'],[['R1','PW','Price Weight','RT_Equip',''],['R2','LAB','Labour','RT_Labor','']]),
      tb('TASKRSRC',['task_id','rsrc_id','target_qty'],[['T1','R1','100'],['T2','R1','400'],['T3','R1','200'],['T4','R1','300'],['T5','R1','50'],['T1','R2','40'],['T2','R2','120'],['T3','R2','60'],['T4','R2','90'],['T5','R2','20']])].join('\n');
    const P='RMX',file=n=>new File([xer],n||'SAMPLE-IPH.xer');
    state.impPid=P;document.body.insertAdjacentHTML('beforeend','<div id="impBox" hidden></div>');
    await handleImportFile(file());let I=state.imp;
    ok('2. The baseline import reads the activity codes and picks the code named for invoicing',I&&(I.codeTypes||[]).join()==='Discipline,Invoice Phase'&&I.ipCode==='Invoice Phase',I&&{ct:I.codeTypes,ip:I.ipCode});
    let rows=mapRows(),R=id=>rows.find(r=>r.id===id)||{};
    ok('3. A phase is suggested for each value from its name',R('IPH-1010').iph==='ENG'&&R('IPH-1020').iph==='PRC'&&R('IPH-1030').iph==='TC'&&R('IPH-1040').iph===null&&R('IPH-1050').iph===null,rows.map(r=>[r.id,r.ipv,r.iph]));
    const h=$('#impBox').innerHTML;
    ok('4. The preview shows the code, each value with its activities and price weight, and the phase to pick',/Invoicing phase taken from/.test(h)&&/Activity code: Invoice Phase/.test(h)&&/data-impip="Equipment supply"/.test(h)&&/no value for this code/.test(h));
    I.ipMap['Other works']='CON';rows=mapRows();
    ok('5. A value is given its phase by hand; an activity without a value follows the WBS wording',R('IPH-1040').iph==='CON'&&R('IPH-1050').iph===null);
    await runImport();
    const A=id=>ACTS.find(a=>a.p===P&&a.id===id)||{};
    ok('6. The imported activities keep their invoicing phase',A('IPH-1010').iph==='ENG'&&A('IPH-1020').iph==='PRC'&&A('IPH-1030').iph==='TC'&&A('IPH-1040').iph==='CON'&&!A('IPH-1050').iph,[A('IPH-1010').iph,A('IPH-1020').iph,A('IPH-1030').iph,A('IPH-1040').iph,A('IPH-1050').iph]);
    ok('7. The invoiceable calculation uses it over the WBS wording ("Transformer foundation" under construction is invoiced as supply)',phaseOf(A('IPH-1020'))==='PRC'&&phaseOf(A('IPH-1010'))==='ENG'&&phaseOf(A('IPH-1030'))==='TC'&&phaseOf(A('IPH-1050'))==='CON');
    const ip=(DB.invPhase||{})[P];
    ok('8. The project keeps the code and the phase of each value',ip&&ip.code_type==='Invoice Phase'&&ip.map['Equipment supply']==='PRC'&&ip.map['Other works']==='CON',ip);
    const pv=phaseValues(P),raw=k=>ACTS.filter(a=>a.p===P&&phaseOf(a)===k).reduce((t,a)=>t+priceOf(a),0);
    ok('9. The phase prices follow it',PHASES.every(([k])=>Math.abs(pv.raw[k]-raw(k))<0.01),PHASES.map(([k])=>[k,pv.raw[k]]));
    /* the next import of a revised baseline: the earlier choice and map come back; a changed mapping is a new import */
    await handleImportFile(file('SAMPLE-IPH-rev1.xer'));I=state.imp;rows=mapRows();
    ok('10. The next import starts from the project\'s code and map',I.ipCode==='Invoice Phase'&&R('IPH-1040').iph==='CON');
    I.ipMap['Equipment supply']='CON';toasts.length=0;await runImport();
    ok('11. The same file with a changed mapping is imported (not taken as the same content)',A('IPH-1020').iph==='CON'&&!toasts.some(t=>/same content/i.test(t)),toasts);
    await handleImportFile(file('SAMPLE-IPH-rev2.xer'));I=state.imp;I.ipCode='';renderImport();rows=mapRows();
    ok('12. Choosing the WBS wording shows no mapping and gives no phase',/The WBS wording/.test($('#impBox').innerHTML)&&!/data-impip=/.test($('#impBox').innerHTML)&&rows.every(r=>r.iph===null));
    await runImport();
    ok('13. ... and once imported the activities go back to the WBS wording, and the project choice is removed',['IPH-1010','IPH-1020','IPH-1030','IPH-1040'].every(id=>!A(id).iph)&&!(DB.invPhase||{})[P]&&phaseOf(A('IPH-1020'))==='CON');
    /* an Excel baseline has no activity codes: nothing to choose */
    state.imp={rows:[{id:'X1',name:'x',path:['A'],bh:10,bs:'2026-10-01',bf:'2026-10-02'}],file:'x.xlsx',kind:'Excel / CSV',lvl:1,maxLvl:1,minBH:0,limit:10,skipDone:true,defDisc:'Civil',lvlCls:1,wres:'',brLvl:1,branches:null,clsOn:{CON:true,ENG:true,PRC:true}};
    ok('14. A baseline without activity codes (Excel) offers no invoicing code',impIphHTML(state.imp,mapRows())==='');state.imp=null;
    /* the page */
    DB.invPhase=DB.invPhase||{};DB.invPhase[P]={code_type:'Invoice Phase',map:{}};const x=ACTS.find(a=>a.p===P&&a.id==='IPH-1010');x.iph='ENG';
    ok('15. Invoicing status by phase says where the phases come from',/the P6 activity code “Invoice Phase” \(1 activity\)/.test(invPhaseHTML(P)),invPhaseHTML(P).slice(0,600));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.toast=keepToast;document.querySelector('#impBox[hidden]')?.remove();try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Invoicing phase from an activity code: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__ipChecks=res;try{sessionStorage.setItem('ipChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
