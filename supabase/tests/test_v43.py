#!/usr/bin/env python3
"""Server-side tests for ProTrack schema update v43 (the budget supplement and change request forms, Approval Hub and the
posting of approved WFs to the logs). Loads schema.sql and every update v2 to v43. Usage: python3 test_v43.py"""
import json, os, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PG = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']
DBN = 'pt_v43_test'
results = []
def find(name):
    for d in (HERE, os.path.dirname(HERE)):
        if os.path.exists(os.path.join(d, name)): return os.path.join(d, name)
    return None
def psql(sql=None, file=None):
    p = subprocess.run(PG + ['-d', DBN] + (['-f', file] if file else ['-c', sql]), capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()
def q(sql):
    rc, out, err = psql(sql)
    if rc: raise SystemExit('setup failed: ' + err + '\n' + sql)
    return {'t': 'true', 'f': 'false'}.get(out, out)
PEOPLE = {'pe': ('plan', 'Pia Planner'), 'cc': ('costing', 'Cody Coordinator'), 'c3': ('costing', 'Cora Costing'), 'sa': ('sa', 'Sara Admin'), 'ap': ('pm', 'Adam Approver'), 'co': ('costing', 'Carla Costing'), 'c2': ('costing', 'Chris Costing'),
          'pm': ('pm', 'Paul Manager'), 'pl': ('plan', 'Peter Planner'), 'fo': ('foreman', 'Faisal Foreman'), 'out': ('costing', 'Olga Outside'), 'ex': ('exec', 'Eva Executive')}
U = {k: f'00000000-0000-0000-0000-0000000043{i:02d}' for i, k in enumerate(PEOPLE, start=1)}
def run_as(who, body):
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write(f"begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub', '{U[who]}', true) \\g /dev/null\n{body}\ncommit;\n"); path = f.name
    try: return psql(file=path)
    finally: os.unlink(path)
def check(name, ok, detail=''):
    results.append({'check': name, 'pass': bool(ok), 'detail': str(detail)[:300]})
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '  -> ' + str(detail)[:300]))
def lit(o): return "'" + json.dumps(o).replace("'", "''") + "'::jsonb"
def call(who, fn, p):
    rc, out, err = run_as(who, f"select {fn}({lit(p)});")
    return rc, (json.loads(out.splitlines()[-1]) if rc == 0 and out else None), err
def ok_(name, res, cond=lambda r: True):
    rc, r, err = res
    try: good = rc == 0 and cond(r)
    except Exception as e: good, err = False, repr(e)
    check(name, good, r if rc == 0 else err); return r
def no_(name, res, msg=None):
    rc, r, err = res; check(name, rc != 0 and (msg is None or msg.lower() in err.lower()), err or r)
def one(who, sql):
    rc, out, err = run_as(who, sql.rstrip().rstrip(';') + ';')
    o = out.splitlines()[-1] if rc == 0 and out else 'ERR ' + err
    return {'t': 'true', 'f': 'false'}.get(o, o)





subprocess.run(PG + ['-d', 'postgres', '-c', f'drop database if exists {DBN}'], capture_output=True)
subprocess.run(PG + ['-d', 'postgres', '-c', f'create database {DBN}'], check=True, capture_output=True)
for f in ['TEST-ONLY-supabase-stub.sql', 'schema.sql'] + [f'schema-update-v{i}.sql' for i in range(2, 44)]:
    path = find(f)
    if not path: continue
    rc, out, err = psql(file=path)
    if rc: raise SystemExit(f + ': ' + err)
q("insert into auth.users (id, email) values " + ",".join(f"('{U[k]}', '{k}@test.local')" for k in PEOPLE))
q("insert into profiles (id, name, role) values " + ",".join(f"('{U[k]}', '{n}', '{r}')" for k, (r, n) in PEOPLE.items()))
q("insert into regions (id, name) values ('R1','Western'); insert into sectors (id, name) values ('S1','Power')")
q("insert into projects (id, name, short, region, sector, start_date, finish_date, value_m, status, pe_number) values ('P1','Thuwal KAUST 2','TK2','R1','S1','2022-12-29','2026-12-31',33.6,'Active','PE-262')")
q("insert into project_access (user_id, project_id) values " + ",".join(f"('{U[k]}','P1')" for k in ['pe', 'cc', 'co', 'c2', 'pm', 'pl', 'fo', 'ap']))
q(f"insert into pcc_designations (user_id, designation) values ('{U['cc']}', 'coordinator')")
TODAY = q("select pt_today_sa()"); MON = TODAY[:7]; PREV = q(f"select pt_wf_prev('{MON}')"); PREV2 = q(f"select pt_wf_prev('{PREV}')")
check('Install: wf.initiate and wf.record are listed; wf.initiate is a planning and costing right by default', q("select 'wf.initiate' = any(pt_rights()) and 'wf.record' = any(pt_rights())") == 'true'
      and q("select pt_right_default('plan', 'wf.initiate') and pt_right_default('costing', 'wf.initiate') and not pt_right_default('pm', 'wf.initiate') and not pt_right_default('costing', 'wf.record')") == 'true')
