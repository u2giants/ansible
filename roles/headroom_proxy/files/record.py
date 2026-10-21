#!/usr/bin/env python3
"""Append Headroom PERF metrics to a durable CSV that survives proxy.log rotation.
Idempotent: dedupes on the hr_ request id. Safe to run repeatedly."""
import csv, glob, os, re

OUT = '/home/ai/headroom-perf/perf.csv'
LOGS = ['/home/ai/.headroom/logs/proxy.log'] + sorted(glob.glob('/home/ai/.headroom/logs/proxy.log.[0-9]'))
COLS = ['ts','reqid','model','msgs','tok_before','tok_after','tok_saved',
        'cache_read','cache_write','cache_hit_pct','transforms']
# Header up to the PERF marker; the rest is parsed as key=value pairs, so new
# fields or reordering in later headroom releases cannot silently drop rows.
HEAD = re.compile(r'^(?P<ts>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d),\d+ .*?\[(?P<reqid>hr_[0-9_]+)\] PERF (?P<tail>.*)$')
KV = re.compile(r'(?:^| )([a-z_]+)=(\S*)')
NUMERIC = {'msgs','tok_before','tok_after','tok_saved','cache_read','cache_write','cache_hit_pct'}


def parse(line):
    m = HEAD.match(line)
    if not m:
        return None
    fields = {}
    for key, value in KV.findall(m.group('tail')):
        fields.setdefault(key, value)  # first occurrence wins
    if not all(k in fields for k in NUMERIC | {'model'}):
        return None
    if not all(re.fullmatch(r'[\d.]+', fields[k]) for k in NUMERIC):
        return None
    r = {c: fields.get(c, '') for c in COLS}
    r['ts'], r['reqid'] = m.group('ts'), m.group('reqid')
    # transforms is space-separated: keep everything from transforms= to the next key=
    t = re.search(r'(?:^| )transforms=(.*?)(?= [a-z_]+=|$)', m.group('tail'))
    r['transforms'] = t.group(1).split(' ')[0] if t else ''
    return r

rows = {}
if os.path.exists(OUT):
    with open(OUT, newline='') as f:
        for r in csv.DictReader(f):
            rows[r['reqid']] = r

added = 0
for path in LOGS:
    try:
        fh = open(path, errors='replace')
    except OSError:
        continue
    with fh:
        for line in fh:
            r = parse(line.rstrip('\n'))
            if not r:
                continue
            if r['reqid'] not in rows:
                rows[r['reqid']] = r
                added += 1

tmp = OUT + '.tmp'
with open(tmp, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=COLS)
    w.writeheader()
    for r in sorted(rows.values(), key=lambda r: (r['ts'], r['reqid'])):
        w.writerow({c: r.get(c, '') for c in COLS})
os.replace(tmp, OUT)
print(f'total={len(rows)} added={added}')
