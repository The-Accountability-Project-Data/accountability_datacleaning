#!/bin/bash
# Re-run read_pages.py (copied fresh from the top level) in both modes in every report directory, then tabulate.
#   bash compare_reports.sh            -> compare_reports.csv
set -uo pipefail
cd "$(dirname "$0")"
echo "report,mode,rows,unparsed_lines,blocks_match,blocks_match_subset,blocks_differ_unparsed,blocks_differ,blocks_summary_only,rollup_match,rollup_differs,first_page,last_page,skipped_pages" > compare_reports.csv
for dir in 1*_sdoc*/; do
  dir=${dir%/}
  [ -d "$dir/pages" ] || continue
  cp read_pages.py "$dir/"
  (
    cd "$dir"
    for mode in baseline improved; do
      if [ $mode = baseline ]; then
        python3 read_pages.py --baseline --out senate_data_baseline.csv > baseline_run.log 2>&1
        mv missing_data.txt missing_data_baseline.txt; mv subtotals.csv subtotals_baseline.csv; log=baseline_run.log
      else
        python3 read_pages.py > improved_run.log 2>&1; log=improved_run.log
      fi
      python3 - "$dir" "$mode" "$log" >> ../compare_reports.csv <<'PY'
import sys, re, ast
d, mode, log = sys.argv[1:]
text = open(log).read()
last = [l for l in text.splitlines() if " mode: " in l][-1]
m = re.search(r"(\d+) rows, (\d+) unparsed lines; subtotals: (\{.*\})", last)
rows, unp, recon = m.group(1), m.group(2), ast.literal_eval(m.group(3))
pages = [int(x) for x in re.findall(r"^Processing page (\d+)", text, re.M)]
skipped = re.findall(r"^skipped page (\d+)", text, re.M)
g = lambda k: recon.get(k, 0)
print(",".join(str(x) for x in [d, mode, rows, unp, g("match"), g("match_subset"), g("differ_unparsed"), g("differ"), g("summary_only"),
                                g("rollup_match"), g("rollup_differs"), min(pages) if pages else "",
                                max(pages) if pages else "", " ".join(skipped)]))
PY
    done
  )
done
column -s, -t < compare_reports.csv