check('Install: the costing coordinator holds wf.record by position', q(f"select pt_wf('{U['cc']}', 'P1', 'wf.record')") == 'true' and q(f"select pt_wf('{U['co']}', 'P1', 'wf.record')") == 'false')
L1 = [{'description': 'Estimate overrun in salaries according to delay in TCC', 'category': 'Project Execution', 'user_field': 'SM', 'amount': '-120000', 'wbs_id': 'PE-262-01-001-01'},
      {'description': 'Actual expenses overrun in 132kV power cables manpower', 'category': 'Project Execution', 'user_field': 'MAN.ELC', 'amount': '-47650'},
      {'description': 'Saving as per attached sheets', 'category': 'Cont-Savings', 'user_field': 'CONT', 'amount': '1939967', 'remarks': 'contingency released'}]
no_('Forms: a foreman cannot prepare a form', call('fo', 'wf_form_save', {'project_id': 'P1', 'kind': 'BRF'}), 'wf.initiate')
no_('Forms: a project manager (no wf.initiate) cannot either', call('pm', 'wf_form_save', {'project_id': 'P1', 'kind': 'BRF'}), 'wf.initiate')
F1 = ok_('Forms: a planning engineer prepares a BRF: BR-01, a draft, with the approval chain', call('pe', 'wf_form_save', {'project_id': 'P1', 'kind': 'BRF', 'title': 'Salaries and cables', 'data': {'date': TODAY}}), lambda r: r['ref_no'] == 'BR-01')
check('Forms: the draft and its history', q(f"select status || '/' || prepared_by_name from wf_forms where id='{F1['id']}'") == 'Draft/Pia Planner' and q(f"select count(*) from wf_events where form_id='{F1['id']}'") == '1')
F2 = ok_('Forms: the next one is BR-02', call('co', 'wf_form_save', {'project_id': 'P1', 'kind': 'BRF'}), lambda r: r['ref_no'] == 'BR-02')
no_('Forms: a reference used twice is refused', call('co', 'wf_form_save', {'project_id': 'P1', 'kind': 'BRF', 'ref_no': 'BR-02'}), 'already used')
no_('Submit: a form without lines is refused', call('pe', 'wf_form_act', {'action': 'submit', 'id': F1['id']}), 'at least one line')
call('pe', 'wf_form_save', {'id': F1['id'], 'lines': [dict(L1[0], user_field='XYZ')]})
no_('Submit: a user field outside the list is refused with its line', call('pe', 'wf_form_act', {'action': 'submit', 'id': F1['id']}), 'Line 1: user field "XYZ" is not in the list')
call('pe', 'wf_form_save', {'id': F1['id'], 'lines': [dict(L1[0], amount='0')]})
no_('Submit: a zero amount is refused', call('pe', 'wf_form_act', {'action': 'submit', 'id': F1['id']}), 'zero')
ok_('Forms: the lines are saved; contingency adds the Vice President to the approvers', call('pe', 'wf_form_save', {'id': F1['id'], 'lines': L1, 'title': 'Salaries and cables'}), lambda r: True)
check('...the chain', json.loads(q(f"select approvers from wf_forms where id='{F1['id']}'"))[-1] == 'Vice President')
no_('Hub: without a token nothing is taken', call('co', 'wf_hub_next', {'token': 'x'}), 'Not authorised')
S1 = ok_('Submit: submitted, with its totals (supplement -167,650, savings 1,939,967)', call('pe', 'wf_form_act', {'action': 'submit', 'id': F1['id']}), lambda r: r['totals'] == {'supplement': -167650, 'savings': 1939967, 'net': 1772317, 'lines': 3})
check('Submit: queued for Approval Hub with the project and the lines', q(f"select status || '/' || (payload -> 'project' ->> 'pe_number') || '/' || jsonb_array_length(payload -> 'lines') from wf_outbox where form_id='{F1['id']}'") == 'Queued/PE-262/3')
no_('Submit: a submitted form is not changed any more', call('pe', 'wf_form_save', {'id': F1['id'], 'lines': []}), 'not changed')
no_('Hub: only a super admin makes the token', call('co', 'wf_hub_setup', {'action': 'new_token'}), 'super admin')
T = ok_('Hub: the super admin makes the token (shown once)', call('sa', 'wf_hub_setup', {'action': 'new_token'}), lambda r: r['token'].startswith('pthub_') and r['active'])['token']
check('Hub: the token is kept only as its hash', q("select token_hash <> '' and position('pthub_' in token_hash) = 0 from wf_hub_cfg") == 'true' and one('co', "select wf_hub_status() ->> 'active'") == 'true')
def anon(fn, p):
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write(f"begin;\nset local role anon;\nselect {fn}({lit(p)});\ncommit;\n"); path = f.name
    try:
        rc, out, err = psql(file=path); return rc, (json.loads(out.splitlines()[-1]) if rc == 0 and out else None), err
    finally: os.unlink(path)
