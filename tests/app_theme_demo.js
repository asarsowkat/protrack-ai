/* ProTrackAI v3.52: the app theme in day and night mode. Acceptance checks for the demo page. How to run: open demo.html, sign in with any
   demo account, open the browser console and paste this whole file. It opens every screen in the menu in both modes (about a minute),
   then puts back the mode and the screen you had. */
(async()=>{
  const res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const wait=ms=>new Promise(r=>setTimeout(r,ms)),root=document.documentElement,keepTheme=root.dataset.theme,keepView=state.view;
  const rgb=c=>{c=c.trim();if(c[0]==='#'){c=c.slice(1);return [0,2,4].map(i=>parseInt(c.substr(i,2),16))}return (c.match(/[\d.]+/g)||[]).map(Number)};
  const lum=c=>{const [r,g,b,a]=rgb(c);if(a!==undefined&&a<.5)return null;const f=v=>{v/=255;return v<=.03928?v/12.92:Math.pow((v+.055)/1.055,2.4)};return .2126*f(r)+.7152*f(g)+.0722*f(b)};
  const cr=(a,b)=>{const x=lum(a),y=lum(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05)};
  const tok=n=>getComputedStyle(root).getPropertyValue('--'+n).trim();
  try{
    if(document.getElementById('app').hidden){ok('Signed in',false,'Sign in with a demo account, then paste the file again');throw new Error('signed out')}
    const pairs=[['ink','bg'],['ink-2','bg'],['ink-2','surface'],['ink-2','surface-2'],['accent','surface'],['surface','accent'],['green','surface'],['amber','surface'],['red','surface'],
      ['green','green-soft'],['amber','amber-soft'],['red','red-soft'],['side-ink','side'],['side-2','side'],['side-act-ink','side-act'],['side-2','side-hover']];
    const views=[...document.querySelectorAll('.nav .nav-item:not(.planned)')];
    for(const mode of ['light','dark']){
      root.dataset.theme=mode;await wait(150);const M=mode==='light'?'Day':'Night';
      const low=pairs.map(([a,b])=>[a+' on '+b,cr(tok(a),tok(b))]).filter(([,v])=>v<4.5);
      ok(`${M}: text and state colours reach 4.5:1 on their backgrounds`,!low.length,low.map(([k,v])=>k+' '+v.toFixed(2)));
      const side=getComputedStyle(document.querySelector('.side')).backgroundColor;
      ok(`${M}: the menu is ${mode==='light'?'white':'blue-black'}`,mode==='light'?lum(side)>.95:lum(side)<.01,side);
      ok(`${M}: the page is ${mode==='light'?'pale blue':'blue-black'} and cards are ${mode==='light'?'white':'navy'}`,
        mode==='light'?tok('bg').toUpperCase()==='#F4F8FD'&&tok('surface').toUpperCase()==='#FFFFFF':tok('bg').toUpperCase()==='#071226'&&tok('surface').toUpperCase()==='#0E1C33');
      const patches={},hidden={};
      for(const v of views){v.click();await wait(150);
        for(const e of document.querySelectorAll('#app *')){if(!e.offsetParent)continue;const cs=getComputedStyle(e);
          if(mode==='dark'){const l=lum(cs.backgroundColor),r=e.getBoundingClientRect();if(l!=null&&l>.6&&r.width*r.height>=400){const k=(typeof e.className==='string'&&e.className||e.tagName);patches[k]=v.textContent.trim()}}
          else if(e.closest('.side')&&[...e.childNodes].some(n=>n.nodeType===3&&n.textContent.trim())&&lum(cs.color)>.55){hidden[(typeof e.className==='string'&&e.className||e.tagName)]=v.textContent.trim()}}}
      if(mode==='dark')ok(`Night: no light patches on any of the ${views.length} screens in the menu`,!Object.keys(patches).length,patches);
      else ok(`Day: menu text readable on the white menu, on all ${views.length} screens`,!Object.keys(hidden).length,hidden);
      const cur=document.querySelector('.nav .nav-item[aria-current="page"]');
      ok(`${M}: the open screen is marked in the menu with the selection tint`,!!cur&&rgb(getComputedStyle(cur).backgroundColor).join()===rgb(tok('side-act')).join(),cur&&getComputedStyle(cur).backgroundColor);
      const mark=getComputedStyle(document.querySelector('.top h1'),'::before');
      ok(`${M}: the page title carries the orange mark`,rgb(mark.backgroundColor).join()===rgb(tok('brand-orange')).join(),mark.backgroundColor);
    }
    const chip=document.querySelector('.chip[aria-pressed="true"]');
    ok('Selected chips use ProTrack blue',!chip||rgb(getComputedStyle(chip).backgroundColor).join()===rgb(tok('accent')).join());
  }catch(e){if(e.message!=='signed out')ok('Unexpected error',false,e.stack||e.message)}
  finally{if(keepTheme)root.dataset.theme=keepTheme;else delete root.dataset.theme;try{go(keepView)}catch(x){}
    console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`App theme: ${res.length-f} passed, ${f} failed.`);window.__themeChecks=res}
})();
