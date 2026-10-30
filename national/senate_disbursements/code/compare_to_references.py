"""
Compare our parses with the earlier ones: the user's repo (2011-2015, repo_senate_data.csv, 11-column raw format) and
ProPublica's fork (2015-2017: propublica_senate_data.csv raw, or *_cleaned 16-column). For each report and mode:
exact identical rows (raw format only), and rows matching on document no. / date posted / start / end / amount (the
fields both formats share), with counts only in the reference ("ref-only") or only in ours ("ours-only").
Writes compare_to_references.csv.
  python3 compare_to_references.py
"""
import collections
import csv
import glob
import os

out = []


def raw_key(r):        # 11-column read_pages.py rows
    return (r[4], r[5], r[7], r[8], r[10].replace("$", ""))


def clean_key(r):      # 16-column cleaned rows
    return (r["document_number"], r["date_posted"], r["start_date"], r["end_date"], r["amount"].replace("$", ""))


def read_raw(path):
    return [r for r in csv.reader(open(path, encoding="utf-8", errors="replace")) if len(r) >= 11]


def read_clean(path):
    fh = open(path, encoding="utf-8", errors="replace")
    first = fh.readline()
    if not first.startswith("source_doc"):      # Sunlight citation line above the header
        first = fh.readline()
    return list(csv.DictReader([first] + fh.readlines()))


for d in sorted(glob.glob("1*_sdoc*")):
    refs = [("repo", os.path.join(d, "repo_senate_data.csv"), "raw"),
            ("propublica", os.path.join(d, "propublica_senate_data.csv"), None),
            ("propublica", os.path.join(d, "propublica_senate_data_cleaned-combined.csv"), "clean")]
    for name, path, fmt in refs:
        if not os.path.exists(path):
            continue
        if fmt is None:
            fmt = "clean" if open(path, encoding="utf-8", errors="replace").readline().startswith(("This data", "source_doc")) else "raw"
        ref_rows = read_raw(path) if fmt == "raw" else read_clean(path)
        ka = collections.Counter((raw_key if fmt == "raw" else clean_key)(r) for r in ref_rows)
        for mode, f in [("baseline", "senate_data_baseline.csv"), ("improved", "senate_data.csv")]:
            p = os.path.join(d, f)
            if not os.path.exists(p):
                continue
            ours = read_raw(p)
            kb = collections.Counter(raw_key(r) for r in ours)
            ident = ""
            if fmt == "raw":
                ident = sum((collections.Counter(map(tuple, ref_rows)) & collections.Counter(map(tuple, ours))).values())
            row = [d, name, fmt, mode, len(ref_rows), len(ours), ident, sum((ka & kb).values()),
                   sum((ka - kb).values()), sum((kb - ka).values())]
            out.append(row)
            print("%-11s %-10s %-5s %-8s ref %6d ours %6d | identical %6s | key match %6d, ref-only %5d, ours-only %5d" % tuple(row))

with open("compare_to_references.csv", "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["report", "reference", "ref_format", "mode", "ref_rows", "our_rows", "identical_rows", "key_match",
                "ref_only", "ours_only"])
    w.writerows(out)
