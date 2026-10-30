"""
Python 3 version of read_pages.py (jsfenfen/senate_disbursements, 2014-15). Reads pages/layout_<n>.txt (from
rip_pages.py) and writes, as before:
  senate_data.csv     no header; 11 columns: office (with its "Funding Year" text), line type, continuation flag, page,
                      document no., date posted, payee, start date, end date, description, amount (no "$")
  missing_data.txt    one line per page with lines that couldn't be parsed (they're also printed: "missing <...>")
and, new, subtotals.csv (CSV, with a header): every subtotal line the report prints, reconciled against the parsed rows
it closes. Differences are expected -- it measures them, it doesn't promise the Senate's arithmetic.

  cd 119_sdoc6 && python3 read_pages.py              # improved parsing (default)
  cd 119_sdoc6 && python3 read_pages.py --baseline   # the 2015 logic, for comparison

What changed from the 2015 script, both modes:
  * Python 3; no hand-edited start_page/end_page: the itemized pages are the ones with exactly one
    "DOCUMENT NO. ... START END" header, and pages without one are skipped (and printed) instead of hard-coded
  * amounts may carry a "$" (2026 reports print "$500.00", "-$5,704.52"); the "$" is dropped in senate_data.csv so
    the column looks like the old files ("60,000.00")
Improved mode only (--baseline turns these off):
  * continuation lines that start a new page attach to the entry they continue (2015 reset at every page and lost them)
  * a payroll line with only "LAST, FIRST" and an amount, its title wrapped onto the lines above/below, is parsed as a
    'three data line' with the title reassembled
  * subtotals.csv: a block whose rows add up, to the cent, to some of its subtotals is "match_subset", with the
    others listed in unitemized_subtotals (an office's summary prints payroll and benefits totals not itemized there)
  * a subtotal label with no amount under an open entry ("INTERDEPARTMENTAL TRANSPORTATION") is a description line,
    not a subtotal (2015 split the reconciliation there and dropped the text)
  * subtotal labels match case-insensitively ("Net Payroll Expenses") and include "BENEFITS FOR FORMER PERSONNEL"
  * payee names that wrap (2021+ layout) are rejoined: text below the row in the payee column, and, when the row's
    payee field is blank, text above it too
  * object-class codes alone at the margin ("3.00", 2015 layout) are skipped as layout markers
  * five-data lines that newer pdftotext splits in two (end date, or description and amount, on the next line) are
    rejoined
  * an entry continued from the previous page uses the new page's column positions; appendix page numbers ("C-4")
    are skipped, as are GPO print marks at the left margin ("25-107", "05/05/2017", "JA"), also in the office text
  * a page whose header sits low but has no office text above it continues the previous page's office (2020+ pages
    put the column header at the margin, below a stray line, and 2015 took the header itself for the office)
"""
import argparse
import csv
import glob
import re

AMT = r"(\-?\$?\-?[\d\.\,]+)"           # 2015: ([\d\.\-\,]+)

header_end = re.compile(r"\s+START\s+END\s+")

## p. 1172 is missing a space between the final date and the description. Can't understand why the layout option does this; a space is clearly visible. I dunno.
five_data_re = re.compile(r"\s*([\w\d]+)\s+(\d\d\/\d\d\/\d\d\d\d)\s+(.*?)\s+(\d\d\/\d\d\/\d\d\d\d)\s+(\d\d\/\d\d\/\d\d\d\d)\s*(.+?)\s+" + AMT + r"\s*\Z")
five_data_missing_date = re.compile(r"\s*([\w\d]+)\s+(\d\d\/\d\d\/\d\d\d\d)\s+(.*?)\s{10,}(.*?)\s+" + AMT + r"\s*\Z")
three_data_re = re.compile(r"\s+(\w[\w\,\s\.\-\']+?)\s{10,}(\w.*?)\s{4,}" + AMT + r"\s*")

top_matter_end_re = re.compile(r"\s+DOCUMENT\s+NO\.\s+DATE\s+PAYEE")
# improved: the column header can start at the left margin (2020+), which the 2015 pattern (leading spaces) misses
top_matter_start_re = re.compile(r"\s*DOCUMENT\s+NO\.\s+DATE\s+PAYEE")
funding_year_re = re.compile(r"\s*Funding\s+Year\s+(\d+)")
blank_line_re = re.compile(r"\s+\Z")

