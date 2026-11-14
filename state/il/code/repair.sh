#!/bin/bash
# Run on Receipts.txt and Expenditures.txt before il_contribs.R / il_expends.R read them. From the repo root:
#   bash state/il/code/repair.sh contribs   # state/il/contribs/data/raw/Receipts.txt -> Receipts-fixed.txt, Receipts-rejects.txt
#   bash state/il/code/repair.sh expends    # state/il/expends/data/raw/Expenditures.txt -> Expenditures-fixed.txt, Expenditures-rejects.txt
# or with explicit files:
#   bash state/il/code/repair.sh <Receipts.txt> <Receipts-fixed.txt> <Receipts-rejects.txt>
#
# Repair an Illinois SBE tab-delimited bulk file: strip CRs, join continuation lines (not starting with "<id><tab>")
# onto the record above with a space, then keep only lines with the header's field count; set aside the rest.
IL="$(cd "$(dirname "$0")/.." && pwd)"
case "$1" in
  contribs) D="$IL/contribs/data/raw"; in="$D/Receipts.txt"; out="$D/Receipts-fixed.txt"; rej="$D/Receipts-rejects.txt" ;;
  expends)  D="$IL/expends/data/raw"; in="$D/Expenditures.txt"; out="$D/Expenditures-fixed.txt"; rej="$D/Expenditures-rejects.txt" ;;
  *)        in=$1; out=$2; rej=$3 ;;
esac
n=$(head -1 "$in" | tr -d "\r" | tr "\t" "\n" | wc -l)
tr -d "\r" < "$in" | awk -v n=$n -v out="$out" -v rej="$rej" -F"\t" "
  function flush() { if (have) { k = split(buf, f, \"\t\"); if (NR_rec == 1 || k == n) print buf > out; else { print buf > rej; bad++ } } }
  NR == 1 { buf = \$0; have = 1; NR_rec = 1; next }
  /^[0-9]+\t/ { flush(); buf = \$0; have = 1; NR_rec++; next }
  { buf = buf \" \" \$0; joined++ }
  END { flush(); printf \"%s: %d records, %d continuation lines joined, %d set aside\n\", FILENAME, NR_rec - 1, joined, bad > \"/dev/stderr\" }"