no_('Hub: a wrong token is refused', anon('wf_hub_next', {'token': T + 'x'}), 'Not authorised')
N = ok_('Hub: with its token (the anon key), the hub takes the queued submission', anon('wf_hub_next', {'token': T}), lambda r: len(r['items']) == 1 and r['items'][0]['payload']['ref_no'] == 'BR-01')
ok_('Hub: taken once: the next call gives nothing', anon('wf_hub_next', {'token': T}), lambda r: r['items'] == [])
ok_('Hub: it reports the WF number: In approval', anon('wf_hub_update', {'token': T, 'message_id': N['items'][0]['message_id'], 'status': 'received', 'wf_no': 'WF-1001', 'step': 'Costing Manager'}), lambda r: r['status'] == 'In approval')
check('...the form shows the WF number and the step', q(f"select status || '/' || wf_no || '/' || hub_step from wf_forms where id='{F1['id']}'") == 'In approval/WF-1001/Costing Manager')
no_('Record: while the hub is connected, a decision is not recorded by hand', call('cc', 'wf_form_act', {'action': 'record', 'id': F1['id'], 'decision': 'approved', 'wf_no': 'WF-1001', 'date': TODAY}), 'connected')
R1 = ok_('Hub: approved: the form is approved and posted at once', anon('wf_hub_update', {'token': T, 'form_id': F1['id'], 'status': 'approved', 'date': TODAY, 'approver': 'Vice President'}), lambda r: r['status'] == 'Approved' and r['version'] == MON and len(r['posted']['rows']) == 3)
rows = q(f"select string_agg(supp_no || ':' || amount::numeric(14,0) || ':' || user_field || ':' || version || ':' || wf_no, ',' order by supp_no) from budget_supplements where wf_form='{F1['id']}'")
check('Post: three rows in the budget supplement log, BR-01/1 to /3, with the WF number and the version of the approval month', rows == f'BR-01/1:-120000:SM:{MON}:WF-1001,BR-01/2:-47650:MAN.ELC:{MON}:WF-1001,BR-01/3:1939967:CONT:{MON}:WF-1001', rows)
check('Post: the log was started by the WF; the rows are approved, dated the approval', q("select file_name from import_batches where kind='supplements'") == 'Started by the approved WF WF-1001' and q(f"select bool_and(approval_status = 'Approved' and supp_date = '{TODAY}') from budget_supplements where wf_form='{F1['id']}'") == 'true')
check('Post: the cost report\'s budget change counts them (supplements raise the budget, savings lower it)', q(f"select pt_supp_approved('P1', '{MON}')") == '-1772317.000000' or q(f"select pt_supp_approved('P1', '{MON}')::numeric(14,0)") == '-1772317')
check('Post: the history says it', q(f"select string_agg(action, ' | ' order by id) from wf_events where form_id='{F1['id']}'").endswith('Approval Hub: approved | Posted to the budget supplement log'))
rid = q("select id from budget_supplements where supp_no='BR-01/1'")
no_('Log: a row posted from a WF is not removed on the log screen', call('co', 'supp_update', {'action': 'remove', 'project_id': 'P1', 'id': rid, 'reason': 'no longer needed'}), 'posted from the approved WF')
no_('Log: nor is its amount changed', call('co', 'supp_update', {'action': 'edit', 'project_id': 'P1', 'id': rid, 'values': {'supp_no': 'BR-01/1', 'supp_date': TODAY, 'user_field': 'SM', 'category': 'Project Execution', 'description': 'x', 'amount': '-1', 'version': MON}}), 'only its version and remarks')
ok_('Log: its remarks change on the log screen', call('co', 'supp_update', {'action': 'edit', 'project_id': 'P1', 'id': rid, 'values': {'supp_no': 'BR-01/1', 'supp_date': TODAY, 'user_field': 'SM', 'category': 'Project Execution',
    'description': 'Estimate overrun in salaries according to delay in TCC', 'amount': '-120000', 'wbs_id': 'PE-262-01-001-01', 'version': MON, 'remarks': 'see WF'}}), lambda r: r['changed'])
