"""ProTrackAI v2.6 controlled imports in demo (browser) mode: file checks, preview reconciliation,
acknowledgement of refused rows, exception report, duplicate detection, batch log and the Import centre.
Usage: python3 imports_demo.py /path/to/index.html > results_imports_demo.json"""
import sys, json, time, csv, io
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
PW = 'ProTrack@2026'; R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
XLSX_STUB = """window.__xl={sheets:[]};window.XLSX={read:function(ab){var t=new TextDecoder().decode(new Uint8Array(ab));var j=JSON.parse(t);var n=j.sheet||'Sheet1';var o={SheetNames:[n],Sheets:{}};o.Sheets[n]={aoa:j.aoa};return o},
utils:{sheet_to_json:function(ws){return ws.aoa||[]},aoa_to_sheet:function(a){window.__xl.sheets.push(a);return{aoa:a}},json_to_sheet:function(r){window.__xl.sheets.push(r);return{}},
book_new:function(){return{SheetNames:[],Sheets:{}}},book_append_sheet:function(wb,ws,n){wb.SheetNames.push(n);wb.Sheets[n]=ws},encode_range:function(){return'A1'},decode_range:function(){return{s:{r:0,c:0},e:{r:0,c:0}}},encode_cell:function(){return'A1'}},
write:function(){return new Uint8Array([80,75,3,4])},writeFile:function(){}};"""

def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:240]})

def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        if 'xlsx' in u.lower(): return r.fulfill(body=XLSX_STUB, content_type='application/javascript')
        return r.abort()
    return r.continue_()

def book(aoa, sheet, name):
    return {'name': name, 'mimeType': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'buffer': json.dumps({'sheet': sheet, 'aoa': aoa}).encode()}

