"""
Group the lines read_pages.py couldn't parse, so they can be fixed a group at a time.

Reads <report>/missing_data.txt (and missing_data_baseline.txt) in every report directory -- the 2015 format, one
Python list of {'data', 'offset', 'page_num'} per page -- and groups the lines by shape:
  position   top of page (nothing parsed above it on the page) or mid-page
  indent     leading spaces, in bins of 10
  has        date / amount / "LAST, FIRST" name / text only
  shape      the first ~6 tokens with digits -> 9 and letters -> a (so "STAFF PER DIEM  $949.75" -> "aaaaa aaa aaaa $999.99")
Writes error_groups.csv (one row per group: count, money in lines with an amount, reports it occurs in, examples with
page numbers), biggest first, and prints the top groups.

  python3 group_errors.py                 # improved-mode missing_data.txt in every report directory
  python3 group_errors.py --baseline      # missing_data_baseline.txt
  python3 group_errors.py 119_sdoc6 ...   # only these reports
"""
import argparse
import ast
import collections
import csv
import glob
import os
import re

AMOUNT = re.compile(r"(-?\$?-?[\d,]+\.\d\d)\s*$")
DATE = re.compile(r"\d\d/\d\d/\d\d\d\d")
NAME = re.compile(r"^[A-Z][A-Z'\-\. ]+,\s*[A-Z]")


def shape_of(text, n_tokens=6):
    toks = text.split()[:n_tokens]
    out = []
    for t in toks:
        t = re.sub(r"[A-Za-z]", "a", t)
        t = re.sub(r"\d", "9", t)
        t = re.sub(r"a{2,}", "aa", t)
        t = re.sub(r"9{2,}", "99", t)
        out.append(t)
    return " ".join(out)


def amount_of(text):
    m = AMOUNT.search(text)
    if not m:
        return 0.0
    a = m.group(1).replace("$", "").replace(",", "")
    neg = a.count("-") % 2 == 1
    try:
        return (-1 if neg else 1) * float(a.replace("-", ""))
    except ValueError:
        return 0.0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reports", nargs="*")
    ap.add_argument("--baseline", action="store_true")
    ap.add_argument("--top", type=int, default=25)
    a = ap.parse_args()
    fname = "missing_data_baseline.txt" if a.baseline else "missing_data.txt"
    dirs = a.reports or sorted(d.rstrip("/") for d in glob.glob("1*_sdoc*/"))

    groups = collections.defaultdict(lambda: {"count": 0, "money": 0.0, "reports": collections.Counter(), "examples": []})
    total = 0
    for d in dirs:
        path = os.path.join(d, fname)
        if not os.path.exists(path):
            continue
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if not line:
                continue
            for m in ast.literal_eval(line):
                raw = m["data"].rstrip("\n")
                text = raw.strip()
                indent = len(raw) - len(raw.lstrip())
                has = ("date" if DATE.search(text) else "") + ("+amount" if AMOUNT.search(text) else "") + \
                      ("+name" if NAME.match(text) else "")
                has = has.strip("+") or "text only"
                key = ("top of page" if m["offset"] == 0 else "mid-page", "indent %d-%d" % (indent // 10 * 10, indent // 10 * 10 + 9),
                       has, shape_of(text))
                g = groups[key]
                g["count"] += 1
                g["money"] += amount_of(text)
                g["reports"][d] += 1
                if len(g["examples"]) < 3:
                    g["examples"].append("%s p%s: %s" % (d, m["page_num"], text[:100]))
                total += 1

    ranked = sorted(groups.items(), key=lambda kv: (-kv[1]["count"], -abs(kv[1]["money"])))
    out = "error_groups%s.csv" % ("_baseline" if a.baseline else "")
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["rank", "count", "money", "position", "indent", "has", "shape", "reports", "examples"])
        for i, (k, g) in enumerate(ranked, 1):
            w.writerow([i, g["count"], "%.2f" % g["money"], k[0], k[1], k[2], k[3],
                        " ".join("%s:%d" % rc for rc in sorted(g["reports"].items())), " | ".join(g["examples"])])
    print("%d unparsed lines in %d groups (%s) -> %s" % (total, len(groups), fname, out))
    for i, (k, g) in enumerate(ranked[:a.top], 1):
        print("%3d. %5d lines  $%13s  %-11s %-12s %-18s %-34s %s" % (
            i, g["count"], format(round(g["money"], 2), ","), k[0], k[1], k[2], k[3][:34], g["examples"][0][:90]))


if __name__ == "__main__":
    main()