no_('Version: a project manager does not move it', call('pm', 'wf_form_act', {'action': 'set_version', 'id': F1['id'], 'version': PREV, 'reason': 'September report'}), 'costing')
no_('Version: a reason is needed', call('co', 'wf_form_act', {'action': 'set_version', 'id': F1['id'], 'version': PREV}), 'reason')
no_('Version: not two months back', call('co', 'wf_form_act', {'action': 'set_version', 'id': F1['id'], 'version': PREV2, 'reason': 'too far back'}), 'the month before the approval')
no_('Version: not in the future', call('co', 'wf_form_act', {'action': 'set_version', 'id': F1['id'], 'version': '2099-01', 'reason': 'future month'}), 'this month')
ok_('Version: the costing engineer moves it to the previous month, with the reason', call('co', 'wf_form_act', {'action': 'set_version', 'id': F1['id'], 'version': PREV, 'reason': 'management approved the values in the previous month'}), lambda r: r['changed'] and r['rows'] == 3)
check('...the three rows and the form are in the previous month, and the log history says it', q(f"select string_agg(distinct version, ',') from budget_supplements where wf_form='{F1['id']}'") == PREV and q(f"select version from wf_forms where id='{F1['id']}'") == PREV
      and q("select count(*) from supp_audit where action='changed' and reason like 'management approved%'") == '1')
q("insert into import_batches (project_id, kind, file_name, file_hash, source_period, status) values ('P1', 'supplements', 'upload.xlsx', 'h1', '" + MON + "', 'committed')")
q("insert into budget_supplements (batch_id, project_id, period, supp_no, amount, category, user_field, approval_status, version) select id, 'P1', '" + MON + "', 'BR-01/1', -120000, 'Project Execution', 'SM', 'Approved', '" + PREV + "' from import_batches where file_name='upload.xlsx'")
check('Log: a new log carrying BR-01/1 keeps its link to the WF', q("select wf_form || '/' || wf_no from budget_supplements where supp_no='BR-01/1' order by id desc limit 1") == f"{F1['id']}/WF-1001")
# ---- by hand while the hub is off
ok_('Hub: the super admin switches the link off', call('sa', 'wf_hub_setup', {'action': 'off'}), lambda r: r['active'] is False)
no_('Hub: the old token stops working', anon('wf_hub_next', {'token': T}), 'Not authorised')
call('co', 'wf_form_save', {'id': F2['id'], 'lines': [{'description': 'Office rent saving', 'category': 'Project Execution', 'user_field': 'SM', 'amount': '25000'}], 'version_pref': PREV})
ok_('Submit: BR-02 (a saving, version asked: the previous month)', call('co', 'wf_form_act', {'action': 'submit', 'id': F2['id']}), lambda r: r['totals']['savings'] == 25000)
check('...no VP or EVP without contingency or management reserve', 'Vice President' not in q(f"select approvers::text from wf_forms where id='{F2['id']}'"))
no_('Record: a planning engineer (no wf.record) does not record a decision', call('pe', 'wf_form_act', {'action': 'record', 'id': F2['id'], 'decision': 'approved', 'wf_no': 'WF-2002', 'date': TODAY}), 'coordinator')
no_('Record: the WF number is needed', call('cc', 'wf_form_act', {'action': 'record', 'id': F2['id'], 'decision': 'approved', 'date': TODAY}), 'WF number')
no_('Record: a decision date in the future is refused', call('cc', 'wf_form_act', {'action': 'record', 'id': F2['id'], 'decision': 'approved', 'wf_no': 'WF-2002', 'date': '2099-01-01'}), 'future')
no_('Record: a decision date before the submission is refused', call('cc', 'wf_form_act', {'action': 'record', 'id': F2['id'], 'decision': 'approved', 'wf_no': 'WF-2002', 'date': '2020-01-01'}), 'before the form was submitted')
ok_('Record: the costing coordinator records the approval by hand: posted, in the version asked', call('cc', 'wf_form_act', {'action': 'record', 'id': F2['id'], 'decision': 'approved', 'wf_no': 'WF-2002', 'date': TODAY, 'approver': 'Regional Manager'}),
    lambda r: r['status'] == 'Approved' and r['version'] == PREV and r['posted']['rows'] == ['BR-02'])
