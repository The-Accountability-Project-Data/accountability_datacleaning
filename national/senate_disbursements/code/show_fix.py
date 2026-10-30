"""
Show what a fix changes: run read_pages.py in both modes (--baseline = the 2015 logic) on a few pages of one report,
in a scratch directory (the report directory's outputs are untouched), and print
  1. the pdftotext layout lines around the text you name, with page breaks;
  2. the baseline rows around it: every field, a few rows above and below;
  3. the improved rows over the same stretch.
Rows only one version produces are marked "*"; a page break between rows prints as blank lines.

  python3 show_fix.py 118_sdoc8 191-192 "LANE MARSHALL"
  python3 show_fix.py 117_sdoc8 345 "SOFTWARE INFORMATION|VSAA22108403"   # "|": fall back to the next string
Several examples into one file: python3 show_fix.py --examples > fix_examples.txt
"""
import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FIELDS = ["office", "line type", "continuation", "page", "document no.", "date posted", "payee", "start", "end",
          "description", "amount"]

EXAMPLES = [
    ("Continuation at the top of a page (2023 layout: the columns move at the page break)",
     "118_sdoc8", "191-192", "LANE MARSHALL"),
    ("Payee name printed around its row (2021 layout: part above, blank on the row, part below)",
     "117_sdoc8", "345", "SOFTWARE INFORMATION|VSAA22108403"),
    ("A line split in two by today's pdftotext (2015 report; end date and amount on the next line)",
     "114_sdoc4", "151", "DAPP21500006|DAPP21500009"),
    ("'INTERDEPARTMENTAL TRANSPORTATION' as a description line, not a subtotal (2017)",
     "115_sdoc2", "38", "MCCONNELL"),
    ("Office name on a 2020 continuation page (the column header was taken as the office)",
     "116_sdoc19", "815-820", "DHOE20200270"),
]


def run_modes(report, pages):
    lo, hi = (pages.split("-") + [pages])[:2]
    tmp = tempfile.mkdtemp(prefix="show_fix_")
    os.symlink(os.path.join(HERE, report, "pages"), os.path.join(tmp, "pages"))
    shutil.copy(os.path.join(HERE, "read_pages.py"), tmp)
    out = {}
    for mode in ("baseline", "improved"):
        args = [sys.executable, "read_pages.py", "--pages", "%s-%s" % (lo, hi), "--out", mode + ".csv"]
        if mode == "baseline":
            args.insert(2, "--baseline")
        subprocess.run(args, cwd=tmp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        out[mode] = list(csv.reader(open(os.path.join(tmp, mode + ".csv"), encoding="utf-8")))
    shutil.rmtree(tmp)
    return int(lo), int(hi), out


def show_source(report, lo, hi, needle, context):
    print("--- pdftotext layout (pages %s-%s), lines near %r ---" % (lo, hi, needle))
    hit_pages = []
    for p in range(lo, hi + 1):
        lines = open(os.path.join(HERE, report, "pages", "layout_%s.txt" % p), encoding="utf-8",
                     errors="replace").read().split("\n")
        hits = [i for i, l in enumerate(lines) if any(n in l for n in needle.split("|"))]
        if hits:
            hit_pages.append(p)
            a, b = max(0, hits[0] - context), min(len(lines), hits[-1] + context + 1)
        elif p < hi and lo < hi:          # the page before the one with the hit: show its end
            nonblank = [i for i, l in enumerate(lines) if l.strip()]
            a, b = max(0, (nonblank[-1] if nonblank else 0) - context), len(lines)
        else:                              # the page after: show its start
            a, b = 0, min(len(lines), context * 3)
        print("\n\n[page %s, lines %s-%s]" % (p, a + 1, b))
        for l in lines[a:b]:
            if l.strip():
                print("  " + l.rstrip())


def show_rows(title, rows, other, idx, context):
    other_set = {tuple(r) for r in other}
    a, b = max(0, min(idx) - context), min(len(rows), max(idx) + context + 1)
    print("\n--- %s: rows %s-%s of %s (* = not in the other version) ---" % (title, a + 1, b, len(rows)))
    last_page = None
    for i in range(a, b):
        r = rows[i]
        if last_page is not None and r[3] != last_page:
            print("\n\n   ---- page break (page %s) ----\n" % r[3])
        last_page = r[3]
        mark = "*" if tuple(r) not in other_set else " "
        print("%s row %s" % (mark, i + 1))
        for f, v in zip(FIELDS, r):
            print("      %-13s %s" % (f + ":", v))


def show(report, pages, needle, context=3, title=None):
    """needle may be several strings separated by "|": the first found is used (the source text is shown for all)"""
    needles = needle.split("|")
    lo, hi, out = run_modes(report, pages)
    print("=" * 110)
    print("%s  %s pages %s  (%r)" % (title or "", report, pages, needle))
    print("=" * 110)
    show_source(report, lo, hi, needle, context + 2)
    for mode, other in (("baseline", "improved"), ("improved", "baseline")):
        rows = out[mode]
        idx = []
        for n in needles:      # the first needle found in this version's rows; later ones are fallbacks
            idx = [i for i, r in enumerate(rows) if any(n in f for f in r)]
            if idx:
                break
        if not idx:
            # the baseline may have lost the line altogether: show the rows where it would be (by page)
            pg = [i for i, r in enumerate(rows) if r[3] == str(hi)] or [len(rows) - 1]
            print("\n--- %s: no row contains %r ---" % ("ORIGINAL (2015 logic)" if mode == "baseline" else "IMPROVED", needle))
            idx = pg[:1]
        elif n != needles[0]:
            print("\n--- %s: no row contains %r; centered on %r instead ---" % (
                "ORIGINAL (2015 logic)" if mode == "baseline" else "IMPROVED", needles[0], n))
        show_rows("ORIGINAL (2015 logic)" if mode == "baseline" else "IMPROVED", rows, out[other], idx, context)
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("report", nargs="?")
    ap.add_argument("pages", nargs="?")
    ap.add_argument("needle", nargs="?")
    ap.add_argument("--context", type=int, default=3)
    ap.add_argument("--examples", action="store_true")
    a = ap.parse_args()
    if a.examples:
        for title, report, pages, needle in EXAMPLES:
            show(report, pages, needle, a.context, title)
    else:
        show(a.report, a.pages, a.needle, a.context)


if __name__ == "__main__":
    main()
