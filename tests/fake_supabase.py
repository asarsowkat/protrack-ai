#!/usr/bin/env python3
"""A small stand-in for Supabase, for testing ProTrackAI in server mode without the internet.

It serves the app and answers the same calls the real Supabase client makes (sign in, table reads and
writes, server functions) by running them against a local PostgreSQL database built from the real
ProTrack schema, as the signed-in user, with row level security switched on. So every permission check
the tests see is the database's own, not something imitated here.

Only what ProTrackAI uses is implemented: select with eq/in/order/range and embedded child tables,
insert, upsert, update, delete, rpc, password sign-in and function calls (recorded, never sent).
Usage: python3 fake_supabase.py APP_HTML DBNAME PORT
"""
import json, os, subprocess, sys, tempfile, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP, DBN, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])
PSQL = ['psql', '-h', '/tmp', '-p', '5499', '-U', 'postgres', '-X', '-q', '-At', '-d', DBN, '-v', 'ON_ERROR_STOP=1']
PASSWORD = 'Test-Pass-2026'
EMBED_FK = {'dpr_lines': 'dpr_id', 'dpr_audit': 'dpr_id'}
CALLS = []            # function invocations (emails), for the tests to inspect
FAIL = set()          # tables made to fail, to test error handling
LOCK = threading.Lock()
_meta = {}

FAKE_JS = r"""(function(){
const API='/__sb';
function post(path,body){return fetch(API+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}).then(r=>r.json())}
function createClient(){
  let session=null;try{session=JSON.parse(localStorage.getItem('sb-fake-session')||'null')}catch(e){}
  const tok=()=>session&&session.access_token;
  class Q{constructor(t){this.q={table:t,op:'select',cols:'*',filters:[],order:[],range:null,body:null,ret:false,single:false}}
    select(c){if(this.q.op==='select')this.q.cols=c||'*';else{this.q.ret=true;this.q.cols=c||'*'}return this}
    insert(b){this.q.op='insert';this.q.body=Array.isArray(b)?b:[b];return this}
    upsert(b){this.q.op='upsert';this.q.body=Array.isArray(b)?b:[b];return this}
    update(b){this.q.op='update';this.q.body=b;return this}
    delete(){this.q.op='delete';return this}
    eq(c,v){this.q.filters.push([c,'eq',v]);return this}
    in(c,v){this.q.filters.push([c,'in',v]);return this}
    order(c,o){this.q.order.push([c,!(o&&o.ascending===false)]);return this}
    limit(n){this.q.range=[0,n-1];return this}
    range(a,b){this.q.range=[a,b];return this}
    single(){this.q.single=true;return this}
    then(res,rej){return post('/q',Object.assign({token:tok()},this.q)).then(res,rej)}
  }
  return {from:t=>new Q(t),
    rpc:(fn,args)=>({then:(res,rej)=>post('/rpc',{token:tok(),fn,args:args||{}}).then(res,rej)}),
    auth:{signInWithPassword:async({email,password})=>{const r=await post('/auth',{email,password});if(r.data&&r.data.session){session=r.data.session;localStorage.setItem('sb-fake-session',JSON.stringify(session))}return r},
      getSession:async()=>({data:{session}}),getUser:async()=>({data:{user:session&&session.user}}),
      signOut:async()=>{session=null;localStorage.removeItem('sb-fake-session');return {error:null}},
      resetPasswordForEmail:async()=>({data:{},error:null})},
    functions:{invoke:async(name,o)=>post('/fn',{name,body:o&&o.body})}};
}
window.supabase={createClient};})();"""


def lit(v):
    if v is None: return 'NULL'
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, (dict, list)): v = json.dumps(v)
    return "'" + str(v).replace("'", "''") + "'"


def ident(x):
    if not x.replace('_', '').isalnum(): raise ValueError('bad identifier ' + x)
    return '"' + x + '"'


def run(sql, uid=None):
    role = 'authenticated' if uid else 'anon'
    if sql.startswith('with r as ('):      # data-changing statements must stay at the top level
        body = sql.replace("select coalesce(jsonb_agg(to_jsonb(r)), '[]') from r", "select '@@' || coalesce(jsonb_agg(to_jsonb(r)), '[]')::text from r")
    else:
        body = f"select '@@' || coalesce(({sql})::text, 'null')"
    script = (f"begin;\nset local role {role};\nselect set_config('request.jwt.claim.sub', {lit(uid or '')}, true) is null;\n"
              f"{body};\ncommit;\n")
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write(script); path = f.name
    try:
        p = subprocess.run(PSQL + ['-f', path], capture_output=True, text=True)
    finally:
        os.unlink(path)
    if p.returncode:
        msg = p.stderr.strip().split('\n')[0]
        msg = msg.split('ERROR:', 1)[-1].strip()
        return None, {'message': msg}
    for line in p.stdout.splitlines():
        if line.startswith('@@'): return json.loads(line[2:]), None
    return None, None


def admin_sql(sql):
    p = subprocess.run(PSQL + ['-c', sql], capture_output=True, text=True)
    return p.stdout.strip()


def pk(table):
    if table not in _meta:
        out = admin_sql(f"select string_agg(a.attname, ',' order by array_position(i.indkey, a.attnum)) from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey) where i.indrelid = 'public.{table}'::regclass and i.indisprimary")
        _meta[table] = out.split(',') if out else []
    return _meta[table]


def where(filters):
    w = []
    for c, op, v in filters:
        if op == 'eq': w.append(f't.{ident(c)} = {lit(v)}')
        elif op == 'in': w.append(f't.{ident(c)} in ({",".join(lit(x) for x in v) or "NULL"})')
    return (' where ' + ' and '.join(w)) if w else ''


