# Stack the DC OCF e-filing Excel exports (one .xlsx per type and date window)
# into one UTF-8 CSV per type in state/dc/data/parsed/
# (dc_contributions.csv, dc_expenditures.csv), where dc_common.R reads them. Read-only on inputs.
#   python3 state/dc/code/reparse.py <raw dir with contributions_*.xlsx and expenditures_*.xlsx>
#
# Each workbook has one sheet: a title row ("... Contributions Report"), the header row, then one row per
# transaction. Empty cells are left out of the sheet XML, so values are placed by their cell reference (column
# letters). Text is kept as published (shared and inline strings); "$1,234.50" amounts too. Adds source_file.
# Stops if a header differs between files or a value lands outside the header's columns.
import csv, re, sys, zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
raw = Path(sys.argv[1]).resolve()
out = Path(__file__).resolve().parent.parent / 'data' / 'parsed'
out.mkdir(parents=True, exist_ok=True)

def col_index(ref):
    n = 0
    for ch in re.match(r'[A-Z]+', ref).group(0):
        n = n * 26 + ord(ch) - 64
    return n - 1

def sheet_rows(path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        ss = []
        sst = [n for n in names if n.lower() == 'xl/sharedstrings.xml']
        if sst:
            ss = [''.join(si.itertext()) for si in ET.fromstring(z.read(sst[0])).findall('m:si', NS)]
        sheet = [n for n in names if n.startswith('xl/worksheets/') and n.endswith('.xml')]
        if len(sheet) != 1:
            sys.exit('%s: %d sheets' % (path.name, len(sheet)))
        for r in ET.fromstring(z.read(sheet[0])).iter('{%s}row' % NS['m']):
            vals = {}
            for c in r.findall('m:c', NS):
                v, t, inline = c.find('m:v', NS), c.get('t'), c.find('m:is', NS)
                if t == 's' and v is not None:
                    val = ss[int(v.text)]
                elif inline is not None:
                    val = ''.join(inline.itertext())
                else:
                    val = v.text if v is not None else ''
                vals[col_index(c.get('r'))] = val
            yield vals

for kind in ('contributions', 'expenditures'):
    files = sorted(raw.glob(kind + '_*.xlsx'))
    if not files:
        sys.exit('no %s_*.xlsx in %s' % (kind, raw))
    hdr, total = None, 0
    with open(out / ('dc_%s.csv' % kind), 'w', newline='', encoding='utf-8') as fo:
        w = csv.writer(fo, lineterminator='\n')
        for f in files:
            if f.stat().st_size == 0:      # the export returns an empty body when the window has no transactions
                print('  %s: 0 bytes, no rows' % f.name)
                continue
            rows = sheet_rows(f)
            title = next(rows, {})
            h = next(rows, None)
            n = 0
            if h is None:
                print('  %s: empty (%r)' % (f.name, title.get(0)))
                continue
            h = [h[i] for i in sorted(h)]
            if hdr is None:
                hdr = h
                w.writerow(hdr + ['source_file'])
            elif h != hdr:
                sys.exit('%s: header differs: %r' % (f.name, h))
            for vals in rows:
                if not vals:
                    continue
                if max(vals) >= len(hdr):
                    sys.exit('%s: value outside the header columns: %r' % (f.name, vals))
                w.writerow([vals.get(i, '') for i in range(len(hdr))] + [f.name])
                n += 1
            total += n
            print('  %s: %d rows' % (f.name, n))
    print('%s: %d files, %d rows -> %s' % (kind, len(files), total, out / ('dc_%s.csv' % kind)))
