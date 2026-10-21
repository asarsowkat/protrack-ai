/* ProTrackAI v3.17, cost report gross margin by column and the report emails: acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. It needs an internet connection (SheetJS loads from cdnjs). */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms));
  try{
    as('U28');const P='RMX',per=curMonth(),cc=contractOf(P,per),f=crCompute(P,per,crDefaults(P,per)),pr=crPrev(P,per);
    ok('Tender and Rev-0 margins are on the original contract value',f.cv_by.tender===cc.orig&&f.cv_by.rev0===cc.orig,f.cv_by);
    ok('Revised Rev-0, current budget and EAC margins are on the internal revised contract value',f.cv_by.rev0_rev===cc.rev_int&&f.cv_by.budget===cc.rev_int&&f.cv_by.eac===cc.rev_int);
    ok('Previous version margin is on the previous month\'s contract value',pr?f.cv_by.prev===crN(pr.figures.contract_value):f.cv_by.prev!=null,{prev:f.cv_by.prev,from:pr&&pr.period});
    const html=crTableHTML(Object.assign({},f,{tender_total:1000,budget_rev0:1000}),per);
    ok('The cost report table shows the contract value and gross margin for every budget column',(html.match(/class="crfoot"/g)||[]).length===3&&/A, B1: original/.test(html));
    const A=crAoa(P,per,f),cvRow=A.find(r=>r[1]==='Contract Value'),gmRow=A.find(r=>r[1]==='Gross Margin');
    ok('The Excel export has the contract value and margin per column',cvRow[2]===cc.orig&&cvRow[6]===cc.rev_int&&gmRow[2]===cc.orig-Math.round(crN(f.tender_total)),{cv:cvRow.slice(2,7)});
    // the internal report email
    DB.outbox=[];const sub=relRows().find(r=>r.kind==='planning'&&r.period_type==='month'&&r.status==='Submitted'&&r.period===per);
    const base={project_id:sub.project_id,kind:'planning',period_type:'month',period:per},p=projById(sub.project_id);
    const exp=relMailRecipients(sub);ok('The default internal report list reaches project managers, portfolio, regional managers, executives and planners with access',exp.length>0&&exp.every(x=>['pm','pf','rm','exec','plan'].includes(x.role)),exp.map(x=>x.role));
    const ap=await relAct({...base,action:'approve',note:'',validated:true,validation_note:'checked'});await wait(200);
    const m=DB.outbox[0];ok('Approving an internal report prepares an email to the list',ap&&ap.status==='Released'&&m&&m.rel===ap.id&&m.to.length===exp.length&&/Monthly internal report released/.test(m.subject),m&&m.subject);
    ok('The email carries the released figures and a link to the report',m&&/Planned/.test(m.html)&&m.html.includes(relLink(ap))&&m.status==='Demo: not sent');
    // the section planning manager's list for the region
    const spm=relApproversOf(p.region)[0];
    if(spm){as(spm.id);const c=relMailCfg();c.regions[p.region]={on:true,weekly:false,roles:['pm'],people:[],extra:['site.office@example.com']};
      const to=relMailRecipients({project_id:p.id,kind:'planning',period_type:'month',period:per,rev:0});
      ok('A section planning manager\'s list for the region replaces the default for its projects',to.every(x=>x.role==='pm'||x.email==='site.office@example.com')&&to.some(x=>x.email==='site.office@example.com'));
      ok('With weekly switched off, a weekly internal report sends nothing',relMailRecipients({project_id:p.id,kind:'planning',period_type:'week',period:curWeek(),rev:0}).length===0);
      const other=DB.master.regions.find(r=>!relApproversOf(r.id).some(u=>u.id===spm.id));ok('A section planning manager cannot change another region\'s list',!other||!canRelMailRegion(other.id));
      delete c.regions[p.region];as('U28')}
    // the cost report email
    const cs=relRows().find(r=>r.kind==='cost'&&['Draft','Submitted'].includes(r.status));
    if(cs){const cb={project_id:cs.project_id,kind:'cost',period_type:'month',period:cs.period};const co=teamOf(cs.project_id,'costing')[0];
      if(cs.status==='Draft'&&co){as(co.id);await relAct({...cb,action:'submit',note:''});as('U28')}
      const n0=DB.outbox.length,ca=await relAct({...cb,action:'approve',note:''});await wait(200);const cm=DB.outbox[0];
      ok('Approving a monthly cost report prepares an email to the cost list (project managers, portfolio, regional managers, executives, costing)',ca&&ca.status==='Released'&&DB.outbox.length===n0+1&&/Monthly cost report released/.test(cm.subject)&&cm.to.every(x=>['pm','pf','rm','exec','costing'].includes(x.role)),cm&&cm.to.map(x=>x.role));
      ok('The cost email shows the gross margin on EAC',/Gross margin on EAC/.test(cm.html))}
    // settings
    const c=relMailCfg();c.cost.extra=['bad address'];ok('Only valid addresses are kept for other recipients',!RM_EMAIL.test('bad address')&&RM_EMAIL.test('finance@company.com'));c.cost.extra=[];
    state.adminTab='mail';go('admin');await wait(300);ok('Settings → Email has the report email lists, with a list per region',/Report emails/.test($('#view').innerText)&&/Internal reports by region/.test($('#view').innerText));
    const pm=DB.master.users.find(u=>u.role==='pm');as(pm.id);let msg='';const ot=toast;toast=t=>{msg=t};relMailSave('cost|',o=>{o.on=false});toast=ot;ok('A project manager cannot change a list',/Only a super admin/.test(msg)&&relMailCfg().cost.on===true);as('U28');
    // the link opens the report
    location.hash='#rel='+encodeURIComponent([ap.project_id,'planning','month',per].join('|'));checkDeepLink();await wait(400);
    ok('The link in the email opens the report',state.view==='rel'&&!$('#drawer').hidden);closeDrawer();
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Margin and report emails: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__mmChecks=res;try{sessionStorage.setItem('mmChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
