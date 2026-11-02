/* ProTrackAI v3.51: the sign-in page in the approved desktop and mobile design, with the logo opening (needle and tagline). Acceptance checks for the demo page. How to run: open
   demo.html signed out (sign out first if needed), open the browser console and paste this whole file. Run it again after changing the
   window size (or the device size in the developer tools) to check each layout: 320, 360, 375, 390, 430, 768, 1024, 1280, 1366, 1440
   and 1920 pixels wide. It tries a wrong password (one counted attempt, cleared at the end) and never signs in. */
(async()=>{
  const res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const wait=ms=>new Promise(r=>setTimeout(r,ms)),A=document.getElementById('auth'),q=s=>A.querySelector(s),R=e=>e.getBoundingClientRect();
  const ov=(a,b)=>{a=R(a);b=R(b);return a.left<b.right-1&&a.right>b.left+1&&a.top<b.bottom-1&&a.bottom>b.top+1};
  try{
    if(A.hidden){ok('Signed out: the sign-in page is showing',false,'Sign out first, then paste the file again');throw new Error('signed in')}
    const W=innerWidth,mobile=W<768;
    // branding and images
    const logo=q('.lg-pt img'),rasa=q('.lg-rasa');
    ok('1. The original ProTrack logo, undistorted (520 x 131)',logo.src===LOGO&&logo.naturalWidth===520&&Math.abs(R(logo).width/R(logo).height-520/131)<.02,[logo.naturalWidth,logo.naturalHeight]);
    ok('2. The alfanar Projects slot: the official file when ALFANAR_LOGO is set, a labelled placeholder until then',ALFANAR_LOGO?!!q('#lgAlfanar img'):!!q('#lgAlfanar .lg-af-ph')&&/placeholder/i.test(q('#lgAlfanar .lg-af-ph').title));
    ok('3. RASA is the approved badge, shown whole and round, not cropped',rasa.src===RASA_BADGE&&rasa.naturalWidth===640&&Math.abs(R(rasa).width-R(rasa).height)<1&&getComputedStyle(rasa).objectFit==='contain');
    ok('4. Both images have alternative text',!!logo.alt&&/RASA/.test(rasa.alt));
    // content
    const caps=[...A.querySelectorAll('.lg-caps li b')].map(b=>b.innerText.trim()),flow=[...A.querySelectorAll('.lg-flow li b')].map(b=>b.innerText.trim());
    ok('5. Four capabilities: Initiation & Setup, Scheduling & Progress, Costing & EAC, Cash Flow (and Reports on phones)',caps.length===4&&caps[0]==='Initiation & Setup'&&caps[1]==='Scheduling & Progress'&&caps[2]==='Costing & EAC'&&/^Cash Flow/.test(caps[3]),caps);
    ok('6. The workflow runs from Initiation & Setup to the reports dashboard, six stages',flow.length===6&&flow[0]==='Initiation & Setup'&&/Dashboard/.test(flow[5]),flow);
    ok('7. No tendering stage and no 4D BIM or digital twin on the page',!/tender/i.test(A.innerText)&&!/\bBIM\b|digital twin/i.test(A.innerText));
    ok('8. The headline for this width',q('.lg-copy h1').innerText.trim()===(mobile?'Integrated Project Controls Platform':'From Initiation to Delivery in One Platform'),q('.lg-copy h1').innerText);
    ok('9. RASA speech bubble: RASA, Your AI Project Assistant',/RASA/.test(q('.lg-bubble').innerText)&&/Your AI Project Assistant/.test(q('.lg-bubble').innerText.replace(/\s+/g,' ')));
    ok('10. No Microsoft 365 button (no integration) and no language switch (the sign-in text is English only)',!/Microsoft/i.test(A.innerText)&&!A.querySelector('select'));
    // layout at this width
    const b=R(rasa),bu=R(q('.lg-bubble')),p={x1:(bu.left-b.left)/b.width,x2:(bu.right-b.left)/b.width,y1:(bu.top-b.top)/b.height,y2:(bu.bottom-b.top)/b.height};
    const hit=z=>p.x1<z.x2&&p.x2>z.x1&&p.y1<z.y2&&p.y2>z.y1;
    ok(`11. ${W}px: no sideways scrolling of the page`,A.scrollWidth<=A.clientWidth,[A.scrollWidth,A.clientWidth]);
    ok(`12. ${W}px: the bubble covers neither RASA's face nor the helmet`,!hit({x1:.28,x2:.56,y1:.2,y2:.47})&&!hit({x1:.23,x2:.57,y1:.06,y2:.30}),p);
    ok(`13. ${W}px: nothing lies over the sign-in card`,!ov(q('.lg-bubble'),q('.lg-card'))&&!ov(rasa,q('.lg-card'))&&!ov(q('.lg-flow'),q('.lg-card'))&&!ov(q('.lg-caps'),q('.lg-card')));
    ok(`14. ${W}px: the capability tiles clear RASA`,!ov(q('.lg-caps'),rasa)&&!ov(q('.lg-caps'),q('.lg-bubble')));
    const order=['.lg-head','.lg-copy','.lg-hero','.lg-caps','.lg-card','.lg-flow'].map(s=>R(q(s)).top);
    ok(`15. ${W}px: ${mobile?'phone order: logos, headline, RASA, tiles, sign-in, workflow':'the workflow runs below the sign-in card'}`,mobile?order.every((t,i)=>!i||t>=order[i-1]-1):R(q('.lg-flow')).top>=R(q('.lg-card')).bottom-1,order.map(Math.round));
    ok(`16. ${W}px: the fields and the button are easy to tap (44 px or more)`,R(q('#lgId')).height>=44&&R(q('#lgPw')).height>=44&&R(q('#lgBtn')).height>=44&&R(q('#lgEye')).width>=40);
    ok(`17. ${W}px: ${W<360?'two by two':'four'} capability tiles a row`,getComputedStyle(q('.lg-caps')).gridTemplateColumns.split(' ').length===(W<360?2:W<1024?4:2));
    // the form
    ok('18. Labels for both fields; errors linked and announced',!!A.querySelector('label[for=lgId]')&&!!A.querySelector('label[for=lgPw]')&&q('#lgId').getAttribute('aria-describedby')==='lgIdErr'&&q('#lgErr').getAttribute('role')==='alert');
    q('#lgId').value='';q('#lgPw').value='';q('#lgBtn').click();await wait(30);
    ok('19. An empty username is refused with a message',q('#lgIdErr').textContent==='Enter your username or email.');
    q('#lgPw').value='abc';q('#lgEye').click();const shown=q('#lgPw').type,lab=q('#lgEye').getAttribute('aria-label');q('#lgEye').click();
    ok('20. The eye shows and hides the password, and says which',shown==='text'&&lab==='Hide password'&&q('#lgPw').type==='password');
    const id='asarudeen@company.com';q('#lgId').value=id;q('#lgPw').value='not-the-password';q('#lgBtn').click();
    const busy=q('#lgBtn').innerText.trim(),dis=q('#lgBtn').disabled,ab=q('#lgBtn').getAttribute('aria-busy');await wait(1500);
    ok('21. While checking: Signing in…, disabled, aria-busy',busy==='Signing in…'&&dis&&ab==='true',{busy,dis,ab});
    ok('22. A wrong password: the message, the button back to normal, the password cleared',/incorrect/.test(q('#lgErr').textContent)&&q('#lgBtn').innerText.trim()==='Sign in'&&!q('#lgBtn').disabled&&q('#lgPw').value==='',q('#lgErr').textContent);
    ok('23. A failed sign-in does not replay the opening',!A.classList.contains('lg-play'));
    clearFails(id);q('#lgErr').textContent='';
    q('[data-auth=forgot]').click();await wait(30);const fg=q('#authCard h2').textContent;q('[data-auth=login]').click();await wait(30);
    ok('24. Forgot password opens the reset form and comes back',fg==='Reset your password'&&q('#authCard h2').textContent==='Sign in to ProTrack');
    ok('25. Demo page: the sample-data note, the demo accounts and the team sign-in link',/Demo page with sample data/.test(q('#authCard').innerText)&&A.querySelectorAll('details.demo').length===1&&A.querySelectorAll('#authCard a[href="live.html"]').length===1);
    // motion
    let rm='';for(const sh of document.styleSheets){let rs;try{rs=sh.cssRules}catch(e){continue}for(const r of rs)if(r.media&&/prefers-reduced-motion/.test(r.media.mediaText)&&/#auth \*/.test(r.cssText))rm=r.cssText}
    ok('26. Reduced motion switches every sign-in animation off',/animation[^;]*none !important/.test(rm)&&/transition: none !important/.test(rm));
    ok('27. The opening plays once per page load and has finished',lgPage.played===true&&!A.classList.contains('lg-play'));
    const nd=q('.lg-pt-ndl'),tg=q('.lg-pt-tag'),cs=e=>getComputedStyle(e);
    ok('28. Logo opening: the needle and tagline layers are cut from the logo itself and, at rest, match it (not turned, fully shown, nothing hidden)',
      [nd,tg].every(e=>cs(e).backgroundImage.includes(LOGO.slice(0,60)))&&/circle/.test(cs(nd).clipPath)&&cs(nd).transform==='none'&&cs(tg).opacity==='1'&&cs(logo).clipPath==='none');
    ok('29. Logo opening: the needle spins and settles, the tagline fades in, within about 3 seconds',(()=>{const k=n=>[...document.styleSheets].flatMap(s=>{try{return [...s.cssRules]}catch(e){return []}}).find(r=>r.name===n);
      const a=k('lgNeedle'),b=k('lgTag');return !!a&&!!b&&/rotate\(-450deg\)/.test(a.cssText)&&/opacity: 0/.test(b.cssText)})());
  }catch(e){if(e.message!=='signed in')ok('Unexpected error',false,e.stack||e.message)}
  finally{console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Sign-in page (${innerWidth}px): ${res.length-f} passed, ${f} failed.`);window.__loginChecks=res}
})();
