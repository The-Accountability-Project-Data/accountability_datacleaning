# Stack the monthly ELECT files (data/raw/<YYYY_MM>/<File>.csv) into one UTF-8 CSV per file type in data/parsed/,
# where va_common.R reads them. Read-only on inputs.
#   python3 state/va/code/reparse.py state/va/contribs   -> parsed/va_report.csv, va_schedulea.csv, va_scheduleb.csv
#   python3 state/va/code/reparse.py state/va/expends    -> parsed/va_report.csv, va_scheduled.csv
#
# The export quotes every field and does not escape quotes inside a field ("William E. Bill" Moody, Jr."), so a
# standard CSV reader splits those rows wrongly. Records end with "\r\n" and fields are separated by ",", so each
# file is split on those two strings instead; quotes inside a field are kept as published. Fields can contain
# line breaks.
# Encoding: each file is either ASCII or windows-1252 (curly quotes, (R), accented letters). The 12 bytes that are
# undefined in windows-1252 (0x81, all in one contributor name in 2021_12 and 2022_01 Schedule A) are kept as the
# Latin-1 code point.
# Adds source_file ("2020_10_ScheduleA.csv", as in the earlier builds) and reports records per file type.
import codecs, csv, sys
from pathlib import Path


def latin1_fallback(e):
    return e.object[e.start:e.end].decode('latin-1'), e.end


codecs.register_error('latin1_fallback', latin1_fallback)
FILES = {'contribs': ['Report', 'ScheduleA', 'ScheduleB'], 'expends': ['Report', 'ScheduleD']}

base = Path(sys.argv[1]).resolve()
raw, out = base / 'data' / 'raw', base / 'data' / 'parsed'
out.mkdir(exist_ok=True)
months = sorted(p.name for p in raw.iterdir() if p.is_dir())
for kind in FILES[base.name]:
    hdr, n = None, 0
    with open(out / f'va_{kind.lower()}.csv', 'w', newline='', encoding='utf-8') as g:
        w = csv.writer(g)
        for mo in months:
            t = (raw / mo / f'{kind}.csv').read_bytes().decode('cp1252', 'latin1_fallback')
            assert t.startswith('"') and t.endswith('"\r\n'), (mo, kind)
            recs = t[1:-3].split('"\r\n"')
            h = recs[0].split('","')
            if hdr is None:
                hdr = h
                w.writerow(h + ['source_file'])
            assert h == hdr, (mo, kind, 'header differs')
            src = f'{mo}_{kind}.csv'
            for r in recs[1:]:
                row = r.split('","')
                assert len(row) == len(hdr), (mo, kind, row[:3])
                w.writerow(row + [src])
                n += 1
    print(kind, 'months', len(months), 'records', n, 'columns', len(hdr))