with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    ctx = b.new_context(viewport={'width': 1440, 'height': 900}, accept_downloads=True)
    pg = ctx.new_page(); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.on('dialog', lambda d: d.accept()); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', PW); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{}")

    # --- Import centre is in the menu for planning roles, not for site roles
    ck('Navigation', 'Import centre in the Imports menu', pg.locator('[data-navkey]').filter(has_text='Import centre').count() >= 1 or 'Import centre' in pg.inner_text('#nav'), pg.inner_text('#nav')[-300:])
    pg.evaluate("go('imp')"); pg.wait_for_timeout(600)
    ck('Import centre', 'page opens with upload links and SAP marked planned', 'Import history' in pg.inner_text('#view') and 'SAP ECC Excel exports' in pg.inner_text('#view') and pg.locator('[data-impgoto]').count() >= 3, pg.inner_text('#view')[:300])
    fm = pg.evaluate("(DB.master.users.find(u=>u.role==='foreman')||{}).id")
    pg.select_option('#role', fm); pg.wait_for_timeout(500)
    ck('Import centre', 'not offered to a foreman', 'Import centre' not in pg.inner_text('#nav'))
    pg.evaluate("go('imp')"); pg.wait_for_timeout(400)
    ck('Import centre', 'forcing it open as a foreman shows no history', 'Import history' not in pg.inner_text('#view'))
    pr = pg.evaluate("(DB.master.users.find(u=>u.name==='Priya Raman')||{}).id")
    pg.select_option('#role', pr); pg.wait_for_timeout(500)
    pg.evaluate("state.impPid='QOT';go('base')"); pg.wait_for_timeout(800)

    # --- file checks
    pg.set_input_files('#invfile', {'name': 'register.xlsm', 'mimeType': 'application/vnd.ms-excel', 'buffer': b'PK..'}); pg.wait_for_timeout(500)
    ck('File checks', 'macro workbook refused before reading', 'macros' in pg.inner_text('#invBox') and pg.evaluate("state.inv") is None, pg.inner_text('#invBox'))
    pg.set_input_files('#invfile', {'name': 'notes.pdf', 'mimeType': 'application/pdf', 'buffer': b'%PDF'}); pg.wait_for_timeout(500)
    ck('File checks', 'other file types refused', 'not a file ProTrackAI can import' in pg.inner_text('#invBox'))
    pg.set_input_files('#invfile', {'name': 'big.xlsx', 'mimeType': 'application/octet-stream', 'buffer': b'x' * (10 * 1024 * 1024 + 10)}); pg.wait_for_timeout(800)
    ck('File checks', 'files over 10 MB refused', '10 MB' in pg.inner_text('#invBox'), pg.inner_text('#invBox'))

    # --- invoice register with problems
    head = ['Invoice number', 'Invoice date', 'Type', 'Invoice amount (SAR)', 'Submitted amount (SAR)', 'Approved amount (SAR)', 'Collected amount (SAR)', 'Remark', 'Currency', 'Project']
    aoa = [head, ['INV-1', '2026-03-31', 'Progress', 1000000, 1000000, 900000, 800000, 'IPC 1', 'SAR', 'QOT'],
           ['INV-2', '2026-04-30', 'Progress', 500000, 500000, 400000, 0, '', 'SAR', ''],
           ['INV-2', '2026-05-31', 'Progress', 1, 1, 0, 0, 'duplicate', '', ''],
           ['INV-3', '2026-02-30', 'Progress', 300000, 300000, 0, 0, 'bad date', '', ''],
           ['INV-4', '2026-05-31', 'Progress', 200000, 200000, 0, 0, '', 'USD', ''],
           ['INV-5', '2026-05-31', 'Progress', 100000, 100000, 0, 0, '', '', 'RMX'],
           ['INV-6', '2026-05-31', 'Progress', 'abc', 'abc', 0, 0, '', '', '']]
    before = pg.evaluate("JSON.stringify(invOf('QOT'))")
    pg.set_input_files('#invfile', book(aoa, 'Invoices', 'invoices_QOT.xlsx')); pg.wait_for_timeout(1200)
    st = pg.evaluate("state.inv&&state.inv.rows.map(r=>({no:r.no,ln:r.ln,err:r.err||null}))") or []
    errs_by = {}
    for r in st: errs_by.setdefault(r['no'], []).append(r['err'])
    ck('Invoice checks', 'duplicate invoice numbers refused', all(errs_by.get('INV-2', [None])) and len(errs_by.get('INV-2', [])) == 2, errs_by)
    ck('Invoice checks', 'impossible date refused', 'date' in (errs_by.get('INV-3', [''])[0] or ''), errs_by)
    ck('Invoice checks', 'foreign currency refused', 'USD' in (errs_by.get('INV-4', [''])[0] or ''), errs_by)
    ck('Invoice checks', 'row for another project refused', 'RMX' in (errs_by.get('INV-5', [''])[0] or ''), errs_by)
    ck('Invoice checks', 'text in an amount refused', 'not a number' in (errs_by.get('INV-6', [''])[0] or ''), errs_by)
    ck('Invoice checks', 'rows keep their sheet row number', [r['ln'] for r in st][:2] == [2, 3], st[:2])
    box = pg.inner_text('#invBox')
    ck('Preview', 'reconciliation shows file total, accepted total and difference', 'Total in the file' in box and 'Difference' in box and 'fingerprint' in box.lower(), box[:400])
    ck('Preview', 'Apply stays disabled until the refused rows are acknowledged', pg.is_disabled('[data-invgo]'))
    with pg.expect_download() as dl:
        pg.click('[data-excdl="inv"]')
    rows = list(csv.reader(io.StringIO(open(dl.value.path(), encoding='utf-8-sig').read())))
    body = [r for r in rows if len(r) == 4 and r[0] not in ('Sheet row',)]
    ck('Exception report', 'downloads every refused row with sheet row and reason', len(body) == 6 and any(r[1] == 'INV-4' and 'USD' in r[3] for r in body), body)
    ck('Preview', 'nothing changed before Apply', pg.evaluate("JSON.stringify(invOf('QOT'))") == before)
    pg.check('#reconAck'); pg.fill('#reconNote', 'refused rows go to next week'); pg.wait_for_timeout(200)
    ck('Preview', 'Apply enabled once acknowledged', not pg.is_disabled('[data-invgo]'))
    pg.click('[data-invgo]'); pg.wait_for_timeout(900)
    t = pg.evaluate("(()=>{const b=DB.batches.at(-1);return {n:invOf('QOT').length,kind:b.kind,seq:b.seq,st:b.recon_status,diff:b.recon_diff,by:b.recon_accepted_by,note:b.recon_note,sha:(b.file_sha256||'').length,rej:b.rows_rejected,tot:b.rows_total}})()")
    ck('Commit', 'only the valid row is stored', t['n'] == 1, t)
    ck('Commit', 'batch records difference, who accepted it, note and fingerprint',
       t['kind'] == 'invoices' and t['st'] == 'Accepted with difference' and t['diff'] == 1100001 and t['by'] and t['note'] == 'refused rows go to next week' and t['sha'] == 64 and t['rej'] == 6 and t['tot'] == 7, t)
    nb = pg.evaluate("DB.batches.length")
    pg.set_input_files('#invfile', book(aoa, 'Invoices', 'invoices_QOT.xlsx')); pg.wait_for_timeout(1000)
    pg.check('#reconAck'); pg.click('[data-invgo]'); pg.wait_for_timeout(700)
    ck('Duplicates', 'the same file again changes nothing and adds no batch', pg.evaluate("DB.batches.length") == nb and 'nothing changed' in pg.inner_text('#toast'), pg.inner_text('#toast'))
    good = [head, ['INV-1', '2026-03-31', 'Progress', 1000000, 1000000, 900000, 800000, 'IPC 1', 'SAR', 'QOT'], ['INV-7', '2026-06-30', 'Progress', 400000, 400000, 0, 0, '', 'SAR', 'QOT']]
    pg.set_input_files('#invfile', book(good, 'Invoices', 'invoices_QOT_v2.xlsx')); pg.wait_for_timeout(1000)
    ck('Preview', 'a clean file needs no acknowledgement', pg.locator('#reconAck').count() == 0 and not pg.is_disabled('[data-invgo]'))
    pg.click('[data-invgo]'); pg.wait_for_timeout(700)
    ck('Commit', 'clean file reconciles as Matched', pg.evaluate("DB.batches.at(-1).recon_status") == 'Matched' and pg.evaluate("invOf('QOT').length") == 2)

    # --- costing
    ids = pg.evaluate("ACTS.filter(a=>a.p==='QOT'&&isCon(a)).slice(0,2).map(a=>a.id)")
    ch = ['Activity ID', 'Description', 'Budget quantity', 'UOM', 'Unit rate', 'Budget cost', 'Budget manhours', 'Currency']
    caoa = [ch, [ids[0], 'A', 100, 'm3', 50, 5000, 400, 'SAR'], [ids[1], 'B', 'many', 't', 20, 4000, 800, ''], ['NOPE', 'x', 1, 'm', 1, 1, 1, '']]
    pg.set_input_files('#costfile', book(caoa, 'Costing', 'costing_QOT.xlsx')); pg.wait_for_timeout(1000)
    cst = pg.evaluate("state.cost.rows.map(r=>({id:r.id,err:r.err||null}))")
    ck('Costing checks', 'text in the quantity is refused, not read as zero', any(r['id'] == ids[1] and 'text' in (r['err'] or '') for r in cst), cst)
    ck('Costing checks', 'Apply disabled until acknowledged', pg.is_disabled('[data-costgo]'))
    pg.check('#reconAck'); pg.click('[data-costgo]'); pg.wait_for_timeout(900)
    ck('Costing checks', 'valid row applied and batch logged', pg.evaluate(f"ACTS.find(a=>a.id==='{ids[0]}').bcost") == 5000 and pg.evaluate("DB.batches.at(-1).kind") == 'costing')

    # --- weekly progress
    sa = pg.evaluate("(DB.master.users.find(u=>u.email==='asarudeen@company.com')||{}).id")
    pg.select_option('#role', sa); pg.wait_for_timeout(500)
    pg.evaluate("go('upd')"); pg.wait_for_timeout(700)
    eng = pg.evaluate("ACTS.filter(a=>a.cls==='ENG'&&SCOPE.has(a.p)).slice(0,2).map(a=>a.id)")
    uh = ['Activity ID', 'Milestone reached', 'Actual start', 'Actual finish', 'Forecast finish', 'Data date', 'Remarks']
    uaoa = [uh, [eng[0], 'IFC', '2026-08-01', '2026-09-20', '', '2026-09-21', 'done'], [eng[0], 'IFC', '', '', '', '2026-09-21', 'dup'], [eng[1], 'ST', '2026-13-01', '', '', '2026-09-21', 'bad date']]
    pg.set_input_files('#updfile', book(uaoa, 'Update', 'update_wk38.xlsx')); pg.wait_for_timeout(1000)
    ust = pg.evaluate("state.upd.rows.map(r=>({id:r.id,err:r.err||null}))")
    ck('Progress checks', 'duplicate activity and invalid date refused', sum(1 for r in ust if r['err']) == 3 and any('date' in (r['err'] or '') for r in ust), ust)
    ck('Progress checks', 'nothing to apply when every row is refused', pg.is_disabled('[data-updgo]'))

    # --- Import centre lists everything
    pg.evaluate("go('imp')"); pg.wait_for_timeout(700)
    v = pg.inner_text('#view')
    ck('Import centre', 'history lists the batches with results', v.count('IMP-') >= 3 and 'Committed with difference' in v, v[:500])
    pg.click('[data-impf="st:diff"]'); pg.wait_for_timeout(300)
    ck('Import centre', 'filter shows only batches with a difference', pg.locator('#view tbody tr').count() == 2, pg.locator('#view tbody tr').count())
    pg.click('#view tbody tr.click >> nth=0'); pg.wait_for_timeout(500)
    d = pg.inner_text('#sheet')
    ck('Import centre', 'batch detail shows fingerprint, reconciliation, acknowledgement and audit reference',
       'SHA-256' in d and 'Difference accepted by' in d and 'Audit reference' in d and 'Committed in one transaction' in d, d[:400])
    with pg.expect_download() as dl2:
        pg.click('[data-batchexc]')
    ck('Import centre', 'exception report downloads from the batch', dl2.value.suggested_filename.startswith('exceptions-IMP-'), dl2.value.suggested_filename)
    pg.evaluate("closeDrawer()")
    pg.reload(); pg.wait_for_timeout(1500)
    ck('General', 'batch history survives a reload', pg.evaluate("(DB.batches||[]).length") >= 3)
    ck('General', 'no script errors', not errs, errs[:3])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
