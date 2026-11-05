/* ProTrackAI v3.59, RASA understands more questions: typos, everyday words and Arabic keywords read again when no rule
   answers, a question about several topics answered topic by topic, a project named in the question narrowing the answer,
   follow-ups carrying on from the last question, "Did you mean" suggestions, and the new progress and productivity rules.
   Also the v3.59 fix: the collection answer adds up every project in scope, not only the first. How to run: open demo.html,
   sign in with the demo Super Admin account (U28), open the browser console and paste this whole file. It saves this
   browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds();RASA.ctx=null},wait=ms=>new Promise(r=>setTimeout(r,ms));
  const txt=h=>String(h||'').replace(/<[^>]+>/g,' ').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/\s+/g,' ').trim();
  const A=async q=>{let a=answer(q);if(a&&typeof a.then==='function')a=await a;return a||''};
  const R=async q=>{const r=await rasaAnswer(q);return {...r,t:txt(r.html)}};
  const U=DB.master.users,sa=U.find(u=>u.role==='sa');
  try{
    as(sa.id);
    // ---- reading the question again
    const N=['porgress of RMX','invocie','how much is unpaid','labour on site','where is the state of works','status of the works','RMX'].map(rasaNorm);
    ok('1. Typos corrected to ProTrackAI terms, everyday words put in its terms, project codes and common words left alone',
      N[0]==='progress of rmx'&&N[1]==='invoice'&&N[2]==='how much is outstanding'&&N[3]==='manpower on site'&&/\bwhere\b/.test(N[4])&&/\bstate\b/.test(N[4])&&N[5]==='progress'&&N[6]==='rmx',N);
    const again=['porgress of RMX','how much is unpaid','labour on site','ما هي نسبة الإنجاز'].every(q=>rasaNorm(rasaNorm(q))===rasaNorm(q));
    ok('2. Reading a question again changes nothing more',again);
    const AR=['ما هي نسبة الإنجاز','رؤساء العمال','الفواتير RMX','الإنتاجية اليوم'].map(rasaNorm);
    ok('3. Arabic: the keywords in English, the longer phrase first ("foremen", not "manpower"), latin codes kept',AR[0]==='progress'&&AR[1]==='foremen'&&AR[2]==='invoice rmx'&&AR[3]==='productivity today',AR);
    const same=[];for(const q of ['Unit rates','Best subcontractor','Early warnings','Invoicing and collection','Milestones and EOT']){RASA.ctx=null;const r=await R(q);same.push(r.html===await A(q))}
    ok('4. A question the rules already answer is answered exactly as before, with no note and no extra part',same.every(Boolean),same);
    RASA.ctx=null;const ty=await R('what is the produktivity');
    ok('5. A typo the rules miss: read again, answered, and RASA says how it read it',ty.html&&ty.t.startsWith('I read this as “what is the productivity”.')&&ty.html.endsWith(await A('what is the productivity')),ty.t);
    RASA.ctx=null;const ar=await R('ما هي نسبة الإنجاز');ok('6. An Arabic question answered by the rule its keywords point to',/I read this as “progress”/.test(ar.t)&&ar.topics[0]==='progress',ar.t);
    // ---- progress and productivity
    const P=scopeProjects().map(p=>evm(ACTS.filter(a=>a.p===p.id),ASOF)).filter(e=>e.bac),T=P.reduce((t,e)=>({pv:t.pv+e.pv,ev:t.ev+e.ev,bac:t.bac+e.bac}),{pv:0,ev:0,bac:0});
    const hp=txt(await A('What is the overall progress?'));
    ok('7. Progress: earned value against planned value at the data date, every project with a baseline, worst first',RASA_TOPIC==='progress'&&hp.includes(`Across ${P.length} projects, work done is ${pct(T.ev/T.bac)} against ${pct(T.pv/T.bac)} planned at ${fmtDY(ASOF)}`)&&/Based on the baseline/.test(hp),hp);
    const w14=valid().filter(d=>d.date>=addDays(TODAY,-14)),g=agg(w14),hq=txt(await A('productivity'));
    ok('8. Productivity: the last 14 days of daily reports, by project, the lowest activities',RASA_TOPIC==='prod'&&hq.includes(`Productivity over the last 14 days is ${pct(g.pi)}`)&&/Lowest activities/.test(hq),hq);
    ok('9. Earlier rules keep their questions: "today\'s productivity", foremen, "behind"',
      (await A("Today's productivity"),RASA_TOPIC==='today')&&(await A('productivity of the foremen'),RASA_TOPIC==='foremen')&&(await A('which activities are behind'),RASA_TOPIC==='under'));
    // ---- a project named in the question
    RASA.ctx=null;const nr=await R('progress of RMX');
    ok('10. A project named in the question narrows the answer to it, and RASA says so',nr.pid==='RMX'&&nr.t.includes('For Riyadh Metro L7 only: the project named in your question.')&&!/Across \d+ projects/.test(nr.t),nr.t);
    SCOPE=new Set(['QOT']);RASA.ctx=null;const os=await R('progress of RMX');
    ok('11. A project outside the scope: the scope answer as before, nothing narrowed',!os.pid&&/outside the current scope/.test(os.t),os.t);
    SCOPE=new Set(['RMX']);RASA.ctx=null;const one=await R('progress of RMX');ok('12. Scope of one project: no narrowing note',!one.pid&&!/only: the project named/.test(one.t));
    SCOPE=scopeIds();
    // ---- several topics
    RASA.ctx=null;const mt=await R('early warnings and manpower forecast');
    ok('13. Two topics in one question: both answered, the second under "Also asked"',mt.topics.join()==='warn,histo'&&(mt.html.match(/class="rasa-part"/g)||[]).length===2&&mt.t.includes('Also asked: “manpower forecast”'),mt.t.slice(0,200));
    RASA.ctx=null;const m3=await R('progress and cash flow and productivity for RMX');
    ok('14. Three topics, narrowed to the project named',m3.pid==='RMX'&&m3.topics.length===3&&m3.topics.includes('progress')&&m3.topics.includes('prod'),m3.topics);
    RASA.ctx=null;const ch=await R('Design and procurement');ok('15. A suggestion\'s own wording is never split',ch.topics.length===1&&!/Also asked/.test(ch.t));
    // ---- follow-ups
    RASA.ctx=null;await R('progress of RMX');const f1=await R('and for QOT?');
    ok('16. "and for QOT?": the last topic, for the project named',f1.pid==='QOT'&&f1.topics[0]==='progress'&&f1.t.startsWith('Following on from your last question, I read this as “progress for Riyadh-Qassim OHTL”.'),f1.t.slice(0,200));
    const f2=await R('what about productivity?');ok('17. "what about productivity?": the new topic, for the last project',f2.pid==='QOT'&&f2.topics[0]==='prod'&&/I read this as “productivity for Riyadh-Qassim OHTL”/.test(f2.t),f2.t.slice(0,200));
    const f3=await R('same for all projects');ok('18. "same for all projects": the last topic, the whole scope',!f3.pid&&f3.topics[0]==='prod'&&/I read this as “productivity”/.test(f3.t)&&/Jubail/.test(f3.t),f3.t.slice(0,200));
    RASA.ctx=null;await R('progress of RMX');const f4=await R('For JDC, what is the productivity?');
    ok('19. A full question that starts with "For": answered as asked, not as a follow-up',f4.pid==='JDC'&&f4.topics[0]==='prod'&&!/Following on/.test(f4.t),f4.t.slice(0,160));
    RASA.ctx=null;const f5=await R('and for QOT?');ok('20. No last question: nothing to follow on from',!/Following on/.test(f5.t||''));
    await R('progress of RMX');RASA.ctx.t-=31*60e3;const f6=await R('and for QOT?');ok('21. A follow-up more than 30 minutes later is not taken as one',!/Following on/.test(f6.t||''));
    await R('progress of RMX');RASA.ctx.uid='U01';const f7=await R('and for QOT?');ok('22. Another person\'s last question is never followed on',!/Following on/.test(f7.t||''));
    RASA.ctx=null;await R('porgress and cash flow for RMX');const f8=await R('and for QOT?');
    ok('23. A follow-up reads the last question again, so a typo in it is not repeated',/I read this as “progress and cash flow for Riyadh-Qassim OHTL”/.test(f8.t)&&f8.topics.length===2,f8.t.slice(0,160));
    // ---- "Did you mean"
    const dy=rasaDidYouMean('show me the warnigs');ok('24. Nothing answers: "Did you mean" offers the nearest suggestions as buttons',/data-q="Early warnings"/.test(dy)&&rasaDidYouMean('zzqx wvvk')==='',dy);
    // ---- the collection answer adds up every project (v3.59 fix: map passed the list index as the date)
    const B=scopeProjects().map(p=>billPosition(p)).filter(x=>x.b.contract||x.t.n),inv=B.reduce((t,x)=>t+x.invoiceable,0),sub=B.reduce((t,x)=>t+x.t.submitted,0),hc=txt(await A('Invoicing and collection'));
    ok('25. Invoicing and collection: invoiceable and invoiced over every project in scope',B.length>1&&hc.startsWith(`Invoiceable ${sar(inv)} , invoiced ${sar(sub)}`),[sar(inv),sar(sub),hc.slice(0,90)]);
    // ---- the chat itself
    RASA.ctx=null;state.chat=[];aiTurns=[];RASA.tok++;
    const reply=async n=>{for(let i=0;i<40&&state.chat.length<n;i++)await wait(100);return txt((state.chat[n-1]||{}).h)};
    await ask('porgress of RMX');const c1=await reply(2);
    await ask('and for QOT?');const c2=await reply(4);
    ok('26. In the chat: the note, the narrowed answer, then the follow-up',/I read this as “progress of rmx”/.test(c1)&&/For Riyadh Metro L7 only/.test(c1)&&/Following on from your last question/.test(c2)&&/Riyadh-Qassim OHTL only/.test(c2),[c1.slice(0,120),c2.slice(0,120)]);
    const rk=await rkAsk('and for QOT?');ok('27. RASA Intelligence reads typos too but never takes a question as a follow-up',!/Following on/.test(txt(rk&&rk.html))&&/I read this as/.test(txt((await rkAsk('porgress of RMX')||{}).html)));
    as(sa.id);RASA.tok++;
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`RASA understanding: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__ruChecks=res;try{sessionStorage.setItem('ruChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
