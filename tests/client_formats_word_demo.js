/* ProTrackAI v3.46: client report formats for Word reports (the SEC monthly progress report): page levels (2.1, 2.2 …), portrait
   and landscape pages, the revision record and invoices from ProTrack, the report number, the header line and table colours, a
   format drafted from a client's Word document, and the Word, PDF and PowerPoint files. Acceptance checks for the demo page.
   How to run: open demo.html, sign in with the demo Super Admin account (U28), open the browser console and paste this whole
   file. It saves this browser's demo data first and puts it back at the end, then reloads the page. */
(async()=>{
  const KEYDATA=localStorage.getItem(KEY),res=[],ok=(n,c,d)=>res.push({check:n,result:c?'PASS':'FAIL',detail:d===undefined?'':typeof d==='string'?d.slice(0,300):JSON.stringify(d).slice(0,300)});
  const as=id=>{state.uid=id;state.role=userById(id).role;state.scope='ALL';SCOPE=scopeIds()},wait=ms=>new Promise(r=>setTimeout(r,ms)),keep=saveFile,keepToast=toast,toasts=[],files={};
  try{
    const sa=me().id,pid='QOT',per='2026-09',pl=teamOf(pid,'plan')[0];window.toast=m=>toasts.push(m);await loadLib(LIBS.zip);await loadLib(LIBS.docx);const X=window.docx;
    ok('1. Version 3.46 or later',+APP_VERSION.split('.')[0]===3&&+APP_VERSION.split('.')[1]>=46,APP_VERSION);
    const F2=crfById('F2');
    ok('2. The SAMPLE SEC monthly format (headings and columns only) is used for the monthly client report, the weekly format for the weekly one',!!F2&&/SAMPLE/.test(F2.name)&&crfFor(pid,'month')===F2&&crfFor(pid,'week')!==F2&&F2.style.orient==='portrait'&&F2.sections.some(s=>s.lvl===2)&&F2.sections.some(s=>s.orient==='landscape'),F2&&F2.name);
    const base=JSON.parse(JSON.stringify(F2));const chk=o=>crfCheck(Object.assign(JSON.parse(JSON.stringify(base)),o));
    ok('3. The checks take levels 1 and 2, portrait or landscape, the revision record and invoices; they refuse level 3, another orientation and a bad colour',
      chk({})===null&&/level is 1/.test(chk({sections:[{key:'a',title:'X',src:'auto:invoices',lvl:3}]}))&&/portrait or landscape/.test(chk({sections:[{key:'a',title:'X',src:'auto:revisions',orient:'diagonal'}]}))&&/hex codes/.test(chk({style:Object.assign({},base.style,{th:'olive'})})));
    /* a client's Word report drawn here: title lines, headings at two levels, a table, a landscape section, a footer */
    const H=(t,l)=>new X.Paragraph({heading:l===2?X.HeadingLevel.HEADING_2:X.HeadingLevel.HEADING_1,children:[new X.TextRun({text:t,color:'3B4121'})]}),Pp=t=>new X.Paragraph({children:[new X.TextRun(t)]});
    const tb=(cols)=>new X.Table({rows:[new X.TableRow({children:cols.map(c=>new X.TableCell({shading:{fill:'E6E9D5'},children:[Pp(c)]}))}),new X.TableRow({children:cols.map(()=>new X.TableCell({children:[Pp('x')]}))})]});
    const ft={default:new X.Footer({children:[Pp('CLASSIFICATION: Public')]})};
    const D=new X.Document({sections:[{footers:ft,children:[new X.Paragraph({heading:X.HeadingLevel.TITLE,children:[new X.TextRun('Sample project (SAMPLE)')]}),new X.Paragraph({heading:X.HeadingLevel.TITLE,children:[new X.TextRun('Monthly Progress Report No. 12')]}),
        H('1 Project Details',1),H('2 Project description',1),H('2.1 Scope of works',2),tb(['Scope Description','Details']),H('3 Quality - Site A',1),tb(['Item','This month','Cumulative till date']),H('Quality – Site B',1),tb(['Item','This month','Cumulative till date'])]},
      {properties:{page:{size:{orientation:X.PageOrientation.LANDSCAPE}}},footers:ft,children:[H('4 Financial',1),tb(['Sl. No','Activity','Amount','Status']),H('5 Escalated Issues',1),tb(['#','Escalated Issue','Date of Escalation'])]}]});
    const WF=await crfFromDocx(new File([await X.Packer.toBlob(D)],'Client Monthly Report_Oct-26.docx')),sec=t=>WF.sections.find(s=>s.title===t)||{};
    ok('4. A format drafted from a client\'s Word report: headings as pages at their level (numbers taken off), the table under a heading as its columns, sites kept once',
      WF.sections.map(s=>s.title).join('|')==='Cover page|Project Details|Project description|Scope of works|Quality|Financial|Escalated Issues'&&sec('Scope of works').lvl===2&&sec('Scope of works').cols.join()==='Scope Description,Details'&&sec('Quality').cols.join()==='Item,This month,Cumulative till date'&&sec('Project Details').src==='auto:info'&&sec('Financial').src==='auto:invoices'&&sec('Escalated Issues').src==='manual:table',WF.sections.map(s=>s.title+'→'+s.src));
    ok('5. … and the landscape pages, the footer, the table heading colour, the report title with its number, a monthly format',sec('Financial').orient==='landscape'&&sec('Quality').orient==='portrait'&&WF.style.footer==='CLASSIFICATION: Public'&&WF.style.th==='E6E9D5'&&WF.style.report==='Monthly Progress Report'&&WF.style.sub==='{report} No. {report_no}'&&WF.periods.join()==='month'&&!crfCheck(WF),WF.style);
    // 6-8: the monthly report in ProTrack
    as(pl.id);state.clTab='fmt';openClientRelease(pid,'month',per);await wait(200);const P0=$('#crPanel').innerText;
    ok('6. The monthly client report\'s tab numbers its pages by level (2.1, 2.2 …)',/SEC monthly progress report \(SAMPLE format\)/.test(P0)&&/\n2\.1\n/.test(P0)&&/\n5\.3\n/.test(P0),P0.slice(0,200));
    [...document.querySelectorAll('#sheet button')].find(b=>/^Save draft$/i.test(b.textContent.trim())).click();await wait(700);
    (DB.invoices=DB.invoices||{})[pid]=[{no:'INV-001 (SAMPLE)',date:'2026-08-30',type:'Progress',amount:1250000,sub:1250000,sub_date:'2026-09-02',appr:1200000,appr_date:'2026-09-20',coll:0,note:'IPC 1'}];
    const doc=await crDoc(pid,'month',per),pg=t=>doc.pages.find(x=>x.s.title===t);
    ok('7. Numbers by level; the cover, revision record and index carry none; {report_no} counts the months from the project start',pg('Project Details').num==='1'&&pg('Scope of Works').num==='2.1'&&pg('Approved Suppliers and Subcontractors').num==='2.5'&&pg('Financial').num==='6'&&pg('Document Revision Record').num===null&&pg('Index').num===null&&doc.M.report_no===String((2026-+projById(pid).start.slice(0,4))*12+9-+projById(pid).start.slice(5,7)+1),doc.M.report_no);
    const rv=pg('Document Revision Record').blocks[0],iv=pg('Financial').blocks[0];
    ok('8. The revision record comes from the report\'s revisions and the Financial page from the invoice register',rv.cols.join()==='Rev,Description,Prepared,Checked,Approved,Date'&&rv.rows[0][0]==='0'&&rv.rows[0][1]==='First issue'&&iv.rows.length===1&&iv.rows[0][1].startsWith('INV-001')&&iv.rows[0][5]==='Approved',iv.rows);
    // 9-11: the files
    saveFile=async(n,b)=>{files[n]=b};await crExport(pid,'month',per,'docx','review',false);await crExport(pid,'month',per,'pdf','client',true);await crExport(pid,'month',per,'pptx','client',true);saveFile=keep;
    const nm=Object.keys(files),dz=await JSZip.loadAsync(await files[nm.find(n=>/docx$/.test(n))].arrayBuffer()),dx=await dz.file('word/document.xml').async('string'),hd=(await Promise.all(Object.keys(dz.files).filter(k=>/word\/header\d*\.xml$/.test(k)).map(k=>dz.file(k).async('string')))).join('');
    ok('9. Word: numbered headings at two levels, a table of contents updated on opening, portrait and landscape sections, the header line, the table heading colour',
      /2\.1  Scope of Works/.test(dx)&&/Heading2/.test(dx)&&/TOC/.test(dx)&&/updateFields/.test(await dz.file('word/settings.xml').async('string'))&&(dx.match(/w:orient="landscape"/g)||[]).length>=2&&/w:fill="E6E9D5"/.test(dx)&&/Monthly Progress Report : 30 Sept 2026/.test(hd));
    const pdf=await (await pvPdfLib()).getDocument({data:new Uint8Array(await files[nm.find(n=>/pdf$/.test(n))].arrayBuffer())}).promise,o=[];for(let i=1;i<=pdf.numPages;i++){const v=(await pdf.getPage(i)).view;o.push(v[2]>v[3]?'L':'P')}
    ok('10. PDF: the portrait pages and the landscape pages as the format says',o[0]==='P'&&o.includes('L')&&o.filter(x=>x==='P').length>o.filter(x=>x==='L').length,o.join(''));
    const pz=await JSZip.loadAsync(await files[nm.find(n=>/pptx$/.test(n))].arrayBuffer()),tx=[];for(const k of Object.keys(pz.files).filter(k=>/^ppt\/slides\/slide\d+\.xml$/.test(k)))tx.push(await pz.file(k).async('string'));
    ok('11. PowerPoint: the slide titles numbered too',tx.some(x=>/2\.1  Scope of Works/.test(x))&&tx.some(x=>/6  Financial/.test(x)));
    // 12: the editor
    as(sa);state.adminTab='crf';state.crfEdit=JSON.parse(JSON.stringify(F2));go('admin');await wait(100);const th=[...document.querySelectorAll('#crfForm .crfsec th')].map(x=>x.textContent);
    const e=state.crfEdit;e.sections[3].lvl=2;e.sections[3].orient='landscape';e.style.th='DDDDDD';await crfSave(e);const s3=crfById('F2').sections[3];state.crfEdit=null;
    ok('12. Settings: each page\'s level and orientation, the table heading colours, header line and page orientation are kept with the format',th.includes('Level')&&th.includes('Page')&&/Header line/.test($('#view').innerText)&&s3.lvl===2&&s3.orient==='landscape'&&crfById('F2').style.th==='DDDDDD'&&crfById('F2').rev===2);
    {const x=document.querySelector('#sheet [data-close]');if(x)x.click()}
  }catch(x){ok('The checks ran to the end',false,x.message+' '+(x.stack||'').split('\n')[1])}
  finally{saveFile=keep;window.toast=keepToast;try{localStorage.setItem(KEY,KEYDATA)}catch(x){}}
  console.table(res);const f=res.filter(r=>r.result==='FAIL').length;console.log(`Client report formats for Word: ${res.length-f} passed, ${f} failed. Restoring the demo data and reloading…`);
  window.__cwChecks=res;try{sessionStorage.setItem('cwChecks',JSON.stringify(res))}catch(x){}setTimeout(()=>location.reload(),1500);
})();
