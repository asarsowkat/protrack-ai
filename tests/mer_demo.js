/* ProTrackAI v3.41, Cost Control -> Cost plan and MER – Monthly Executive Report, and the Areas of concern of the monthly internal
   report. Acceptance checks for the demo page. How to run: open demo.html, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then reloads. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms)),keep=saveFile,near=(a,b,e)=>a!=null&&b!=null&&Math.abs(a-b)<=(e||1e-6);
  const toasts=[],keepToast=toast;
  try{
    const sa=me().id,y=+ym(ASOF).slice(0,4),pid='RMX',co=teamOf(pid,'costing')[0],coOther=DB.master.users.find(u=>u.role==='costing'&&u.active!==false&&!onProject(u,pid)),
      pmU=DB.master.users.find(u=>u.role==='pm'&&u.active!==false&&onProject(u,pid)),hd=pccHeads()[0],fm=DB.master.users.find(u=>u.role==='foreman'&&u.active!==false),eng=DB.master.users.find(u=>u.role==='eng'&&u.active!==false);
    // 1-3: version, menu and who sees the screens
    ok('1. Version 3.41 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=41,APP_VERSION);
    const cost=DOMAINS.find(g=>g.k==='cost'),its=cost?cost.items.map(i=>i.v):[];
    ok('2. Cost Control lists Cost plan and MER – Monthly Executive Report, after the monthly cost report',its.indexOf('cplan')===its.indexOf('rel')+1&&its.indexOf('mer')===its.indexOf('rel')+2&&SCREENS.includes('cplan')&&SCREENS.includes('mer'),its);
    const sees={};[['costing',co],['pm',pmU],['head',hd],['foreman',fm],['eng',eng]].forEach(([k,u])=>{if(!u)return;as(u.id);sees[k]=navDefault('mer')&&navDefault('cplan')});as(sa);
    ok('3. Those who see cost figures open them; the foreman and the site engineer do not',sees.costing&&sees.pm&&sees.head&&!sees.foreman&&!sees.eng,sees);
    // 4: sample plans, labelled
    const S=(DB.costPlans||[]).filter(c=>c.sample);
    ok('4. The demo has SAMPLE cost plans for this year, labelled sample',S.length>=3&&S.every(c=>c.year===y&&/SAMPLE/.test(c.fin.ref)&&/SAMPLE/.test(c.hist[0].note)),S.length);
    // 5-6: the server's checks, and who keeps the plan
    ok('5. The checks: a budget is needed, the finance target is 0–100 %, the twelve months are numbers',
      /budget/.test(cpCheck('int',{budget:0,months:Array(12).fill(1)}))&&/target POC/.test(cpCheck('fin',{target:120,months:Array(12).fill(1)}))&&/Mar/.test(cpCheck('fin',{target:50,months:[1,1,'x',...Array(9).fill(1)]}))&&cpCheck('int',{budget:100,months:Array(12).fill(null)})===null);
    window.toast=m=>toasts.push(m);
    as(coOther.id);const okOther=await cpSave(pid,y,'int',{budget:1e6,cv:2e6,months:Array(12).fill(1e4)});as(sa);
    ok('6. A costing engineer who is not on the project cannot keep its cost plan',!okOther&&/costing engineer of the project/.test(toasts.pop()||''),coOther&&coOther.id);
    // 7-9: the costing engineer saves, the PM agrees, a change returns it to draft; the head approves the finance plan
    as(co.id);const m=[1e5,2e5,3e5,4e5,5e5,6e5,7e5,8e5,9e5,1e6,1.1e6,1.2e6],bud=crBud(merRel(pid,'cost',`${y}-12`).figures);
    const sv=await cpSave(pid,y,'int',{budget:bud,cv:2*bud,months:m},'test');let c=cpOf(pid,y);
    ok('7. The costing engineer saves the internal plan: back to draft, kept in the history',sv&&c.int.status==='Draft'&&c.int.saved_by===co.id&&c.hist.slice(-1)[0].action==='Saved',c.int.status);
    const agreeCo=canCpAgree(pid);as(pmU.id);const ag=await cpAct(pid,y,'agree');c=cpOf(pid,y);as(co.id);await cpSave(pid,y,'int',{budget:bud,cv:2*bud,months:m});const back=cpOf(pid,y).int.status;
    ok('8. Only the project manager marks it agreed; changing it afterwards returns it to draft',!agreeCo&&ag&&back==='Draft'&&cpOf(pid,y).hist.some(h=>/Back to draft/.test(h.action))&&cpOf(pid,y).hist.some(h=>h.action==='Agreed with the project manager'),{agreeCo,ag,back});
    as(pmU.id);await cpAct(pid,y,'agree');
    as(co.id);const fm12=[2,2,2,2,2,2,2,2,2,2,2,2],base=merBase(pid,y);await cpSave(pid,y,'fin',{target:+(base.poc+24).toFixed(2),ref:'Test approval',months:fm12});
    const appCo=canCpApprove();as(hd.id);const ap=await cpAct(pid,y,'approve');c=cpOf(pid,y);as(sa);
    ok('9. Only the head of planning and cost control (or an executive) approves the finance plan',!appCo&&ap&&c.fin.status==='Approved'&&c.fin.approved_by===hd.id,{appCo,ap});
    // 10-13: the MER figures of the project
    const per=merDefaultPer(),mi=+per.slice(5,7),r=merProject(projById(pid),per,'int'),f=merRel(pid,'cost',per).figures;
    ok('10. Cumulative actual POC = (actual − stock) ÷ current budget, from the released cost report',near(r.poc,(crN(f.actual)-crStock(f))/crBud(f)*100),{poc:r.poc});
    ok('11. KPI 2 (internal): planned POC this year to the cut-off = Σ planned cost ÷ budget; actual = POC − POC at the end of last year; variance on the budget',
      near(r.t_plan,cpSum(m.slice(0,mi))/bud*100)&&near(r.t_act,r.poc-base.poc)&&near(r.t_var,(r.t_act-r.t_plan)/100*r.budget,1),{t:r.t_plan,u:r.t_act});
    const rf=merProject(projById(pid),per,'fin');
    ok('12. KPI 2 and 3 (finance): the finance plan; the year target and its check (target − end of last year − planned)',near(rf.t_plan,2*mi)&&near(rf.x_plan,24)&&near(rf.year_target,24,1e-4)&&near(rf.fin_check,0,1e-4),{t:rf.t_plan,x:rf.x_plan,yt:rf.year_target});
    ok('13. KPI 3: the year-end forecast = actual this year + the forecast of the months after the cut-off',near(r.y_fc,r.t_act+cpSum(r.fc.slice(mi))),{y:r.y_fc});
    const cont=crHead(f,'CONT'),sm=crHead(f,'SM'),pf=merRel(pid,'planning',per).figures;
    ok('14. Gross profit %, contingency and site management earned value from the WBS heads',near(r.gp_cur,(1-r.budget/r.cv)*100)&&(!cont||near(r.cont_ut,crN(cont.budget)-crN(cont.rev0)))&&(!sm||near(r.sm_ev,pf.actual_pct/100*crN(sm.budget))),{gp:r.gp_cur,cont:!!cont,sm:!!sm});
    const st={per,basis:'int',reg:'ALL',sec:'ALL'},D=merData(st),wb=D.rows.filter(x=>x.poc!=null&&x.budget),wpoc=wb.reduce((t,x)=>t+x.poc*x.budget,0)/wb.reduce((t,x)=>t+x.budget,0);
    ok('15. Portfolio and region rows: amounts summed, POC weighted by budget',near(D.all.poc,wpoc,1e-6)&&near(D.all.cv,D.rows.reduce((t,x)=>t+(x.cv||0),0),1)&&D.regs.length>0,{poc:D.all.poc});
    // 16: the stock value on the cost report
    let neg='';try{crCompute(pid,per,Object.assign({},f,{stock_value:-5}))}catch(e){neg=e.message}
    const saved=f.stock_value;f.stock_value=Math.round(crN(f.actual)*0.1);const r2=merProject(projById(pid),per,'int');f.stock_value=saved;
    ok('16. The cost report takes an actual stock value (not negative); the MER takes it out of the POC',/stock value cannot be negative/.test(neg)&&r2.poc<r.poc&&/h_stock_value/.test(crFormHTML(pid,per,f,true)),{neg});
    // 17-20: areas of concern in the monthly internal report
    const curM=ym(ASOF);state.rdTab='aoc';openPlanRelease(pid,'month',curM);await wait(150);let F=$('#relForm');const prevRel=relPrevOf(pid,'month',curM);
    const tabs=[...document.querySelectorAll('#sheet [data-rdtab]')].map(b=>b.dataset.rdtab);
    ok('17. The monthly internal report has an Areas of concern tab: five areas, three rows each (concern, action by, action needed)',tabs.includes('aoc')&&F.querySelectorAll('[name^="ac_"]').length===AOC.length*AOC_N*3,tabs);
    const pc=prevRel&&prevRel.narrative.concerns,first=AOC.map(([k])=>k).find(k=>pc&&pc[k]&&pc[k].length);
    ok('18. A new month starts from last month\'s released concerns',!!first&&F.elements[`ac_${first}_0_c`].value===pc[first][0].c,first);
    DB.issues=DB.issues||[];DB.issues.push({id:'T-MER',issue_no:'T-MER-1',project_id:pid,status:'Open',issue_type:'FAT Test',impact:'High',description:'Test: FAT of the RMUs failed',action_by:'Vendor QA',action_required:'Repeat the FAT'});
    $('[data-aocfill]').click();await wait(50);const procV=[0,1,2].map(i=>F.elements[`ac_proc_${i}_c`].value);
    ok('19. Fill from the issue register puts open issues into the empty rows of their area only',procV.includes('Test: FAT of the RMUs failed')&&(!pc.proc||!pc.proc[0]||procV[0]===pc.proc[0].c),procV);
    const N=relFormPayload().narrative.concerns;
    ok('20. The concerns are saved with the report (narrative.concerns), by area',Array.isArray(N.proc)&&N.proc.some(x=>x.c==='Test: FAT of the RMUs failed'&&x.by==='Vendor QA'&&x.act==='Repeat the FAT'),N.proc);
    DB.issues=DB.issues.filter(i=>i.id!=='T-MER');
    state.rdTab='aoc';openPlanRelease(pid,'week',recentWeeks(2)[1]);await wait(100);
    ok('21. A weekly report has no Areas of concern tab',![...document.querySelectorAll('#sheet [data-rdtab]')].some(b=>b.dataset.rdtab==='aoc'));{const x=document.querySelector('#sheet [data-close]');if(x)x.click()}
    // 22-24: the screens and the workbook
    go('mer');Object.assign(merState(),{per,basis:'int',tab:'cost',reg:'ALL',sec:'ALL'});render();await wait(100);const tC=$('#view').innerText;
    merState().tab='dash';render();await wait(50);const tD=$('#view').innerText;merState().tab='proj';merState().pid=pid;render();await wait(50);const tP=$('#view').innerText;
    ok('22. The MER shows Cost (I), Dashboard and Project wise, with the six KPIs, the concerns and the PLAN-006 sections',
      /KPI #01 – Gross profit %/.test(tC)&&/KPI #06 – Site management/.test(tC)&&/Overall portfolio/.test(tC)&&/Areas of concern/.test(tD)&&/\(sample\)/.test(tD)&&
      ['Project information','Progress percentage','Schedule status','Claim status','Commercial status','Budget status','Manpower','Areas of concern','Cost plan for the current year','Cash status','Site management analysis'].every(h=>tP.includes(h)));
    let out=null;saveFile=async(n,b)=>{out={n,b}};await merExport();saveFile=keep;const W=XLSX.read(new Uint8Array(await out.b.arrayBuffer()),{type:'array'});
    const cr=XLSX.utils.sheet_to_json(W.Sheets['COST(I)'],{header:1,defval:''}),row=cr.find(x=>x[1]===pcode(projById(pid)));
    ok('23. Export to Excel: COST (I), DASHBOARD and one PLAN-006 sheet per project; the POC as a percentage',out.n===`MER ${per} I.xlsx`&&W.SheetNames[0]==='COST(I)'&&W.SheetNames[1]==='DASHBOARD'&&W.SheetNames.includes(pcode(projById(pid)))&&!!row&&near(row[6],r.poc/100,1e-5),W.SheetNames);
    out=null;saveFile=async(n,b)=>{out={n,b}};state.cp={pid,y};await cpExport();saveFile=keep;const W2=XLSX.read(new Uint8Array(await out.b.arrayBuffer()),{type:'array'});
    ok('24. The cost plans export as COST PLAN (I) and COST PLAN (F) (from v3.43 with ACTUAL TO LAST YEAR)',['COST PLAN (I),COST PLAN (F)','COST PLAN (I),COST PLAN (F),ACTUAL TO LAST YEAR'].includes(W2.SheetNames.join()),W2.SheetNames);
    go('cplan');await wait(80);
    ok('25. The Cost plan page lists the projects and opens one: year start, internal, finance, actual and forecast, history',['Internal plan','Finance plan','Actual and forecast','History','Year start'].every(h=>$('#view').innerText.includes(h)));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keep;window.toast=keepToast;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Cost plan and MER: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__merChecks=res;try{sessionStorage.setItem('merChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