page_number_alt_re = re.compile(r"\s+\w\-\d\-\d+")
continuation_with_amount_re = re.compile(r"\s*(.+?)\s{10,}" + AMT + r"\s+\Z")
page_number_re = re.compile(r"\s+B\s*\-\s*\d+\s*")
# object-class code printed alone at the left margin between subtotal blocks ("3.00"): a layout marker (improved mode)
# appendix page numbers on a line of their own ("C-4"; 2015's "B-2-" form is page_number_alt_re) (improved mode)
appendix_page_re = re.compile(r"\s+[A-Z]-\d+-?\s*\Z")
# GPO print marks at the left margin, alone on a line (115_sdoc2 prints them on every page): job number "25-107",
# print date "05/05/2017", "JA" (improved mode)
gpo_mark_re = re.compile(r"(?:\d\d-\d{3}|\d\d/\d\d/\d\d\d\d|JA)\s*\Z")
class_code_re = re.compile(r" {0,4}\d\.\d\d\s*\Z")
# five-data line whose end date (and amount) pdftotext pushed onto the next line (newer poppler, 2015 layout):
#   "DAPP21500006  10/30/2014  KIEFFER,CHARLES E   10/16/2014   STAFF TRANSPORTATION"
#   "                                                         10/16/2014                      69.52"
split_head_re = re.compile(r"(\s*[\w\d]+\s+\d\d\/\d\d\/\d\d\d\d\s+.*?\s+\d\d\/\d\d\/\d\d\d\d)\s+(\S.*?)\s*(?:" + AMT + r")?\s*\Z")
split_dates_re = re.compile(r"(\s*[\w\d]+\s+\d\d\/\d\d\/\d\d\d\d\s+.*?\s+\d\d\/\d\d\/\d\d\d\d\s+\d\d\/\d\d\/\d\d\d\d)\s*\Z")
split_tail_re = re.compile(r"\s+(\d\d\/\d\d\/\d\d\d\d)(?:\s+" + AMT + r")?\s*\Z")

# payroll line whose title wrapped onto the lines above/below: just "LAST, FIRST M." and the amount (improved mode)
name_amount_re = re.compile(r"\s+([A-Z][A-Z'\-\. ]+,\s*[A-Z][\w'\-\. ]*?)\s{10,}" + AMT + r"\s*\Z")

SUBTOTALS_2015 = [r"TRAVEL\s+AND\s+TRANSPORTATION\s+OF\s+PERSONS", r"INTERDEPARTMENTAL\s+TRANSPORTATION",
                  r"OTHER\s+CONTRACTUAL\s+SERVICES", r"ACQUISITION\s+OF\s+ASSETS", r"PERSONNEL\s+BENEFITS",
                  r"NET\s+PAYROLL\s+EXPENSES", r"PERSONNEL COMP. FULL-TIME PERMANENT", r"OTHER PERSONNEL COMPENSATION",
                  r"RE-EMPLOYED ANNUITANTS", r"BENEFITS FOR NON SENATE/FORMER PERSONNEL"]
SUBTOTALS_ADDED = [r"BENEFITS\s+FOR\s+FORMER\s+PERSONNEL"]
# roll-ups sum the subtotals above them (Net Payroll Expenses = compensation + benefits + ...): for subtotals.csv only
ROLLUPS = {"net payroll expenses"}
subtotal_amount_re = re.compile(r"\s*(?:\d+\.\d\d\s+)?(.+?)\s{2,}" + AMT + r"\s*\Z")
# subtotals the report prints without itemized rows (2021+ layout): left out of block sums so they don't make the
# itemized subtotal they sit next to look short; still feed roll-ups
NON_ITEMIZED = {"personnel benefits"}


def make_is_subtotal(baseline):
    if baseline:
        res = [re.compile(r"\s+" + s + r"\s+") for s in SUBTOTALS_2015]
    else:
        # some sections print an object-class code before the label at the left margin: "3.00   TRAVEL AND ..."
        res = [re.compile(r"\s*(?:\d+\.\d\d\s+)?\s*" + s + r"\s+", re.I) for s in SUBTOTALS_2015 + SUBTOTALS_ADDED]
    return lambda line: any(r.match(line) for r in res)


def matching_subset(subs, target, max_subs=10):
    """the smallest set of a block's subtotals whose amounts add up to target (the parsed rows) to the cent, or None"""
    import itertools
    with_amt = [x for x in subs if x["amount"]]
    if len(with_amt) > max_subs:
        return None
    for k in range(1, len(with_amt)):
        for combo in itertools.combinations(with_amt, k):
            if abs(sum(amount_num(x["amount"]) for x in combo) - target) < 0.005:
                return list(combo)
    return None


