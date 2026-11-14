#!/bin/bash
# Download the Pennsylvania Department of State yearly campaign finance full exports (2000-2026) and readme from
# https://www.pa.gov/agencies/dos/resources/voting-and-elections-resources/campaign-finance-data into
# state/pa/campaign_finance/data/raw/, 1.5 s apart, resuming dropped connections; logs each download to
# state/pa/campaign_finance/data/retrievals.jsonl. Extract the zips into data/raw/x/ for pa_append_2023_2026.R.
#   bash state/pa/campaign_finance/code/fetch.sh
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
B=https://www.pa.gov/content/dam/copapwp-pagov/en/dos/resources/voting-and-elections/campaign-finance/campaign-finance-data
D="$(cd "$(dirname "$0")/.." && pwd)/data"
mkdir -p "$D/raw"
cd "$D/raw" || exit 1
for y in $(seq 2000 2026); do
  for a in 1 2 3 4 5; do
    curl -sS -C - --retry 3 -A "$UA" -o $y.zip $B/$y.zip && unzip -tq $y.zip >/dev/null && break
    sleep 10
  done
  printf '{"retrieved_at": "%s", "url": "%s", "bytes": %s, "sha256": "%s"}\n' "$(date -u +%FT%TZ)" "$B/$y.zip" "$(stat -f %z $y.zip)" "$(shasum -a 256 $y.zip | cut -c1-64)" >> "$D/retrievals.jsonl"
  echo "$y $(stat -f %z $y.zip)"
  sleep 1.5
done
