"""Runs an earlier server test suite with the later updates loaded straight after the suite's own update: N+1 .. LAST.
Run it with LAST = 15 and LAST = 16 and compare: a check failing only with 16 would be a change made by v16.
Usage (from supabase/tests): python3 with_later_updates.py test_vN.py N LAST"""
import subprocess, sys, runpy, os
test, N, LAST = sys.argv[1], sys.argv[2], int(sys.argv[3])
SBD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '')
LATER = [SBD + f'schema-update-v{i}.sql' for i in range(int(N) + 1, LAST + 1)]
target = f'schema-update-v{N}.sql'
real = subprocess.run
seen = {'n': 0}
def run(args, *a, **k):
    r = real(args, *a, **k)
    if isinstance(args, list) and '-f' in args:
        f = args[args.index('-f') + 1]
        if os.path.basename(f) == target and r.returncode == 0:
            for L in LATER:
                r2 = real(args[:args.index('-f')] + ['-f', L] + args[args.index('-f') + 2:], *a, **k)
                if r2.returncode: print('LATER LOAD FAILED', L, r2.stderr[-500:]); return r2
            seen['n'] += 1
    return r
subprocess.run = run
sys.argv = [test]
try: runpy.run_path(test, run_name='__main__')
finally: print('later updates loaded', seen['n'], 'times', file=sys.stderr)
