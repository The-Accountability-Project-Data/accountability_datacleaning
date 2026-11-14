# Process Florida properties


Florida parcels are available via public FTP per county here: 

[ftp://sdrftp03.dor.state.fl.us/Tax%20Roll%20Data%20Files/2018%20Final%20NAL%20-%20SDF%20Files/](ftp://sdrftp03.dor.state.fl.us/Tax%20Roll%20Data%20Files/2018%20Final%20NAL%20-%20SDF%20Files/)

It's actually the SDF files we want. Download all of them to this directory, either by using the "download_files.py" to download and unzip them or some other means. (the download script just runs the command line commands curl and unzip on the files). 

After downloading the files, you can combine them into a single file using csvkit's csvstack:

	$ csvstack files/*.csv > fl_properties.csv
	
And then run the fix_properties.py script on the output. That script assumes the output is 'fl_propertis.csv' you'll need to update it if it is called something else. 

The script simply adds a PHY_STATE column set to Florida. This is the state that the parcel is located in, it is needed to set the site state in public accountability. 

## Note: `cleaned_fl_properties.csv` is the 2021 roll

`cleaned_fl_properties.csv` was replaced on 2022-03-17 with the 2021 Final NAL (10,542,430 rows, `ASMNT_YR` 2021, 162
columns: `EXMPT_42` added after `EXMPT_41`). The 2018 file is `csv_archive/cleaned_fl_properties.csv` (10,266,898
rows).


## Update: November 2026

New dataset "Florida Property Assessments 2026", built 2026-11-05 from the 2026 tax roll. The 2021 dataset is unchanged.

* **Source:** the Department of Revenue's Data Portal, "Tax Roll Data File directory"
  (<https://floridarevenue.com/property/Pages/DataPortal_RequestAssessmentRollGISData.aspx>), which posts only the
  current roll: `.../Tax%20Roll%20Data%20Files/NAL/2026F/<County> <CO> Final NAL 2026.zip` and, for counties without a
  final file, `.../NAL/2026P/<County> <CO> Preliminary NAL 2026.zip`. Retrieved 2026-11-05. Users guide:
  `2026_NAL_SDF_NAP_Users_Guide.pdf`.
* **Counties:** 66 of 67.
  * 63 Final NAL 2026 files.
  * DeSoto (24), Flagler (28) and Liberty (49): Preliminary NAL 2026 (July 2026); no final file was posted.
  * **Jackson (42) is not included.** The portal had no NAL file for it, only the sales file ("Jackson 42 Final SDF
    2026.zip").
  * Each county's file and rows: [`fl_properties_2026_counties.tsv`](fl_properties_2026_counties.tsv).
* **Script:** [`code/build.py`](code/build.py) (Python). It stacks the county files and adds `PHY_STATE` = "FL", as
  `fix_properties.py` does. Columns: the 2026 NAL layout in the state's order, then `PHY_STATE`. The 2026 layout is
  the 2021 one with `EXMPT_43` to `EXMPT_48` added after `EXMPT_42`. The preliminary files have no `EXMPT_47` or
  `EXMPT_48`; those are blank for their rows. Values are as published.
* **Output:** `fl_properties_2026.csv`, 11,071,703 rows, 168 columns, UTF-8, `ASMNT_YR` 2026 on every row.
* The Department of Revenue leaves out owners whose records are confidential by law. Six rows carry
  "CONFIDENTIAL" placeholders (Brevard 4, Okeechobee 1, Volusia 1).
