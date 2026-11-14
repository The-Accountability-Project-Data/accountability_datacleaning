"""Second step of "Texas Parcels 2026": add separate site and mailing address columns to the file build.py writes, and
write the parcels with no PROP_ID and no OWNER_NAME last.

    python address_columns.py <tx_parcels_2026_base.csv> <output.csv>

All source columns are kept as published. Added after LONGITUDE:
  site_state         TX on every row (SITUS_STAT is blank in 18% of rows).
  SITE_STREET        SITUS_NUM, SITUS_STRE, SITUS_ST_1 and SITUS_ST_2 joined with spaces. When all four are blank, the
                     street part of SITUS_ADDR: the text before its first comma; when nothing but state and ZIP follows
                     it, a trailing city name of that county (see below) is moved to SITE_CITY.
  SITE_CITY          SITUS_CITY; when blank, the city part of SITUS_ADDR (the text after the first comma, without a
                     trailing TX and ZIP), or the city moved from the street.
  SITE_ZIP           SITUS_ZIP when it is 5 digits; otherwise a 5-digit ZIP (with optional 4-digit extension) at the end
                     of SITUS_ADDR.
  MAIL_CITY_PARSED   MAIL_CITY, without a trailing ", XX" state (Tarrant writes "FORT WORTH, TX").
  MAIL_STATE_PARSED  The ", XX" state from MAIL_CITY; else a full state name before the ZIP in MAIL_ADDR (Dallas writes
                     "ROWLETT, TEXAS 750898805, UNITED STATES OF AMERICA" and MAIL_STAT "TE"); else MAIL_STAT when it
                     is a U.S. state, territory or military abbreviation; else blank.
County city names: SITUS_CITY values seen at least 20 times in the county, and parsed mailing cities in Texas seen at
least 50 times in the county. A city is moved from the street only when two or more words of street remain. When no
county city name matches, Texas city names seen at least 500 times statewide are tried, and a city is moved only when
the street left ends in a street type (ST, RD, DR, ...) or a county/farm road number (CR 12, FM 1960).
"""
import collections
import csv
import re
import sys

csv.field_size_limit(10 ** 9)

NAMES = {
    'ALABAMA': 'AL', 'ALASKA': 'AK', 'ARIZONA': 'AZ', 'ARKANSAS': 'AR', 'CALIFORNIA': 'CA', 'COLORADO': 'CO',
    'CONNECTICUT': 'CT', 'DELAWARE': 'DE', 'DISTRICT OF COLUMBIA': 'DC', 'FLORIDA': 'FL', 'GEORGIA': 'GA',
    'HAWAII': 'HI', 'IDAHO': 'ID', 'ILLINOIS': 'IL', 'INDIANA': 'IN', 'IOWA': 'IA', 'KANSAS': 'KS', 'KENTUCKY': 'KY',
    'LOUISIANA': 'LA', 'MAINE': 'ME', 'MARYLAND': 'MD', 'MASSACHUSETTS': 'MA', 'MICHIGAN': 'MI', 'MINNESOTA': 'MN',
    'MISSISSIPPI': 'MS', 'MISSOURI': 'MO', 'MONTANA': 'MT', 'NEBRASKA': 'NE', 'NEVADA': 'NV', 'NEW HAMPSHIRE': 'NH',
    'NEW JERSEY': 'NJ', 'NEW MEXICO': 'NM', 'NEW YORK': 'NY', 'NORTH CAROLINA': 'NC', 'NORTH DAKOTA': 'ND',
    'OHIO': 'OH', 'OKLAHOMA': 'OK', 'OREGON': 'OR', 'PENNSYLVANIA': 'PA', 'RHODE ISLAND': 'RI',
    'SOUTH CAROLINA': 'SC', 'SOUTH DAKOTA': 'SD', 'TENNESSEE': 'TN', 'TEXAS': 'TX', 'UTAH': 'UT', 'VERMONT': 'VT',
    'VIRGINIA': 'VA', 'WASHINGTON': 'WA', 'WEST VIRGINIA': 'WV', 'WISCONSIN': 'WI', 'WYOMING': 'WY',
    'PUERTO RICO': 'PR', 'VIRGIN ISLANDS': 'VI', 'GUAM': 'GU', 'AMERICAN SAMOA': 'AS', 'NORTHERN MARIANA ISLANDS': 'MP'}
STATES = set(NAMES.values()) | {'AA', 'AE', 'AP'}
CITY_ST = re.compile(r'^(.*\S)\s*,\s*([A-Za-z]{2})$')
FULL = re.compile(r',\s*(' + '|'.join(sorted(NAMES, key=len, reverse=True)) + r')\s+\d{5}', re.I)
ZIP_END = re.compile(r'(\d{5})(?:-?\d{4})?\s*$')
TAIL = re.compile(r'(?:\s*,?\s*\bTX\b)?\s*(?:\d{5}(?:-?\d{4})?)?\s*$', re.I)
ZIP5 = re.compile(r'^\d{5}$')
STREET_END = re.compile(r'(?:\b(?:ST|STREET|RD|ROAD|DR|DRIVE|LN|LANE|AVE?|AVENUE|CIR|CT|BLVD|TRL|TRAIL|WAY|PL|PLACE|HWY|'
                        r'PKWY|LOOP|PASS|PATH|RUN|TER|TERRACE|XING|BND|COVE|CV|SQ|ROW|ALY|EXPY|FWY|TRCE|PT|HL|HOLW|'
                        r'MDWS|PARK|VW|WALK)|\b(?:CR|FM|RR|SH|US|IH|HWY|RM|PR)\s*\d+[A-Z]?)$', re.I)


