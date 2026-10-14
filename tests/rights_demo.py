"""ProTrackAI v3.7 in demo (browser) mode: roles, rights and access, controlled by the super admin.
Administration → Roles and rights (rights by role, screens by role, custom roles, people with exceptions, history);
Users and access (custom roles, All projects, regions and projects for any role, rights for one person); every
button and menu following the rights; the rules that never change (super admins, foremen and cost figures,
Administration); phone width. Usage: python3 rights_demo.py /path/to/live.html > results_rights_demo.json"""
import sys, json
from playwright.sync_api import sync_playwright
APP = sys.argv[1] if len(sys.argv) > 1 else 'live.html'
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
    J = lambda js: pg.evaluate(js)
    J("aiHint=()=>{};rasaBubble=()=>{};window.confirmBox=()=>Promise.resolve(true);state.scope='ALL';render()")
    SA = J("me().id")
    def as_(uid): pg.select_option('#role', uid); pg.wait_for_timeout(300); J("state.scope='ALL';render()")
    def admin(tab): as_(SA); J(f"state.view='admin';state.adminTab='{tab}';render()"); pg.wait_for_timeout(200)
    def nav(): return J("NAV_VIEWS.slice()")
    def first(role, extra=''): return J(f"(DB.master.users.find(u=>u.role==='{role}'&&u.active!==false{extra})||{{}}).id")
    CO, PM, SM, EN, FO, PL = first('costing', '&&!isCoord(u)'), first('pm', '&&!isHead(u)'), first('sm'), first('eng'), first('foreman'), first('plan', "&&!u.crole")

    # ---- the tab
    admin('rights')
    ck('Roles and rights', 'Administration has a Roles and rights tab, also in the side menu', 'Roles and rights' in pg.inner_text('.chips') and J("[...document.querySelectorAll('#nav [data-navtab]')].some(b=>b.dataset.navtab==='rights')"))
    rows = J("document.querySelectorAll('#rightsPanel tbody tr:not(.rgrp)').length")
    ck('Roles and rights', 'seventeen rights in four groups (daily reports, planning, cost, projects)', rows == 17 and J("[...document.querySelectorAll('#rightsPanel tr.rgrp')].map(r=>r.textContent.trim())") == ['Daily reports', 'Planning', 'Cost', 'Projects'], rows)
    heads = J("[...document.querySelectorAll('#rightsPanel thead th.rcol')].map(t=>t.textContent.trim())")
    ck('Roles and rights', 'a column for each role except super admin, plus the demo custom role', len(heads) == 11 and 'Super Admin' not in ' '.join(heads) and heads[-1].startswith('Planning Section Manager'), heads)
    ck('Roles and rights', 'the ticks show today\'s rights: planning engineers load baselines; costing engineers and project managers load costing files; site engineers and foremen prepare daily reports',
       J("document.querySelector('[data-rr=\"plan|planning.manage\"]').checked && document.querySelector('[data-rr=\"costing|costing.manage\"]').checked && document.querySelector('[data-rr=\"pm|costing.manage\"]').checked && document.querySelector('[data-rr=\"eng|dpr.create\"]').checked && document.querySelector('[data-rr=\"foreman|dpr.create\"]').checked && !document.querySelector('[data-rr=\"sm|money.view\"]').checked"))
    ck('Roles and rights', 'foremen and cost figures cannot be ticked', J("document.querySelector('[data-rr=\"foreman|money.view\"]').disabled") and not J("document.querySelector('[data-rr=\"foreman|money.view\"]').checked"))
    ck('Roles and rights', 'rights that come with a position say so (Head, coordinator, regional approver)', 'Also with the position: Head of Planning and Cost Control; regional report approver' in pg.inner_text('#rightsPanel'))
    ck('Roles and rights', 'nothing is marked as changed to start with', J("document.querySelectorAll('#rightsPanel .rdot,#screensPanel .rdot').length") == 0)
    sc = J("document.querySelectorAll('#screensPanel tbody tr').length")
    ck('Screens by role', 'twenty-one menu screens per role; Administration is not one of them', sc == 21 and 'Settings' not in J("[...document.querySelectorAll('#screensPanel tbody td:first-child')].map(t=>t.textContent).join('|')"), sc)
    ck('Screens by role', 'the ticks show today\'s menus (a foreman sees Daily reports, not the Executive summary; a project manager sees the cost dashboard)',
       J("document.querySelector('[data-sr=\"foreman|dpr\"]').checked && !document.querySelector('[data-sr=\"foreman|exec\"]').checked && document.querySelector('[data-sr=\"pm|cdash\"]').checked"))

    # ---- role rights
    as_(CO)
    ck('Rights by role', 'before: a costing engineer prepares monthly cost reports', J("canPrepRel('cost')") is True)
    admin('rights'); pg.uncheck('[data-rr="costing|report.cost.prepare"]'); pg.wait_for_timeout(300)
    ck('Rights by role', 'unticking a right marks it changed (●)', J("!!document.querySelector('[data-rr=\"costing|report.cost.prepare\"]').parentElement.querySelector('.rdot')") and J("DB.rights.role.costing['report.cost.prepare']") is False)
    as_(CO)
    ck('Rights by role', '...the costing engineer can no longer prepare one', J("canPrepRel('cost')") is False)
    r = J(f"(()=>{{try{{relActLocal({{action:'save',project_id:accessIds()[0],kind:'cost',period_type:'month',period:curMonth(),figures:{{}}}});return 'saved'}}catch(e){{return e.message}}}})()")
    ck('Rights by role', '...and saving one is refused', r != 'saved', r)
    ck('Rights by role', '...the costing coordinator keeps it through the position', J("(()=>{const c=DB.master.users.find(u=>isCoord(u));if(!c)return null;const k=state.uid,kr=state.role;state.uid=c.id;state.role=c.role;const v=canPrepRel('cost');state.uid=k;state.role=kr;return v})()") in (True, None))
    admin('rights'); pg.check('[data-rr="costing|report.cost.prepare"]'); pg.wait_for_timeout(300)
    ck('Rights by role', 'ticking it again goes back to the default and removes the setting', J("DB.rights.role.costing['report.cost.prepare']") is None and J("document.querySelectorAll('#rightsPanel .rdot').length") == 0)
    pg.check('[data-rr="pm|planning.manage"]'); pg.wait_for_timeout(300)
    as_(PM)
    ck('Rights by role', 'a right given to project managers: they load baselines and see the weekly update', J("canBaseline()&&canUpdate()") is True and 'upd' in nav(), nav())
    admin('rights'); pg.uncheck('[data-rr="pm|planning.manage"]'); pg.wait_for_timeout(300)
    as_(PM); ck('Rights by role', '...and back', J("canBaseline()") is False and 'upd' not in nav())
    admin('rights'); pg.check('[data-rr="eng|money.view"]'); pg.wait_for_timeout(300)
    as_(EN); ck('Rights by role', 'cost figures given to site engineers: the cost layout and the Contract row of the rack', J("isSiteRole()") is False and J("rasaMoneyOk()") is True and J("docCanRead('contract')") is True)
    admin('rights'); pg.uncheck('[data-rr="eng|money.view"]'); pg.wait_for_timeout(300)
    as_(EN); ck('Rights by role', '...and taken away again', J("isSiteRole()") is True and J("docCanRead('contract')") is False)
    admin('rights'); r = J("(()=>{try{rightsLocal({action:'role_right',role_key:'foreman',right_key:'money.view',allow:true});return 'saved'}catch(e){return e.message}})()")
    ck('Rules that never change', 'cost figures cannot be given to foremen (refused even when ticked by script)', 'Foremen never' in r, r)

    # ---- screens
    admin('rights'); pg.uncheck('[data-sr="pm|cdash"]'); pg.wait_for_timeout(300)
    as_(PM); ck('Screens by role', 'a screen unticked for project managers leaves their menu', 'cdash' not in nav(), nav())
    J("state.view='cdash';render()"); ck('Screens by role', '...opening it directly sends them back to an allowed screen', J("state.view") != 'cdash' and J("state.view") in nav(), J("state.view"))
    admin('rights'); pg.check('[data-sr="pm|cdash"]'); pg.wait_for_timeout(300)
    ck('Screens by role', '...ticking it again removes the setting', J("(DB.rights.screen.pm||{}).cdash") is None)
    pg.check('[data-sr="sm|new"]'); pg.check('[data-rr="sm|dpr.create"]'); pg.wait_for_timeout(300)
    as_(SM); ck('Screens by role', 'daily reports and the New report screen given to site managers: the menu shows it and drafts can be edited', 'new' in nav() and J("canCreate()") is True and J("actionsFor({status:'Draft',p:accessIds()[0]}).includes('edit')") is True, nav())
    admin('rights'); pg.uncheck('[data-rr="sm|dpr.create"]'); pg.uncheck('[data-sr="sm|new"]'); pg.wait_for_timeout(300)
    as_(SM); ck('Screens by role', '...a screen shown without the right still needs the right (New report needs Prepare daily reports)', 'new' not in nav())
    admin('rights'); ck('Screens by role', 'Administration cannot be given to other roles', 'Unknown screen' in J("(()=>{try{rightsLocal({action:'screen',role_key:'pm',view_key:'admin',visible:true});return 'saved'}catch(e){return e.message}})()"))

    # ---- custom roles
    pg.fill('#crName', 'Contract & Commercial Engineer'); pg.select_option('#crBase', 'costing'); pg.click('[data-crcreate]'); pg.wait_for_timeout(300)
    ck('Custom roles', 'a custom role is created from Costing Engineer and gets its own column in both tables', J("!!appRole('c_contract_commercial_engineer')") and J("!!document.querySelector('[data-rr=\"c_contract_commercial_engineer|costing.manage\"]')") and J("!!document.querySelector('[data-sr=\"c_contract_commercial_engineer|cdash\"]')"))
    ck('Custom roles', '...it starts with the rights of the role it is made from', J("document.querySelector('[data-rr=\"c_contract_commercial_engineer|costing.manage\"]').checked && !document.querySelector('[data-rr=\"c_contract_commercial_engineer|planning.manage\"]').checked"))
    pg.fill('#crName', 'contract & COMMERCIAL engineer'); pg.select_option('#crBase', 'plan'); pg.click('[data-crcreate]'); pg.wait_for_timeout(300)
    ck('Custom roles', 'names are unique whatever the capitals', J("appRoles().filter(r=>/contract/i.test(r.name)).length") == 1)
    ck('Custom roles', 'a custom role cannot be made from the super admin', 'any role except super admin' in J("(()=>{try{rightsLocal({action:'role_create',name:'Deputy',base_role:'sa'});return 'saved'}catch(e){return e.message}})()"))
    pg.uncheck('[data-rr="c_contract_commercial_engineer|report.cost.prepare"]'); pg.check('[data-rr="c_contract_commercial_engineer|docs.planning"]'); pg.wait_for_timeout(300)
    admin('users'); J(f"admDrawer('users','{CO}')"); pg.wait_for_timeout(200)
    opts = J("[...document.querySelectorAll('#admForm [name=role] option')].map(o=>o.value)")
    ck('Users and access', 'the role list includes the custom roles', 'c_contract_commercial_engineer' in opts and 'c_planning_section_manager' in opts, opts)
    pg.select_option('#admForm [name=role]', 'c_contract_commercial_engineer'); J("document.querySelector('#admForm').requestSubmit()"); pg.wait_for_timeout(300)
    ck('Users and access', 'a person is given the custom role; the users list shows its name', J(f"userById('{CO}').crole") == 'c_contract_commercial_engineer' and J(f"userById('{CO}').role") == 'costing' and 'Contract & Commercial Engineer' in pg.inner_text('#view'))
    as_(CO); ck('Custom roles', '...the person gets the custom role\'s rights and keeps the built-in rules of a costing engineer', J("canPrepRel('cost')") is False and J("docCanKeep('planning')") is True and J("canCost()") is True)
    admin('rights'); pg.click('[data-cractive="c_contract_commercial_engineer|0"]'); pg.wait_for_timeout(300)
    ck('Custom roles', 'a role still given to someone cannot be switched off', J("appRole('c_contract_commercial_engineer').active") is True)
    pg.fill('[data-crname="c_contract_commercial_engineer"]', 'C&C Engineer'); pg.press('[data-crname="c_contract_commercial_engineer"]', 'Tab'); pg.wait_for_timeout(300)
    ck('Custom roles', 'it can be renamed', J("appRole('c_contract_commercial_engineer').name") == 'C&C Engineer')
    admin('users'); J(f"admDrawer('users','{CO}')"); pg.select_option('#admForm [name=role]', 'costing'); J("document.querySelector('#admForm').requestSubmit()"); pg.wait_for_timeout(300)
    admin('rights'); pg.click('[data-cractive="c_contract_commercial_engineer|0"]'); pg.wait_for_timeout(300)
    ck('Custom roles', 'once nobody has it, it can be switched off; its column goes', J("appRole('c_contract_commercial_engineer').active") is False and not J("!!document.querySelector('[data-rr=\"c_contract_commercial_engineer|costing.manage\"]')"))
    ck('Custom roles', 'the demo section managers have the Planning Section Manager role and still approve their region', J("userById('U48').crole") == 'c_planning_section_manager' and J("(()=>{const k=state.uid,kr=state.role;state.uid='U48';state.role='plan';const p=PROJECTS.find(p=>p.region===(DB.relApprovers.find(a=>a.user_id==='U48')||{}).region_id&&accessIds().includes(p.id));const v=p?relCanApprove(p.id,'planning'):null;state.uid=k;state.role=kr;return v})()") is True)

    # ---- access for any role
    admin('users'); J(f"admDrawer('users','{PL}')"); pg.wait_for_timeout(200)
    ck('Users and access', 'the access choice is offered for a planning engineer, with regions and projects', J("!document.querySelector('#accMode').hidden && !document.querySelector('#accR').hidden && !document.querySelector('#accP').hidden"))
    pg.select_option('#admForm [name=accmode]', 'all'); pg.wait_for_timeout(100)
    ck('Users and access', 'All projects hides the region and project lists', J("document.querySelector('#accR').hidden && document.querySelector('#accP').hidden"))
    J("document.querySelector('#admForm').requestSubmit()"); pg.wait_for_timeout(300)
    ck('Users and access', 'the users list says All projects', J(f"accessText(userById('{PL}'))") == 'All projects' and 'All projects' in pg.inner_text('#view'))
    as_(PL); ck('Users and access', 'the planning engineer now has every project', J("accessIds().length") == J("PROJECTS.length"), J("accessIds().length"))
    admin('users'); J(f"admDrawer('users','{PM}')"); pg.wait_for_timeout(200)
    reg = J("DB.master.regions.find(r=>PROJECTS.some(p=>p.region===r.id&&!accessIds(userById('%s')).includes(p.id))).id" % PM)
    pg.check(f'#admForm input[name=regions][value="{reg}"]'); J("document.querySelector('#admForm').requestSubmit()"); pg.wait_for_timeout(300)
    as_(PM); ck('Users and access', 'a project manager can be given a whole region (before: projects only)', J(f"PROJECTS.filter(p=>p.region==='{reg}').every(p=>accessIds().includes(p.id))") is True)
    admin('users'); J(f"admDrawer('users','{EN}')"); J("document.querySelectorAll('#admForm input[name=projects],#admForm input[name=regions]').forEach(c=>c.checked=false)")
    J("document.querySelector('#admForm').requestSubmit()"); pg.wait_for_timeout(200)
    ck('Users and access', 'a site engineer needs at least one project, one region or All projects', 'at least one project' in J("document.querySelector('#admErr').textContent"), J("document.querySelector('#admErr').textContent"))
    J("closeDrawer()")
    ck('Users and access', 'super admins and executive managers see everything without an access choice', (J(f"admDrawer('users','{SA}');document.querySelector('#accMode').hidden") is True))
    J("closeDrawer()")

    # ---- rights for one person
    admin('users'); J(f"admDrawer('users','{CO}');document.querySelector('#urWrap').open=true"); pg.wait_for_timeout(200)
    ck('Rights for one person', 'the person form lists every right with "As the role", Allow and Remove', J("document.querySelectorAll('#urBox select[data-ur]').length") == 17 and 'As the role (yes)' in pg.inner_text('#urBox'))
    pg.select_option(f'#urBox select[data-ur="{CO}|report.cost.prepare"]', '0'); pg.wait_for_timeout(300)
    ck('Rights for one person', 'Remove is saved at once', J(f"DB.rights.user['{CO}']['report.cost.prepare']") is False)
    J("closeDrawer()"); as_(CO); ck('Rights for one person', '...the costing engineer cannot prepare the cost report; the exception wins over the role', J("canPrepRel('cost')") is False and J("canCost()") is True)
    admin('rights'); ck('Rights for one person', '...and is listed under People with their own exceptions', 'Removed: Prepare monthly cost reports' in pg.inner_text('#rightsPeople'))
    admin('users'); J(f"admDrawer('users','{CO}');document.querySelector('#urWrap').open=true"); pg.select_option(f'#urBox select[data-ur="{CO}|report.cost.prepare"]', ''); pg.wait_for_timeout(300); J("closeDrawer()")
    as_(CO); ck('Rights for one person', 'back to "As the role" removes the exception', J("canPrepRel('cost')") is True and not J(f"(DB.rights.user['{CO}']||{{}})['report.cost.prepare']!==undefined"))
    ck('Rules that never change', 'a foreman cannot be given cost figures, even by a person exception', 'Foremen never' in J(f"(()=>{{const k=state.uid,kr=state.role;state.uid='{SA}';state.role='sa';try{{rightsLocal({{action:'user_right',user_id:'{FO}',right_key:'money.view',allow:true}});return 'saved'}}catch(e){{return e.message}}finally{{state.uid=k;state.role=kr}}}})()"))
    admin('users'); J(f"admDrawer('users','{FO}')"); pg.wait_for_timeout(200)
    ck('Rules that never change', '...the foreman\'s cost figures choice is locked in the form', J(f"document.querySelector('#urBox select[data-ur=\"{FO}|money.view\"]').disabled") is True)
    J("closeDrawer()")
    ck('Rules that never change', 'a super admin cannot be limited', 'super admin always' in J("(()=>{try{rightsLocal({action:'user_right',user_id:'U29',right_key:'money.view',allow:false});return 'saved'}catch(e){return e.message}})()"))
    as_(PM); ck('Rules that never change', 'only a super admin changes rights', 'Only a super admin' in J("(()=>{try{rightsLocal({action:'role_right',role_key:'pm',right_key:'money.view',allow:false});return 'saved'}catch(e){return e.message}})()"))
    ck('Rules that never change', 'Administration is never in a project manager\'s menu', 'admin' not in nav())

    # ---- history, persistence
    admin('rights')
    hist = pg.inner_text('#rightsHist')
    ck('History', 'every change is in the history with who made it', all(x in hist for x in ['Role right', 'Screen', 'Role created', 'Role changed', 'Person exception']) and 'Asarudeen Sowkath Ali' in hist, hist[:300])
    pg.reload(); pg.wait_for_timeout(1500)
    if J("!!document.querySelector('#lgId')&&!document.querySelector('#auth').hidden"):
        pg.fill('#lgId', 'asarudeen@company.com'); pg.fill('#lgPw', 'ProTrack@2026'); pg.click('#lgBtn'); pg.wait_for_timeout(1400)
    ck('History', 'the settings are kept after a reload', J("appRole('c_contract_commercial_engineer')&&appRole('c_contract_commercial_engineer').name") == 'C&C Engineer' and J(f"accessText(userById('{PL}'))") == 'All projects')

    # ---- phone
    ph = b.new_page(viewport={'width': 390, 'height': 844}); ph.route('**/*', route); perr = []; ph.on('pageerror', lambda e: perr.append(str(e)))
    ph.goto('file://' + APP); ph.wait_for_timeout(800)
    ph.fill('#lgId', 'asarudeen@company.com'); ph.fill('#lgPw', 'ProTrack@2026'); ph.click('#lgBtn'); ph.wait_for_timeout(1400)
    ph.evaluate("aiHint=()=>{};rasaBubble=()=>{};state.view='admin';state.adminTab='rights';render()"); ph.wait_for_timeout(300)
    ck('Phone', 'the Roles and rights tab fits the phone width (tables scroll inside their box)', ph.evaluate("document.documentElement.scrollWidth") <= 392, ph.evaluate("document.documentElement.scrollWidth"))
    ph.evaluate(f"state.adminTab='users';render();admDrawer('users','{CO}');document.querySelector('#urWrap').open=true"); ph.wait_for_timeout(200)
    ck('Phone', 'the person form with its rights fits too', ph.evaluate("document.documentElement.scrollWidth") <= 392)
    ck('Page', 'no script errors', not errs and not perr, errs + perr)
    b.close()
print(json.dumps({'suite': 'rights_demo', 'page': APP, 'passed': sum(r['result'] == 'PASS' for r in R), 'total': len(R), 'checks': R}, indent=1))
