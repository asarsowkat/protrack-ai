"""ProTrackAI v3.5 in demo (browser) mode: the progress release dashboard. Weekly and monthly progress releases open
full screen with tabs (Overview, Milestones, Progress, Manpower, Energization, Release notes, Approval); internal progress
stays the headline and external progress is entered beside it; delays, variances, SPI and manpower totals are worked
out; each region's planning section manager approves, with an optional project manager review first; the executive
report shows the released dashboard figures.
Usage: python3 reldash_demo.py /path/to/index.html > results_reldash_demo.json"""
import sys, json
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
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg = b.new_page(viewport={'width': 1440, 'height': 900}); errs = []; pg.on('pageerror', lambda e: errs.append(str(e))); pg.route('**/*', route)
    pg.goto('file://' + APP); pg.wait_for_timeout(800)
    pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);state.scope='ALL';render()")
    J = lambda js: pg.evaluate(js)
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(400); J("state.scope='ALL';render()")
    def tryact(p): return J(f"(()=>{{try{{const r=relActLocal({json.dumps(p)});return r&&r.id?'ok':'ok'}}catch(e){{return e.message}}}})()")
    def calc(pid, f): return J(f"(()=>{{try{{return relPlanCalc('{pid}',{json.dumps(f)})}}catch(e){{return {{err:e.message}}}}}})()")
    SA = J("me().id"); PID = 'RMX'; PL = J("(teamOf('RMX','plan')[0]||{}).id"); PM = J("(teamOf('RMX','pm')[0]||{}).id")
    PSM_C, PSM_E = 'U48', 'U49'; MON = J("curMonth()"); WK = J("recentWeeks(1)[0]")

    # ---- demo set-up
    ck('Demo data', 'each region has a planning section manager, and Central projects go to the Central one', J("DB.master.regions.every(rg=>relApproversOf(rg.id).length>0)") and J("relApproversOf('C').map(u=>u.id)") == [PSM_C], J("DB.relApprovers"))
    ck('Demo data', 'the planning section managers are not the planning engineers who prepare the releases', PL not in [PSM_C, PSM_E] and J("teamOf('RMX','plan')[0].id") == PL)
    ck('Demo data', 'seeded released progress releases carry dashboard figures (milestones, external progress, manpower, energization)',
       J("relRows().filter(r=>r.kind==='planning'&&r.status==='Released').every(r=>r.figures.tcc_orig_date&&r.figures.ext_act_pct!=null&&r.figures.mp_tot_plan!=null&&r.figures.energ_status_text)"))
    ck('Demo data', 'project manager review is off to start with; regional approval only', J("relSettings().pm_review") is False)

    # ---- full screen, tabs
    J(f"state.rdTab='overview';openRelease('{PID}','planning','month','{MON}')"); pg.wait_for_timeout(400)
    ck('Full screen', 'a monthly progress release opens full screen, not as a half-width panel', J("document.querySelector('#sheet').classList.contains('full')") and J("document.querySelector('#sheet').getBoundingClientRect().width") >= 1400, J("document.querySelector('#sheet').getBoundingClientRect().width"))
    tabs = J("[...document.querySelectorAll('#sheet [data-rdtab]')].map(b=>b.textContent.trim())")
    ck('Full screen', 'tabs: Overview, Milestones, Progress, Manpower, Energization, Release notes, Approval', tabs == ['Overview', 'Milestones', 'Progress', 'Manpower', 'Energization', 'Release notes', 'Approval'], tabs)
    ok = True
    for k in ['overview', 'ms', 'prog', 'mp', 'en', 'notes', 'appr']:
        pg.click(f'#sheet [data-rdtab="{k}"]'); pg.wait_for_timeout(120)
        vis = J("[...document.querySelectorAll('#sheet [data-rdp]')].filter(s=>!s.hidden).map(s=>s.dataset.rdp)")
        ok = ok and vis == [k]
    ck('Full screen', 'each tab shows its own section only', ok)
    pg.click('#sheet [data-rdtab="overview"]')
    ov = pg.inner_text('#sheet [data-rdp="overview"]')
    ck('Project information', 'data date, project number, sub project number, name, region, sector, contract value, project manager and planning engineer',
       all(x in ov for x in ['Data date', 'Project number', 'Sub project number', 'Riyadh Metro Line 7', 'Central', 'Infrastructure', 'SAR 420.0M', J(f"userById('{PM}').name"), J(f"userById('{PL}').name")]), ov[:400])
    kp = pg.inner_text('#sheet .rkpis')
    ck('KPIs', 'the strip shows actual and planned progress, variance, SPI, forecast completion, manpower variance, TCC and PAC status and energization',
       all(x in kp for x in ['Actual progress', 'Planned progress', 'Progress variance', 'SPI', 'Forecast completion', 'Manpower variance', 'TCC status', 'PAC status', 'Energization']), kp)
    ck('KPIs', 'trend icons compare with the last released month (▲ ▼ ■)', any(x in kp for x in ['▲', '▼', '■']) and 'Trends compare with the released' in pg.inner_text('#sheet'))
    ck('KPIs', 'internal progress is the headline (P6 internal weightage); external is labelled client weightage',
       'internal weightage' in kp and 'client weightage' in pg.inner_text('#sheet [data-rdp="prog"]', timeout=2000) if J("document.querySelector('#sheet [data-rdp=prog]')") else False)
    J("closeDrawer()")
    J(f"openRelease('{PID}','cost','month','{MON}')"); pg.wait_for_timeout(300)
    ck('Full screen', 'the monthly cost report keeps its own layout (not the progress dashboard)', not J("document.querySelector('#sheet').classList.contains('full')") and J("document.querySelector('#sheet [data-rdtab]')") is None)
    J("closeDrawer()")
    J(f"state.rdTab='notes';openRelease('{PID}','planning','week','{WK}')"); pg.wait_for_timeout(300)
    ck('Full screen', 'a weekly progress release opens the same full-screen dashboard, with a next week target', J("document.querySelector('#sheet').classList.contains('full')") and 'Next week target' in pg.inner_text('#sheet'))
    J("closeDrawer()")

    # ---- calculations (the same rules the server applies)
    c = calc(PID, {'actual_pct': 50, 'planned_pct': 55, 'tcc_orig_date': '2026-12-31', 'tcc_ext_fc_date': '2027-01-10', 'pac_orig_date': '2027-03-31', 'pac_rev_date': '2027-05-31', 'pac_ext_fc_date': '2027-05-31',
                   'fac_orig_date': '2028-01-31', 'fac_ext_fc_date': '2028-04-30', 'tcc_int_target_date': '2026-11-30', 'tcc_int_fc_date': '2026-12-15',
                   'ext_plan_pct': 60, 'ext_act_pct': 45, 'mp_dir_plan': 100, 'mp_dir_act': 80, 'mp_ind_plan': 20, 'mp_ind_act': 20, 'mp_sub_plan': 50, 'mp_sub_act': 40})
    ck('Calculations', 'delay = external forecast − original contractual date (TCC 10 days)', c.get('tcc_delay_days') == 10, c)
    ck('Calculations', 'an approved revised date replaces the original (PAC on the revised date = 0 days)', c.get('pac_delay_days') == 0, c)
    ck('Calculations', 'FAC 90 days late', c.get('fac_delay_days') == 90, c)
    ck('Calculations', 'internal TCC delay = internal forecast − internal target (15 days)', c.get('tcc_int_delay_days') == 15, c)
    ck('Calculations', 'external variance = actual % − planned % (−15) and external SPI = actual ÷ planned (0.75)', c.get('ext_var_pct') == -15 and c.get('ext_spi') == 0.75, c)
    ck('Calculations', 'internal variance −5 and internal amounts from the contract value (SAR 420M × %)', c.get('int_var_pct') == -5 and c.get('int_plan_amt') == 231000000 and c.get('int_act_amt') == 210000000, c)
    ck('Calculations', 'manpower totals 170 planned / 140 actual, variance −30, utilization 82.4%', c.get('mp_tot_plan') == 170 and c.get('mp_tot_act') == 140 and c.get('mp_var') == -30 and c.get('mp_util_pct') == 82.4, c)
    ck('Calculations', 'a missing figure stays empty rather than becoming zero', calc(PID, {'actual_pct': 50}).get('ext_spi') is None and calc(PID, {'actual_pct': 50}).get('mp_var') is None)
    L = J("[msLight(0),msLight(-4),msLight(1),msLight(30),msLight(31),msLight(45,'2026-09-01'),msLight(null)].map(x=>x.t)")
    ck('Traffic lights', 'green on schedule (≤ 0 days), amber at risk (1–30), red delayed (over 30), green once the certificate is received, and Data unavailable', L == ['On schedule', 'On schedule', 'At risk', 'At risk', 'Delayed', 'Received', 'Data unavailable'], L)
    ck('Validation', 'external % over 100 is refused', 'between 0 and 100' in calc(PID, {'ext_plan_pct': 120}).get('err', ''))
    ck('Validation', 'negative manpower is refused', 'cannot be negative' in calc(PID, {'mp_dir_act': -1}).get('err', ''))
    ck('Validation', 'an unknown energization status is refused', 'Energization status' in calc(PID, {'energ_status_text': 'Done'}).get('err', ''))
    ck('Validation', 'Energized needs the energization date', 'energization date' in calc(PID, {'energ_status_text': 'Energized'}).get('err', ''))

    # ---- live recalculation in the form
    as_(PL)
    J(f"state.rdTab='prog';openRelease('{PID}','planning','month','{MON}')"); pg.wait_for_timeout(300)
    pg.fill('#sheet [name="d_ext_plan_pct"]', '80'); pg.fill('#sheet [name="d_ext_act_pct"]', '72'); pg.wait_for_timeout(500)
    ck('Live figures', 'typing external progress updates the SPI card at once (external 0.90)', 'external 0.90' in pg.inner_text('#sheet .rkpis'), pg.inner_text('#sheet .rkpis'))
    pg.click('#sheet [data-rdtab="mp"]')
    for k, v in [('dir_plan', 50), ('dir_act', 40), ('ind_plan', 10), ('ind_act', 10), ('sub_plan', 20), ('sub_act', 30)]: pg.fill(f'#sheet [name="d_mp_{k}"]', str(v))
    pg.wait_for_timeout(500)
    ck('Live figures', 'manpower variance in the KPI strip updates (80 planned, 80 actual → 0, utilization 100%)', 'utilization 100.0%' in pg.inner_text('#sheet .rkpis'), pg.inner_text('#sheet .rkpis'))
    pg.click('#sheet [data-rdtab="ms"]'); pg.fill('#sheet [name="d_tcc_rev_date"]', '2027-02-28'); pg.fill('#sheet [name="d_tcc_ext_fc_date"]', '2027-04-15')
    pg.click('#sheet [data-rdtab="en"]'); pg.select_option('#sheet [name="d_energ_status_text"]', 'Under Testing'); pg.fill('#sheet [name="d_energ_remarks_text"]', 'Relay tests in progress')
    pg.click('#sheet [data-rdtab="notes"]'); pg.fill('#sheet [name="n_summary"]', 'Steady month'); pg.fill('#sheet [name="n_recovery"]', 'Add a second shift for cabling'); pg.fill('#sheet [name="n_next"]', 'Finish station roof')
    ck('Release notes', 'management remarks cannot be typed by the planning engineer (approver only)', J("document.querySelector('#relMgmt')") is None)
    pg.click('#sheet [data-reldo="save"]'); pg.wait_for_timeout(600)
    r = J(f"relOpen('{PID}','planning','month','{MON}')")
    f = r['figures'] if r else {}
    ck('Save draft', 'the draft keeps the dashboard fields and the worked-out figures', f.get('ext_spi') == 0.9 and f.get('mp_tot_act') == 80 and f.get('tcc_rev_date') == '2027-02-28' and f.get('tcc_delay_days') == 46 and f.get('energ_status_text') == 'Under Testing', {k: f.get(k) for k in ['ext_spi', 'mp_tot_act', 'tcc_rev_date', 'tcc_delay_days', 'energ_status_text']})
    ck('Save draft', 'summary, recovery actions and next target are saved', (r or {}).get('narrative', {}).get('recovery') == 'Add a second shift for cabling' and r['narrative'].get('next') == 'Finish station roof')
    ck('KPIs', 'TCC 46 days late shows red, Delayed', 'Delayed' in pg.inner_text('#sheet .rkpis') and J("!!document.querySelector('#sheet .rkpis .rkpi.r')"))

    # ---- workflow: planner → regional planning section manager
    pg.click('#sheet [data-rdtab="appr"]')
    ap = pg.inner_text('#sheet [data-rdp="appr"]')
    ck('Approval', 'the approval tab names the regional planning section manager and the workflow', 'Faris Al-Zahrani (planning section manager)' in ap and 'regional planning section manager approves' in ap, ap[:400])
    pg.click('#sheet [data-reldo="submit"]'); pg.wait_for_timeout(600)
    r = J(f"relOpen('{PID}','planning','month','{MON}')")
    ck('Workflow', 'Submit for approval', r and r['status'] == 'Submitted' and r['submitted_by'] == PL)
    ck('Workflow', 'the planning engineer cannot approve', 'Only the Head of Planning and Cost Control, the regional planning section manager' in tryact({'action': 'approve', 'id': r['id']}))
    as_(PM)
    ck('Workflow', 'the project manager cannot approve while the review step is off', 'regional planning section manager' in tryact({'action': 'approve', 'id': r['id']}))
    ck('Workflow', 'and has no review step to do', 'not switched on' in tryact({'action': 'review', 'id': r['id']}))
    as_(PSM_E)
    ck('Workflow', 'another region\'s planning section manager cannot approve a Central project', tryact({'action': 'approve', 'id': r['id']}) == 'You do not have access to this project')
    as_(PSM_C)
    ai = J("actionItems().filter(x=>x.type==='Release approval'&&x.mine&&x.pid==='RMX').length")
    ck('Workflow', 'the Central planning section manager sees it in his action list', ai >= 1, ai)
    J("go('rel')"); pg.wait_for_timeout(300)
    ck('Workflow', 'and on Progress releases (Waiting for you)', 'Waiting for you' in pg.inner_text('#view') and 'regional planning section manager approves it' in pg.inner_text('#view'))
    J(f"state.rdTab='notes';openRelease('{PID}','planning','month','{MON}')"); pg.wait_for_timeout(300)
    ck('Approval', 'the approver sees Approve and release and Reject (return to planner)', pg.locator('#sheet [data-reldo="approve"]').count() == 1 and pg.locator('#sheet [data-reldo="return"]', has_text='Reject').count() == 1)
    pg.click('#sheet [data-reldo="return"]'); pg.wait_for_timeout(400)
    ck('Workflow', 'rejecting needs a comment', J(f"relOpen('{PID}','planning','month','{MON}').status") == 'Submitted' and 'comment' in pg.inner_text('#relErr').lower() + J("relAct.err||''").lower())
    pg.fill('#relMgmt', 'Recovery plan accepted; watch cabling'); pg.click('#sheet [data-reldo="approve"]'); pg.wait_for_timeout(600)
    rr = J(f"relReleased('{PID}','planning','month','{MON}')")
    ck('Workflow', 'the regional planning section manager approves and releases it', rr and rr['approved_by'] == PSM_C and rr['status'] == 'Released')
    ck('Approval', 'management remarks are saved with the approval; reviewed by is filled', rr['narrative'].get('mgmt') == 'Recovery plan accepted; watch cabling' and rr.get('reviewed_by') == PSM_C)
    ck('Approval', 'a released version cannot be edited', 'cannot be edited' in tryact({'action': 'save', 'id': rr['id'], 'figures': {'actual_pct': 1}}) or 'already released' in tryact({'action': 'save', 'project_id': PID, 'kind': 'planning', 'period_type': 'month', 'period': MON, 'figures': {'actual_pct': 1}}))
    as_(PSM_C)
    ck('Workflow', 'the planning section manager cannot approve cost reports (they stay with the Head)', J(f"relCanApprove('{PID}','cost')") is False)

    # ---- executive report
    as_(SA); J(f"go('xr');state.xrTab='proj';state.xrPid='{PID}';state.xrPt='month';state.xrPer='{MON}';render()"); pg.wait_for_timeout(400)
    v = pg.inner_text('#view')
    ck('Executive report', 'the project view shows milestones, external progress, energization and manpower as released', all(x in v for x in ['Milestones, progress, energization and manpower', 'External progress', 'Under Testing', 'Relay tests in progress', '+46 days']), v[-900:])
    ck('Executive report', 'with recovery actions and management remarks', 'Recovery actions. Add a second shift for cabling' in v and 'Management remarks. Recovery plan accepted' in v)
    J("state.xrTab='sum';render()"); pg.wait_for_timeout(300)
    why = J(f"xrRows('month','{MON}').find(x=>x.p.id==='{PID}').why")
    ck('Executive report', 'a TCC more than 30 days late makes the project critical, with the reason', any('TCC 46 days late' in w for w in why) or any('days after baseline' in w for w in why), why)

    # ---- project manager review switched on by a super admin
    J("go('admin');state.adminTab='matrix';render()"); pg.wait_for_timeout(300)
    J("(()=>{const b=[...document.querySelectorAll('[data-admtab],[data-tab]')].find(x=>/matrix/i.test(x.dataset.admtab||x.dataset.tab||''));if(b)b.click()})()"); pg.wait_for_timeout(300)
    has = pg.locator('[data-relpmrev]').count() == 1
    ck('Set-up', 'Administration shows who approves progress releases in each region and the project manager review switch', has and 'Internal and client report approval' in pg.inner_text('#view'))  # v3.6 heading
    if has: pg.check('[data-relpmrev]'); pg.wait_for_timeout(400)
    else: J("relSetup({action:'pm_review',on:true})")
    ck('Set-up', 'a super admin switches on the project manager review', J("relSettings().pm_review") is True)
    as_(PL)
    ck('Set-up', 'nobody else can change it', J("relSetup({action:'pm_review',on:false})") is not None and J("relSettings().pm_review") is True)
    P2 = 'QOT'
    ck('Workflow (PM review)', 'prepare and submit another Central project', tryact({'action': 'save', 'project_id': P2, 'kind': 'planning', 'period_type': 'week', 'period': WK, 'figures': {'actual_pct': 40, 'planned_pct': 42}, 'narrative': {}}) == 'ok'
       and tryact({'action': 'submit', 'project_id': P2, 'kind': 'planning', 'period_type': 'week', 'period': WK}) == 'ok')
    rid = J(f"relOpen('{P2}','planning','week','{WK}').id")
    as_(PSM_C)
    ck('Workflow (PM review)', 'the planning section manager cannot approve before the project manager reviews', 'must review' in tryact({'action': 'approve', 'id': rid}))
    J(f"openRelease('{P2}','planning','week','{WK}')"); pg.wait_for_timeout(300)
    ck('Workflow (PM review)', 'his screen says it is waiting for the project manager', "Waiting for the project manager" in pg.inner_text('#sheet') and pg.locator('#sheet [data-reldo="approve"]').count() == 0)
    J("closeDrawer()")
    as_('U06')
    ck('Workflow (PM review)', 'a project manager of another project cannot review it', tryact({'action': 'review', 'id': rid}) == 'You do not have access to this project')
    QPM = J(f"teamOf('{P2}','pm')[0].id"); as_(QPM)
    ck('Workflow (PM review)', 'the project manager sees a Release review action', J(f"actionItems().some(x=>x.type==='Release review'&&x.mine&&x.pid==='{P2}')"))
    J(f"openRelease('{P2}','planning','week','{WK}')"); pg.wait_for_timeout(300)
    pg.click('#sheet [data-reldo="review"]'); pg.wait_for_timeout(500)
    r2 = J(f"relOpen('{P2}','planning','week','{WK}')")
    ck('Workflow (PM review)', 'the project manager marks it reviewed', r2['reviewed_by'] == QPM and r2['status'] == 'Submitted')
    ck('Workflow (PM review)', 'and cannot approve it himself', 'regional planning section manager' in tryact({'action': 'approve', 'id': rid}))
    as_(PSM_C)
    ck('Workflow (PM review)', 'then the planning section manager approves', tryact({'action': 'approve', 'id': rid, 'validated': True, 'validation_note': 'Checked against the updated schedule'}) == 'ok' and J(f"relReleased('{P2}','planning','week','{WK}').reviewed_by") == QPM)  # v3.6: QOT has an updated schedule, so the differences are validated
    J(f"openRelease('{P2}','planning','week','{WK}');state.rdTab='appr'"); pg.wait_for_timeout(300)
    J(f"openRelease('{P2}','planning','week','{WK}')"); pg.wait_for_timeout(200)
    ap = pg.inner_text('#sheet [data-rdp="appr"]')
    ck('Approval', 'released by, reviewed by and approved by are all shown', J(f"userById('{PL}').name") in ap and J(f"userById('{QPM}').name") in ap and 'Faris Al-Zahrani' in ap, ap[:500])
    J("closeDrawer()")

    # ---- list filters
    as_(SA); J("go('rel');state.relTab='planning';state.relF={};render()"); pg.wait_for_timeout(300)
    ck('Filters', 'Progress releases has Region and Sector filters and a Data date column', pg.locator('[data-relf="rg"]').count() == 1 and pg.locator('[data-relf="sec"]').count() == 1 and 'Data date' in pg.inner_text('#view'))
    pg.select_option('[data-relf="rg"]', 'E'); pg.wait_for_timeout(300)
    v = pg.inner_text('#view')
    ck('Filters', 'filtering by region lists that region\'s projects only', 'Jubail 380kV' in v and 'Riyadh Metro L7' not in v)
    pg.select_option('[data-relf="sec"]', 'ONG'); pg.wait_for_timeout(300)
    v = pg.inner_text('#view')
    ck('Filters', 'and by sector', 'Ras Tanura TF' in v and 'Jubail 380kV' not in v)
    J("state.relF={};render()")

    # ---- set-up changes and phone width
    J("relSetup({action:'approver_add',region_id:'E',user_id:'U48'})")
    ck('Set-up', 'a super admin can name a second planning section manager for a region', 'U48' in J("relApproversOf('E').map(u=>u.id)"))
    J("relSetup({action:'approver_remove',region_id:'E',user_id:'U48'})")
    ck('Set-up', 'and remove one', 'U48' not in J("relApproversOf('E').map(u=>u.id)"))
    pg.set_viewport_size({'width': 390, 'height': 844}); J(f"state.rdTab='overview';openRelease('JBS','planning','month','{MON}')"); pg.wait_for_timeout(400)
    ck('Phone', 'the dashboard fits a phone screen without sideways scrolling', J("document.querySelector('#sheet').scrollWidth<=document.querySelector('#sheet').clientWidth+2"), J("[document.querySelector('#sheet').scrollWidth,document.querySelector('#sheet').clientWidth]"))
    ck('Errors', 'no script errors', not errs, errs[:3])
    b.close()
import time
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
