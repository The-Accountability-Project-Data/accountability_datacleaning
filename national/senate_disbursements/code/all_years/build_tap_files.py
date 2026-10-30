"""
Split senate_disbursements_all.csv into one file per report for TAP (Accountability Project), adding a `year` column.

  python3 build_tap_files.py [--out DIR]     # default ~/uc_berkeley/datacleaning_agents/work/senate-disbursements

Each report covers six months: Apr-Sep of one year or Oct of one year to Mar of the next. The period is taken from
the report's posting dates (1st percentile), so file names carry the calendar years, e.g.
senate-disbursements_2025-2026_119-sdoc6.csv (Oct 2025 - Mar 2026) or senate-disbursements_2025_119-sdoc5.csv.

year (the year TAP shows; user, 2026-10-13: from the funding year):
  - funding_year when it is a single fiscal year (2011, 2026);
  - otherwise (multi-year funds, written "1115" = FY2011-2015 through early 2021 and "2021-2025" after, or blank)
    the year of date_posted;
  - and if there is no date (some payroll lines), the last calendar year of the report period.
Until early 2021 multi-year funds are written as two 2-digit years run together ("1214" = FY2012-2014, "2024" =
FY2020-2024); after that as "2021-2025". So a 4-digit funding_year counts as a single year only when it is a
plausible one for the report: from 6 years before the report period through 1 year after it. That keeps "2024" in a
2020 report (= FY2020-2024) from being read as 2024.
"""
import argparse
import collections
import csv
import os

ap = argparse.ArgumentParser()
ap.add_argument('--src', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'senate_disbursements_all.csv'))
ap.add_argument('--out', default=os.path.expanduser('~/uc_berkeley/datacleaning_agents/work/senate-disbursements'))
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)

rows = collections.defaultdict(list)
with open(a.src, encoding='utf-8', newline='') as fh:
    reader = csv.DictReader(fh)
    header = reader.fieldnames
    for r in reader:
        rows[r['source_doc']].append(r)


def ymd(d):  # MM/DD/YYYY -> (Y, M) or None
    return (int(d[6:]), int(d[:2])) if len(d) == 10 and d[2] == '/' and d[5] == '/' else None


def report_key(doc):
    c, n = doc.split('_sdoc')
    return int(c), int(n)


def single_year(v, period):
    return len(v) == 4 and v.isdigit() and period[0] - 6 <= int(v) <= period[1] + 1


summary = []
for doc in sorted(rows, key=report_key):
    rs = rows[doc]
    posted = sorted(p for p in (ymd(r['date_posted']) for r in rs) if p)
    y0, m0 = posted[len(posted) // 100]
    if m0 in (4, 5, 6, 7, 8, 9):
        period = (y0, y0); label = '%d' % y0
    else:
        period = (y0, y0 + 1) if m0 >= 10 else (y0 - 1, y0); label = '%d-%d' % period
    how = collections.Counter()
    for r in rs:
        fy = r['funding_year'].strip()
        if single_year(fy, period):
            r['year'] = fy; how['funding_year'] += 1
        elif ymd(r['date_posted']):
            r['year'] = str(ymd(r['date_posted'])[0]); how['date_posted'] += 1
        else:
            r['year'] = str(period[1]); how['report_end'] += 1
    name = 'senate-disbursements_%s_%s.csv' % (label, doc.replace('_', '-'))
    with open(os.path.join(a.out, name), 'w', encoding='utf-8', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=header + ['year'])
        w.writeheader(); w.writerows(rs)
    years = collections.Counter(r['year'] for r in rs)
    summary.append((name, len(rs), period, dict(how), min(years), max(years)))
    print('%-50s %7d rows  period %d-%d  year from %s  years %s..%s' % (name, len(rs), period[0], period[1],
                                                                        dict(how), min(years), max(years)))
print('%d files, %d rows' % (len(summary), sum(s[1] for s in summary)))
