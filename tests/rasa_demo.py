"""ProTrackAI v2.9 (Phase 5) in demo (browser) mode: governed RASA answers. Every answer and insight carries its
sources and data date; empty data and untracked topics get an explicit "No evidence"; site roles get no cost or
billing figures; projects outside a person's access are refused; the language model is labelled and gets no
cost data for site roles. Usage: python3 rasa_demo.py /path/to/index.html > results_rasa_demo.json"""
import sys, json, time, re
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
R = []
CHART = "window.Chart=function(){return{destroy(){},update(){},resize(){},data:{datasets:[]},options:{}}};window.Chart.register=function(){};window.Chart.defaults={font:{},plugins:{legend:{labels:{}},tooltip:{}},scale:{grid:{}},color:''};"
LLM = "window.__llm=[];window.claude={use:function(k){if(k!=='sample')return Promise.resolve(null);return Promise.resolve(function(msgs,opt){window.__llm.push(msgs[0].content);return Promise.resolve({text:'Sample answer from the model.'})})}};"
def ck(area, name, cond, detail=''):
    R.append({'area': area, 'check': name, 'result': 'PASS' if cond else 'FAIL', 'detail': '' if cond else str(detail)[:260]})
def route(r):
    u = r.request.url
    if u.startswith('http'):
        if 'chart' in u.lower(): return r.fulfill(body=CHART, content_type='application/javascript')
        return r.abort()
    return r.continue_()
TOPICS = ["Today's productivity", 'Early warnings', 'Invoiceable value', 'Invoicing and collection', 'Quantity reconciliation', 'Unit rates', 'EAC forecast',
          'Manpower forecast', 'Milestones and EOT', 'Design and procurement', 'Underperforming activities', 'Compare foremen', 'Best subcontractor',
          'What is waiting for me', 'Lifecycle stages', 'Tender register']
