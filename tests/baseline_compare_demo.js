/* ProTrackAI v3.14, actual progress against the chosen baselines in internal and client reports: acceptance checks for the
   demo page. How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28),
   open the browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end,
   then reloads the page. It prints one line per check and a total. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms));
  try{
    const per=curMonth(),end=periodEnd(per,'month'),P='QOT',base={project_id:P,kind:'planning',period_type:'month',period:per};
    ok('Sample: revised and recovery baselines and the schedule\'s own baseline are there to compare',!!bsetOf(P,'REV')&&!!bsetOf(P,'REC')&&(schedRowsOf(schedAt(P,end))||[]).some(r=>r.xbs&&r.xbf));
    const L=blCompare(P,'month',per,['ORG','REV','REC','SCH'],'internal',40,null),pg=progOf(P,end);
    ok('Original baseline planned = the report headline (internal weightage)',Math.abs(L[0].plan-pg.plan*100)<0.01,{bl:L[0].plan,head:pg.plan*100});
    const sc=schedAt(P,end,'client').summary,LC=blCompare(P,'month',per,['ORG'],'client',40,null);
    ok('Client weightage: original baseline planned = the client headline',Math.abs(LC[0].plan-sc.client_plan)<0.01);
    const u=schedAt(P,end),rows=schedRowsOf(u),b=bsetOf(P,'REV'),R=rows.map(r=>{const x=b.rows[r.id];return x?{...r,bs:x.bs,bf:x.bf}:r}),exp=schedSummary(R,u.data_date,u.weightage,u.weights).int_plan;
    ok('Revised baseline planned = the same activities and weights with the revised dates',Math.abs(L[1].plan-exp)<0.01,{got:L[1].plan,exp});
    ok('Variance = actual − planned and SPI = actual ÷ planned, for every baseline',L.every(x=>Math.abs(x.var-(40-x.plan))<0.011&&Math.abs(x.spi-40/x.plan)<0.001));
    ok('A later revised baseline plans less progress by now than the original',L[1].plan<L[0].plan);
    const av=blAvail('RMX','month',per,'internal');ok('A project without those baselines or a schedule shows why they are off',/not loaded/.test(av.REV)&&/no updated schedule/.test(av.SCH));
    const ev=blCompare('RMX','month',per,['ORG'],'internal',40,null)[0];ok('Without an updated schedule the earned-value plan is used and says so',ev&&/earned value/.test(ev.basis)&&ev.plan!=null);
    ok('Choosing nothing is refused',/at least one baseline/.test((()=>{try{blSelOk(P,'month',per,[],'internal');return ''}catch(e){return e.message}})()));
    // the screen and saving
    const pl=teamOf(P,'plan')[0];if(relOpen(P,'planning','month',per)?.status==='Submitted'){as('U28');await relAct({...base,action:'return',note:'test'})}
    as(pl.id);openRelease(P,'planning','month',per);await wait(500);const c=$('#blCard');
    ok('The internal report shows four baseline check boxes, the original ticked',c&&c.querySelectorAll('[data-blsel]').length===4&&[...c.querySelectorAll('[data-blsel]:checked')].map(x=>x.value).join()==='ORG');
    ['REV','SCH'].forEach(k=>{const el=c.querySelector(`[data-blsel][value=${k}]`);el.checked=true;el.dispatchEvent(new Event('change',{bubbles:true}))});await wait(100);
    ok('Ticking a baseline adds its row at once',$('#blTable').querySelectorAll('tbody tr').length===3);
    $('#relForm').querySelectorAll('[name^="r_"]').forEach(x=>{x.value='Checked'});document.querySelector('[data-reldo="save"]').click();await wait(800);
    const d=relOpen(P,'planning','month',per);ok('Saving keeps the choice and the figures with the report',d&&d.figures.bl_sel.join()==='ORG,REV,SCH'&&d.figures.bl_cmp.length===3,d&&d.figures.bl_sel);
    await relAct({...base,action:'submit',note:''});as('U28');const ap=await relAct({...base,action:'approve',note:'',validated:true,validation_note:'checked'});
    const fr=JSON.stringify(ap.figures.bl_cmp);DB.baselines[P].REV.rows=Object.fromEntries(Object.entries(DB.baselines[P].REV.rows).map(([k,v])=>[k,{...v,bs:addDays(v.bs,-30)}]));
    openRelease(P,'planning','month',per);await wait(400);
    ok('An approved report keeps its comparison frozen, check boxes locked',JSON.stringify(relReleased(P,'planning','month',per).figures.bl_cmp)===fr&&/As saved when this report was approved/.test($('#blCard').innerText)&&[...$('#blCard').querySelectorAll('[data-blsel]')].every(x=>x.disabled));
    closeDrawer();as(pl.id);state.clTab='overview';openRelease(P,'client','month',per);await wait(500);
    ok('The client report has the same check boxes, on client weightage',$('#blCard')&&$('#blCard').dataset.wt==='client');
    // the XER: a schedule exported with its baseline project
    const T=(n,f,rows)=>`%T\t${n}\n%F\t${f.join('\t')}\n`+rows.map(r=>`%R\t${r.join('\t')}`).join('\n')+'\n';
    const xer=T('PROJECT',['proj_id','proj_short_name','orig_proj_id','sum_base_proj_id','last_recalc_date'],[['1','CUR','','2','2026-09-20 00:00'],['2','CUR-BL1','1','','2026-01-01 00:00']])
      +T('TASK',['task_id','proj_id','task_code','task_name','target_start_date','target_end_date','status_code','complete_pct_type','phys_complete_pct','task_type'],[['10','1','A100','Pour','2026-05-01 08:00','2026-06-30 17:00','TK_Active','CP_Phys','40','TT_Task'],['20','2','A100','Pour','2026-04-01 08:00','2026-05-31 17:00','TK_NotStart','CP_Phys','0','TT_Task']]);
    const px=parseSchedXER(xer);
    ok('XER with a baseline project: only the schedule\'s activities are read, with the baseline\'s dates kept apart',px.rows.length===1&&px.rows[0].bs==='2026-05-01'&&px.rows[0].xbs==='2026-04-01'&&px.rows[0].xbf==='2026-05-31'&&/baseline project CUR-BL1/.test(px.blSrc),px.rows);
    const px2=parseSchedXER(T('PROJECT',['proj_id','proj_short_name'],[['1','CUR']])+T('TASK',['task_id','proj_id','task_code','task_name','target_start_date','target_end_date','status_code','complete_pct_type','phys_complete_pct','task_type'],[['10','1','A100','Pour','2026-05-01 08:00','2026-06-30 17:00','TK_Active','CP_Phys','40','TT_Task']]));
    ok('XER without a baseline project: the schedule\'s planned dates, said so',px2.rows[0].xbs==='2026-05-01'&&/no baseline project/.test(px2.blSrc));
    // the cost reports tab
    closeDrawer();as('U28');state.navSec='planning';go('rel');await wait(200);
    ok('Internal reporting no longer has the Monthly cost reports tab',![...document.querySelectorAll('[data-reltab]')].some(b=>b.dataset.reltab==='cost')&&[...document.querySelectorAll('[data-reltab]')].length===2);
    state.navSec='cost';go('rel');await wait(200);
    ok('Cost Control → Monthly cost report still opens the cost reports',/Monthly cost reports/.test($('#view .card-head h2').textContent)&&state.relTab==='cost');
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Baselines in reports: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__blChecks=res;try{sessionStorage.setItem('blChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
