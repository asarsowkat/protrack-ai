/* ProTrackAI v3.10, Project Visual: acceptance checks for the demo page.
   How to run: open demo.html (or index.html) on the demo page, sign in with the demo Super Admin account (U28), open the
   browser console and paste this whole file. It saves this browser's demo data first and puts it back at the end, then
   reloads the page. It prints one line per check and a total. It needs an internet connection (pdf.js and jsPDF load
   from cdnjs). */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d:JSON.stringify(d)});
  const sleep=ms=>new Promise(r=>setTimeout(r,ms)),as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()};
  try{
    as('U28');delete DB.pv;DB.pvSeeded=false;relRows().forEach(r=>{delete r.pv_snapshot});save();
    await pvSeedDemo();const X=pvDB();
    ok('Demo sample: three projects set up (site, linear, hybrid)',['JBS','QOT','JWP'].every(p=>X.cfg[p])&&X.cfg.JBS.type==='site'&&X.cfg.QOT.type==='linear'&&X.cfg.JWP.type==='hybrid',Object.keys(X.cfg));
    ok('Demo sample: each drawing is a real PDF kept in this browser',(await Promise.all(X.drawings.map(async d=>{const b=await DOCIDB.get(d.file);return b&&new TextDecoder().decode(new Uint8Array((await b.arrayBuffer()).slice(0,5)))==='%PDF-'}))).every(Boolean),X.drawings.length+' drawings');
    ok('Demo sample: released internal reports carry a snapshot',relRows().filter(r=>r.pv_snapshot).length>=6,relRows().filter(r=>r.pv_snapshot).length);
    const zid=(p,n)=>X.zones.find(z=>z.pid===p&&z.name===n&&z.status==='active').id;
    let e='';try{pvMapAdd({pid:'JBS',act:'JBS-C5010',tk:'zone',tid:zid('JBS','Switchyard'),share:0.5})}catch(x){e=x.message}
    ok('An activity cannot be allocated more than 100%',/already has 100%/.test(e),e);
    const m0=X.maps.find(m=>m.pid==='JBS'&&m.act==='JBS-C5010'&&m.status==='approved');pvMapDecide(m0.id,'edit',{share:0.6});pvMapAdd({pid:'JBS',act:'JBS-C5010',tk:'zone',tid:zid('JBS','Switchyard'),share:0.4});
    let md=pvModel('JBS',{nomemo:true});const W=md.acts.filter(a=>a.S>0).reduce((t,a)=>t+a.wshare*a.S,0);
    ok('Many-to-many mapping counts each activity once (coverage = share-weighted budget)',Math.abs(W-md.kpi.coverage)<1e-9&&md.acts.find(a=>a.id==='JBS-C5010').S===1,{coverage:md.kpi.coverage,W});
    X.maps.push({id:'MTEST',pid:'JBS',act:'JBS-E5020',tk:'zone',tid:zid('JBS','Control Building'),share:1,status:'approved',method:'manual'});md=pvModel('JBS',{nomemo:true});
    ok('A share above 100% (bad data) is scaled back and flagged',md.acts.find(a=>a.id==='JBS-E5020').S===1&&md.warnings.some(w=>/more than 100%/.test(w.t)));X.maps.splice(X.maps.findIndex(m=>m.id==='MTEST'),1);
    const z=md.zones.find(q=>q.name==='Transformer Area'),A=Object.fromEntries(md.acts.map(a=>[a.id,a]));
    const exp=(()=>{let w=0,p=0;X.maps.filter(m=>m.pid==='JBS'&&m.status==='approved'&&m.tk==='zone'&&m.tid===z.id).forEach(m=>{const a=actById(m.act),e2=evm([a],ASOF),s=bacOf(a)*m.share;w+=s;p+=s*(e2.bac?Math.min(1,e2.ev/e2.bac):0)});return p/w})();
    ok('Zone actual = budget × share weighted earned value (existing evm)',Math.abs(exp-z.act)<1e-9,{zone:z.act,expected:exp});
    ok('Variance = actual − planned',Math.abs(z.var-(z.act-z.plan))<1e-12);
    const sug=pvMaps('QOT','suggested').find(m=>m.act==='QOT-C3010');ok('Ambiguous route-wide match left for review with evidence and confidence',!!sug&&sug.conf<0.8&&/whole route/.test(sug.evidence),sug&&{conf:sug.conf,ev:sug.evidence});
    pvMapDecide(sug.id,'approve');md=pvModel('QOT',{nomemo:true});ok('A whole-route mapping is spread over the sections by length',md.sections.every(s=>s.acts.includes('QOT-C3010')));
    const st=md.stages.find(s=>s.k==='FDN');ok('Stage quantity in its own unit (towers counted as nos)',st.method==='quantity'&&st.scope>0,{scope:st.scope,unit:st.u,method:st.method});
    ok('Incompatible units are never added (km ⇄ towers)',pvConv(1,'km','twr')===null&&pvConv(2,'km','m')===2000);
    ok('Route coverage is reported apart from construction progress',md.covered===48000&&md.kpi.act<1,{covered:md.covered,act:md.kpi.act});
    for(const [n,f] of [['a text file',new File(['hi'],'x.txt')],['a file that is not a PDF',new File(['hello'],'x.pdf')]]){let m='';try{await pvUpload('JBS',f,{no:'X',rev:'1'})}catch(x){m=x.message}ok(`Upload refused: ${n}`,!!m,m)}
    const {jsPDF}=window.jspdf,rel0=JSON.stringify(relRows().filter(r=>r.pv_snapshot).map(r=>r.pv_snapshot));
    const nd=await pvUpload('JBS',new File([pvSamplePdf(jsPDF,'JBS-LAY-001','C','rev C',[],null)],'c.pdf'),{no:'JBS-LAY-001',rev:'C',view:'site'});
    md=pvModel('JBS',{nomemo:true});ok('A new revision waits for review; Live keeps the current one',nd.status==='pending'&&md.drawings[0].rev==='B');
    const prev=X.drawings.find(d=>d.no==='JBS-LAY-001'&&d.rev==='B'),dec={};pvZonesOf(prev.id).forEach(q=>dec[q.id]=q.name==='Cable trench, west'?'retire':'migrate');pvMakeCurrent(nd.id,dec);
    ok('Making it current moves the chosen zones with their mappings and retires the others',pvZonesOf(nd.id).length===4&&prev.status==='superseded'&&pvMaps('JBS','approved').every(m=>m.tk!=='zone'||X.zones.find(q=>q.id===m.tid).did===nd.id));
    ok('Earlier releases do not change',rel0===JSON.stringify(relRows().filter(r=>r.pv_snapshot).map(r=>r.pv_snapshot)));
    const sub=relRows().find(r=>r.project_id==='JBS'&&r.kind==='planning'&&r.period_type==='month'&&['Draft','Submitted'].includes(r.status)),base={project_id:'JBS',kind:'planning',period_type:'month',period:sub.period};
    if(sub.status==='Draft'){as(teamOf('JBS','plan')[0].id);await relAct({...base,action:'submit',note:''})}as('U28');
    const ap=await relAct({...base,action:'approve',note:'',validated:true,validation_note:'checked'});ok('Approving an internal report freezes Project Visual into it',!!(ap&&ap.pv_snapshot&&ap.pv_snapshot.drawings[0].rev==='C'),ap&&ap.pv_snapshot&&ap.pv_snapshot.release.id);
    const snap0=JSON.stringify(ap.pv_snapshot);pvMapDecide(X.maps.find(m=>m.pid==='JBS'&&m.status==='approved').id,'retire');
    as(teamOf('JBS','plan')[0].id);await relAct({...base,action:'revise',note:'Correction'});await relAct({...base,action:'save',figures:ap.figures,overrides:[],narrative:{summary:'Corrected'},data_date:ASOF});await relAct({...base,action:'submit',note:''});as('U28');
    const ap2=await relAct({...base,action:'approve',note:'',validated:true,validation_note:'ok'});
    ok('A correction is a new revision with its own snapshot; the first stays as released',ap2&&ap2.rev===1&&ap2.pv_snapshot&&JSON.stringify(relRows().find(r=>r.id===ap.id).pv_snapshot)===snap0&&relRows().find(r=>r.id===ap.id).status==='Superseded');
    as('U06');let pe='';try{pvCfgSave('JBS',pvCfg('JBS'))}catch(x){pe=x.message}ok('A project manager cannot change the set-up',/Only the people who keep/.test(pe),pe);
    as('U18');state.view='pv';render();ok('A foreman opening the screen directly is sent back',state.view!=='pv',state.view);as('U28');
    const g=pvGisParse(JSON.stringify({type:'LineString',coordinates:[[46,24],[46,25]]}),'t.geojson');ok('GIS route length from coordinates (1° of latitude ≈ 111.2 km)',Math.abs(g.len-111195)<300,g.len);
    let blob=null;const of=saveFile;saveFile=async(n,b)=>{blob=b};try{await pvExport(pvModel('QOT',{nomemo:true}),'live')}finally{saveFile=of}
    const t=blob?await blob.text():'';ok('PDF export (Live) with the drawing and several pages',(t.match(/\/Type\s*\/Page[^s]/g)||[]).length>=4&&/\/Subtype\s*\/Image/.test(t),blob&&blob.size);
  }catch(x){ok('The checks ran to the end',false,x.message)}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Project Visual: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__pvChecks=res;try{sessionStorage.setItem('pvChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
