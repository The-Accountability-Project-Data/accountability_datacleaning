# Turn the Kansas Secretary of State viewer exports (<kind>_<from>_<to>.xls, HTML tables) into one UTF-8 CSV per kind in
# state/ks/data/parsed/ (ks_contribution.csv, ks_expenditure.csv), where ks_common.R reads them. Read-only on inputs.
#   python3 state/ks/code/reparse.py <raw dir>
#
# Each table row holds one transaction; every value is in a <span id="lbl<Field>_<row>">, so fields are taken by their
# label, not by cell position: lblCandName -> cand_name, lblContributor -> contributor, lblAddress2 -> address2,
# lblTypeofTender -> typeof_tender, and so on (CamelCase to snake case). The labels and their order must be the same in
# every row of every file of a kind. HTML entities are decoded; text otherwise as published. Adds source_file.
import csv, html, re, sys
from pathlib import Path

raw = Path(sys.argv[1]).resolve()
out = Path(__file__).resolve().parent.parent / 'data' / 'parsed'
out.mkdir(parents=True, exist_ok=True)
ROW = re.compile(r'<tr[^>]*>(.*?)</tr>', re.S | re.I)
SPAN = re.compile(r'<span id="lbl([A-Za-z0-9]+?)_\d+"[^>]*>(.*?)</span>', re.S)

def snake(label):
    return re.sub(r'(?<=[a-z0-9])(?=[A-Z])', '_', label).lower()

for kind in ('contribution', 'expenditure'):
    files = sorted(raw.glob(kind + '_*.xls'))
    if not files:
        sys.exit('no %s_*.xls in %s' % (kind, raw))
    labels, total = None, 0
    with open(out / ('ks_%s.csv' % kind), 'w', newline='', encoding='utf-8') as fo:
        w = csv.writer(fo, lineterminator='\n')
        for f in files:
            n = 0
            for row in ROW.findall(f.read_text(encoding='utf-8')):
                spans = SPAN.findall(row)
                if not spans:
                    continue                      # the header row has no labeled spans
                lab = [s[0] for s in spans]
                if labels is None:
                    labels = lab
                    w.writerow([snake(l) for l in labels] + ['source_file'])
                elif lab != labels:
                    sys.exit('%s: labels differ: %r' % (f.name, lab))
                w.writerow([html.unescape(re.sub(r'<[^>]+>', ' ', v)).strip() for _, v in spans] + [f.name])
                n += 1
            total += n
            print('  %s: %d rows' % (f.name, n))
    print('%s: %d files, %d rows -> %s; columns %s' % (kind, len(files), total, out / ('ks_%s.csv' % kind),
                                                    [snake(l) for l in labels]))
