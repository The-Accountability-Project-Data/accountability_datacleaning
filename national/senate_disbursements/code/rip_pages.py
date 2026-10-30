"""
Python 3 version of rip_pages.py (jsfenfen/senate_disbursements, 2014-15). Runs `pdftotext -layout` on one page at a
time into pages/layout_<n>.txt, as before.

Changes: no hand-edited start_page/end_page or file name. It uses the one PDF in the current directory (or the one
given), rips every page (already-ripped pages are skipped), and prints the itemized page range it finds -- the pages
with the "DOCUMENT NO. ... START END" header -- which read_pages.py also finds on its own.

  cd 119_sdoc6 && python3 rip_pages.py [GPO-CDOC-119sdoc6.pdf]
"""
import glob
import os
import re
import subprocess
import sys

if len(sys.argv) > 1:
    pdf = sys.argv[1]
else:
    pdfs = glob.glob("*.pdf")
    if len(pdfs) != 1:
        sys.exit("Put exactly one report PDF in this directory, or name it: python3 rip_pages.py <file.pdf>")
    pdf = pdfs[0]

os.makedirs("pages", exist_ok=True)
info = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True, check=True).stdout
n_pages = int(re.search(r"Pages:\s+(\d+)", info).group(1))

header_end = re.compile(r"\s+START\s+END\s+")
itemized = []
for page_number in range(1, n_pages + 1):
    output_filename = "pages/layout_%s.txt" % (page_number)
    if not os.path.exists(output_filename):
        layout_cmd = ["pdftotext", "-f", str(page_number), "-l", str(page_number), "-layout", pdf, output_filename]
        print(" ".join(layout_cmd))
        subprocess.run(layout_cmd, check=True)
    with open(output_filename, encoding="utf-8", errors="replace") as fh:
        if any(header_end.search(line) for line in fh.readlines()):
            itemized.append(page_number)

if itemized:
    print("%s: %s pages; itemized pages %s to %s" % (pdf, n_pages, itemized[0], itemized[-1]))
else:
    print("%s: %s pages; no itemized pages found" % (pdf, n_pages))