def amount_num(a):
    a = (a or "").replace("$", "").replace(",", "")
    neg = a.count("-") % 2 == 1
    try:
        return -float(a.replace("-", "")) if neg else float(a.replace("-", ""))
    except ValueError:
        return 0.0


def process_top_matter(page_num, top_matter, baseline=True):
    top_matter_top_left_column_delimiter = 48
    expense_description = ''
    for whole_line in top_matter:
        if top_matter_end_re.match(whole_line) or (not baseline and top_matter_start_re.match(whole_line)):
            break
        line = whole_line[:top_matter_top_left_column_delimiter]
        if blank_line_re.match(line):
            continue
        if not baseline and gpo_mark_re.match(line.strip()):
            continue
        line_stripped = line.strip()
        if line_stripped:
            expense_description += ' ' + line_stripped + ' '
    expense_description = re.sub(r'\s+', ' ', expense_description).strip()
    return expense_description


# some carryover lines have amounts in them, and some don't -- that is, they are just extensions of the text field. See, e.g. p. 1672.
def test_carryover_line(line_offset, line):
    line_start = line[:line_offset]
    if blank_line_re.match(line_start):
        line_end = line[line_offset:]
        if not blank_line_re.match(line_end):
            return True
    return False


def process_data_lines(page_num, data_lines, is_subtotal, baseline, carry):
    """2015 logic, plus (improved mode) `carry` across page breaks and wrapped payroll titles.
    carry: last_idx = column where the last entry's description starts; chain = that entry's rows (its five-data line
    and continuation rows), which later one-part continuations extend."""
    missing_data, return_data, subtotals = [], [], []
    # these are lines that describe prior lines--typically the travel associated with a per diem or a transportation
    # line. In baseline mode they're recorded in one_part_continuation_register and processed after the page.
    one_part_continuation_register = []
    pending_text, title_row = [], None
    if baseline:
        carry = {"last_idx": None, "chain": []}
    elif carry["chain"]:
        # the columns can move at a page break (118_sdoc8 p. 191 -> 192: description column 114 -> 85), so the entry
        # carried over from the previous page takes this page's columns, from its first five-data line
        for line in data_lines:
            m = five_data_re.match(line)
            if m:
                carry["last_idx"] = m.start(6)
                if m.group(3).strip():
                    carry["payee_idx"] = carry["payee_col"] = m.start(3)
                break

    def to_missing(line):
        print("missing <" + line + ">")
        missing_data.append({'data': line, 'offset': len(return_data), 'page_num': page_num})

    def flush_text():
        for t in pending_text:
            to_missing(t)
        pending_text.clear()

    def next_row_has_blank_payee(i):
        for nxt in data_lines[i + 1:]:
            if blank_line_re.match(nxt):
                continue
            m = five_data_re.match(nxt)
            return bool(m) and not m.group(3).strip()
        return False

    consumed = set()

    def rejoin_split(i, line):
        """improved mode: a five-data line missing its end date, with the date (and amount) alone on the next line"""
        both = split_dates_re.match(line)
        if both:
            # all three dates on the line, description and amount on the next one
            for j in range(i + 1, len(data_lines)):
                if blank_line_re.match(data_lines[j]):
                    continue
                rest = continuation_with_amount_re.match(data_lines[j])
                if not rest:
                    return None
                consumed.add(j)
                return five_data_re.match("%s   %s   %s" % (both.group(1), rest.group(1).strip(), rest.group(2)))
            return None
        head = split_head_re.match(line)
        if not head or re.search(r"\d\d/\d\d/\d\d\d\d\s+\d\d/\d\d/\d\d\d\d", line):
            return None
        for j in range(i + 1, len(data_lines)):
            if blank_line_re.match(data_lines[j]):
                continue
            tail = split_tail_re.match(data_lines[j])
            amount = head.group(3) or (tail and tail.group(2))
            if not tail or not amount or (head.group(3) and tail.group(2)):
                return None
            consumed.add(j)
            return five_data_re.match("%s   %s   %s   %s" % (head.group(1), tail.group(1), head.group(2), amount))
        return None

    for line_i, data_line in enumerate(data_lines):
        if line_i in consumed:
            continue
        if not baseline and (class_code_re.match(data_line) or appendix_page_re.match(data_line)
                             or gpo_mark_re.match(data_line)):
            continue
        if blank_line_re.match(data_line):
            # don't reset last line data index--sometimes the page number appears in the middle of a page.
            continue
        if page_number_re.match(data_line):
            continue
        if is_subtotal(data_line) and not (not baseline and carry["chain"] and not subtotal_amount_re.match(data_line)):
            # improved: a subtotal label with no amount while an entry is open is the entry's description continuing
            # ("STAFF TRANSPORTATION" / "INTERDEPARTMENTAL TRANSPORTATION"), not a subtotal
            flush_text()
            carry["last_idx"], carry["chain"], title_row = None, [], None
            st = subtotal_amount_re.match(data_line)
            subtotals.append({"after_row": len(return_data),
                              "label": re.sub(r"\s+", " ", st.group(1) if st else data_line).strip(),
                              "amount": st.group(2) if st else ""})
            continue

        found_data = five_data_re.match(data_line)
        if not found_data and not baseline:
            found_data = rejoin_split(line_i, data_line)
        if found_data:
            row = ['five data line', False, page_num] + list(found_data.groups())
            payee_idx = found_data.start(3)
            if not baseline:
                if row[5].strip():
                    carry["payee_col"] = payee_idx
                else:
                    # payee printed around the row (2021+ layout): first part on the line(s) above, the rest below,
                    # nothing on the row itself. Take the pending text lines that sit in the payee column.
                    col = carry.get("payee_col") or found_data.end(2) + 3
                    above = [t for t in pending_text if abs((len(t) - len(t.lstrip())) - col) <= 3]
                    if above:
                        row[5] = " ".join(t.strip() for t in above)
                        pending_text[:] = [t for t in pending_text if t not in above]
                    payee_idx = col
            flush_text()
            return_data.append(row)
            carry["last_idx"], carry["chain"], title_row = found_data.start(6), [row], None
            carry["payee_idx"] = payee_idx
            continue

        found_data2 = three_data_re.match(data_line)
        found_data_missing_date = five_data_missing_date.match(data_line)
        found_name = None if baseline else name_amount_re.match(data_line)
        if found_data2:
            flush_text()
            results = list(found_data2.groups())
            return_data.append(['three data line', False, page_num, '', '', results[0], '', '', results[1], results[2]])
            carry["last_idx"], carry["chain"], title_row = None, [], None
        elif found_data_missing_date:
            flush_text()
            print("**found missing date line")
            results = list(found_data_missing_date.groups())
            return_data.append(['missing date line', False, page_num, results[0], results[1], results[2], '', '',
                                results[3], results[4]])
            carry["last_idx"], carry["chain"], title_row = None, [], None
        elif found_name:
            # a payroll line whose title wrapped: the text lines just above are its first part
            title = " ".join(t.strip() for t in pending_text)
            pending_text.clear()
            row = ['three data line', False, page_num, '', '', found_name.group(1).strip(), '', '', title,
                   found_name.group(2)]
            return_data.append(row)
            carry["last_idx"], carry["chain"], title_row = None, [], row
        else:
            is_page_num = page_number_re.match(data_line)
            is_page_num_alt = page_number_alt_re.match(data_line)
            if is_page_num or is_page_num_alt:
                continue
            if baseline and carry["last_idx"] and not test_carryover_line(int(carry["last_idx"]), data_line):
                continue   # 2015: a non-continuation line after a five-data line was dropped without being recorded
            stripped = data_line.strip()
            lead = len(data_line) - len(data_line.lstrip())
            if (not baseline and carry["chain"] and carry.get("payee_idx") is not None
                    and abs(lead - carry["payee_idx"]) <= 3 and lead < carry["last_idx"] - 10
                    and not continuation_with_amount_re.match(data_line) and not re.search(r"\d\d/\d\d/\d\d\d\d", data_line)
                    and not next_row_has_blank_payee(line_i)):
                # a payee name that wrapped onto the next line (2021+ layout): add it to the entry's payee
                for r in carry["chain"]:
                    r[5] = r[5] + " " + stripped
                continue
            # improved: allow the description column to sit up to 10 characters further left (it shifts from page to page)
            slack = 0 if baseline else 10
            if carry["last_idx"] and carry["chain"] and test_carryover_line(max(1, int(carry["last_idx"]) - slack), data_line):
                continuation_data = continuation_with_amount_re.match(data_line)
                if continuation_data:
                    # it's a two part continuation--probably per diem/travel. So add same data as for the first line.
                    p = carry["chain"][-1]
                    row = ['continuation_data', True, p[2], p[3], p[4], p[5], p[6], p[7], continuation_data.group(1),
                           continuation_data.group(2)]
                    return_data.append(row)
                    carry["chain"].append(row)
                elif baseline:
                    one_part_continuation_register.append({'array_index': len(return_data),
                                                           'data': data_line.strip()})
                else:
                    for r in carry["chain"]:
                        r[8] = r[8] + " + " + data_line.strip()
            elif title_row is not None and not continuation_with_amount_re.match(data_line):
                # the rest of a wrapped payroll title, below the name line (improved mode)
                title_row[8] = (title_row[8] + " " + data_line.strip()).strip()
            elif not baseline:
                pending_text.append(data_line.rstrip("\n"))
            else:
                to_missing(data_line.rstrip("\n"))
    flush_text()

    # baseline: run through the continuation lines and append them to the right places (2015 logic)
    for cl in one_part_continuation_register:
        current_line_position = cl['array_index'] - 1
        while current_line_position >= 0:
            return_data[current_line_position][8] = return_data[current_line_position][8] + " + " + cl['data']
            if return_data[current_line_position][0] != 'continuation_data':
                break
            current_line_position -= 1   # it's a continuation line, so append this to the previous line too.
    return return_data, subtotals, missing_data


