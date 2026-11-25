# Stack Indiana's yearly campaign finance files into one UTF-8 CSV per file type, where in_common.R reads them.
# Read-only on inputs.
#   python3 state/in/code/reparse.py <folder with the unzipped yearly files> state/in
#   -> state/in/contribs/data/parsed/in_contributions.csv, state/in/expends/data/parsed/in_expenditures.csv
#
# Source: https://campaignfinance.in.gov/PublicSite/Docs/BulkDataDownloads/<YEAR>_ContributionData.csv.zip and
# <YEAR>_ExpenditureData.csv.zip, 2000-2026. Every field is quoted and quotes inside a field are not escaped
# (`"Bob "Junior" Smith"`); fields can hold line breaks. Records end with "\r\n" and fields are separated by ",",
# so each file is split on those two strings; every record then has the header's field count. Quotes inside fields
# are kept as published.
# Encoding: a file is read as UTF-8 when it is valid UTF-8, otherwise as windows-1252; bytes undefined in
# windows-1252 are kept as the Latin-1 code point.
# Adds source_file ("2024_ContributionData.csv") and reports records per file type.
import codecs, csv, sys
from pathlib import Path


def latin1_fallback(e):
    return e.object[e.start:e.end].decode('latin-1'), e.end


codecs.register_error('latin1_fallback', latin1_fallback)
KINDS = {'Contribution': ('contribs', 'in_contributions.csv'), 'Expenditure': ('expends', 'in_expenditures.csv')}

src, base = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
for kind, (folder, outname) in KINDS.items():
    out = base / folder / 'data' / 'parsed'
    out.mkdir(parents=True, exist_ok=True)
    hdr, n, enc = None, 0, {}
    with open(out / outname, 'w', newline='', encoding='utf-8') as g:
        w = csv.writer(g)
        for f in sorted(src.glob(f'*_{kind}Data.csv')):
            b = f.read_bytes()
            try:
                t = b.decode('utf-8'); enc[f.name] = 'utf-8'
            except UnicodeDecodeError:
                t = b.decode('cp1252', 'latin1_fallback'); enc[f.name] = 'windows-1252'
            assert t.startswith('"') and t.endswith('"\r\n'), f.name
            recs = t[1:-3].split('"\r\n"')
            h = recs[0].split('","')
            if hdr is None:
                hdr = h
                w.writerow(h + ['source_file'])
            assert h == hdr, (f.name, 'header differs')
            for r in recs[1:]:
                row = r.split('","')
                assert len(row) == len(hdr), (f.name, row[:3])
                w.writerow(row + [f.name])
                n += 1
    print(kind, 'files', len(enc), 'records', n, 'columns', len(hdr),
          'utf-8 files', sum(v == 'utf-8' for v in enc.values()), 'windows-1252 files',
          sum(v != 'utf-8' for v in enc.values()))
