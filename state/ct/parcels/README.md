# Connecticut Parcels

_Built 2026-11-07. The runnable script is
[`code/build.py`](code/build.py)._

Connecticut parcels come from the [Connecticut CAMA and Parcel Layer 2025][layer], published by the GIS Office of the
Office of Policy and Management. Each town sends its parcel map and its assessor's database (the CAMA report) to its
regional council of governments by May 1 each year; the state joins the two into one statewide layer. The file
`ct_parcels_2025.csv` has 1,282,833 parcels in all 169 towns, mostly from the 2025 collection. It is the first
Connecticut parcels dataset.

[layer]: https://geodata.ct.gov/datasets/ctmaps::connecticut-cama-and-parcel-layer-2025

## Source

The layer (item `45cc26320c634f64a67f1b6c6afbd9d1`, CC0, last modified Sept. 10, 2026) was downloaded 2026-11-07 from
the CT Geodata Portal as CSV and as GeoJSON in WGS 84, both the portal's export of Oct. 24, 2026, with the same
1,282,833 `OBJECTID`s. Attributes come from the CSV and parcel points from the GeoJSON.

`Collection_year` is 2025 for 1,217,852 parcels, 2024 for 57,231 (ten towns, among them Waterbury and Old Saybrook)
and blank for the 7,750 parcels of Bolton and Stafford. Rows, collection years and owner gaps by town are in
[`ct_parcels_2025_towns.tsv`](ct_parcels_2025_towns.tsv).

## Columns

The CSV's 56 columns, in its order and with its names, then:

* `site_state`: `CT`.
* `LATITUDE` and `LONGITUDE`: the centroid of each parcel polygon, computed in Connecticut State Plane (EPSG:6434) and
  converted to WGS 84, to 6 decimal places. 77 parcels have no polygon and no coordinates. The polygons are not in the file.

Values are as published in the CSV. Sale dates come in more than one format ("2/21/2024 12:00:00 AM", "1/1/2022 0:00").
Two town names have a trailing space: "Monroe " (2 parcels) and "New Hartford " (25). Twelve rows have a line break
inside a field. UTF-8.

## Owners

In towns that withheld owner names, the state wrote "Current Owner" as the owner, "Current Co-Owner" as the co-owner,
and the property address as the mailing address: 46,770 parcels in 122 towns, almost all in Middletown (15,752),
Clinton, East Hampton, Cromwell, Old Lyme, Essex and Lyme. 35,771 parcels have no owner, among them all 3,628 in
Woodbridge, which has no assessor data in the layer.
