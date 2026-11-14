"""Build "DC Property Tax 2026" from the DC Office of Tax and Revenue's Integrated Tax System Public Extract Facts.

    python build.py <Integrated_Tax_System_Public_Extract_Facts.csv> <output.csv>

Source: the DC Open Data CSV download of item 6c3a37dfce05413bb11937dd66cf89b7 ("Integrated Tax System Public Extract
Facts", https://opendata.dc.gov/datasets/integrated-tax-system-public-extract-facts), downloaded 2026-11-06. The
download is the Hub's export of July 17, 2026 (every LASTMODIFIEDDATE is 2026/07/17); the live service,
ITSPE_FACTS_05022025/FeatureServer/0, is newer; this build uses the download.
Columns: the file's 37 columns, in its order and with its names, as published; then the five columns the 2019
build (state/dc/property_taxes/fix_dc_taxes.py) added:
* site_state "DC" and site_city "Washington";
* OWNER_CITY, OWNER_STATE, OWNER_ZIP, split from OWNER_ADDRESS_CITYSTZIP. In 2019 the city and the state were
  separated by a run of spaces; now they are separated by one space. When the value ends in a two-letter state code
  and a ZIP (5 digits or ZIP+4), the last word is OWNER_ZIP, the one before it OWNER_STATE and the rest OWNER_CITY.
  Otherwise (foreign addresses, blanks) the whole value goes in OWNER_CITY and the other two are blank.
Then PROPERTY_ADDRESSCITY, PROPERTY_STATE, PROPERTY_ZIP, split from PROPERTY_ADDRESS ("555 E ST SW WASHINGTON DC
20024"): PROPERTY_STATE is "DC" for every row (every property is in DC). The source cuts PROPERTY_ADDRESS at 50
characters, so some values end in a partial ZIP ("... WASHINGTON DC 2000") or stop before the state. PROPERTY_ZIP is the
ZIP after " DC " when at least five digits of it are there (the first five when a ZIP+4 is cut short), else blank;
PROPERTY_ADDRESSCITY is the text before " DC ", or the whole value when " DC" is not in it.
Writes UTF-8 without the source's byte-order mark.
"""
import collections
import csv
import re
import sys

US = re.compile(r'^(.*\S)\s+([A-Z]{2})\s+(\d{5}(?:-\d{4})?)$')
ADDED = ['site_state', 'site_city', 'OWNER_CITY', 'OWNER_STATE', 'OWNER_ZIP',
         'PROPERTY_ADDRESSCITY', 'PROPERTY_STATE', 'PROPERTY_ZIP']
PROP = re.compile(r'^(.*\S)\s+DC(?:\s+(\d[\d-]*))?$')


def split_csz(csz):
    m = US.match(csz.strip())
    if m:
        return list(m.groups())
    return [csz.strip(), '', '']


def split_property(addr):
    addr = addr.strip()
    m = PROP.match(addr)
    if not m:
        return [addr, 'DC', '']
    zip_ = m.group(2) or ''
    if re.fullmatch(r'\d{5}(-\d{4})?', zip_):
        pass
    elif re.match(r'\d{5}', zip_):
        zip_ = zip_[:5]
    else:
        zip_ = ''
    return [m.group(1), 'DC', zip_]


def main(src, out):
    counts = collections.Counter()
    with open(src, encoding='utf-8-sig', newline='') as fh, open(out, 'w', encoding='utf-8', newline='') as oh:
        r = csv.reader(fh)
        header = next(r)
        ci = header.index('OWNER_ADDRESS_CITYSTZIP')
        pi = header.index('PROPERTY_ADDRESS')
        w = csv.writer(oh)
        w.writerow(header + ADDED)
        for rec in r:
            assert len(rec) == len(header), rec
            city_state_zip = split_csz(rec[ci])
            counts['split' if city_state_zip[1] else ('blank' if not rec[ci].strip() else 'not split')] += 1
            prop = split_property(rec[pi])
            counts['property zip' if prop[2] else 'property no zip'] += 1
            w.writerow(rec + ['DC', 'Washington'] + city_state_zip + prop)
            counts['rows'] += 1
    print(f'wrote {out}: {counts["rows"]:,} rows, {len(header) + len(ADDED)} columns; OWNER_ADDRESS_CITYSTZIP split '
          f'{counts["split"]:,}, not split {counts["not split"]:,}, blank {counts["blank"]:,}; PROPERTY_ZIP filled '
          f'{counts["property zip"]:,}, blank {counts["property no zip"]:,}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
