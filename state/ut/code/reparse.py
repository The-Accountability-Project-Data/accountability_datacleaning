# Stack the Utah disclosures "Download Data by Year" files (<TYPE>-<YEAR>.csv, one per filer entity type and report
# year) into one UTF-8 CSV,
# state/ut/data/parsed/ut_transactions.csv, with entity_type and report_year from the file name. Read-only on inputs.
#   python3 state/ut/code/reparse.py <raw dir>
#
# The export quotes text fields but does not escape quotes inside them ("CORNER BAKERY CAFE RED BUTTE" #1516 SLC,
# UT"), and a few fields hold line breaks. Records are found by their start: "X" or "" in FILED, then the filer, the
# report, a numeric TRAN_ID and a TRAN_TYPE (Contribution, Expenditure, Balance, PCC Balance); following lines that do not start a record are
# joined to it (with a line break, as published). Each record is read with a standard CSV reader; if that does not
# give 18 fields it is rebuilt from the fixed layout: FILED, filer, REPORT, TRAN_ID (unquoted digits), TRAN_TYPE,
# TRAN_DATE, TRAN_AMT, INKIND, LOAN, AMENDS, then NAME, PURPOSE, ADDRESS1, ADDRESS2, CITY (split on '","'), STATE,
# ZIP (unquoted), INKIND_COMMENTS (the rest). Quotes inside fields are kept as published. A record that still does
# not fit is written to state/ut/data/parsed/unparsed.txt and counted.
import csv, io, re, sys
from pathlib import Path

N = 18
raw = Path(sys.argv[1]).resolve()
out = Path(__file__).resolve().parent.parent / 'data' / 'parsed'
out.mkdir(parents=True, exist_ok=True)
START = re.compile(r'^"X?",".*?",(?:"[^"]*"|[^,]*),\d+,"[A-Za-z /-]+",')
HEAD = re.compile(r'^"(X?)","(.*?)","(.*?)",(\d+),"([A-Za-z /-]+)","([^"]*)","([^"]*)","([^"]*)","([^"]*)","([^"]*)",(.*)$', re.S)
TAIL = re.compile(r'^(.*),"([^"]*)",("?[^",]*"?),"(.*)"$', re.S)

def rebuild(rec):
    m = HEAD.match(rec)
    if not m:
        return None
    head, rest = list(m.groups()[:10]), m.group(11)
    t = TAIL.match(rest)
    if not t:
        return None
    middle, state, zip_, comments = t.groups()
    if not (middle.startswith('"') and middle.endswith('"')):
        return None
    mid = middle[1:-1].split('","')
    if len(mid) != 5:
        return None
    return head + mid + [state, zip_.strip('"'), comments]

files = sorted(raw.glob('*.csv'))
total = repaired = dropped = 0
with open(out / 'ut_transactions.csv', 'w', newline='', encoding='utf-8') as fo, \
        open(out / 'unparsed.txt', 'w', encoding='utf-8') as fu:
    w = csv.writer(fo, lineterminator='\n')
    hdr = None
    for f in files:
        etype, year = re.match(r'([A-Z]+)-(\d{4})\.csv$', f.name).groups()
        lines = f.read_text(encoding='utf-8').split('\n')
        h = next(csv.reader([lines[0]]))
        h = ['ENTITY_NAME' if i == 1 else c for i, c in enumerate(h)]
        if hdr is None:
            hdr = h
            w.writerow(hdr + ['ENTITY_TYPE', 'REPORT_YEAR'])
        elif h != hdr:
            sys.exit('%s: header differs' % f.name)
        recs, cur = [], None
        for line in lines[1:]:
            line = line.rstrip('\r')
            if START.match(line):
                if cur is not None:
                    recs.append(cur)
                cur = line
            elif cur is not None:
                cur += '\n' + line
            elif line.strip():
                fu.write('%s: orphan line: %s\n' % (f.name, line)); dropped += 1
        if cur is not None:
            recs.append(cur)
        n = fixed = bad = 0
        for rec in recs:
            rec = rec.rstrip('\n')
            row = next(csv.reader(io.StringIO(rec)), [])
            if len(row) != N:
                row = rebuild(rec)
                if row is None:
                    fu.write('%s: %s\n' % (f.name, rec)); bad += 1
                    continue
                fixed += 1
            w.writerow(row + [etype, year])
            n += 1
        total += n; repaired += fixed; dropped += bad
        if fixed or bad:
            print('  %s: %d records, %d rebuilt, %d not parsed' % (f.name, n, fixed, bad))
print('%d files, %d records, %d rebuilt, %d not parsed (unparsed.txt)' % (len(files), total, repaired, dropped))
