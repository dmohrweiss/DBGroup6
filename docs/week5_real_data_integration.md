# Week 5: Testing the Design Against Real-World Data

**Group 6** · Repository: <https://github.com/dmohrweiss/DBGroup6> · Database: MySQL 8.4

This week we replaced our synthetic mock data with two openly licensed real-world datasets. With that data loaded we did five things:
- checked the schema and constraints for violations
- cleaned and transformed the data, documenting each step
- reran the Week-3 example queries
- re-verified 3NF
- reviewed the limitations named in our stakeholder video

Every number in this report was produced by the scripts in [`etl/`](../etl) and the SQL in this repository. The raw outputs are in [`query_results/`](query_results) and [`constraint_tests/`](constraint_tests).

---

## 1. The two datasets

| | **A. CDC Behavioral Risk Factor Surveillance System (BRFSS) 2023** | **B. BEA Regional Price Parities by State (SARPP)** |
|---|---|---|
| Publisher | U.S. Centers for Disease Control and Prevention (CDC) | U.S. Bureau of Economic Analysis (BEA) |
| What it is | Annual telephone health survey; one record per adult respondent | Price level of each state relative to the US average (= 100), overall and for goods, housing, utilities and other services |
| URL | <https://www.cdc.gov/brfss/annual_data/annual_2023.html> (file `LLCP2023ASC.zip`) | <https://apps.bea.gov/regional/zip/SARPP.zip> (file `SARPP_STATE_2008_2024.csv`) |
| Publication date | Data file 10 Sep 2024 (Last-Modified header); codebook revised 28 Feb 2025 | 19 Feb 2026 ("new statistics for 2024; revised statistics for 2008-2023") |
| License | **Public domain.** CDC: *"Most of the information on the CDC and ATSDR websites is not subject to copyright, is in the public domain, and may be freely used or reproduced without obtaining copyright permission."* Attribution to CDC is requested ([source](https://www.cdc.gov/other/agencymaterials.html)). | **Public domain.** BEA: *"Unless stated otherwise, the information posted on the BEA web site is in the public domain and may be used or reproduced without specific permission."* Citation "Source: U.S. Bureau of Economic Analysis" requested ([source](https://www.bea.gov/help/faq/145)). |
| Access | Direct download, no registration | Direct download, no registration |
| Size | 433,323 respondents × 345 variables. We use a **random sample of 500** (100 each from CA, NY, IL, WV, MS; seed 2023) | 50 states + DC + US total × 5 categories × 17 years. We use **51 (50 states + DC) × 17 years = 867 rows** |
| Tables filled | `Household`, `Person`, `HealthMetrics` (and `Region`, `Gender`, `ResidenceType` via codes) | `Region`, `BEARegion`, `CostOfLiving` |

Download dates and server timestamps of the exact files used are recorded by `etl/fetch_data.py` in `data/raw/MANIFEST.txt`.

**Why these datasets are complementary (A ⊈ B, B ⊈ A).** They overlap on only two attributes: the **state** (both use the official FIPS state code) and the **year 2023**.
- BRFSS has everything about persons, households and health, none of which is in BEA.
- BEA has price levels, which BRFSS lacks, for 45 states plus DC and 16 years that are not in our BRFSS sample.
- BRFSS also covers Guam, Puerto Rico and the US Virgin Islands (FIPS 66/72/78), which BEA does not.

Together they fill the schema: the BEA price level of the state-year a household lives in is reached through `Household.CostOfLivingID`.

**Why BRFSS 2023 and not a newer year:**
- The 2025 file excludes California and Mississippi, two of our five states.
- The 2024 file lacks the exercise-frequency question.
- 2023 includes all five states and has the urban/rural classification `_URBSTAT`.

**Rejected candidate.** The cost-of-living index we modelled in Week 3, with grocery, healthcare and transport sub-indexes, matches MERIC/C2ER's index. C2ER's data is a **paid** survey and not openly licensed. That is why our `CostOfLiving` columns changed to BEA's categories.

## 2. Integration pipeline (reproducible)

```
python etl/fetch_data.py    # download both sources + BRFSS layout and codebook (data/raw, not committed)
python etl/clean_brfss.py   # parse fixed-width file, validate, sample, clean -> data/extract, data/processed
python etl/clean_bea.py     # parse, drop aggregates/footers, unpivot years -> data/extract, data/processed
mysql -u root -p < healthcare_db_schema.sql
mysql -u root -p < healthcare_db_lookup.sql
mysql --local-infile=1 -u root -p < healthcare_db_load_data.sql   # bulk load, run from the repo root
```

**Extract and clean (Python).**
- The scripts use only the Python standard library.
- They write plain CSV files: one per target table, with an empty field meaning *missing*.
- The sample is seeded, so running them twice produces identical files.
- For each source, `data/extract/` holds the **raw, uncleaned** rows that were used, so every cleaning step can be checked against the original codes.

**Load (SQL)** — [`healthcare_db_load_data.sql`](../healthcare_db_load_data.sql), with staging tables and no row-by-row `INSERT` statements:
1. `LOAD DATA LOCAL INFILE` copies each CSV file into a **staging table** (all columns text), one statement per file.
2. One `INSERT … SELECT` per target table moves the rows into the real tables:
   - `NULLIF(column, '')` turns empty fields into `NULL`;
   - foreign keys are resolved by **joining on natural keys**: lookup labels, (state, year) and the survey record key. `AUTO_INCREMENT` generates every ID.
3. Lookups are joined with `LEFT JOIN` on purpose. An unknown label then produces `NULL` in a `NOT NULL` column and the load **fails loudly**, instead of an inner join silently dropping the row.
4. A final check compares row counts in each CSV with the rows loaded, and reports unmatched labels.

`LOAD DATA LOCAL` has to be allowed on both sides: by the client (`--local-infile=1`) and by the server (`SET GLOBAL local_infile = 1;`, once, as admin).

Loaded result: `Region` 51, `BEARegion` 8, `CostOfLiving` 867, `Household` 500, `Person` 500, `HealthMetrics` 500, with **0 errors**.

## 3. Data cleaning and transformation

### 3.1 How is missing data reported?

The two sources report missing data completely differently, and BRFSS is not even consistent between its own variables:

| Source | Convention | Example | Our handling |
|---|---|---|---|
| BRFSS | `7` / `77` / `777` = *Don't know*; `9` / `99` / `999` = *Refused*; the width depends on the field | `GENHLTH` 7, `INCOME3` 77, `EXEROFT1` 777 | → `NULL` |
| BRFSS | **`88` / `888` = "None", a valid zero and not missing** | `MENTHLTH` 88 = 0 bad days, `CHILDREN` 88 = 0 children, `PRIMINS1` 88 = no insurance | → `0` / `FALSE` |
| BRFSS | **blank** = not asked: skip pattern, a module not used by the state, or a question only for landline or only for cell-phone respondents | `EXEROFT1` blank when the person does not exercise; `NUMADULT` blank for all cell-phone interviews | → `NULL`, or a derived value (no exercise → 0 days) |
| BRFSS | Special codes inside calculated variables | `_AGEG5YR` 14 = unknown age, `_SMOKER3` 9 = unknown | → `NULL` |
| BRFSS | The same number means different things in different variables | 7 = *Don't know* in `GENHLTH`, but *$50–75k* in `INCOME3` and *age 50–54* in `_AGEG5YR` | per-variable code tables from the codebook (`SPECIAL_CODES` in `clean_brfss.py`) |
| BEA | `(NA)`, `(D)` (suppressed), `(NM)`, `(L)` markers in numeric columns | none occurred in this file | the parser treats them as missing |
| BEA | A "United States" aggregate row (`GeoFIPS 00000`) with an **empty** `Region` | | row dropped (it is not a state) |

How much is missing in the five-state population (43,012 respondents; full table in `data/processed/brfss_missing_profile.csv`):

| Variable | Don't know | Refused | Blank (not asked) | Valid "none" (88) |
|---|---|---|---|---|
| `INCOME3` (income) | 3,898 | 3,812 | 874 | — |
| `_BMI5` (BMI) | — | — | 4,269 | — |
| `PRIMINS1` (insurance) | 1,503 | 666 | — | 2,323 (*no coverage*) |
| `MENTHLTH` (poor mental-health days) | 762 | 228 | — | 24,533 (*zero days*) |
| `CHILDREN` | — | 453 | 581 | 30,598 (*no children*) |
| `EXEROFT1` (exercise frequency) | 690 | 68 | 11,215 (no exercise or no answer) | — |
| `NUMADULT` / `HHADULT` (adults) | 155 | 223 | 36,057 / 6,958 (*the other phone type*) | — |

NULLs after cleaning, in the 500-respondent sample:

| Column | NULLs |
|---|---|
| `HouseholdIncome` | 80 |
| `BMI` | 47 |
| `SmokingStatus` | 25 |
| `HasInsurance` | 18 |
| `ExerciseDaysPerWeek` | 16 |
| `HouseholdSize` | 11 |
| `ChildrenUnderLegalAge` | 11 |
| `MentalHealthScore` | 11 |
| `AgeGroup` | 5 |
| `SelfReportedHealth` | 1 |
| `DistanceToCareKM`, `NumEarners` | 500 (not collected) |

### 3.2 How are dates formatted?

| Source | Format | Transformation |
|---|---|---|
| BRFSS `IDATE` | Text `MMDDYYYY`, e.g. `07232023`. The leading zero matters: read as a number it becomes `7232023`. | Parsed with `strptime("%m%d%Y")` into ISO `2023-07-23` (`DATE`) → `HealthMetrics.MeasurementDate` |
| BRFSS survey year vs interview date | Interviews for the **2023** survey continued into **2024** (latest in our sample: 2 March 2024): 68 of our 500 interviews are dated 2024 | The survey year (2023) selects the BEA price year; the real interview date is kept in `MeasurementDate` |
| BEA | No dates; **years are column headers** (`2008` … `2024`), i.e. wide format | Unpivoted into a `Year SMALLINT` column, one row per state-year |

### 3.3 Are there duplicate records?

| Check | Result |
|---|---|
| BRFSS: key (`_STATE`, `SEQNO`) over all 433,323 records | **0 duplicates** (`clean_brfss.py` stops if any are found) |
| BEA: key (`GeoFIPS`, `LineCode`) | **0 duplicates** (`clean_bea.py` stops if any are found) |
| Loading the same survey interview twice | prevented by `UNIQUE (Household.SourceRecordKey)`, tested: `ERROR 1062 Duplicate entry 'BRFSS2023-06-2023000418'` |
| Two price rows for one state-year | prevented by `UNIQUE (StateID, Year)`, tested: `ERROR 1062 Duplicate entry '6-2023'` |
| Same state from both sources | not duplicated: both sources are joined on the FIPS code, and `Region` is loaded once, from BEA |
| BEA footer rows | 4 trailing note rows ("Note: See the included footnote file.", "Last updated: …") look like data rows. They were detected by their column count and dropped. |

### 3.4 Inconsistent naming conventions and codings

| Inconsistency | Between | Resolution |
|---|---|---|
| A "region" means a **state** in our schema, but a **multi-state area** (e.g. *Far West*) in BEA | our schema ↔ BEA | kept `Region` = state; new table `BEARegion` |
| State identified by `_STATE` = `"06"` (zero-padded text), `GeoFIPS` = `' "06000"'` (quoted, leading space, state + county), `GeoName` = `California` | BRFSS ↔ BEA | all converted to the integer FIPS code `6` = `Region.StateID`; the name comes from BEA |
| Sex coded `SEXVAR` 1 = Male, 2 = Female; our `Gender` IDs are 1 = Female, 2 = Male | BRFSS ↔ schema | mapped by **label**, never by number (see 4.2: a naive load swaps every gender) |
| General health `GENHLTH` 1 = Excellent … 5 = Poor; our `SelfReportedHealth` 5 = best | BRFSS ↔ schema | reversed: `6 − GENHLTH` |
| Mental health: BRFSS counts *bad days in the last 30*; our score is 1–5 with 5 = best | BRFSS ↔ schema | banded: 0 days → 5, 1–5 → 4, 6–13 → 3, 14–20 → 2, 21–30 → 1 (14+ days is CDC's "frequent mental distress") |
| Number of adults is **two variables**: `NUMADULT` (landline interviews) and `HHADULT` (cell-phone interviews) | within BRFSS | whichever is filled + `CHILDREN` = `HouseholdSize` |
| Residence: BRFSS has only *Urban / Rural* counties (`_URBSTAT`); we model *Urban / Suburban / Rural* | BRFSS ↔ schema | Urban → Urban, Rural → Rural; *Suburban* stays unused (the suburban code `MSCODE` exists for landline respondents only, 16% of cases) |
| Insurance: BRFSS asks for the **type** of plan (10 types) | BRFSS ↔ schema (`BOOLEAN`) | any type → 1, `88` → 0 |
| Exercise: BRFSS asks **times per week** (`1xx`) **or per month** (`2xx`) for the main activity | BRFSS ↔ schema (days/week) | per month ÷ 4.33; capped at 7 because "times" can exceed days |
| BEA category names with extra spaces (`" RPPs: Goods "`) | within BEA | trimmed; mapped by `LineCode` |

### 3.5 Other transformations

- **Fixed-width parsing.** BRFSS has no header row. Column positions were parsed from CDC's official layout page instead of being typed in by hand. We checked that every record is exactly 2,111 characters long. Frequencies were compared with the codebook, e.g. `GENHLTH` = 1 occurs 63,410 times in both.
  - A tool-generated summary of the layout had `IYEAR` at the wrong position and claimed `_LLCPWT` was missing. Parsing the official file avoided both errors.
- **Implied decimals.** `_BMI5` = `4069` means 40.69, rounded to `40.7`.
- **Income brackets.** `INCOME3` gives brackets, not amounts. We store the bracket midpoint, e.g. $100,000–$150,000 → $125,000. The open top bracket "$200,000 or more" → $200,000.
- **Chronic conditions.** The count of 10 yes/no diagnoses, covering heart attack, coronary heart disease, stroke, asthma, COPD, depression, kidney disease, arthritis, cancer and diabetes. For diabetes only code 1 counts: code 2 = pregnancy only, code 4 = pre-diabetes.
- **Health label.** Assigned by a documented rule (`derive_health_label`), discussed in the design report §4.6:
  - **Critical:** ≥ 4 conditions, or ≥ 3 conditions with fair or poor health.
  - **High Burden:** ≥ 3 conditions, or ≥ 2 conditions with poor physical or mental health.
  - **Moderate:** any condition, poor health, smoking or BMI ≥ 30.
  - **Optimal:** otherwise.
- **Character encoding.** The BEA CSV is Latin-1, not UTF-8.
- **Precision.** BEA publishes 3 decimals. Our Week-3 type `DECIMAL(6,2)` would have rounded them, so it was widened to `DECIMAL(7,3)`.

## 4. Schema and constraint check

### 4.1 What did not fit the Week-3 schema

| Finding in the real data | Schema update |
|---|---|
| Price indexes exist per **year** (17 years) | `CostOfLiving.Year` + `UNIQUE (StateID, Year)` |
| Open data has *goods / housing / utilities / other services*, not grocery / healthcare / transport | `CostOfLiving` columns replaced |
| Both sources identify states by FIPS code | `Region.StateID` = FIPS code; `StateAbbrev` moved here from `CostOfLiving.RegionCode` (3NF fix) |
| BEA groups states into regions | new table `BEARegion` |
| Survey data is de-identified: no names, no date of birth, only an age band | names/`DOB` nullable; new `Person.AgeGroup` |
| Need to trace a row back to its source, prevent double loads, and link the bulk-loaded rows | new `Household.SourceRecordKey` (`UNIQUE`): BRFSS samples a household and interviews one adult in it |
| Interview date available | new `HealthMetrics.MeasurementDate` |
| Week-3 schema had no `NOT NULL`, `CHECK`, `UNIQUE`, referential actions or `AUTO_INCREMENT` (also the Week-3 feedback) | all added, see [design report §5](design_report.md#5-constraints) |

### 4.2 Test: what if we had loaded the raw codes without cleaning?

To show what the constraints actually protect against, [`constraint_tests/uncleaned_load_test.sql`](constraint_tests/uncleaned_load_test.sql) puts every raw BRFSS code into its target column with a naive 1:1 mapping:
- **Raw extract staged.** The raw extract is bulk-loaded into a staging table with `LOAD DATA`.
- **One value at a time.** A **stored procedure** loops over the raw values with a cursor and writes each one into its column through a prepared `UPDATE`. A `CONTINUE HANDLER` logs every error and moves on. This is needed because MySQL reports only the first violation of a statement.
- **Rolled back.** Everything runs inside a transaction that is rolled back, so the database is unchanged afterwards.

**Rejected by the database (2,887 errors**, [`uncleaned_load_output.txt`](constraint_tests/uncleaned_load_output.txt)):

| Raw variable → column | Rejected | Caught by |
|---|---|---|
| `IDATE` `'07232023'` → `MeasurementDate` | 500 | data type `DATE` (`ERROR 1292 Incorrect date value`) |
| `_BMI5` `4069` → `BMI` | 453 | data type `DECIMAL(4,1)` (`ERROR 1264 Out of range`) |
| `_SMOKER3` 2/3/4/9 → `SmokingStatus` | 450 | `CHECK chk_hm_smoking` |
| `CHILDREN` `88` → `ChildrenUnderLegalAge` | 340 | `CHECK chk_hh_children` (children < household size) |
| `NUMADULT`/`HHADULT` (adults only) → `HouseholdSize` | 78 | `CHECK chk_hh_children`: without the children, the size is no longer larger than the number of children |
| `MENTHLTH` 6–30 / 77 / 88 / 99 → `MentalHealthScore` | 399 | `CHECK chk_hm_mental` |
| `PRIMINS1` 2–10 / 77 / 88 / 99 → `HasInsurance` | 310 | `CHECK chk_hm_insurance` |
| `EXEROFT1` 101–127 / 201–299 → `ExerciseDaysPerWeek` | 215 + 141 | `CHECK chk_hm_exercise` + data type `TINYINT` |
| `GENHLTH` 7/9 → `SelfReportedHealth` | 1 | `CHECK chk_hm_srh` |

**Accepted although wrong.** These raw codes passed every constraint but are semantically incorrect:

| Raw variable → column | Wrong values accepted | Why the constraint cannot see it |
|---|---|---|
| `SEXVAR` → `GenderID` | **500 (every row)** | 1 and 2 are both valid IDs, but they mean the opposite gender |
| `_AGEG5YR` → `AgeGroup` | 500 | code `11` stored instead of `70-74` |
| `INCOME3` → `HouseholdIncome` | 488 | bracket code `9` stored as **$9** instead of ~$125,000 |
| `GENHLTH` → `SelfReportedHealth` | 335 | 1–5 is in range, but the scale is reversed |
| `EXEROFT1` → `ExerciseDaysPerWeek` | 138 | blank (no exercise) becomes `NULL` instead of 0 |
| `MENTHLTH` → `MentalHealthScore` | 88 | 1–5 *bad days* fits the 1–5 *score* range |
| `NUMADULT`/`HHADULT` → `HouseholdSize` | 84 | adults only, children missing |
| `_URBSTAT` → `ResidenceTypeID` | 76 | Rural (2) becomes **Suburban** (ID 2) |

**Conclusion.** The constraints catch about half of the problems, mainly values outside the domain. They cannot catch values that are valid but mean something else: a swapped code, a reversed scale or the wrong unit. Those can only be prevented by explicit, documented cleaning (`clean_brfss.py`) and by **looking up IDs by label** instead of copying source codes. After cleaning, the load produces **0 errors**.

### 4.3 Referential actions on real data

[`constraint_tests/referential_actions_output.txt`](constraint_tests/referential_actions_output.txt), all rolled back:
- Deleting a person removes their health record (`CASCADE`: 1 → 0 rows).
- Deleting a household with members, or a residence type in use, fails (`RESTRICT`, `ERROR 1451`).
- A non-existent gender is refused (`ERROR 1452`).
- Renumbering a residence type updates all 76 rural households (`ON UPDATE CASCADE`).
- Duplicate respondents and state-years are refused (`ERROR 1062`).

## 5. Is the database still in 3NF?

**Yes, after the changes above.** The full step-by-step derivation, from the raw source records via functional dependencies to 1NF, 2NF and 3NF/BCNF, is in the [design report §4](design_report.md#4-normalization-from-the-raw-data-to-3nfbcnf). Violations found while integrating the real data:

| Violation | Normal form | Where | Fix |
|---|---|---|---|
| Years as repeating columns (`2008` … `2024`) | 1NF | BEA source file | unpivoted to one row per state-year |
| Composite values: `' "06000"'`, `'07232023'`, `4069` | 1NF (atomicity) | both sources | parsed into integer, `DATE`, `DECIMAL` |
| One flat record per respondent with person, household, state and health facts | 2NF/3NF | BRFSS source file | decomposed into `Household`, `Person`, `HealthMetrics` + lookups |
| `CostOfLiving.RegionCode` depends on the state, not on the record | 3NF (2NF once `Year` is part of the key) | **our Week-3 schema** | moved to `Region.StateAbbrev` |
| `StateID → BEARegionCode → RegionName` | 3NF | would arise from BEA's `Region` column | `BEARegion` table |
| `Gender.Code` duplicates `GenderID` | redundancy | our Week-3 schema | removed |
| `HealthLabelID` derived from metrics by rule | potential 3NF | survey data | kept on purpose; the label can be overridden by a professional (design report §4.6) |

The real data is inserted in normalized form:
- Each state appears once, in `Region`, and each state-year once, in `CostOfLiving`.
- Each respondent becomes one `Household`, one `Person` and one `HealthMetrics` row.
- Lookup values are stored only once.

## 6. Example queries rerun on real data

Original Week-3 queries, unchanged, on real data: [`week3_queries_on_real_data_UNCHANGED.txt`](query_results/week3_queries_on_real_data_UNCHANGED.txt). Adapted queries: [`advanced_queries.sql`](../advanced_queries.sql) → [`advanced_queries_week5.txt`](query_results/advanced_queries_week5.txt).

| Query | What happened with the unchanged query | Adaptation |
|---|---|---|
| **Q1** profile by state × residence type | Ran, but: `AvgDistanceToCareKM` = NULL everywhere; no *Suburban* rows; groups of **2–3 people** (e.g. "California Rural": 2 respondents, avg income $125,000) passed `HAVING COUNT >= 1`; uninsured *counts* not comparable between groups of 2 and 98 | `HAVING >= 10` (10 → 7 groups); distance replaced by the BEA housing index; **price-adjusted income** (income ÷ RPP × 100); uninsured as % of those who answered |
| **Q2** deprived high-risk individuals | 80 rows, but `FullName` = NULL in every row (anonymous survey) and distance NULL | name falls back to `SourceRecordKey`; deprivation judged on **price-adjusted** income (81 rows); shows state and insurance |
| **Q3** ranking within state | 500 unreadable rows; names and distance NULL; and a hidden bug: MySQL sorts `NULL` **first** in `ASC`, so respondents who did not answer the mental-health question would be ranked as the *most* deprived | CTE + top 5 ranks per state (28 rows); ranks on chronic conditions, self-rated health and mental health, with `IS NULL` sorted last |
| **Q4** *(new)* | — | joins **both** sources per state: price level, housing index, price-adjusted income, chronic conditions, % fair or poor health, % uninsured, % smokers, `RANK()` |
| **Q5** *(new)* | — | housing price index 2008–2024 with `LAG()` / `FIRST_VALUE()`. First draft bug: filtering years in the same `SELECT` made `LAG()` compare with the previous *shown* year; fixed by computing the window in a CTE first |

`BasicSQL.sql` ([before](query_results/week3_basicsql_on_real_data_UNCHANGED.txt) / [after](query_results/basicsql_week5.txt)):
- **UPDATE 1** labelled people with *good* mental health as *Critical Risk* (inverted condition), and on real data changed **0 rows**, because `NULL < 50` is never true.
- **UPDATE 2** changed the official BEA housing index of all 5 states.
- Both were replaced: a correctly-oriented escalation (3 rows), an income correction, and INSERT/DELETE examples using `AUTO_INCREMENT` / `LAST_INSERT_ID()` / `CASCADE`.

## 7. Are the results meaningful?

**Yes, and they agree with known public-health patterns.** From Q4 and the summary statistics (500 respondents, unweighted):

| | < $35k | $35–75k | ≥ $75k |
|---|---|---|---|
| Respondents | 127 | 116 | 177 |
| Avg. chronic conditions | **1.57** | 1.04 | **0.93** |
| Avg. self-rated health (1–5) | **2.84** | 3.27 | **3.64** |
| % uninsured | **13.8%** | 4.5% | **2.8%** |

- **Income gradient.** Lower-income respondents have more chronic disease, worse self-rated health and are about 5× as often uninsured.
- **Rural vs urban.** Rural respondents average 1.45 chronic conditions; urban respondents average 1.12.
- **Cost of living changes the picture.**
  - Nominal income: CA $95,888 vs MS $70,945, a gap of $24,943.
  - After price adjustment: CA $85,466 vs MS $81,742, a gap of only **$3,724**.
  - Housing in CA costs 158% of the US average; in MS, 55%.
  - In Q2, judging deprivation on price-adjusted instead of nominal income adds 5 Californian households to the deprived group (36 → 41). The other states do not change, because the coarse income brackets fall on the same side of the average either way.
- **West Virginia** has the highest health burden (1.63 chronic conditions on average, rank 1), despite low living costs.
- **Q5** shows that, *relative to the US average*, housing price levels in CA (−7.0) and NY (−8.7) have moved towards the average since 2008.

**What still limits meaning, and the updates required:**
- **No distance-to-care data.** The access-to-care dimension of the project cannot be analysed yet; it needs an extra dataset (see §8).
- **Unweighted sample.** BRFSS provides survey weights (`_LLCPWT`). Without them our percentages describe the *sample*, not the state population. Use weights for real estimates.
- **Small groups.** With 100 respondents per state, the 2–3 respondent "Rural" groups in CA, NY and IL are filtered out. A larger sample would be needed for rural analysis there.
- **Income** is a bracket midpoint, so averages are approximate.

## 8. Limitations and future work from the stakeholder video (Week 4), revisited

The [Week-4 video](week4/week4_stakeholder_video.mp4) named four limitations and assumptions, and a plan for future work. The real data affects each of them:

| From the Week-4 video | Status after Week 5 |
|---|---|
| **Missing data: geographic granularity.** *"Our geographic data is currently limited to the state level and broad region codes, which misses critical, localized insights (averages)."* | **Partly addressed.** The open BRFSS file only identifies the state, because counties are suppressed for privacy, and BEA publishes state RPPs. So the analysis stays at state level. New: every respondent now has the urban/rural classification of their county (`_URBSTAT`), and `BEARegion` adds a level above states. Next step: BEA also publishes price levels for several hundred metropolitan areas (`MARPP.zip`, same license). |
| **Missing data: longitudinal snapshot.** *"We currently lack historical tracking; the health and economic metrics represent a single snapshot in time."* | **Partly addressed.** `CostOfLiving` now holds **17 years** (2008–2024) per state; Q5 uses this to show the trend. `HealthMetrics.MeasurementDate` records when each measurement was taken. Individuals still cannot be followed over time: BRFSS interviews different people every year. Loading more BRFSS years would allow trend analysis per state, not per person. |
| **Assumption: household strain distribution.** *"We assumed that economic strain is shared equally among all members of a household."* | **Still an assumption.** BRFSS interviews only one adult per household, so we cannot see how strain is divided. Income stays a household attribute. Price-adjusted income (Q1, Q2, Q4) now at least accounts for where the household lives. |
| **Assumption: general measurements.** *"The use of measurements that may generalize someone's health based on little information (BMI)."* | **Improved.** Real health data adds a count of 10 diagnosed chronic conditions, self-rated health, poor mental-health days, smoking, exercise frequency and insurance status. The risk label is now based on several of these (rule documented in §3.5), not on BMI alone. BMI itself is calculated from *self-reported* height and weight. |
| **Short-term: dataset expansion.** *"Expand our mock dataset to include more diverse edge cases and larger sample sizes."* | **Done differently.** Instead of more mock data: 500 real respondents sampled from 433,323, with real edge cases (missing answers, BMI 14.6–61.7, households of up to 10 people). The sample size can be raised in one line (`SAMPLE_PER_STATE`). |
| **Short-term: algorithm improvement.** *"Refine our health risk categories and improve the scoring algorithms used to rank vulnerable populations."* | **Done.** The labelling rule is now explicit and documented. Ranking (Q3) uses chronic conditions, self-rated health and mental health, with unknown values sorted last. Deprivation (Q2) uses price-adjusted income. |
| **Short-term: expand the health indexes, which are very broad and outdated.** | **Done.** Health data from 2023 (BRFSS) and price levels up to 2024 (BEA, released Feb 2026), replacing the illustrative mock values. |
| **Long-term: cross-government integration.** *"Integrate real-time data on housing and energy security."* | **First step taken.** Two federal agencies (CDC, BEA) are integrated through the shared FIPS state code. BEA's housing and utilities price indexes are a first proxy for housing and energy costs. |
| **Long-term: longitudinal tracking.** | See *longitudinal snapshot* above. |

Limitations and future work identified in Week 5:

| Item | Status / proposal |
|---|---|
| Mock data did not reflect reality | **Resolved:** replaced by CDC BRFSS + BEA real data |
| Distance to care unknown | Open. Candidate open source: HRSA Health Professional Shortage Areas or County Health Rankings, at county level. That would require adding a `County` entity. |
| `Suburban` residence type never filled | Open. BRFSS only distinguishes urban/rural counties. Options: drop the type, or use the NCHS 6-level urban-rural code. |
| One respondent per household | Inherent to BRFSS. Multi-person households would need e.g. Census ACS PUMS (also public domain), but those people cannot be linked to BRFSS health data. |
| Individual chronic conditions only stored as a count | Future: `Condition` + `PersonCondition` (many-to-many) tables |
| Survey weights not used | Future: add `Person.SurveyWeight` and use weighted averages |
| `NumEarners`, `IndividualIncome`, `Debt` not in any open per-person source | Kept nullable; candidates for removal if no source is found |
