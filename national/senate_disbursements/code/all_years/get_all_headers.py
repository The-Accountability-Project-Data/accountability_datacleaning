"""
Python 3 version of all_years/get_all_headers.py: counts the office names (column 1) across the *_senate_data.csv
files in this directory and writes headerlist.csv (office, count), for checking parse_office_names.py.
Change: reads every *_senate_data.csv here instead of a hand-edited file list.
"""
import csv
import glob

office_dict = {}
for filename in sorted(glob.glob("*_senate_data.csv")):
    for line in csv.reader(open(filename, encoding="utf-8")):
        office_dict[line[0]] = office_dict.get(line[0], 0) + 1

writer = csv.writer(open("headerlist.csv", "w", newline="", encoding="utf-8"))
for key, n in office_dict.items():
    print("%s - %s" % (key, n))
    writer.writerow([key, n])
