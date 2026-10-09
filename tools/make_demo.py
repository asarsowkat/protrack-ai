"""Builds demo.html from index.html: the same app, but it never loads config.js or the Supabase library,
so it always runs on sample data in the visitor's browser, under its own storage key.
Usage: python3 make_demo.py index.html demo.html"""
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
for old, new in [
    ('<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>\n', ''),
    ('<script src="config.js" onerror="console.info(\'No config.js: running on demo data\')"></script>\n',
     "<script>window.PROTRACK={DEMO_PAGE:true,DATE_MODE:'demo'};</script>\n<meta name=\"robots\" content=\"noindex\">\n"),
    ('<title>ProTrack — Construction Productivity Intelligence</title>', '<title>ProTrack — Demo with sample data</title>'),
]:
    assert s.count(old) == 1, 'pattern not found once: ' + old[:60]
    s = s.replace(old, new)
assert 'config.js' not in s.split('</head>')[0] and 'supabase-js' not in s
open(dst, 'w', encoding='utf-8').write(s)
print('demo page written:', dst)
