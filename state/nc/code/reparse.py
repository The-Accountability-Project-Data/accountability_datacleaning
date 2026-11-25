# Stack the NC SBoE transaction exports (one CSV per date window, receipts and expenditures fetched separately)
# into one UTF-8 CSV per type in
# state/nc/data/parsed/ (nc_receipts.csv, nc_expenditures.csv), where nc_common.R reads them. Read-only on inputs.
#   python3 state/nc/code/reparse.py <raw dir with receipts_*.csv and expenditures_*.csv>
#
# The export quotes fields that contain commas or quotes, but not line breaks: a line break inside a field (seen
# only in Purpose, e.g. "Event Expenditures\n - Event Supplies") ends the line, so that record comes out as two
# short rows whose field counts add up to 25 (24 + the split field). Such pairs are joined back into one record,
# the two parts of the split field joined with a newline, as published. Any other row without 24 fields stops the
# script. Adds source_file (the window file's name). Reports records and repairs per file.
import csv, sys
from pathlib import Path

N = 24
raw = Path(sys.argv[1]).resolve()
out = Path(__file__).resolve().parent.parent / 'data' / 'parsed'
out.mkdir(parents=True, exist_ok=True)
for kind in ('receipts', 'expenditures'):
    files = sorted(raw.glob(kind + '_*.csv'))
    if not files:
        sys.exit('no %s_*.csv in %s' % (kind, raw))
    hdr, total, repaired = None, 0, 0
    with open(out / ('nc_%s.csv' % kind), 'w', newline='', encoding='utf-8') as fo:
        w = csv.writer(fo, quoting=csv.QUOTE_MINIMAL, lineterminator='\n')
        for f in files:
            with open(f, newline='', encoding='utf-8') as fi:
                rows = csv.reader(fi)
                h = next(rows)
                if hdr is None:
                    hdr = h
                    w.writerow(h + ['source_file'])
                elif h != hdr:
                    sys.exit('%s: header differs' % f.name)
                n = fixed = 0
                pending = None
                for r in rows:
                    if pending is not None:
                        if len(pending) + len(r) - 1 != N:
                            sys.exit('%s: cannot repair %r + %r' % (f.name, pending[:3], r[:3]))
                        r = pending[:-1] + [pending[-1] + '\n' + r[0]] + r[1:]
                        pending = None
                        fixed += 1
                    elif len(r) < N:
                        pending = r
                        continue
                    if len(r) != N:
                        sys.exit('%s: row with %d fields: %r' % (f.name, len(r), r[:4]))
                    w.writerow(r + [f.name])
                    n += 1
                if pending is not None:
                    sys.exit('%s: file ends inside a split record' % f.name)
            total += n
            repaired += fixed
            if fixed:
                print('  %s: %d records, %d repaired (line break in a field)' % (f.name, n, fixed))
    print('%s: %d files, %d records, %d repaired -> %s' % (kind, len(files), total, repaired, out / ('nc_%s.csv' % kind)))
