# New York Parcel data

Go to this [NY State GIS page](http://gis.ny.gov/gisdata/inventories/details.cfm?DSID=1300). Download the file "NYS Tax Parcel Centroid Points." This is the only file for the whole state; the parcel file is only from counties that cooperated. The metadata is also available on that page. 

The summary for this file is: "Parcel centroid data for all 62 New York State counties. Parcel centroids were generated using the NYS Office of Information Technology Services GIS Program Office's (GPO) Statewide Parcel Map program data. Attribute values were populated using Assessment Roll tabular data the GPO obtained from the NYS Department of Tax and Finances Office of Real Property Tax Services (ORPTS)."

You can download it as a geodatabase or as a shapefile. Download the file, and then export the attribute data to a .csv file using your favorite GIS editor. 

Rename the .csv file to match the script; in this example we're calling it "ny\_parcels\_2018\_raw.csv" (because the file was last updated in 2018).


Run the script 'fix\_ny\_parcels.py'. (If the name of the input file is different, you'll need to edit the script to make it match). 

	$ python fix_ny_output.py 
	Writing output to outfile ny_parcels_2018_output.csv

The raw file allows multiple owners and addresses per line, but we can only index one name per row. The script breaks lines with two owners into two individual lines. 



## Update: November 2026

New dataset "New York Parcels 2026", built 2026-11-05 from the 2025 assessment roll. The 2018 dataset is unchanged.

* **Source:** `https://gisdata.ny.gov/GISData/State/Parcels/NYS-Tax-Parcel-Centroid-Points.gdb.zip`, linked from
  <https://gis.ny.gov/parcels> (file geodatabase, Last-Modified 2026-10-16, retrieved 2026-11-05). Layer
  `NYS_Tax_Parcels_Centroid_Points` in `NYS_2025_Tax_Parcels_Centroid_Points_2605.gdb`: 5,510,061 parcels in all 62
  counties, `ROLL_YR` 2025. NYC parcels come from MapPLUTO and have no mailing address.
* **Script:** [`code/build.py`](code/build.py) (Python). As in `fix_ny_output.py`, there is one row per owner:
  `PRIMARY_OWNER` with the `MAIL_*` fields, and a second row for `ADD_OWNER` with the `ADD_MAIL_*` fields. `STATE` is
  "NY".
* **Columns:** the 40 columns of `ny_parcels_2018.csv`, in the same order, then the layer's other 27 fields: SWIS,
  PRINT_KEY, SBL, CITYTOWN_SWIS, SCHOOL_CODE, SEWER_TYPE, SEWER_DESC, WATER_SUPPLY, WATER_DESC, UTILITIES,
  UTILITIES_DESC, BLDG_STYLE, HEAT_TYPE, HEAT_TYPE_DESC, FUEL_TYPE, FUEL_TYPE_DESC, GFA, USED_AS_CODE, AG_DIST_CODE,
  AG_DIST_NAME, SWIS_SBL_ID, SWIS_PRINT_KEY_ID, SPATIAL_YR, NYS_NAME, NYS_NAME_SOURCE, DUP_GEO, ORIG_FID.
* **Data dictionary:** [`ny_parcels_dictionary.md`](ny_parcels_dictionary.md), from the state's
  [field metadata](https://gis.ny.gov/current-parcel-centroid-metadata).
* **Values** are as published: blanks for missing values, whole numbers without a decimal point, other numbers to 15
  significant digits.
* **Output:** `ny_parcels_2025.csv`, 7,158,491 rows (5,510,061 parcels, 1,648,430 second-owner rows), 67 columns,
  UTF-8.