check('...the form says it was recorded by hand, and by whom', q(f"select decision_source || '/' || recorded_by_name from wf_forms where id='{F2['id']}'") == 'manual/Cody Coordinator' and 'recorded by hand' in q(f"select string_agg(action, '|') from wf_events where form_id='{F2['id']}'"))
F3 = call('co', 'wf_form_save', {'project_id': 'P1', 'kind': 'BRF', 'lines': [{'description': 'Management reserve for prolongation', 'category': 'Mgmt Res-Proj Exe', 'user_field': 'MGT.RES', 'amount': '-300000'}]})[1]
call('co', 'wf_form_act', {'action': 'submit', 'id': F3['id']})
check('Chain: the management reserve adds the Executive Vice President', 'Executive Vice President' in q(f"select approvers::text from wf_forms where id='{F3['id']}'"))
no_('Record: a return needs its reason', call('cc', 'wf_form_act', {'action': 'record', 'id': F3['id'], 'decision': 'returned', 'wf_no': 'WF-3003', 'date': TODAY}), 'reason')
ok_('Record: returned for correction', call('cc', 'wf_form_act', {'action': 'record', 'id': F3['id'], 'decision': 'returned', 'wf_no': 'WF-3003', 'date': TODAY, 'comment': 'attach the prolongation sheet'}), lambda r: r['status'] == 'Returned' and r['posted'] is None)
ok_('Forms: a returned form is corrected and submitted again, keeping its WF number', call('co', 'wf_form_save', {'id': F3['id'], 'lines': [{'description': 'Management reserve for prolongation (sheet attached)', 'category': 'Mgmt Res-Proj Exe', 'user_field': 'MGT.RES', 'amount': '-250000'}]}), lambda r: True)
call('co', 'wf_form_act', {'action': 'submit', 'id': F3['id']})
check('...WF-3003 kept', q(f"select status || '/' || wf_no from wf_forms where id='{F3['id']}'") == 'Submitted/WF-3003')
ok_('Record: rejected: nothing is posted', call('cc', 'wf_form_act', {'action': 'record', 'id': F3['id'], 'decision': 'rejected', 'wf_no': 'WF-3003', 'date': TODAY, 'comment': 'use contingency first'}), lambda r: r['status'] == 'Rejected')
check('...no row of BR-03 in the log', q("select count(*) from budget_supplements where supp_no like 'BR-03%'") == '0')
F4 = call('co', 'wf_form_save', {'project_id': 'P1', 'kind': 'BRF'})[1]
no_('Cancel: a reason is needed', call('co', 'wf_form_act', {'action': 'cancel', 'id': F4['id']}), 'reason')
ok_('Cancel: a draft is cancelled with its reason', call('co', 'wf_form_act', {'action': 'cancel', 'id': F4['id'], 'reason': 'made by mistake'}), lambda r: r['status'] == 'Cancelled')
# ---- change requests
C1 = ok_('CRF: a change request is prepared: CR-01', call('co', 'wf_form_save', {'project_id': 'P1', 'kind': 'CRF', 'data': {'description': 'Additional 132kV cable route', 'sub_date': TODAY, 'client_ref': 'SEC/VO/14',
     'price_submitted': '600000', 'client_status': 'Submitted', 'price_client': '500000', 'cost_rev0': '380000', 'cost_current': '400000'}}), lambda r: r['ref_no'] == 'CR-01')
