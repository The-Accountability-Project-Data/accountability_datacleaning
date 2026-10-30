"""Stream-compare the repaired MS voter file with the indexed one (csv/ms_voters_clean.csv): after applying the
repair's fixes to the indexed values (WSD line break -> blank, extra column dropped, whitespace squished,
double quote -> apostrophe), every row must match.  python3 ms_voters_compare.py <indexed csv> <repaired csv>"""
import csv, sys, re
csv.field_size_limit(10**9)
old_p, new_p = sys.argv[1:]
fix = lambda v: re.sub(r"\s+", " ", v).strip().replace('"', "'")
with open(old_p, newline='', encoding='utf-8', errors='surrogateescape') as fo, \
     open(new_p, newline='', encoding='utf-8', errors='surrogateescape') as fn:
    ro, rn = csv.reader(fo), csv.reader(fn)
    ho, hn = next(ro), next(rn)
    assert ho[:58] == hn and len(hn) == 58, (ho[-3:], hn[-3:])
    n = diff = 0; shown = 0
    for a, b in zip(ro, rn):
        n += 1
        a = [fix(v) for v in a[:57]] + ['']
        if a != b:
            diff += 1
            if shown < 5:
                shown += 1; print("row", n, [(hn[i], a[i], b[i]) for i in range(58) if a[i] != b[i]][:4])
    extra_o, extra_n = sum(1 for _ in ro), sum(1 for _ in rn)
print("rows compared %d | differing %d | leftover rows old %d new %d" % (n, diff, extra_o, extra_n))
