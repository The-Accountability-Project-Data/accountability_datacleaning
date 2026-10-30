"""
Python 3 version of all_years/parse_office_names.py (jsfenfen/senate_disbursements, 2014-15): splits the office text
read_pages.py puts in column 1 ("SENATOR MARK KIRK Funding Year 2013 SENATORS OFFICIAL PERSONNEL ...") into senator
name, funding year, fiscal year and congress.
Changes: Python 3; fiscal years 20xx (2015 matched only 201x); congress numbers 1xx (2015 matched only 11x); the
office text's case is ignored when matching "SENATOR" and "Funding Year" (2021+ reports print mixed case); multi-year
funding ("Funding Year 2026-2030", Sergeant at Arms, 2021+) is kept whole.

  python3 parse_office_names.py            # print the parse of every office in headerlist.csv
"""
import re

senate_office_re = re.compile(r"SENATOR\s+([\w\.\s\,\(\)\'\-]+?)\s+Funding Year (\d+)\s", re.I)
funding_year_re = re.compile(r".+Funding Year ([\dX]+(?:-\d+)?)\s.*", re.I)
congress_no = re.compile(r".+\((1\d\d)TH\)\s.*", re.I)
fy_re = re.compile(r".+ FY (20\d\d) .*")


def parse_office(office):
    funding_year = ""
    fiscal_year = ""
    congress = ""
    senator_name = ""
    # sometimes this gets in
    office = office.replace("DOCUMENT NO. DATE POSTED", "")

    if office.upper().startswith("SENATOR "):
        found_data = senate_office_re.match(office)
        if found_data:
            senator_name, funding_year = found_data.groups()
        else:
            print("No senate match in *** " + office)
    else:
        # first try for a funding year
        found_data = funding_year_re.match(office)
        if found_data:
            funding_year = found_data.group(1)
        else:
            found_data = congress_no.match(office)
            if found_data:
                congress = found_data.group(1)
            else:
                found_data = fy_re.match(office)
                if found_data:
                    fiscal_year = found_data.group(1)

    return [senator_name, funding_year, fiscal_year, congress, office]


if __name__ == "__main__":
    import csv
    for line in csv.reader(open("headerlist.csv", encoding="utf-8")):
        office = line[0]
        print(office)
        print(parse_office(office))
