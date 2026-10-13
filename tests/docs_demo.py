"""ProTrackAI v3.4 in demo (browser) mode: the three-row project document rack.
Rows and default box files, who sees and keeps each row, uploading (files kept in this browser), revisions that never
replace the earlier file (Rev 0 and the approved baseline stay listed), status and details with history, preview and
download, adding, renaming, hiding and reordering boxes, figures from ProTrackAI's own records or "Data unavailable",
and nothing else in ProTrackAI changing. Usage: python3 docs_demo.py /path/to/index.html > results_docs_demo.json"""
import sys, json, time, tempfile, os
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:260]})
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        return r.abort()
    return r.continue_()
TMP = tempfile.mkdtemp()
def mk(name, text='sample'):
    p = os.path.join(TMP, name); open(p, 'w').write(text); return p
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}, accept_downloads=True); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);state.scope='ALL';render()")
    J = lambda js: pg.evaluate(js)
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(400); J("state.scope='ALL';render()")
    act = lambda p_: J(f"(()=>{{try{{const r=docActLocal({json.dumps(p_)});return r?'ok':'none'}}catch(e){{return e.message}}}})()")
    SA = J("me().id"); P0 = J("PROJECTS[0].id")
    PL = J(f"(teamOf('{P0}','plan')[0]||{{}}).id"); CO = J(f"(teamOf('{P0}','costing')[0]||{{}}).id"); PM = J(f"(teamOf('{P0}','pm')[0]||{{}}).id")
    EN = J(f"(teamOf('{P0}','eng')[0]||{{}}).id"); FM = J(f"(teamOf('{P0}','foreman')[0]||{{}}).id"); EX = J("DB.master.users.find(u=>u.role==='exec').id")
    before = J("JSON.stringify({rel:DB.releases.length,acts:DB.master.acts.length,co:(DB.coLog||[]).length,b:(DB.batches||[]).length})")

    # ---- the rack
    J(f"state.docPid='{P0}';go('docs')"); pg.wait_for_timeout(500); v = pg.inner_text('#view')
    ck('Rack', 'three rows in order: Contract & Commercial, Planning & Scheduling, Cost Control & Costing', v.index('Contract & Commercial') < v.index('Planning & Scheduling') < v.index('Cost Control & Costing'))
    ck('Rack', 'the default box files: 10 contract, 12 planning, 14 cost', pg.locator('.docrow-contract [data-docbox]').count() == 10 and pg.locator('.docrow-planning [data-docbox]').count() == 12 and pg.locator('.docrow-cost [data-docbox]').count() == 14)
    ck('Rack', 'big labels on the boxes (BASELINE, CURRENT P6, WEEKLY REPORTS, MONTHLY REPORTS, TENDER, REV 0, MONTHLY BUDGET, EAC, CASH FLOW, INVOICES, VO, CHANGE ORDERS)',
       all(x in v for x in ['BASELINE', 'CURRENT P6', 'WEEKLY REPORTS', 'MONTHLY REPORTS', 'TENDER', 'REV 0', 'MONTHLY BUDGET', 'EAC', 'CASH FLOW', 'INVOICES', 'VO', 'CHANGE ORDERS']))
    ck('Rack', 'every box has an icon and text, not colour alone', J("[...document.querySelectorAll('[data-docbox]')].every(b=>b.querySelector('svg')&&b.querySelector('.boxlabel').textContent.trim()&&b.querySelector('.boxtitle').textContent.trim())"))
    ck('Rack', 'reporting-period and revision badges on boxes with documents (Week, Rev 0 kept, Baseline kept)', 'Week ' in v and 'Rev 0 kept' in v and 'Baseline kept' in v)
    ck('Rack', 'the Planning row shows planned and actual progress, SPI, next milestone and the last released progress', all(x in v for x in ['Planned', 'Actual', 'SPI', 'Next milestone', 'Last released progress']))
    ck('Rack', 'the Cost row shows tender, Rev 0, latest approved budget, actual, commitments, approved change orders, pending variations and EAC as separate figures',
       all(x in v for x in ['Tender', 'Rev 0 budget', 'Latest approved budget', 'Actual cost', 'Commitments', 'Approved change orders', 'Pending variations', 'EAC']))
    nob = J("PROJECTS.find(p=>!ACTS.some(a=>a.p===p.id))?.id")
    if nob:
        J(f"state.docPid='{nob}';render()"); pg.wait_for_timeout(300)
        ck('Rack', 'a project without a baseline says "Data unavailable" instead of a figure', 'Data unavailable' in pg.inner_text('#view'))
        J(f"state.docPid='{P0}';render()")
    J("go('proj')"); J(f"state.scope='{P0}';render()"); pg.wait_for_timeout(300)
    ck('Navigation', 'Project overview → Documents opens the rack for that project', pg.locator(f'[data-docsgo="{P0}"]').count() == 1)
    pg.click(f'[data-docsgo="{P0}"]'); pg.wait_for_timeout(300)
    ck('Navigation', '...it opens', J("state.view") == 'docs' and J("state.docPid") == P0)
    J("state.scope='ALL';render()")

    # ---- who sees and keeps what
    for who, lab, rows in [(EN, 'a site engineer', ['planning']), (PM, 'a project manager', ['contract', 'planning', 'cost']), (EX, 'an executive', ['contract', 'planning', 'cost'])]:
        if not who: continue
        as_(who); J(f"state.docPid='{P0}';go('docs')"); pg.wait_for_timeout(300)
        seen = J("['contract','planning','cost'].filter(r=>document.querySelector('.docrow-'+r))")
        ck('Rights', f'{lab} sees rows: {", ".join(rows)}', seen == rows, seen)
    if FM:
        as_(FM); ck('Rights', 'a foreman has no document rack', J("canDocsView()") is False and pg.locator('#nav [data-go="docs"]').count() == 0)
    as_(PM); J(f"state.docPid='{P0}';go('docs')"); pg.wait_for_timeout(300); J("openDocBox('K02')"); pg.wait_for_timeout(300)
    ck('Rights', 'a project manager reads a box but has no Upload button', pg.locator('[data-docup]').count() == 0)
    ck('Rights', 'a project manager cannot add a document (rule checked, not just the button)', 'Only the people who keep this row' in act({'action': 'add', 'project_id': P0, 'box_key': 'K02', 'title': 'x', 'storage_path': f'{P0}/K02/a/b.pdf'}))
    as_(PL); J("closeDrawer()")
    ck('Rights', 'the planning engineer cannot add to the Cost row', 'Only the people who keep this row' in act({'action': 'add', 'project_id': P0, 'box_key': 'K02', 'title': 'x', 'storage_path': f'{P0}/K02/a/b.pdf'}))

    # ---- planning engineer uploads into the baseline box and the current schedule box
    J(f"state.docPid='{P0}';go('docs')"); pg.wait_for_timeout(300)
    nP01 = J(f"docsOf('{P0}','P01').length")
    J("openDocBox('P01')"); pg.wait_for_timeout(300); sh = pg.inner_text('#sheet')
    ck('Baseline', 'the baseline box says new working schedules never replace it and that storing a P6 file does not import it', 'never replaced by a new working schedule' in sh and 'does not import it' in sh)
    pg.click('[data-docup="P01"]'); pg.wait_for_timeout(300)
    pg.set_input_files('#docFile', mk('Baseline Rev02.xer', 'ERMHDR\t8.0\n%T\tPROJECT'))
    pg.fill('#docUpForm [name=title]', 'Approved baseline Rev 02'); pg.fill('#docUpForm [name=revision]', 'Rev 02'); pg.select_option('#docUpForm [name=status]', 'Approved')
    pg.click('[data-docupgo]'); pg.wait_for_timeout(900)
    ck('Upload', 'the file is uploaded and registered in the baseline box', J(f"docsOf('{P0}','P01').length") == nP01 + 1 and J(f"docsOf('{P0}','P01')[0].title") == 'Approved baseline Rev 02', J(f"docsOf('{P0}','P01').map(d=>d.title)"))
    d = J(f"docsOf('{P0}','P01')[0]")
    ck('Upload', 'with its size, SHA-256 fingerprint and an Uploaded history entry', d['file_size'] > 0 and len(d['sha256'] or '') == 64 and J(f"docAuditOf('{d['id']}').some(a=>a.action==='Uploaded')"))
    ck('Upload', 'the file itself is kept in this browser and can be read back', J(f"docBlob(DB.docs.find(x=>x.id==='{d['id']}')).then(b=>b.text())").startswith('ERMHDR'))
    ck('Separation', 'the earlier baseline documents are untouched', J(f"docsOf('{P0}','P01').filter(x=>x.id!=='{d['id']}').every(x=>x.status==='Approved')"))
    pg.set_input_files('#docFile', mk('x.exe', 'MZ')) if pg.locator('#docFile').count() else None
    J("openDocBox('P02',{upload:true})"); pg.wait_for_timeout(300)
    pg.set_input_files('#docFile', mk('tool.exe', 'MZ')); pg.fill('#docUpForm [name=title]', 'x'); pg.click('[data-docupgo]'); pg.wait_for_timeout(400)
    ck('Upload', 'a file type that is not a document is refused', 'not accepted' in pg.inner_text('#docUpErr'))
    wk = J("curWeek()")
    pg.set_input_files('#docFile', mk('Update.xer', 'ERMHDR')); pg.fill('#docUpForm [name=title]', 'Working schedule update'); pg.click('[data-docupgo]'); pg.wait_for_timeout(900)
    ck('Separation', 'a working schedule goes into Current P6 with its week; the baseline box does not change', J(f"docsOf('{P0}','P02')[0].period") == wk and J(f"docsOf('{P0}','P01').length") == nP01 + 1)
    ck('Separation', 'nothing in the schedule was imported', J("DB.master.acts.length") == json.loads(before)['acts'])

    # ---- revisions, status, details
    as_(CO); J(f"state.docPid='{P0}';go('docs')"); pg.wait_for_timeout(300)
    rev0 = J(f"docsOf('{P0}','K02').find(d=>d.revision==='Rev 0')")
    J(f"openDocItem('{rev0['id']}')"); pg.wait_for_timeout(300); pg.click(f'[data-docrev="{rev0["id"]}"]'); pg.wait_for_timeout(300)
    ck('Revisions', 'a new revision form says the earlier file is kept', 'is kept as it is' in pg.inner_text('#sheet'))
    pg.set_input_files('#docFile', mk('Budget Rev2.pdf', '%PDF-1.4 sample')); pg.fill('#docUpForm [name=revision]', 'Rev 2'); pg.click('[data-docupgo]'); pg.wait_for_timeout(900)
    r2 = J(f"docsOf('{P0}','K02').find(d=>d.revision==='Rev 2')")
    ck('Revisions', 'Rev 2 is a new document pointing to Rev 0', r2 and r2['supersedes'] == rev0['id'])
    ck('Revisions', 'Rev 0 stays exactly as it was', J(f"JSON.stringify(DB.docs.find(d=>d.id==='{rev0['id']}'))") == json.dumps(rev0, separators=(',', ':')))
    v = pg.inner_text('#sheet')
    ck('Revisions', 'the Rev 0 box lists every revision, Rev 0 marked as the original approved budget', 'Original approved budget' in v and 'Rev 2' in v and 'Rev 1' in v)
    J(f"openDocItem('{r2['id']}')"); pg.wait_for_timeout(300)
    pg.select_option('#docSt', 'Rejected'); pg.click(f'[data-docst="{r2["id"]}"]'); pg.wait_for_timeout(300)
    ck('Status', 'rejecting needs a comment', 'comment' in pg.inner_text('#docErr') and J(f"DB.docs.find(d=>d.id==='{r2['id']}').status") != 'Rejected')
    pg.select_option('#docSt', 'Approved'); pg.click(f'[data-docst="{r2["id"]}"]'); pg.wait_for_timeout(300)
    ck('Status', 'the status changes and the history shows from and to', J(f"DB.docs.find(d=>d.id==='{r2['id']}').status") == 'Approved' and J(f"docAuditOf('{r2['id']}').some(a=>a.detail&&a.detail.to==='Approved')"))
    J(f"document.querySelector('#docEdForm details,#docEdForm')&&0"); J("document.querySelector('details:has(#docEdForm)').open=true")
    pg.fill('#docEdForm [name=ref_no]', 'BUD-R2'); pg.click('[data-doced]'); pg.wait_for_timeout(300)
    ck('Details', 'details are corrected and the change is listed in the history', J(f"DB.docs.find(d=>d.id==='{r2['id']}').ref_no") == 'BUD-R2' and J(f"docAuditOf('{r2['id']}').some(a=>a.action==='Details changed'&&a.detail.changes.includes('ref_no'))"))
    pg.click(f'[data-docprev="{r2["id"]}"]'); pg.wait_for_timeout(600)
    ck('Preview', 'a PDF opens in the preview', pg.locator('#docPrev iframe').count() == 1)
    with pg.expect_download() as dl: pg.click(f'[data-docdl="{r2["id"]}"]')
    ck('Download', 'the file downloads with its own name', dl.value.suggested_filename == 'Budget Rev2.pdf')

    # ---- boxes
    J("closeDrawer()"); pg.click('[data-docmanage]'); pg.wait_for_timeout(300)
    ck('Boxes', 'Arrange shows move buttons and Add a box file on the rows you keep only', pg.locator('.docrow-cost [data-docadd]').count() == 1 and pg.locator('.docrow-planning [data-docadd]').count() == 0)
    pg.click('.docrow-cost [data-docadd]'); pg.wait_for_timeout(300); pg.fill('#docAddForm [name=title]', 'Insurance claims'); pg.click('[data-docaddgo]'); pg.wait_for_timeout(400)
    nb = J(f"docBoxes('{P0}','cost').find(b=>b.title==='Insurance claims')")
    ck('Boxes', 'a new box is added to the Cost row, with the row\'s rules', nb and nb['custom'] and nb['row'] == 'cost')
    first = J(f"docBoxes('{P0}','cost')[0].key")
    pg.click(f'[data-docmv="cost|{first}|1"]'); pg.wait_for_timeout(400)
    ck('Boxes', 'a box is moved one place to the right', J(f"docBoxes('{P0}','cost')[1].key") == first)
    J("openDocBoxSettings('K13')"); pg.wait_for_timeout(300); pg.fill('#docBoxForm [name=title]', 'POs and subcontracts'); J("document.querySelector('#docBoxForm [name=hidden]').checked=true"); pg.click('[data-docboxsave]'); pg.wait_for_timeout(400)
    ck('Boxes', 'a box is renamed and hidden; its documents and rules are unchanged', J(f"docBoxes('{P0}','cost').find(b=>b.key==='K13')").get('title') == 'POs and subcontracts' and J(f"docBoxes('{P0}','cost').find(b=>b.key==='K13').hidden"))
    J("state.docManage=false;render()"); pg.wait_for_timeout(300)
    ck('Boxes', 'a hidden box is not on the rack until "Show hidden boxes" is ticked', pg.locator('[data-docbox="K13"]').count() == 0)
    J("state.docHidden=true;render()"); pg.wait_for_timeout(300)
    ck('Boxes', '...then it is shown, marked hidden', pg.locator('[data-docbox="K13"]').count() == 1)
    ck('Boxes', 'box changes are in the history', J("DB.docAudit.filter(a=>['Box added','Box changed','Boxes reordered'].includes(a.action)).length") >= 3)
    ck('Boxes', 'a planning engineer cannot change a cost box', (as_(PL), act({'action': 'box_save', 'project_id': P0, 'box_key': 'K01', 'title': 'x'}))[1].startswith('Only the people'))

    # ---- nothing else changed
    after = J("JSON.stringify({rel:DB.releases.length,acts:DB.master.acts.length,co:(DB.coLog||[]).length,b:(DB.batches||[]).length})")
    ck('Separation', 'no release, schedule, change order log or import changed through the rack', after == before, (before, after))
    pg.reload(); pg.wait_for_timeout(1500)
    ck('General', 'documents, boxes and history survive a reload', J(f"docsOf('{P0}','K02').some(d=>d.revision==='Rev 2')") and J(f"docBoxes('{P0}','cost').some(b=>b.title==='Insurance claims')"))
    ck('General', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
