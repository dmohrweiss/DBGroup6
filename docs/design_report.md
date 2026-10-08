# healthcare_db Design Report

**Group 6** · [Repository](https://github.com/dmohrweiss/DBGroup6)

This report summarizes the database purpose, structure, normalization, and integrity rules. See the [original Week 2 report](week2/week2_erd_normalization_report.pdf) and the [Week 5 integration report](week5_real_data_integration.md) for supporting detail.

## Purpose

The database explores how household income and regional living costs relate to health outcomes. It combines CDC BRFSS survey data with BEA state price data to support analysis of household economics, demographics, and health.

## Data model

- `Region` stores states by FIPS code. `BEARegion` stores BEA's multi-state regions.
- `CostOfLiving` stores one price record per state and year.
- `Household` stores income, size, and residence, and references the applicable state-year price record.
- `Person` stores respondent details. `HealthMetrics` stores optional one-to-one health measures.
- `ResidenceType`, `Gender`, and `HealthLabel` provide shared lookup values.
- A state can have many price records. A household belongs to one state-year and can have multiple people. A person can have at most one health record.

## ERD

The original diagram is in the [Week 2 report](week2/week2_erd_normalization_report.pdf). The current [ERD source](erd.mmd) and [diagram](erd.png) show the Week 5 structure.

![Current healthcare database ERD](erd.png)

## Normalization

The source files contain repeated year columns, combined codes, and facts about states, households, people, and health in the same records. Cleaning makes values atomic and reshapes price data into state-year records.

The final schema separates state, BEA region, price, household, person, health, and lookup facts. This removes repeating groups, partial dependencies, and transitive dependencies, bringing the tables to 3NF and BCNF under the documented keys.

The state abbreviation belongs in `Region`, not `CostOfLiving`, and the redundant `Gender.Code` was removed. `HealthLabel` remains stored because professionals may override it. Household income is an estimate based on a survey bracket.

## Integrity rules

Required identifiers and labels are not nullable; fields that survey respondents may not provide remain nullable. `CHECK` constraints bound numeric and coded values. `UNIQUE` constraints prevent duplicate states, state-year prices, lookup labels, and source records.

IDs are generated automatically. The data loader resolves references using source keys and labels. Deleting a person also deletes their health record, while referenced households, lookup values, and price records are protected from deletion. Key updates cascade to related records.

## Week 5 updates

Real data added year-specific BEA prices, FIPS-based state links, BEA regions, respondent source keys, age groups, and interview dates. The schema also added domain checks, uniqueness rules, and referential actions. Synthetic data was replaced by cleaned CDC and BEA data.

See [`healthcare_db_schema.sql`](../healthcare_db_schema.sql) for the schema and [week5_real_data_integration.md](week5_real_data_integration.md) for data cleaning, test results, and limitations.