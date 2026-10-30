#!/bin/bash
# Copied 2026-10-30 from the project EC2 build box (lda-scrape, ~/il/repair.sh; also in datacleaning_agents ec2/il/box_2026-10-13/).
# Run on Receipts.txt and Expenditures.txt before il_contribs.R / il_expends.R read them, e.g.
#   bash repair.sh raw/Receipts.txt work/Receipts-fixed.txt work/Receipts-rejects.txt
#
# Repair an Illinois SBE tab-delimited bulk file: strip CRs, join continuation lines (not starting with "<id><tab>")
# onto the record above with a space, then keep only lines with the header's field count; set aside the rest.
in=$1; out=$2; rej=$3
n=$(head -1 "$in" | tr -d "\r" | tr "\t" "\n" | wc -l)
tr -d "\r" < "$in" | awk -v n=$n -v out="$out" -v rej="$rej" -F"\t" "
  function flush() { if (have) { k = split(buf, f, \"\t\"); if (NR_rec == 1 || k == n) print buf > out; else { print buf > rej; bad++ } } }
  NR == 1 { buf = \$0; have = 1; NR_rec = 1; next }
  /^[0-9]+\t/ { flush(); buf = \$0; have = 1; NR_rec++; next }
  { buf = buf \" \" \$0; joined++ }
  END { flush(); printf \"%s: %d records, %d continuation lines joined, %d set aside\n\", FILENAME, NR_rec - 1, joined, bad > \"/dev/stderr\" }"