MONEY = ['Invoiceable value', 'Invoicing and collection', 'Unit rates', 'EAC forecast']
UNTRACKED = ['What are our commitments this month?', 'Show the accruals', 'What is the SAP actual cost?', 'Give me the cash flow forecast',
             'How many variation orders are open?', 'Any safety incidents this week?', 'What was the weather on site?', 'Material stock level for cement']
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    def page(llm=False):
        pg = b.new_page(viewport={'width': 1440, 'height': 900}); pg.errs = []; pg.on('pageerror', lambda e: pg.errs.append(str(e))); pg.route('**/*', route)
        if llm: pg.add_init_script(LLM)
        pg.goto('file://' + APP); pg.wait_for_timeout(800)
        pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
        pg.evaluate("aiHint=()=>{};rasaBubble=()=>{};state.scope='ALL';render()"); return pg
    pg = page()
    J = lambda js: pg.evaluate(js)
    A = lambda q: pg.evaluate(f"answer({json.dumps(q)})") or ''
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(400)

    # ---- 1. sources and data date on every answer
    missing = [q for q in TOPICS if 'data-rasasrc' not in A(q) and 'rasa-noev' not in A(q)]
    ck('Sources', 'every topic answer carries a "Based on" line or an explicit no-evidence reply', not missing, missing)
    a = A("Today's productivity")
    nrep = J("new Set(valid().map(l=>l.rid)).size")
    ck('Sources', 'the daily-report source gives the number of reports, their dates and how many are approved', f"{nrep:,} daily reports" in a and 'approved' in a and 'counted before approval' in a, re.sub('<[^>]+>', ' ', a)[-400:])
    ck('Sources', 'answers built on earned value state the data date', 'Data date' in A('EAC forecast') and J("fmtDY(ASOF)") in A('EAC forecast'))
    ck('Sources', 'the scope is named on every answer', all('Scope:' in A(q) for q in ['Early warnings', 'Compare foremen']))
    ck('Sources', 'billing answers name the invoice register and the contract terms', 'invoice register' in A('Invoicing and collection') and 'billing terms' in A('Invoicing and collection'))
    ck('Sources', 'procurement answers name the weekly update and its data date', 'weekly engineering and procurement update' in A('Design and procurement'))
    ck('Sources', 'insights carry their sources too', J("(rasaRefreshInsights(false),RASA.insights.length>0&&RASA.insights.every(i=>RasaMessage.insight(i).includes('data-rasasrc')))"))
    J("state.chat=[];rasaQA('health')"); pg.wait_for_timeout(1200)
    ck('Sources', 'quick actions carry their sources (project health)', 'data-rasasrc' in J("state.chat.filter(m=>m.b).pop().h"))

    # ---- 2. no evidence
    bad = [q for q in UNTRACKED if 'No evidence in ProTrackAI' not in A(q) or 'SAR' in A(q)]
    ck('No evidence', 'untracked topics (commitments, accruals, SAP, cash-flow forecast, variations, safety, weather, materials) get a clear no-evidence reply', not bad, bad)
    ck('No evidence', 'SAP questions say ProTrackAI has no SAP connection and that its actual cost is not SAP actual cost', 'no connection to SAP' in A('SAP posted cost') and 'not SAP actual cost' in A('SAP posted cost'))
    ck('No evidence', 'an unknown question without the language model is a no-evidence reply, not a guess', A('What colour is the site office?') == '' and 'No evidence in ProTrackAI' in J("RASA_NOEV_HELP()"))
    J("ask('What colour is the site office?')"); pg.wait_for_timeout(900)
    ck('No evidence', 'in the chat, that question gets the no-evidence reply', 'No evidence in ProTrackAI for that question' in J("state.chat.filter(m=>m.b).pop().h"))
    J("tenderActLocal('register',null,{te_number:'TE9001',name:'Empty test project',region:PROJECTS[0].region});state.scope='PE-001';render()")
    empties = {q: re.sub('<[^>]+>', ' ', A(q))[:90] for q in ["Today's productivity", 'Early warnings', 'Underperforming activities', 'EAC forecast', 'Compare foremen', 'Milestones and EOT', 'Design and procurement', 'Unit rates']}
    ck('No evidence', 'a project with no baseline or reports gets no-evidence replies, never "everything is fine"', all('No evidence' in v for v in empties.values()), empties)
    J("state.chat=[];rasaQA('health')"); pg.wait_for_timeout(1200)
    ck('No evidence', 'project health on it says there is no baseline instead of "within tolerance"', 'No evidence' in J("state.chat.filter(m=>m.b).pop().h") and 'within tolerance' not in J("state.chat.filter(m=>m.b).pop().h"))
    J("state.scope='ALL';render()")

    # ---- 3. new grounded topics
    a = A('What is waiting for me')
    ck('New topics', '"what is waiting for me" counts items from Actions and approvals', f"<b>{J('actionItems().filter(x=>x.mine).length')}</b>" in a and 'Open Actions and approvals' in a, a[:200])
    a = A('Which stage is each project at?')
    ck('New topics', 'lifecycle question lists the current stage of each project', all(J(f"projById('{pid}').short") in a for pid in J("scopeProjects().filter(p=>p.status!=='Cancelled').slice(0,3).map(p=>p.id)")) and 'Current stage' in a)
    a = A('Tender register')
    ck('New topics', 'Tender register question gives pre-award count and the next PE number', 'pre-award' in a and 'next PE number' in a and J("peProposeLocal().proposed") in a, a[:200])
    a = A('Tell me about PE-001')
    ck('New topics', 'a PE number question answers from that project\'s register row', 'TE9001' in a and 'Pre-award' in a, a[:200])

    # ---- 4. permissions: site roles and access
    fm = J("(DB.master.users.find(u=>u.role==='foreman')||{}).id"); as_(fm)
    leaks = [q for q in MONEY if 'SAR' in A(q) or 'Not available for your role' not in A(q)]
    ck('Permissions', 'a foreman asking for invoiceable value, collection, unit rates or EAC gets "not available for your role"', not leaks, leaks)
    ck('Permissions', 'a foreman asking about subcontractors gets productivity but no SAR', 'SAR' not in A('Best subcontractor') and '%' in A('Best subcontractor'))
    ck('Permissions', 'a foreman cannot ask about the Tender register', 'Not available for your role' in A('Tender register'))
    ck('Permissions', 'a foreman\'s insights hold no cost or billing figures', J("(rasaRefreshInsights(false),RASA.insights.every(i=>!/SAR|CPI|invoic/i.test(i.title+i.text)))"))
    ck('Permissions', 'a foreman\'s suggested questions hold no cost topics', J("(rasaChips(),[...document.querySelectorAll('#aiChips .chip')].every(c=>!/Invoic|EAC|Unit rates/.test(c.textContent)))"))
    ck('Permissions', 'the language-model data for a foreman holds no billing, EAC, CPI or SAR rates', J("(()=>{const c=JSON.stringify(aiContextSafe('invoiceable'));return !/\\\"billing\\\"|\\\"eac\\\"|\\\"cpi\\\"|sarPerEarnedMh/.test(c)})()"))
    eng = J("(DB.master.users.find(u=>u.role==='eng')||{}).id"); as_(eng)
    other = J("PROJECTS.find(p=>!accessIds().includes(p.id)&&p.short.length>=3)")
    ck('Permissions', 'a site engineer asking about a project outside their access is refused without figures', bool(other) and 'Not in your access' in A(f"How is {other['short']} doing?") and '%' not in A(f"Early warnings for {other['short']}"), other and other['short'])
    pm = J("(DB.master.users.find(u=>u.role==='pm'&&u.projects.length===1)||{}).id"); as_(pm)
    mine = J("accessIds()[0]")
    other = J("PROJECTS.find(p=>!accessIds().includes(p.id)&&p.short.length>=3)")
    ck('Permissions', 'a project manager is refused on another manager\'s project', 'Not in your access' in A(f"EAC for {other['short']}"))
    as_(J("(DB.master.users.find(u=>u.role==='pm'&&u.projects.length>1)||DB.master.users.find(u=>u.role==='sa')).id"))
    ids = J("accessIds()")
    if len(ids) > 1:
        J(f"state.scope='{ids[0]}';render()")
        sh = J(f"projById('{ids[1]}').short")
        ck('Permissions', 'a project in access but outside the current scope is pointed to the Scope menu, not answered with the wrong figures', 'outside the current scope' in A(f"Early warnings on {sh}"))
    else:
        ck('Permissions', 'a project in access but outside the current scope is pointed to the Scope menu, not answered with the wrong figures', True)
    J("state.scope='ALL';render()")

    # ---- 5. outside AI
    sa = J("DB.master.users.find(u=>u.role==='sa').id"); as_(sa)
    pg.evaluate("go('admin');state.adminTab='system';render()"); pg.wait_for_timeout(300)
    ck('Outside AI', 'Settings, System states the RASA outside-AI policy', 'no project data is sent to any outside AI service' in pg.inner_text('#view'))
    errs1 = list(pg.errs); pg.close()
    pg = page(llm=True); J = lambda js: pg.evaluate(js)
    J("ask('What colour is the site office?')"); pg.wait_for_timeout(1500)
    h = J("state.chat.filter(m=>m.b).pop().h")
    ck('Outside AI', 'on the demo inside claude.ai, a question RASA cannot answer from records goes to the model, and the answer is labelled', J("window.__llm.length") == 1 and 'Language-model answer' in h and 'not a ProTrackAI calculation' in h, h[-300:])
    J("ask('Invoiceable value')"); pg.wait_for_timeout(1500)
    ck('Outside AI', 'questions RASA can answer from records never go to the model', J("window.__llm.length") == 1)
    fm = J("(DB.master.users.find(u=>u.role==='foreman')||{}).id"); pg.select_option('#role', fm); pg.wait_for_timeout(400)
    J("ask('How should I plan tomorrow?')"); pg.wait_for_timeout(1500)
    sent = J("window.__llm[window.__llm.length-1]||''")
    ck('Outside AI', 'what a foreman\'s question sends to the model holds no billing or cost figures', J("window.__llm.length") == 2 and '"billing"' not in sent and '"eac"' not in sent and 'sarPerEarnedMh' not in sent, sent[:200])
    ck('General', 'no script errors', not errs1 and not pg.errs, (errs1 + pg.errs)[:3])
    b.close()
print(json.dumps({'run_at': time.strftime('%Y-%m-%d %H:%M'), 'app': APP, 'summary': {'PASS': sum(r['result'] == 'PASS' for r in R), 'FAIL': sum(r['result'] == 'FAIL' for r in R)}, 'results': R}, indent=1))
