"""
Python 3 version of all_years/clean_files.py: turns each <report>_senate_data.csv (read_pages.py's 11 columns) into
<report>_senate_data_cleaned.csv with a header row and 16 columns: source_doc, senator_flag, senator_name, raw_office,
funding_year, fiscal_year, congress_number, reference_page, document_number, date_posted, start_date, end_date,
description, salary_flag, amount, payee. salary_flag = 1 for 'three data line' rows (payroll).

Changes: Python 3; files named on the command line, or every *_senate_data.csv in this directory (2015 used a
hand-edited list); the "parsed ... by the Sunlight Foundation" line above the header is written only with
--sunlight-preheader (it was true of the 2011-2015 files, not of later parses).

  python3 clean_files.py [--sunlight-preheader] [114_sdoc4_senate_data.csv ...]
"""
import argparse
import csv
import glob

from parse_office_names import parse_office

header_row = ['source_doc', 'senator_flag', 'senator_name', 'raw_office', 'funding_year', 'fiscal_year',
              'congress_number', 'reference_page', 'document_number', 'date_posted', 'start_date', 'end_date',
              'description', 'salary_flag', 'amount', 'payee']

pre_header = ("This data was parsed on an experimental basis by the Sunlight Foundation from Senate disbursement "
              "reports. Please cite 'The Sunlight Foundation' in any usage.  For more information see the readme at "
              "http://assets-reporting.s3.amazonaws.com/1.0/senate_disbursements/readme.txt.\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--sunlight-preheader", action="store_true")
    a = ap.parse_args()
    for filename in a.files or sorted(glob.glob("*_senate_data.csv")):
        cleaned_filename = filename.replace(".csv", "_cleaned.csv")
        source_doc = filename.replace("_senate_data.csv", "")
        n = 0
        with open(filename, encoding="utf-8") as fin, open(cleaned_filename, "w", newline="", encoding="utf-8") as fh:
            if a.sunlight_preheader:
                fh.write(pre_header)
            writer = csv.writer(fh)
            writer.writerow(header_row)
            for line in csv.reader(fin):
                (office_raw, line_type, continuation_line, reference_page, transaction_id, date_posted, payee,
                 start_date, end_date, description, amount) = line[:11]
                senator_name, funding_year, fiscal_year, congress, office = parse_office(office_raw)
                salary_flag = 1 if line_type == 'three data line' else 0
                senator_flag = 1 if senator_name else 0
                writer.writerow([source_doc, senator_flag, senator_name, office, funding_year, fiscal_year, congress,
                                 reference_page, transaction_id, date_posted, start_date, end_date, description,
                                 salary_flag, amount, payee])
                n += 1
        print("%s: %s rows -> %s" % (filename, n, cleaned_filename))


if __name__ == "__main__":
    main()