def mail(row):
    city, st = row['MAIL_CITY'].strip(), ''
    m = CITY_ST.match(city)
    if m and m.group(2).upper() in STATES:
        city, st = m.group(1), m.group(2).upper()
    if not st:
        m = FULL.search(row['MAIL_ADDR'])
        if m:
            st = NAMES[m.group(1).upper()]
    if not st and row['MAIL_STAT'].strip().upper() in STATES:
        st = row['MAIL_STAT'].strip().upper()
    return city, st


def site(row, cities, state_cities):
    parts = [row[k].strip() for k in ('SITUS_NUM', 'SITUS_STRE', 'SITUS_ST_1', 'SITUS_ST_2')]
    a = row['SITUS_ADDR'].strip()
    city = row['SITUS_CITY'].strip()
    z = row['SITUS_ZIP'].strip()
    zip_ = z if ZIP5.match(z) else ''
    if not zip_ and ',' in a:
        m = ZIP_END.search(a.split(',', 1)[1])
        zip_ = m.group(1) if m else ''
    if any(parts):
        return ' '.join(p for p in parts if p), city, zip_
    pieces = [p.strip() for p in a.split(',')]
    street = pieces[0]
    if not zip_ and len(pieces) == 1:
        m = re.search(r'\bTX\s+(\d{5})(?:-?\d{4})?\s*$', street, re.I)
        if m:
            zip_ = m.group(1)
    street = TAIL.sub('', street).strip() if len(pieces) == 1 else street
    parsed = ''
    for p in pieces[1:]:
        p = TAIL.sub('', p).strip()
        if p:
            parsed = p
            break
    if not parsed:
        words = street.split()
        for n in (3, 2, 1):
            if len(words) - n >= 2 and ' '.join(words[-n:]).upper() in cities:
                parsed, street = ' '.join(words[-n:]), ' '.join(words[:-n])
                break
    if not parsed:
        words = street.split()
        for n in (3, 2, 1):
            rest = ' '.join(words[:-n])
            if len(words) - n >= 2 and ' '.join(words[-n:]).upper() in state_cities and STREET_END.search(rest):
                parsed, street = ' '.join(words[-n:]), rest
                break
    return street, city or parsed, zip_


def main(src, out):
    sc, mc = collections.defaultdict(collections.Counter), collections.defaultdict(collections.Counter)
    with open(src, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            c = row['COUNTY']
            if row['SITUS_CITY'].strip():
                sc[c][row['SITUS_CITY'].strip().upper()] += 1
            city, st = mail(row)
            if city and st == 'TX':
                mc[c][city.upper()] += 1
    cities = {c: {k for k, n in sc[c].items() if n >= 20} | {k for k, n in mc[c].items() if n >= 50}
              for c in set(sc) | set(mc)}
    total = collections.Counter()
    for d in list(sc.values()) + list(mc.values()):
        total.update(d)
    state_cities = {k for k, n in total.items() if n >= 500}
    print('pass 1 done; cities per county (median)', sorted(map(len, cities.values()))[len(cities) // 2],
          'statewide', len(state_cities), flush=True)

    stats = collections.Counter()
    with open(src, newline='', encoding='utf-8') as f, open(out, 'w', newline='', encoding='utf-8') as fo, \
            open(out + '.held.tmp', 'w', newline='', encoding='utf-8') as fh:
        r = csv.reader(f)
        head = next(r)
        ix = {k: i for i, k in enumerate(head)}
        w, wh = csv.writer(fo), csv.writer(fh)
        w.writerow(head + ['site_state', 'SITE_STREET', 'SITE_CITY', 'SITE_ZIP', 'MAIL_CITY_PARSED',
                           'MAIL_STATE_PARSED'])
        for rec in r:
            row = {k: rec[i] for k, i in ix.items()}
            street, city, zip_ = site(row, cities.get(row['COUNTY'], set()), state_cities)
            mcity, mst = mail(row)
            parts = any(row[k].strip() for k in ('SITUS_NUM', 'SITUS_STRE', 'SITUS_ST_1', 'SITUS_ST_2'))
            stats['rows'] += 1
            stats['street'] += bool(street)
            stats['street_from_SITUS_ADDR'] += bool(street) and not parts
            stats['city'] += bool(city)
            stats['city_from_SITUS_ADDR'] += bool(city) and not row['SITUS_CITY'].strip()
            stats['zip'] += bool(zip_)
            stats['zip_from_SITUS_ADDR'] += bool(zip_) and not ZIP5.match(row['SITUS_ZIP'].strip())
            stats['mail_state'] += bool(mst)
            stats['mail_state_differs_from_MAIL_STAT'] += bool(mst) and mst != row['MAIL_STAT'].strip()
            stats['mail_city_split'] += mcity != row['MAIL_CITY'].strip()
            out_rec = rec + ['TX', street, city, zip_, mcity, mst]
            if not row['PROP_ID'].strip() and not row['OWNER_NAME'].strip():
                wh.writerow(out_rec)
                stats['held_to_end'] += 1
            else:
                w.writerow(out_rec)
    with open(out + '.held.tmp', newline='', encoding='utf-8') as fh, open(out, 'a', newline='', encoding='utf-8') as fo:
        for line in fh:
            fo.write(line)
    import os
    os.remove(out + '.held.tmp')
    for k, v in stats.items():
        print(f'{k:36} {v:>12,} {v / stats["rows"]:6.1%}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
