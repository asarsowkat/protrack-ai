/* ProTrackAI v3.33, the RASA live avatar on the approved badge. Acceptance checks for the demo page. How to run: open demo.html, sign in
   with the demo Super Admin account (U28), open the browser console and paste this whole file. The frame loop is driven with a
   simulated clock, so the checks also run while the tab is in the background. It reloads the page at the end. */
(async()=>{
  const res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const wait=ms=>new Promise(r=>setTimeout(r,ms));let now=performance.now();
  const run=(ms,f)=>{const end=now+ms;while(now<end){now+=16;RasaLive.tick(now);if(f)f(now)}};
  const keep={tts:RASA.adapters.tts,llm:RASA.adapters.llm,avatar:RASA.adapters.avatar,speak,on:aiSpeakOn};
  try{
    aiOpen(true);await wait(300);RASA.tok++;RasaState.set('IDLE');clearTimeout(RasaLive.bt);run(600);
    const av=document.querySelector('#aiPanel .rasa-av'),q=s=>av.querySelector(s),cs=s=>getComputedStyle(q(s));
    // the approved badge
    const im=new Image();await new Promise(r=>{im.onload=im.onerror=r;im.src=RASA_BADGE;if(im.complete)r()});
    ok('1. The approved RASA badge replaces the earlier pose frames, in the panel and on the floating button',typeof RASA_FRAMES==='undefined'&&/^data:image\/webp/.test(RASA_BADGE)&&im.naturalWidth===640&&im.naturalHeight===640&&q('.rasa-badge').src===RASA_BADGE&&$('#rasaFace').src===RASA_BADGE,[im.naturalWidth,im.naturalHeight]);
    ok('2. Shown as the circular badge',getComputedStyle(av).borderRadius==='50%'&&Math.abs(av.offsetWidth-av.offsetHeight)<1);
    ok('3. At rest nothing is drawn over the badge: no eyelids, no mouth, no light',av.dataset.act==='idle'&&av.dataset.mood==='calm'&&q('.rl-eyes').style.display==='none'&&q('.rl-mouth').style.display==='none'&&cs('.rl-ear').opacity==='0'&&cs('.rasa-orbit').opacity==='0'&&cs('.rasa-glow').boxShadow==='none');
    ok('4. At rest the frame loop sleeps',RasaLive.raf===0,RasaLive.raf);
    // blinking
    RasaLive.blink={t:now,dbl:false};let shown=0,full=0;run(320,()=>{if(q('.rl-eyes').style.display==='')shown++});
    RasaLive.blink={t:now,dbl:false};run(85);const lid=q('.rl-eyes .lid').getBBox();full=q('.rl-eyes').style.display===''?1:0;run(300);
    ok('5. A blink closes in 70 ms, holds and opens again, about 0.2 s in all',shown>=10&&shown<=14&&q('.rl-eyes').style.display==='none',shown*16+' ms');
    const E=RASA_ANCHORS.eyes[0],xs=E.band.map(p=>p[0]),ys=E.band.map(p=>p[1]).concat(E.bot.map(p=>p[1]));
    ok('6. The eyelids sit on the badge\'s own eyes',full&&lid.x>=Math.min(...xs)-3&&lid.x+lid.width<=Math.max(...xs)+3&&lid.y>=Math.min(...ys)-3&&lid.y+lid.height<=Math.max(...ys)+3,lid);
    ok('7. The next blink is always scheduled, about every 4 seconds',(RasaLive.blinkSoon(),!!RasaLive.bt));clearTimeout(RasaLive.bt);
    // the mouth
    const T=rasaLipTimeline('Mama, look.',1),at=c=>T.find(x=>x.i===c).s;
    ok('8. Mouth shapes from the text: closed on m, b and p and at a full stop; open on the vowels; about 60 ms a letter',at(0)[0]===0&&at(1)[0]>.8&&at(10)[0]===0&&at(7)[2]>.8&&at(10)&&T[10].t>500&&T[10].t<900,T[10].t);
    RasaLip.start('One two three four five six seven',1);RasaLip.t0=now;const i=RasaLip.marks.find(x=>x.i===20);RasaLip.at(20);
    ok('9. Each word boundary from the voice puts the mouth back in step',Math.abs((performance.now()-RasaLip.t0)-i.t)<20);
    RasaLip.t0=now;let open=0,seen=0;run(1500,()=>{open=Math.max(open,RasaLive.mouth.open);if(q('.rl-mouth').style.display==='')seen++});
    ok('10. While RASA speaks: the activity is speaking and the mouth moves',av.dataset.act==='speaking'&&open>.6&&seen>20,{open,seen});
    ok('11. The mouth opens on the badge\'s own mouth line',(()=>{const b=q('.rl-mouth .in').getBBox(),M=RASA_ANCHORS.mouth;return b.x>=M.l[0]-8&&b.x+b.width<=M.r[0]+8&&b.y>=M.l[1]-12&&b.y<=M.r[1]+40})(),q('.rl-mouth .in').getBBox());
    RasaLip.stop();run(500);ok('12. When the voice ends the mouth closes and RASA is idle again',av.dataset.act==='idle'&&RasaLive.mouth.open===0&&q('.rl-mouth').style.display==='none');
    // states
    const still=document.createElement('style');still.textContent='.rasa-av *{transition:none!important}';document.head.appendChild(still);
    const st={};for(const s of ['LISTENING','THINKING','WARNING','SUCCESS','IMPORTANT_INSIGHT']){RASA.tok++;RasaState.set(s,{stay:true});await wait(450);st[s]={act:av.dataset.act,mood:av.dataset.mood,ear:+cs('.rl-ear').opacity,orbit:cs('.rasa-orbit').animationName,glow:cs('.rasa-glow').animationName+' '+cs('.rasa-glow').boxShadow.slice(0,22)}}
    ok('13. Listening: the AI ear-cup lights and a ripple runs round the badge',st.LISTENING.act==='listening'&&st.LISTENING.ear>.4&&/rasaListen/.test(st.LISTENING.glow),st.LISTENING);
    ok('14. Thinking: a light runs round the ring and the ear-cup pulses',st.THINKING.act==='thinking'&&st.THINKING.orbit==='rasaSpin'&&st.THINKING.ear>.5,st.THINKING);
    ok('15. Warning, done and insight light the ring amber, green and gold',st.WARNING.mood==='warn'&&/rasaWarn/.test(st.WARNING.glow)&&/rgba\(34, 197, 94/.test(st.SUCCESS.glow)&&/rgba\(250, 204, 21/.test(st.IMPORTANT_INSIGHT.glow),st);
    still.remove();RasaState.set('SHOWING_RESULTS',{frame:'results_left',stay:true});ok('16. Pointing at a tile, the badge leans toward it',av.dataset.pose==='left'&&av.dataset.mood==='present');
    RASA.tok++;RasaState.set('IDLE');
    const r=av.getBoundingClientRect();RasaLive.look(r.right+400,r.top+r.height/2);run(1200);
    ok('17. Attention: the badge turns a few degrees toward the pointer',parseFloat(av.style.getPropertyValue('--ry'))>2&&parseFloat(av.style.getPropertyValue('--ry'))<=4,av.style.getPropertyValue('--ry'));
    RasaLive.aim={x:0,y:0};run(1500);
    // Phase 2: a Live2D rig takes the badge's place with the same pose
    const P={},M={mount:el=>{M.el=el},setParam:(k,v)=>{P[k]=v}};RASA.adapters.avatar=rasaLive2DRenderer(M);
    const tmp=document.createElement('div');tmp.className='rasa-av';document.body.appendChild(tmp);RasaLive.mount();
    RasaLive.blink={t:now,dbl:false};run(85);const shut=P.ParamEyeLOpen;RasaLip.start('aaaa',1);RasaLip.t0=now;run(200);
    ok('18. Phase 2: a Live2D rig mounts in the avatar\'s place and gets the pose as Cubism parameters',M.el===tmp&&tmp.dataset.live==='rig'&&shut<.2&&P.ParamMouthOpenY>.5&&'ParamAngleX' in P&&'ParamBreath' in P,Object.assign({shut},P));
    RasaLip.stop();run(300);tmp.remove();RASA.adapters.avatar=keep.avatar;
    // Phase 3: speech with visemes
    let calls=0;RASA.adapters.tts={name:'Mock speech',speak:(t,h)=>{calls++;h.viseme(2,0);h.viseme(21,300);h.viseme(7,500);h.start();return new Promise(ok2=>setTimeout(()=>{h.end();ok2()},60))}};
    RasaVoiceControl.speak('<p>Test</p>');RasaLip.t0=now;let a=0,b2=1,c=0;run(700,t=>{const e=t-RasaLip.t0;if(e>150&&e<250)a=Math.max(a,RasaLive.mouth.open);if(e>420&&e<480)b2=Math.min(b2,RasaLive.mouth.open);if(e>650)c=Math.max(c,RasaLive.mouth.round)});
    ok('19. Phase 3 speech: visemes drive the mouth, including those that arrive before the audio starts',calls===1&&a>.6&&b2<.2&&c>.6,{a,b2,c});
    await wait(120);ok('20. Phase 3 speech: when it ends RASA is idle again',!RasaLip.on&&RasaState.cur==='IDLE');
    let fell=0;aiSpeakOn=true;speak=()=>{fell++};RASA.adapters.tts={speak:()=>Promise.reject(new Error('no token'))};RasaVoiceControl.speak('Hello');await wait(50);
    ok('21. Phase 3 speech: if the speech service fails, the browser\'s own voice reads the answer',fell===1);speak=keep.speak;aiSpeakOn=keep.on;
    const V=RASA_AZURE_VISEMES;ok('22. All 22 Azure viseme IDs have a mouth shape; silence and p, b, m are closed',V.length===22&&V.every(v=>v.length===3)&&V[0][0]===0&&V[21][0]===0);
    RASA.adapters.tts=keep.tts;
    // Phase 3: the enterprise language model through the ProTrack server
    let sent=null;RASA.adapters.llm={name:'Mock enterprise AI',ask:async x=>{sent=x;return {answer:'Riyadh Metro is **on track**.',sources:[{title:'Daily reports, 21 Sep'}]}}};
    const nq='qqzx vvbnm ttrq '+Date.now();await ask(nq);await wait(100);const last=state.chat[state.chat.length-1];
    ok('23. Phase 3 AI: the question goes to the enterprise model with the role and the projects in scope; the answer is labelled with its records',
      sent&&sent.question===nq&&sent.role===state.role&&sent.projects.length===SCOPE.size&&/on track/.test(last.h)&&/Enterprise AI answer/.test(last.h)&&/Daily reports, 21 Sep/.test(last.h),sent&&{q:sent.question,role:sent.role,n:sent.projects.length});
    RASA.adapters.llm=keep.llm;state.chat=state.chat.filter(m=>!(m.t===nq)&&m!==last);
    // off by default
    state.adminTab='system';go('admin');await wait(300);const v=$('#view').innerText;
    ok('24. Azure Speech and the enterprise AI are off by default, waiting for IT and Cybersecurity approval; Settings says so',!RASA_ENTERPRISE.speech.approved&&!RASA_ENTERPRISE.ai.approved&&!keep.tts&&!keep.llm&&/RASA avatar\tThe approved RASA badge/.test(v)&&/Azure Speech is off until IT and Cybersecurity approve it/.test(v)&&/Enterprise AI\tOff until IT and Cybersecurity approve it/.test(v));
    ok('25. Version 3.33 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=33&&new RegExp('ProTrackAI\\tv'+APP_VERSION.replace(/\./g,'\\.')).test(v));
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{RASA.adapters.tts=keep.tts;RASA.adapters.llm=keep.llm;RASA.adapters.avatar=keep.avatar;speak=keep.speak;aiSpeakOn=keep.on;RasaLip.stop()}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`RASA live avatar: ${res.length-f} passed, ${f} failed. Reloading…`);
  window.__avatarChecks=res;try{sessionStorage.setItem('avatarChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
