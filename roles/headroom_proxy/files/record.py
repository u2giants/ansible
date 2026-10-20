#!/usr/bin/env python3
"""Append Headroom PERF metrics to a durable CSV that survives proxy.log rotation.
Idempotent: dedupes on the hr_ request id. Safe to run repeatedly."""
import csv, glob, os, re

OUT = '/home/ai/headroom-perf/perf.csv'
LOGS = ['/home/ai/.headroom/logs/proxy.log'] + sorted(glob.glob('/home/ai/.headroom/logs/proxy.log.[0-9]'))
COLS = ['ts','reqid','model','msgs','tok_before','tok_after','tok_saved',
        'cache_read','cache_write','cache_hit_pct','transforms']
PAT = re.compile(
    r'^(?P<ts>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d),\d+ .*?\[(?P<reqid>hr_[0-9_]+)\] PERF '
    r'model=(?P<model>\S+) msgs=(?P<msgs>\d+) tok_before=(?P<tok_before>\d+) '
    r'tok_after=(?P<tok_after>\d+) tok_saved=(?P<tok_saved>\d+) '
    r'cache_read=(?P<cache_read>\d+) cache_write=(?P<cache_write>\d+) '
    r'cache_hit_pct=(?P<cache_hit_pct>[\d.]+).*?transforms=(?P<transforms>\S+)')

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
            m = PAT.match(line)
            if not m:
                continue
            r = m.groupdict()
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