def cols_sql(cols):
    parts, depth, cur = [], 0, ''
    for ch in cols.replace(' ', ''):
        if ch == ',' and depth == 0: parts.append(cur); cur = ''; continue
        depth += ch == '('; depth -= ch == ')'; cur += ch
    if cur: parts.append(cur)
    out = []
    for p in parts:
        if '(' in p:
            child = p.split('(')[0]
            out.append(f"(select coalesce(jsonb_agg(to_jsonb(c)), '[]') from public.{ident(child)} c where c.{ident(EMBED_FK[child])} = t.id) as {ident(child)}")
        elif p == '*': out.append('t.*')
        else: out.append('t.' + ident(p))
    return ', '.join(out)


def query(q):
    t = q['table']
    if t in FAIL: return None, {'message': f'simulated failure reading {t}'}
    T = 'public.' + ident(t)
    if q['op'] == 'select':
        sql = f"select t.* from (select {cols_sql(q.get('cols') or '*')} from {T} t{where(q['filters'])}" + \
              (' order by ' + ', '.join(f"t.{ident(c)} {'asc' if a else 'desc'}" for c, a in q['order']) if q['order'] else '')
        if q.get('range'): sql += f" limit {int(q['range'][1]) - int(q['range'][0]) + 1} offset {int(q['range'][0])}"
        sql = f"select coalesce(jsonb_agg(to_jsonb(x)), '[]') from ({sql}) t) x"
    else:
        if q['op'] in ('insert', 'upsert'):
            rows = q['body']; keys = sorted({k for r in rows for k in r})
            cl = ', '.join(ident(k) for k in keys)
            dml = f"insert into {T} as t ({cl}) select {cl} from jsonb_populate_recordset(null::{T}, {lit(rows)})"
            if q['op'] == 'upsert':
                keyc = pk(t); upd = [k for k in keys if k not in keyc]
                dml += f" on conflict ({', '.join(ident(k) for k in keyc)}) do " + \
                       (('update set ' + ', '.join(f'{ident(k)} = excluded.{ident(k)}' for k in upd)) if upd else 'nothing')
        elif q['op'] == 'update':
            keys = sorted(q['body']); cl = ', '.join(ident(k) for k in keys)
            src = ', '.join(f'r.{ident(k)}' for k in keys)
            lhs = f'({cl})' if len(keys) > 1 else cl
            dml = f"update {T} as t set {lhs} = (select {src} from jsonb_populate_record(null::{T}, {lit(q['body'])}) r){where(q['filters'])}"
        elif q['op'] == 'delete':
            dml = f"delete from {T} as t{where(q['filters'])}"
        sql = f"with r as ({dml} returning t.*) select coalesce(jsonb_agg(to_jsonb(r)), '[]') from r"
    data, err = run(sql, q.get('token'))
    if err: return None, err
    if q['op'] != 'select' and not q.get('ret'): data = None
    if q.get('single'):
        if not data: return None, {'message': 'JSON object requested, multiple (or no) rows returned'}
        data = data[0]
    return data, None


def rpc(fn, args, token):
    ident(fn)
    retset = admin_sql(f"select bool_or(proretset) from pg_proc where proname = '{fn}' and pronamespace = 'public'::regnamespace")
    a = ', '.join(f'{ident(k)} => {lit(v)}' for k, v in args.items())
    sql = (f"select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.{ident(fn)}({a}) x" if retset == 't'
           else f"select to_jsonb(public.{ident(fn)}({a}))")
    return run(sql, token)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def send(self, code, body, ctype='application/json'):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code); self.send_header('content-type', ctype); self.send_header('content-length', str(len(b)))
        self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        path = self.path.split('?')[0]
        if path in ('/', '/index.html', '/live.html'): return self.send(200, open(APP, 'rb').read(), 'text/html; charset=utf-8')
        if path == '/demo.html' and os.path.exists(os.path.join(os.path.dirname(APP), 'demo.html')):
            return self.send(200, open(os.path.join(os.path.dirname(APP), 'demo.html'), 'rb').read(), 'text/html; charset=utf-8')
        if path == '/config.js':
            return self.send(200, "window.PROTRACK={SUPABASE_URL:'https://fake-project.supabase.co',SUPABASE_ANON_KEY:'test-anon-key',SITE_URL:'http://localhost/'};", 'application/javascript')
        if path == '/__sb/client.js': return self.send(200, FAKE_JS, 'application/javascript')
        if path == '/__sb/calls': return self.send(200, json.dumps(CALLS))
        self.send(404, 'not found', 'text/plain')

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get('content-length') or 0)) or b'{}')
        with LOCK:
            if self.path == '/__sb/auth':
                email = (body.get('email') or '').lower()
                uid = admin_sql(f"select id from auth.users where lower(email) = {lit(email)}")
                if not uid or body.get('password') != PASSWORD:
                    return self.send(200, json.dumps({'data': {'user': None, 'session': None}, 'error': {'message': 'Invalid login credentials'}}))
                user = {'id': uid, 'email': email}
                return self.send(200, json.dumps({'data': {'user': user, 'session': {'access_token': uid, 'user': user}}, 'error': None}))
            if self.path == '/__sb/q':
                data, err = query(body); return self.send(200, json.dumps({'data': data, 'error': err}))
            if self.path == '/__sb/rpc':
                data, err = rpc(body['fn'], body.get('args') or {}, body.get('token'))
                return self.send(200, json.dumps({'data': data, 'error': err}))
            if self.path == '/__sb/fn':
                CALLS.append(body); return self.send(200, json.dumps({'data': {'ok': True}, 'error': None}))
            if self.path == '/__sb/fail':
                FAIL.clear(); FAIL.update(body.get('tables') or []); return self.send(200, '{}')
        self.send(404, '{}')


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
