"""Download the Tennessee Comptroller county parcel zips listed in code/sources.json into data/raw/ (the links come
from the Comptroller's request form, submitted 2026-11-10). One file at a time, at least 1 s apart, browser headers,
resumed with curl -C - on a dropped connection; skips files already complete. Logs each download (time, URL, size,
SHA-256) to data/retrievals.jsonl.
    python state/tn/parcels/code/fetch.py   (from any directory; paths are relative to this script)
"""
import hashlib, json, os, subprocess, time
from datetime import datetime, timezone
from pathlib import Path
HERE = Path(__file__).resolve().parent
DATA = HERE.parent / 'data'
RAW = DATA / 'raw'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
src = json.load(open(HERE / 'sources.json'))
os.makedirs(RAW, exist_ok=True)
log = open(DATA / 'retrievals.jsonl', 'a')
for c in src['counties']:
    out = str(RAW / ('%s.zip' % c['county']))
    if os.path.exists(out + '.done'):
        continue
    for attempt in range(8):
        r = subprocess.run(['curl', '-sS', '-L', '-C', '-', '-A', UA, '--retry', '3', '-o', out, c['url']])
        if r.returncode == 0 and subprocess.run(['unzip', '-tq', out], capture_output=True).returncode == 0:
            break
        print('%s: curl %s, retrying' % (c['county'], r.returncode), flush=True)
        time.sleep(10)
    else:
        print('%s: FAILED' % c['county'], flush=True)
        continue
    sha = hashlib.sha256(open(out, 'rb').read()).hexdigest()
    rec = {'retrieved_at': datetime.now(timezone.utc).isoformat(timespec='seconds'), 'county': c['county'],
           'url': c['url'], 'path': os.path.relpath(out, HERE.parent), 'bytes': os.path.getsize(out), 'sha256': sha}
    log.write(json.dumps(rec) + '\n'); log.flush()
    open(out + '.done', 'w').close()
    print('%-12s %12s' % (c['county'], format(rec['bytes'], ',')), flush=True)
    time.sleep(1.5)