def find_header_index(line_array):
    hits = [index for index, line in enumerate(line_array) if header_end.search(line)]
    # 2015 asserted exactly one per page; now a page without exactly one is skipped
    return (hits[0] if len(hits) == 1 else None), len(hits)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--baseline", action="store_true", help="the 2015 parsing logic (plus $ amounts), for comparison")
    ap.add_argument("--pages", help="limit to a page range, e.g. 17-2073")
    ap.add_argument("--out", default="senate_data.csv")
    a = ap.parse_args()
    baseline = a.baseline
    is_subtotal = make_is_subtotal(baseline)
    source_doc = (glob.glob("*.pdf") or ["?"])[0].replace("GPO-CDOC-", "").replace(".pdf", "")

    pages = sorted(int(re.search(r"layout_(\d+)\.txt", f).group(1)) for f in glob.glob("pages/layout_*.txt"))
    if a.pages:
        lo, hi = (int(x) for x in a.pages.split("-"))
        pages = [p for p in pages if lo <= p <= hi]

    header_index_hash = {}
    skipped = []
    started = False
    current_description = description = None
    carry = {"last_idx": None, "chain": []}
    # reconciliation state (subtotals.csv). A run of subtotal lines with no rows between them is one BLOCK that sums the
    # rows above it: 2015 reports print a block of category subtotals after mixed rows, 2026 reports print one subtotal
    # per group (a block of one). Blocks may continue across a page break. Roll-ups (Net Payroll Expenses) are checked
    # against the non-roll-up subtotals since the previous roll-up, within an office.
    group = {"rows": 0, "sum": 0.0, "unparsed": 0}     # rows since the last subtotal
    block = None                                        # the open block: its rows and its subtotal lines
    since_rollup, rollup_office = [], None
    recon = {}
    n_blocks = [0]
    counts = {"rows": 0, "missing": 0}

    csvfile = open(a.out, 'w', newline='', encoding='utf-8')
    datawriter = csv.writer(csvfile)
    missing_data_file = open("missing_data.txt", 'w', encoding='utf-8')
    stfile = open("subtotals.csv", 'w', newline='', encoding='utf-8')
    stwriter = csv.writer(stfile)
    stwriter.writerow(["source_doc", "block", "page", "office", "label", "subtotal_amount", "block_subtotal_sum",
                       "parsed_rows", "parsed_sum", "difference", "unparsed_lines_in_block", "status",
                       "unitemized_subtotals"])

    # rows are written at the end: a continuation at the top of the next page can still extend an earlier page's rows
    out_rows = []

    def write_row(desc, r):
        out_rows.append((desc, r))

    def close_block():
        nonlocal block, since_rollup, rollup_office
        if block is None:
            return
        n_blocks[0] += 1
        regular = [x for x in block["subs"] if x["label"].lower() not in ROLLUPS
                   and not (not baseline and x["label"].lower() in NON_ITEMIZED and len(block["subs"]) > 1)]
        amounts = [amount_num(x["amount"]) for x in regular if x["amount"]]
        block_sum = sum(amounts)
        unitemized = ""
        if regular and amounts:
            diff = round(block_sum - block["sum"], 2)
            subset = None
            if abs(diff) >= 0.005 and block["rows"] and not baseline:
                subset = matching_subset(regular, block["sum"])
            if abs(diff) < 0.005:
                status = "match"
            elif subset:
                # the rows equal some of the block's subtotals to the cent; the others aren't itemized here (an
                # office's summary lists payroll/benefits totals whose rows are elsewhere or never itemized)
                status = "match_subset"
                unitemized = "; ".join(x["label"] for x in regular if x not in subset)
            elif block["unparsed"]:
                status = "differ_unparsed"
            elif not block["rows"]:
                status = "summary_only"
            else:
                status = "differ"
        else:
            diff, status = None, "no_amount" if regular else None
        if status:
            recon[status] = recon.get(status, 0) + 1
        for x in block["subs"]:
            if x["office"] != rollup_office:
                since_rollup, rollup_office = [], x["office"]
            is_rollup = x["label"].lower() in ROLLUPS
            if is_rollup:
                rsum = sum(since_rollup)
                rdiff = None if not x["amount"] else round(amount_num(x["amount"]) - rsum, 2)
                rstatus = "rollup_no_amount" if rdiff is None else ("rollup_match" if abs(rdiff) < 0.005 else "rollup_differs")
                recon[rstatus] = recon.get(rstatus, 0) + 1
                stwriter.writerow([source_doc, n_blocks[0], x["page"], x["office"], x["label"], x["amount"], "", "",
                                   "%.2f" % rsum, "" if rdiff is None else "%.2f" % rdiff, block["unparsed"], rstatus, ""])
                since_rollup = []
            else:
                if x["amount"]:
                    since_rollup.append(amount_num(x["amount"]))
                stwriter.writerow([source_doc, n_blocks[0], x["page"], x["office"], x["label"], x["amount"],
                                   "%.2f" % block_sum, block["rows"], "%.2f" % block["sum"],
                                   "" if diff is None else "%.2f" % diff, block["unparsed"], status or "", unitemized])
        block = None

    last_itemized = None
    for page in pages:
        with open("pages/layout_%s.txt" % page, encoding='utf-8', errors='replace') as fh:
            page_array = fh.readlines()
        header_index, n_headers = find_header_index(page_array)
        if header_index is None:
            if started:
                skipped.append((page, n_headers))
            continue
        started, last_itemized = True, page
        print("Processing page %s" % page)
        header_index_hash[header_index] = header_index_hash.get(header_index, 0) + 1

        # This is based on research...
        if header_index > 6:
            top_matter = page_array[:header_index + 1]
            new_description = process_top_matter(page, top_matter, baseline)
            if baseline or new_description:
                description = new_description
                carry = {"last_idx": None, "chain": []}
            # improved: no office text above the header (a continuation page whose header sits low): same office
        current_description = description

        data_lines = page_array[header_index + 1:]
        rows, subtotals, missing = process_data_lines(page, data_lines, is_subtotal, baseline, carry)
        if missing:
            missing_data_file.write(str(missing) + "\n")
        counts["rows"] += len(rows)
        counts["missing"] += len(missing)

        # write rows in order; group subtotal lines into blocks and reconcile each block (subtotals.csv)
        missing_offsets = [m['offset'] for m in missing]
        st_i = 0
        for i in range(len(rows) + 1):
            while st_i < len(subtotals) and subtotals[st_i]["after_row"] == i:
                st = dict(subtotals[st_i], page=page, office=current_description)
                st_i += 1
                group["unparsed"] += sum(1 for o in missing_offsets if o <= i)
                missing_offsets = [o for o in missing_offsets if o > i]
                if group["rows"] or group["unparsed"] or block is None:
                    close_block()          # rows since the last subtotal: this subtotal starts a new block
                    block = {"rows": group["rows"], "sum": group["sum"], "unparsed": group["unparsed"], "subs": []}
                    group = {"rows": 0, "sum": 0.0, "unparsed": 0}
                block["subs"].append(st)
            if i < len(rows):
                write_row(current_description, rows[i])
                group["rows"] += 1
                group["sum"] += amount_num(rows[i][9])
        group["unparsed"] += len(missing_offsets)
    close_block()
    for desc, r in out_rows:
        out = [desc] + r
        out[10] = (out[10] or "").replace("$", "")
        datawriter.writerow(out)
    csvfile.close()

    for p, n in skipped:
        if p < (last_itemized or 0):
            print("skipped page %s: %s header lines" % (p, n))
    for k, v in sorted(header_index_hash.items()):
        print(k, v)
    print("%s mode: %s rows, %s unparsed lines; subtotals: %s" % ("baseline" if baseline else "improved",
                                                                   counts["rows"], counts["missing"], recon))


if __name__ == "__main__":
    main()