no_('CRF: a client approved price without the client approval is refused', call('co', 'wf_form_act', {'action': 'submit', 'id': C1['id']}), 'client approved price needs')
call('co', 'wf_form_save', {'id': C1['id'], 'data': {'description': 'Additional 132kV cable route', 'sub_date': TODAY, 'client_ref': 'SEC/VO/14', 'price_submitted': '600000', 'client_status': 'Approved', 'price_client': '500000', 'price_internal': '550000', 'cost_rev0': '380000', 'cost_current': '400000'}})
ok_('CRF: submitted', call('co', 'wf_form_act', {'action': 'submit', 'id': C1['id']}), lambda r: True)
ok_('CRF: approved (recorded by hand): added to the change order and claim log', call('cc', 'wf_form_act', {'action': 'record', 'id': C1['id'], 'decision': 'approved', 'wf_no': 'WF-4004', 'date': TODAY}), lambda r: r['posted']['how'] == 'added')
check('...with the prices, the cost, the client status and the WF', q("select kind || '/' || ref_no || '/' || est_price::numeric(12,0) || '/' || client_price::numeric(12,0) || '/' || internal_price::numeric(12,0) || '/' || est_cost::numeric(12,0) || '/' || client_status || '/' || wf_no from co_log where ref_no='CR-01'")
      == 'VO/CR-01/600000/500000/550000/400000/Approved/WF-4004')
q("insert into import_batches (project_id, kind, file_name, file_hash, source_period, status) values ('P1', 'volog', 'vo.xlsx', 'h2', '" + MON + "', 'committed')")
q("insert into co_log (batch_id, project_id, period, ref_no, kind, description) select id, 'P1', '" + MON + "', 'CR-02', 'VO', 'Fence' from import_batches where file_name='vo.xlsx'")
C2 = call('co', 'wf_form_save', {'project_id': 'P1', 'kind': 'CRF', 'data': {'description': 'Fence around the substation'}})[1]
call('co', 'wf_form_act', {'action': 'submit', 'id': C2['id']})
ok_('CRF: a change request already in the log gets its WF number and date', call('cc', 'wf_form_act', {'action': 'record', 'id': C2['id'], 'decision': 'approved', 'wf_no': 'WF-5005', 'date': TODAY}), lambda r: r['posted']['how'] == 'updated')
check('...the row of the log is updated, with its history', q("select wf_no || '/' || wf_date from co_log where ref_no='CR-02'") == f'WF-5005/{TODAY}' and q("select count(*) from co_log_updates where ref_no='CR-02'") == '1')
# ---- read and history
check('Read: a foreman reads no form; someone outside the project neither', one('fo', 'select count(*) from wf_forms') == '0' and one('out', 'select count(*) from wf_forms') == '0')
check('Read: a project manager reads the forms and their history; the outbox only a super admin', one('pm', 'select count(*) from wf_forms') == '6' and one('pm', 'select count(*) > 0 from wf_events') == 'true' and one('pm', 'select count(*) from wf_outbox') == '0' and one('sa', 'select count(*) > 0 from wf_outbox') == 'true')
rc, out, err = psql("update wf_events set action = 'x'")
check('History: never changed', rc != 0, err)
check('Hub: queued submissions are counted for the status', one('sa', "select (wf_hub_status() ->> 'queued')::int >= 0") == 'true')
# ---- rollback and again
rc, out, err = psql(file=find('schema-rollback-v43.sql'))
check('Rollback: runs; the functions are gone; forms and posted rows kept', rc == 0 and q("select to_regprocedure('wf_form_act(jsonb)') is null") == 'true' and q("select count(*) from wf_forms") == '6' and q("select count(*) from budget_supplements where wf_form is not null") == '5', err)
for i in range(2):
    rc, out, err = psql(file=find('schema-update-v43.sql'))
    check(f'Again: v43 runs ({i + 1})', rc == 0, err)
no_('Again: the guard of posted rows is back', call('co', 'supp_update', {'action': 'remove', 'project_id': 'P1', 'id': q("select max(id) from budget_supplements where supp_no='BR-01/1'"), 'reason': 'no longer needed'}), 'posted from the approved WF')

passed = sum(r['pass'] for r in results)
print(f'\n{passed}/{len(results)} passed')
json.dump({'suite': 'v43', 'passed': passed, 'total': len(results), 'checks': results}, open(os.path.join(HERE, 'test_v43_results.json'), 'w'), indent=1)
