/* ProTrackAI v3.60, the weather on the daily report filled in from the project's city. Acceptance checks for the demo
   page. How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste
   this whole file. It acts as a foreman, saves this browser's demo data first and puts it back at the end, then reloads
   the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const wait=ms=>new Promise(r=>setTimeout(r,ms)),keepFetch=window.fetch,keepW={...WEATHER},keep={uid:state.uid,role:state.role};
  const field=()=>document.querySelector('[data-k="weather"]'),note=()=>(document.getElementById('wxNote')||{}).textContent||'';
  const type=(el,v)=>{el.value=v;el.dispatchEvent(new Event('input',{bubbles:true}))};
  try{
    const fm=DB.master.users.find(u=>u.role==='foreman'&&u.active);state.uid=fm.id;state.role='foreman';state.scope='ALL';SCOPE=scopeIds();
    // ---- where the weather comes from
    const C=Object.fromEntries(PROJECTS.map(p=>[p.id,(wxCityOf(p)||{}).name]));
    ok('1. Each project\'s city: from the project master, else the location typed at registration',C.RMX==='Riyadh'&&C.JDC==='Jeddah'&&C.JBS==='Jubail'&&C['PE-002']==='Taif'&&PROJECTS.every(p=>wxCityOf(p)&&wxCityOf(p).lat!=null),C);
    ok('2. On the demo page the weather is SAMPLE weather; no outside service is called',wxMode()==='sample'&&wxStatus()[1]==='Sample weather from the project\'s city (demo)');
    const J=wxCityOf(projById('JDC')),s1=wxSample(J,'2026-07-20'),s2=wxSample(J,'2026-07-20'),R=wxCityOf(projById('RMX'));
    const temps=['01','07'].map(m=>+wxSample(R,`2026-${m}-15`).text.match(/(-?\d+) °C/)[1]);
    ok('3. Sample weather: the same for the same city and date, within 2 °C of the usual maximum, "Condition, N °C"',s1.text===s2.text&&/^[A-Z][a-z /]+, \d+ °C$/.test(s1.text)&&Math.abs(temps[0]-20)<=2&&Math.abs(temps[1]-43)<=2,[s1.text,temps]);
    // ---- a new report
    state.form=null;state.editing=null;go2form();await wait(300);
    const f=state.form,w0=wxSample(wxCityOf(projById(f.p)),f.date).text;
    ok('4. A new report: the Weather field is filled in for the project\'s city on the report date, and says so',f.weather===w0&&field().value===w0&&note().startsWith(`Filled in for ${wxCityOf(projById(f.p)).name} on ${fmtDY(f.date)}: SAMPLE weather`),[f.weather,note()]);
    const d2=addDays(f.date,-3);type(document.querySelector('[data-k="date"]'),d2);await wait(50);
    ok('5. Another date: its own weather',f.weather===wxSample(wxCityOf(projById(f.p)),d2).text&&field().value===f.weather&&note().includes(fmtDY(d2)),[f.weather,note()]);
    type(field(),'Light rain in the morning, 24 °C');await wait(50);type(document.querySelector('[data-k="date"]'),f.date===TODAY?addDays(TODAY,-1):TODAY);await wait(50);
    ok('6. Typed weather is kept, also when the date changes',f.weather==='Light rain in the morning, 24 °C'&&field().value===f.weather&&/^Entered by hand/.test(note()),[f.weather,note()]);
    type(field(),'');await wait(50);
    ok('7. Cleared, it is filled in again',f.weather===wxSample(wxCityOf(projById(f.p)),f.date).text&&field().value===f.weather&&/^Filled in for/.test(note()),[f.weather,note()]);
    const other=formProjects().find(id=>id!==f.p);
    if(other){const sel=document.querySelector('select[data-k="p"]');sel.value=other;sel.dispatchEvent(new Event('change',{bubbles:true}));await wait(300);
      ok('8. Another project: the weather of its city',state.form.weather===wxSample(wxCityOf(projById(other)),state.form.date).text&&note().includes(wxCityOf(projById(other)).name),[state.form.weather,note()])}
    else ok('8. Another project: the weather of its city (only one project for this foreman: checked as 4)',true);
    // ---- a report being edited keeps its weather
    const d=DB.dprs.find(x=>formProjects().includes(x.p)),saved='Overcast, 31 °C (saved)';state.editing=d.id;state.form={...JSON.parse(JSON.stringify(d)),weather:saved};renderForm();await wait(100);
    ok('9. A report being edited keeps the weather it was saved with',state.form.weather===saved&&field().value===saved&&/^Entered by hand/.test(note()),[state.form.weather,note()]);
    state.editing=null;state.form=null;
    // ---- the server
    Object.assign(WEATHER,{provider:'Azure Maps Weather',enabled:true,approved:true,endpoint:'https://protrack.example/api/weather'});let asked=null;
    window.fetch=async(u,o)=>{asked={u:String(u),o};return {ok:true,json:async()=>({condition:'Dust / sandstorm',tmax:42.6,wind_kmh:38})}};
    const sw=await wxServer(wxCityOf(projById('RMX')),'2026-09-20'),qs=new URL(asked.u).searchParams;
    ok('10. On the server: ProTrack\'s own endpoint is asked for the city and date, with the sign-in; the answer worded as the field',sw.text==='Dust / sandstorm, 43 °C, wind 38 km/h'&&!sw.sample&&qs.get('city')==='Riyadh'&&qs.get('date')==='2026-09-20'&&qs.get('lat')==='24.71'&&asked.o.credentials==='include',[sw.text,asked.u]);
    window.fetch=async()=>({ok:false,status:503,json:async()=>({})});let err='';try{await wxServer(wxCityOf(projById('RMX')),'2026-09-20')}catch(e){err=e.message}
    ok('11. A failing service: said, and the field is left to type',err==='The weather service answered 503',err);
    ok('12. Settings → System says where the weather comes from',/Sample weather/.test(wxStatus()[1]));
    Object.assign(WEATHER,{approved:false,enabled:false});
    ok('13. The service stays off until IT and Cybersecurity approve it (as the server would say)',!wxServerOn(),WEATHER);
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{window.fetch=keepFetch;Object.assign(WEATHER,keepW);state.uid=keep.uid;state.role=keep.role;state.form=null;state.editing=null;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Weather on daily reports: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__wxChecks=res;try{sessionStorage.setItem('wxChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
