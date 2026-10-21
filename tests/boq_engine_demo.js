/* ProTrackAI v3.25, BOQ Engine. Acceptance checks for the demo page, as in section 20 of the specification:
   A drawing registration, B quantity calculations (fixtures with known answers), C workflow, D budget protection,
   E error handling. How to run: open demo.html (or index.html), sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. The PDFs it makes are test fixtures labelled as such, never project drawings. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms));
  const err=fn=>{try{fn();return ''}catch(e){return e.message}},aerr=async fn=>{try{await fn();return ''}catch(e){return e.message}};
  const U=DB.master.users,sa=U.find(u=>u.role==='sa'),P='RMX',pl=teamOf(P,'plan')[0],eng=U.find(u=>u.role==='eng'&&accessIds(u).includes(P))||U.find(u=>u.role==='eng'),fm=U.find(u=>u.role==='foreman');
  const keepSave=saveFile;let saved=null;
  const budgetJSON=()=>JSON.stringify(Object.fromEntries(Object.entries(DB).filter(([k])=>k!=='boq')));
  try{
    await loadLib(LIBS.jspdf);const {jsPDF}=window.jspdf;
    const pdf=(no,rev,extra)=>{const d=new jsPDF({orientation:'landscape',unit:'pt',format:'a3'});d.setFontSize(10);d.text('TEST FIXTURE - NOT A PROJECT DRAWING',40,40);d.text('FOUNDATION PLAN',100,90);d.text('SECTION A-A',600,90);
      d.text(extra&&extra.L||'4000',300,200);d.text('3000',120,330);d.text('500',700,250);d.text('T16@200',600,330);d.text('ALL DIMENSIONS ARE IN MILLIMETRES',40,700);d.text('REINFORCEMENT DETAIL',600,400);
      d.text('TITLE: POWER TRANSFORMER T9 FOUNDATION PLAN AND SECTIONS',820,740);d.text('DRAWING NO: '+no,820,760);d.text('REV: '+rev,820,780);d.text('SCALE 1:50',1000,780);return new File([d.output('blob')],`${no}_${rev}.pdf`,{type:'application/pdf'})};
    const until=async(id,L)=>{for(let i=0;i<60&&!L.includes(boqDwg(id).ext_status);i++)await wait(150);return boqDwg(id).ext_status};
    const budget0=budgetJSON();
    /* ---------- A. drawing registration ---------- */
    as(pl.id);const st=boqM().structure_types.find(s=>s.name==='Power Transformer Foundation');
    const pk=boqPkgLocal({project_id:P,code:'T-'+Date.now().toString(36).slice(-4),name:'Checks package',location:'Test site',ptype:'380 kV substation'});
    const a1=boqAssetLocal({pkg_id:pk.id,facility:'Main Substation',disc:'Structural',st:st.id,name:'Transformer T9 Foundation (fixture)'});
    ok('A0. A structure name is unique within its package',/already exists/.test(err(()=>boqAssetLocal({pkg_id:pk.id,facility:'Main Substation',disc:'Structural',st:st.id,name:'transformer t9 foundation (fixture)'}))));
    const f1=pdf('TF-T9-001','A'),d1=await boqUpload(P,pk.id,f1);const s1=await until(d1.id,['Extracted','Needs OCR','Extraction Error']);
    const x=boqDwg(d1.id).ext;ok('A1. Upload: the PDF is read in the background; title block, scale and units are proposed',s1==='Extracted'&&x.no==='TF-T9-001'&&x.rev==='A'&&x.scale==='1:50'&&x.units==='mm',{s1,no:x.no,rev:x.rev,scale:x.scale,units:x.units});
    ok('A2. Classification proposes a structure type with confidence and evidence; never one without its words',x.cls.st===st.id&&x.cls.st_conf>=0.6&&(x.cls.st_cands[0].words||[]).includes('transformer'));
    const meta={pkg_id:pk.id,site:'Test site',facility:'Main Substation',ptype:'380 kV substation',disc:'Structural',category:'plan',tags:['plan','sec','rdet'],st:st.id,asset_ids:[a1.id],title:'T9 foundation (fixture)',no:'TF-T9-001',rev:'A',issue_date:'2026-09-01',doc_status:'Issued for Construction (IFC)',scale:'1:50',units:'mm'};
    const eMiss=err(()=>boqRegisterLocal({id:d1.id,meta:{...meta,title:'',issue_date:''}}));ok('A3. Missing mandatory metadata is refused and named',/Drawing title/.test(eMiss)&&/issue date/.test(eMiss),eMiss);
    const r1=boqRegisterLocal({id:d1.id,meta});ok('A4. A planner registering an IFC drawing: the status waits for a reviewer; not eligible yet; first revision is the basis',r1.reg&&!r1.status_ok&&!boqEligible(r1)&&r1.basis);
    ok('A5. The person who registered it cannot confirm its status',/someone else confirms|Only a lead engineer/.test(err(()=>boqDwgStatusLocal({action:'confirm',id:d1.id}))));
    const eDupFile=await aerr(()=>boqUpload(P,pk.id,f1));ok('A6. The same file again is refused as a duplicate',/already registered as TF-T9-001 rev A/.test(eDupFile),eDupFile);
    const d1b=await boqUpload(P,pk.id,pdf('TF-T9-001','A',{L:'4100'}));await until(d1b.id,['Extracted','Needs OCR','Extraction Error']);
    ok('A7. Another file with the same number and revision is refused at registration',/already registered/.test(err(()=>boqRegisterLocal({id:d1b.id,meta}))));boqDiscardLocal({id:d1b.id});
    const eTxt=await aerr(()=>boqUpload(P,pk.id,new File(['hello'],'note.txt'))),eFake=await aerr(()=>boqUpload(P,pk.id,new File(['not a pdf'],'fake.pdf'))),eJs=await aerr(()=>boqUpload(P,pk.id,new File(['%PDF-1.4\n1 0 obj << /OpenAction << /S /JavaScript /JS (app.alert(1)) >> >> endobj'],'js.pdf')));
    ok('A8. Invalid files are refused: not a PDF, a fake PDF, a PDF with scripts',/Only PDF/.test(eTxt)&&/not a valid PDF/.test(eFake)&&/scripts/.test(eJs),[eTxt,eFake,eJs]);
    as(eng.id);const eEng=await aerr(()=>boqUpload(P,pk.id,pdf('TF-T9-009','A')));as(fm.id);const fmSees=boqSees(P);as(pl.id);
    ok('A9. Role-based permissions: a site engineer cannot upload; a foreman does not see BOQ Engine',!!eEng&&!fmSees,eEng);
    as(sa.id);boqDwgStatusLocal({action:'confirm',id:d1.id});ok('A10. A reviewer confirms the status; the drawing becomes eligible',boqEligible(boqDwg(d1.id)));
    /* ---------- B. quantity calculations: fixtures with known answers ---------- */
    const T=(tpl,segs,inputs,w)=>boqEval({tpl,segs:segs.map(s=>({inputs:Object.entries(s).map(([k,v])=>({k,value:String(v[0]),unit:v[1],src:{type:'user',note:'test fixture'}}))})),inputs:(inputs||[]).map(([k,v,u])=>({k,value:v,unit:u,src:{type:'user',note:'test fixture'}})),wst:w||null});
    const b1=T('EXC_RECT',[{L:[10,'m'],W:[2,'m'],D:[1.5,'m']}]),b2=T('CONC',[{kind:['Solid',''],L:[4,'m'],W:[3,'m'],T:[0.5,'m']}],[['cls','Reinforced concrete',''],['grade','C30/37','']]),b3=T('EXC_TRENCH',[{from:[0,'m'],to:[100,'m'],W:[0.8,'m'],D:[1.2,'m']}]);
    const b4=T('RFT_BBS',[{mark:['B1',''],dia:[16,'mm Ø'],n:[1,'No.'],len:[100,'m']}]),b5=T('BACKFILL',[{v:[6,'m³']}],[['exc','30','m³'],['mat','Reusable excavated material',''],['dsp','Not measured','']]);
    ok('B1. Excavation 10 × 2 × 1.5 m = 30 m³',b1.outputs[0].net==='30');ok('B2. Concrete foundation 4 × 3 × 0.5 m = 6 m³',b2.outputs[0].net==='6');ok('B3. Cable trench 100 × 0.8 × 1.2 m = 96 m³',b3.outputs[0].net==='96');
    ok('B4. Reinforcement Ø16, 100 m: 16² ÷ 162 × 100 ≈ 158.02 kg',dqRound(b4.outputs[0].net,2)==='158.02',b4.outputs[0].net);ok('B5. Backfill 30 − 6 = 24 m³',b5.outputs[0].net==='24');
    const mm=T('EXC_RECT',[{L:[10000,'mm'],W:[2000,'mm'],D:[1500,'mm']}]);ok('B6. Units convert exactly: mm in, m³ out',mm.outputs[0].net==='30');
    const ov=T('EXC_TRENCH',[{from:[0,'m'],to:[60,'m'],W:[0.8,'m'],D:[1.2,'m']},{from:[50,'m'],to:[100,'m'],W:[0.8,'m'],D:[1.2,'m']}]);ok('B7. Overlapping chainage segments are refused, not counted twice',ov.status==='Calculation Error'&&/overlap/.test(ov.error),ov.error);
    const inc=T('EXC_RECT',[{L:[10,'m'],W:[2,'m']}]);ok('B8. A missing input gives Incomplete with no quantity, never zero',inc.status==='Incomplete'&&!inc.outputs.length&&inc.missing.some(m=>/Depth/.test(m)));
    const nb=T('EXC_RECT',[{L:[10,'m'],W:[2,'m'],D:[1.5,'m']}],[],{k:'wst',value:'5',unit:'%',src:{type:'user',note:'rule of thumb'}});ok('B9. Wastage without a documented basis is refused',nb.status==='Calculation Error'&&/basis/.test(nb.error),nb.error);
    const neg=T('BACKFILL',[{v:[40,'m³']}],[['exc','30','m³'],['mat','Imported fill',''],['dsp','Not measured','']]);ok('B10. Negative backfill is an error, not a quantity',neg.status==='Calculation Error');
    const sl=T('EXC_RECT',[{L:[4,'m'],W:[3,'m'],D:[2,'m'],slope:[0.5,'ratio']}]);ok('B11. Sloped excavation: prismoidal volume (4 × 3 base, slope 0.5, depth 2 m: 2/6 × (12 + 4 × 20 + 30) = 40.667 m³)',dqRound(sl.outputs[0].net,3)==='40.667',sl.outputs[0].net);
    const tr=T('TRENCH',[{from:[0,'m'],to:[100,'m'],type:['T1',''],W:[0.8,'m'],D:[1.2,'m'],bed:[0.3,'m'],ducts:[3,'No.'],od:[0.16,'m'],rows:[1,'No.'],tile:[1,'m'],tapes:[2,'No.']}],[['bkf','Yes','']]);
    const tq=Object.fromEntries(tr.outputs.map(o=>[o.cat,o.net]));ok('B12. Trench lines: excavation 96, sand 24 less the ducts in it (17.968), ducts 300 m, tiles 100, tape 200 m, backfill above the sand zone 72; cables never multiply the trench',tq.EXC==='96'&&dqRound(tq.SND,3)==='17.968'&&tq.DCT==='300'&&tq.PTS==='100'&&tq.WTP==='200'&&tq.BKF==='72',tq);
    const unit=err(()=>boqToBase('2','m²','L'));ok('B13. A unit of the wrong kind is refused',/unit of area, not length/.test(unit),unit);
    /* ---------- C. workflow ---------- */
    as(pl.id);const D1=boqDimsOf(d1.id),dim=v=>D1.find(z=>z.value===v&&z.page===1);
    ['4000','3000','500'].forEach(v=>boqDimLocal({action:'verify',id:dim(v).id}));boqDimLocal({action:'correct',id:dim('4000').id,value:'4000',unit:'mm',label:'foundation length',reason:''});
    ok('C1. Dimensions verified, with their page and position kept',['4000','3000','500'].every(v=>dim(v).status==='Verified'&&dim(v).bbox&&dim(v).page===1));
    const src=v=>({type:'dim',ref:dim(v).id});
    const c1=boqCalcSaveLocal({asset_id:a1.id,tpl:'CONC',desc:'T9 base (fixture)',inputs:[{k:'cls',value:'Reinforced concrete'},{k:'grade',value:'C30/37',src:{type:'user',note:'drawing note (fixture)'}}],segs:[{inputs:[{k:'kind',value:'Solid'},{k:'L',src:src('4000')},{k:'W',src:src('3000')},{k:'T',src:src('500')}]}]});
    ok('C2. A calculation from verified drawing dimensions: 4 × 3 × 0.5 = 6 m³, traceable to the drawing revision',c1.outputs[0].net==='6'&&c1.drawings.includes(d1.id)&&c1.status==='Needs Verification'&&!!c1.outputs[0].item_code);
    const c2=boqCalcSaveLocal({asset_id:a1.id,tpl:'EXC_RECT',desc:'T9 excavation (fixture)',inputs:[],segs:[{inputs:[{k:'L',src:src('4000')},{k:'W',src:src('3000')},{k:'D',value:'1.5',unit:'m',src:{type:'user',note:'section A-A (fixture)'}}]}]});
    const c3=boqCalcSaveLocal({asset_id:a1.id,tpl:'BACKFILL',desc:'T9 backfill (fixture)',inputs:[{k:'exc',src:{type:'calc',ref:c2.id+':EXC'}},{k:'mat',value:'Reusable excavated material'},{k:'dsp',value:'Surplus after reuse'}],segs:[{inputs:[{k:'v',src:{type:'calc',ref:c1.id+':RCC'}}]}]});
    ok('C3. Backfill takes the excavation and concrete calculations: 18 − 6 = 12 m³, disposal 6 m³',c3.outputs.find(o=>o.key==='BKF').net==='12'&&c3.outputs.find(o=>o.key==='DSP').net==='6',c3.outputs);
    ok('C4. A calculation cannot be verified while its inputs are not',/verified first/.test(err(()=>boqCalcActLocal({action:'verify',id:c3.id}))));
    ok('C4b. Nobody verifies a calculation they prepared',/someone else verifies/.test(err(()=>boqCalcActLocal({action:'verify',id:c1.id}))));as(sa.id);[c1,c2].forEach(c=>boqCalcActLocal({action:'verify',id:c.id}));boqCalcActLocal({action:'verify',id:c3.id});as(pl.id);
    ok('C5. Verified in order: sources first, then the calculation built on them',[c1,c2,c3].every(c=>boqCalc(c.id).status==='Verified'));
    const R=boqReadiness(a1);ok('C6. Completeness: plan and sections available; missing specification listed; partial estimate only',R.level==='Partial estimate only'&&R.rows.find(r=>r.key==='plan').state==='Available'&&R.rows.find(r=>r.key==='conc').state==='Missing',R.rows.map(r=>r.key+':'+r.state));
    const e=boqEstLocal({action:'create',pkg_id:pk.id});boqEstLocal({action:'generate',id:e.id});
    ok('C7. Draft Estimated BOQ generated from the calculations, lines provisional where the package is incomplete',e.lines.length===4&&e.lines.every(l=>l.prov.length>0)&&e.lines.find(l=>l.cat==='RCC').qty==='6');
    ok('C8. Rates: only with the rate right and a source; none are invented',/rate right|right to enter/i.test(err(()=>boqEstLocal({action:'rate',id:e.id,key:e.lines[0].key,rate:'100',note:'x'})))&&e.lines.every(l=>l.rate==null));
    boqEstLocal({action:'submit',id:e.id});ok('C9. The preparer cannot review their own estimate',/someone else reviews|Only a lead engineer/.test(err(()=>boqEstLocal({action:'start',id:e.id}))));
    as(sa.id);boqEstLocal({action:'start',id:e.id});boqEstLocal({action:'approve',id:e.id});boqEstLocal({action:'release',id:e.id});
    ok('C10. Reviewed, approved and released by someone else, with the history recorded',e.status==='Released'&&e.history.length>=5&&e.history.some(h=>h.action==='Released'));
    const frozen=JSON.stringify(e.lines);as(pl.id);boqCalcSaveLocal({id:c1.id,asset_id:a1.id,tpl:'CONC',desc:'T9 base (fixture)',cause:'Changed geometry',inputs:c1.inputs,segs:[{inputs:[{k:'kind',value:'Solid'},{k:'L',src:src('4000')},{k:'W',src:src('3000')},{k:'T',value:'0.6',unit:'m',src:{type:'user',note:'revised thickness (fixture)'}}]}]});
    ok('C11. A released estimate is never overwritten: its lines stay as released after a calculation changes',JSON.stringify(boqEst(e.id).lines)===frozen&&boqCalc(c1.id).outputs[0].net==='7.2');
    ok('C12. A change recalculates what depends on it (backfill 18 − 7.2 = 10.8 m³)',boqCalc(c3.id).outputs.find(o=>o.key==='BKF').net==='10.8');
    const e2=boqEstLocal({action:'create',pkg_id:pk.id});boqEstLocal({action:'generate',id:e2.id});const cmp=boqCompare(e.lines,e2.lines,e.snap_at,e2.snap_at),rc=cmp.find(x=>x.item_code===e.lines.find(l=>l.cat==='RCC').item_code);
    ok('C13. Revision comparison: variance and % with the source of the difference',rc.state==='Modified'&&rc.var==='1.2'&&Math.round(rc.pct)===20&&rc.why.some(w=>/Changed geometry/.test(w)),rc);
    const d2=await boqUpload(P,pk.id,pdf('TF-T9-001','B',{L:'4200'}));await until(d2.id,['Extracted','Needs OCR','Extraction Error']);boqRegisterLocal({id:d2.id,meta:{...meta,rev:'B',issue_date:'2026-09-10'}});
    ok('C14. A new revision is registered without becoming the basis on its own',!boqDwg(d2.id).basis&&boqDwg(d1.id).basis);
    const I=boqRevImpact(boqDwg(d2.id));ok('C15. The calculations the new revision touches are listed',I.calcs.some(c=>c.id===c2.id));
    ok('C16. Changing the basis needs an explicit confirmation',/Confirm/.test(err(()=>boqDwgStatusLocal({action:'basis',id:d2.id}))));
    boqDwgStatusLocal({action:'basis',id:d2.id,confirm:true});ok('C17. After the basis changes, dependent calculations need recalculation',boqCalc(c2.id).status==='Recalculation Required');
    const nd=boqDimsOf(d2.id).find(z=>z.value==='4200');boqDimLocal({action:'correct',id:nd.id,value:'4200',unit:'mm',label:'foundation length',reason:''});const rl=boqRelinkLocal({calc_id:c2.id,dwg_id:d2.id});
    ok('C18. Re-linking moves the named dimension to the new revision and recalculates (4.2 × 3 × 1.5 = 18.9 m³)',rl.moved===1&&boqCalc(c2.id).outputs[0].net==='18.9'&&boqCalc(c2.id).history.some(h=>h.cause==='Changed geometry'),[rl,boqCalc(c2.id).outputs[0].net]);
    as(sa.id);saveFile=async(n,b)=>{saved={n,b}};await boqExcel(pk.id,e.id);saveFile=keepSave;const wb=XLSX.read(new Uint8Array(await saved.b.arrayBuffer()),{type:'array'});
    ok('C19. Excel: the eight sheets, with the estimate label and the calculation sources',['Estimated BOQ','Detailed Calculations','Drawing Register','Assumptions and Exclusions','Missing Information','Drawing References','Revision Changes','Estimation Summary'].every(n=>wb.SheetNames.includes(n))
      &&/ESTIMATE/.test(XLSX.utils.sheet_to_csv(wb.Sheets['Estimated BOQ']))&&/Drawing dimension/.test(XLSX.utils.sheet_to_csv(wb.Sheets['Detailed Calculations'])),wb.SheetNames);
    ok('C20. Audit history records every step',['Drawing registered','Calculation created','Estimate release','Estimation basis changed','Excel exported'].every(t=>boqDB().audit.some(a=>a.action===t)));
    const h=boqHandoffLocal({est_id:e.id,dest:BOQ_DEST[0],mapping:'RCC to WBS head 03 (fixture)',confirm:true});ok('C21. Hand-off: recorded only, awaiting the cost-control interface',h.status==='Awaiting cost-control interface');
    /* ---------- D. budget protection ---------- */
    ok('D1. Uploading, calculating, approving, releasing and handing off changed nothing outside BOQ Engine (budgets, cost reports, POs, actual costs, forecasts)',budgetJSON()===budget0);
    /* ---------- E. error handling ---------- */
    const eBad=await aerr(()=>boqUpload(P,pk.id,new File(['%PDF-1.4\n%%garbage'],'broken.pdf')));ok('E1. An unreadable PDF is refused with a reason',/could not be opened/.test(eBad),eBad);
    as(pl.id);const sp=await boqSpecAdd({project_id:P,kind:'Technical specification',ref:'SPEC-FIX-'+Date.now().toString(36).slice(-3),title:'Fixture spec'},null);
    boqSpecReqLocal({action:'add',spec_id:sp.id,topic:'conc',value:'C30/37',source_ref:'cl. 1 (fixture)'});boqSpecReqLocal({action:'add',spec_id:sp.id,topic:'conc',value:'C40/50',source_ref:'cl. 2 (fixture)'});
    ok('E2. Conflicting requirements are flagged, not chosen',boqSpecConflicts(P,pk.id).some(x=>x.topic==='conc'));
    const bad=boqCalcSaveLocal({asset_id:a1.id,tpl:'EXC_RECT',desc:'Wrong unit (fixture)',segs:[{inputs:[{k:'L',value:'2',unit:'m²',src:{type:'user',note:'fixture'}},{k:'W',value:'1',unit:'m',src:{type:'user',note:'fixture'}},{k:'D',value:'1',unit:'m',src:{type:'user',note:'fixture'}}]}]});
    ok('E3. Invalid units: a calculation error, no quantity',bad.status==='Calculation Error'&&!bad.outputs.length&&/area/.test(bad.error),bad.error);
    as(sa.id);ok('E4. An AI provider cannot be set without authorization for confidential drawings',/authorized/.test(err(()=>boqMasterLocal({kind:'ai',provider:'X',endpoint:'https://x.example',authorized:false}))));
    const ghost={id:'DWG-GHOST'+Date.now(),project_id:P,pkg_id:pk.id,reg:false,file:'boq/none/missing.pdf',file_name:'missing.pdf',pages:1,ext_status:'Not Started',asset_ids:[],tags:[],by:'test',at:new Date().toISOString()};boqDB().dwgs.push(ghost);
    const j=boqQueue(ghost.id);for(let i=0;i<40&&j.status!=='Failed';i++)await wait(100);ok('E5. A processing failure is recorded with its error and can be retried',j.status==='Failed'&&!!j.error&&ghost.ext_status==='Extraction Error',j.error);
    ok('E6. An unresolved calculation gives a BOQ line without a quantity, never zero',boqLines(pk.id).filter(l=>l.calc_id===bad.id).every(l=>l.qty==null));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keepSave;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`BOQ Engine: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__bqChecks=res;try{sessionStorage.setItem('bqChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
