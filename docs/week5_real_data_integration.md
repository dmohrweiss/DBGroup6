# Week 5: Testing the Design Against Real-World Data

**Group 6** · Repository: <https://github.com/dmohrweiss/DBGroup6> · Database: MySQL 8.4

This report integrates two public-domain datasets, tests the updated schema, reruns example queries, checks normalization, and reviews project limitations. Results are recorded in the ETL scripts, query outputs, and constraint tests.

## 1. Datasets

- CDC BRFSS 2023 provides survey, household, and health data. The project uses a reproducible sample of 500 respondents from five states.
- BEA SARPP provides state cost-of-living indices from 2008 through 2024.
- Both sources use state identifiers that can be matched through FIPS codes. This links each respondent to the relevant state price data.
- BRFSS 2023 was chosen because it includes all sampled states and the exercise and urban-rural fields needed for the project. The BEA data is openly licensed, unlike the paid cost-of-living source considered earlier.

## 2. Integration pipeline

Python scripts download and clean the source files, then produce CSVs for loading. The fixed sample makes the process reproducible, and extracted source rows are retained for comparison.

The database is created by running the schema and lookup scripts before the bulk-load script. The loader stages CSV data, maps source values to database records, and checks the loaded counts. `LOAD DATA LOCAL` must be enabled for both MySQL client and server.

The completed load contains 51 states, 8 BEA regions, 867 state-year price records, and 500 respondent records in each health-related table, with no loading errors.

## 3. Data cleaning and transformation
### 3.1 Missing data

BRFSS uses variable-specific codes for unknown or refused answers, while blank values can indicate questions that were not asked. Cleaning converts missing responses to `NULL` and preserves valid zero values. BEA markers for unavailable or suppressed values are treated as missing.

### 3.2 Dates

BRFSS interview dates are converted from text to standard date values. The survey year is kept separate from the interview date because some interviews occurred in the following calendar year. BEA years are reshaped from column headings into state-year records.

### 3.3 Duplicate records

Checks found no duplicate source records. Unique constraints prevent duplicate survey respondents and duplicate state-year price records during loading. Aggregate and footer rows are excluded from the BEA data.

### 3.4 Naming and coding differences

State identifiers from both sources are standardized to FIPS codes. Source labels and codes are mapped to the database conventions for gender, health, residence, insurance, and exercise. BEA region names and price categories are standardized separately from state names.

### 3.5 Other transformations

BRFSS fixed-width records are parsed using the official CDC layout. BMI values and income brackets are converted to usable numeric values, exercise frequency is standardized, and health labels are assigned using documented rules. BEA data is reshaped into one record per state and year, with its published numeric precision retained.

## 4. Schema and constraint check
Real data required year-specific price records, a separate BEA region lookup, source identifiers, interview dates, and nullable fields for unavailable survey data. The schema was updated with keys, checks, uniqueness rules, and referential actions.

Constraint tests showed that invalid values are rejected, but valid codes with the wrong meaning can pass. Source-specific cleaning and label-based lookups are therefore essential. Referential tests confirmed that health records cascade when a person is deleted, while in-use parent records are protected.

## 5. Is the database still in 3NF?

**Yes.** State, BEA region, state-year prices, household, person, health, and lookup facts are stored separately. This avoids repeating attributes and keeps each fact with its appropriate key. See the [design report](design_report.md#4-normalization-from-the-raw-data-to-3nfbcnf) for the full derivation.

## 6. Example queries rerun on real data

The original queries were adapted for anonymous respondents, missing values, and price-adjusted income. New examples compare state-level health outcomes and cost-of-living trends. DML examples were also corrected and tested against the real data. Results are available in [`advanced_queries_week5.txt`](query_results/advanced_queries_week5.txt).

## 7. Findings and limitations

The sample shows an income gradient: lower-income respondents tend to report more chronic conditions, poorer health, and less insurance. Adjusting income for local prices narrows differences between states. West Virginia has the highest average health burden in this sample.

These results are descriptive, not population estimates, because the sample is unweighted. Small rural groups and bracket-based income limit comparisons. The dataset also lacks distance-to-care measures.

## 8. Limitations and future work from the stakeholder video (Week 4), revisited

State-level data and the urban-rural label provide some geographic context, but county-level health and price data would support more local analysis. Historical price data supports state trends, although BRFSS does not track the same people over time.

Future improvements include using survey weights, adding more detailed condition data, and finding compatible sources for care access and household measures. BRFSS interviews one adult per household, so other household members cannot be linked to their health outcomes.
