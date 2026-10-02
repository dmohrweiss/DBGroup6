-- =====================================================================
-- healthcare_db: bulk-load the real-world data from the cleaned CSV files
--
-- Run AFTER healthcare_db_schema.sql and healthcare_db_lookup.sql,
-- from the repository root (the CSV paths below are relative to it):
--
--   mysql --local-infile=1 -u root -p < healthcare_db_load_data.sql
--
-- LOAD DATA LOCAL must also be allowed by the server (once, as admin):
--   SET GLOBAL local_infile = 1;
--
-- Approach (ELT with staging tables):
--   1. LOAD DATA copies each CSV file as-is into a staging table (all text).
--   2. INSERT ... SELECT moves the rows into the real tables. Foreign keys
--      are resolved by joining on natural keys (lookup labels, state + year,
--      survey record key), so no ID is ever typed in: AUTO_INCREMENT
--      generates them.
--   3. Empty CSV fields mean "missing" and become NULL via NULLIF(x, '').
-- Lookups are joined with LEFT JOIN on purpose: an unknown label then gives a
-- NULL in a NOT NULL column and the load FAILS loudly instead of silently
-- dropping the row (which an inner join would do).
-- =====================================================================
USE healthcare_db;

-- ---------------------------------------------------------------------
-- 1. Staging tables (exact copy of the CSV columns, as text)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS stg_state, stg_cost_of_living, stg_brfss;

CREATE TEMPORARY TABLE stg_state (
  StateID       VARCHAR(10),
  StateName     VARCHAR(50),
  StateAbbrev   VARCHAR(10),
  BEARegionCode VARCHAR(10),
  BEARegionName VARCHAR(30)
);

CREATE TEMPORARY TABLE stg_cost_of_living (
  StateID                VARCHAR(10),
  Year                   VARCHAR(10),
  CostIndex              VARCHAR(20),
  GoodsCostIndex         VARCHAR(20),
  HousingCostIndex       VARCHAR(20),
  UtilitiesCostIndex     VARCHAR(20),
  OtherServicesCostIndex VARCHAR(20)
);

CREATE TEMPORARY TABLE stg_brfss (
  SourceRecordKey        VARCHAR(40),
  StateID                VARCHAR(10),
  Year                   VARCHAR(10),
  ResidenceType          VARCHAR(30),
  HouseholdIncome        VARCHAR(20),
  HouseholdSize          VARCHAR(10),
  NumEarners             VARCHAR(10),
  ChildrenUnderLegalAge  VARCHAR(10),
  Gender                 VARCHAR(10),
  AgeGroup               VARCHAR(10),
  HealthLabel            VARCHAR(30),
  MeasurementDate        VARCHAR(10),
  DistanceToCareKM       VARCHAR(10),
  HasInsurance           VARCHAR(5),
  BMI                    VARCHAR(10),
  ChronicConditionsCount VARCHAR(5),
  SelfReportedHealth     VARCHAR(5),
  MentalHealthScore      VARCHAR(5),
  SmokingStatus          VARCHAR(5),
  ExerciseDaysPerWeek    VARCHAR(5)
);

LOAD DATA LOCAL INFILE 'data/processed/bea_states.csv'
INTO TABLE stg_state
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/processed/bea_cost_of_living.csv'
INTO TABLE stg_cost_of_living
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/processed/brfss_2023_clean.csv'
INTO TABLE stg_brfss
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- ---------------------------------------------------------------------
-- 2. Staging -> real tables
-- ---------------------------------------------------------------------
START TRANSACTION;

-- Region: one row per state (BEA, 50 states + DC)
INSERT INTO Region (StateID, StateName, StateAbbrev, BEARegionCode)
SELECT StateID, StateName, StateAbbrev, BEARegionCode
FROM stg_state;

-- CostOfLiving: one row per state and year (BEA Regional Price Parities)
INSERT INTO CostOfLiving (StateID, Year, CostIndex, GoodsCostIndex, HousingCostIndex,
                          UtilitiesCostIndex, OtherServicesCostIndex)
SELECT StateID, Year,
       NULLIF(CostIndex, ''), NULLIF(GoodsCostIndex, ''), NULLIF(HousingCostIndex, ''),
       NULLIF(UtilitiesCostIndex, ''), NULLIF(OtherServicesCostIndex, '')
FROM stg_cost_of_living;

-- Household: one per BRFSS interview, linked to the price level of its state in the survey year
INSERT INTO Household (SourceRecordKey, ResidenceTypeID, CostOfLivingID, HouseholdIncome,
                       HouseholdSize, NumEarners, ChildrenUnderLegalAge)
SELECT s.SourceRecordKey,
       rt.ResidenceTypeID,
       col.CostOfLivingID,
       NULLIF(s.HouseholdIncome, ''),
       NULLIF(s.HouseholdSize, ''),
       NULLIF(s.NumEarners, ''),
       NULLIF(s.ChildrenUnderLegalAge, '')
FROM stg_brfss s
LEFT JOIN ResidenceType rt ON rt.Label = s.ResidenceType
LEFT JOIN CostOfLiving col ON col.StateID = s.StateID AND col.Year = s.Year
ORDER BY s.SourceRecordKey;

-- Person: the interviewed adult of each household
INSERT INTO Person (HouseholdID, GenderID, AgeGroup)
SELECT h.HouseholdID,
       g.GenderID,
       NULLIF(s.AgeGroup, '')
FROM stg_brfss s
JOIN Household h ON h.SourceRecordKey = s.SourceRecordKey
LEFT JOIN Gender g ON g.Label = s.Gender
ORDER BY h.HouseholdID;

-- HealthMetrics: one per person (BRFSS interviews one adult per household)
INSERT INTO HealthMetrics (PersonID, HealthLabelID, MeasurementDate, DistanceToCareKM, HasInsurance,
                           BMI, ChronicConditionsCount, SelfReportedHealth, MentalHealthScore,
                           SmokingStatus, ExerciseDaysPerWeek)
SELECT p.PersonID,
       hl.HealthLabelID,
       NULLIF(s.MeasurementDate, ''),
       NULLIF(s.DistanceToCareKM, ''),
       NULLIF(s.HasInsurance, ''),
       NULLIF(s.BMI, ''),
       s.ChronicConditionsCount,
       NULLIF(s.SelfReportedHealth, ''),
       NULLIF(s.MentalHealthScore, ''),
       NULLIF(s.SmokingStatus, ''),
       NULLIF(s.ExerciseDaysPerWeek, '')
FROM stg_brfss s
JOIN Household h ON h.SourceRecordKey = s.SourceRecordKey
JOIN Person p ON p.HouseholdID = h.HouseholdID
LEFT JOIN HealthLabel hl ON hl.CategoryLabelName = s.HealthLabel
ORDER BY p.PersonID;

COMMIT;

-- ---------------------------------------------------------------------
-- 3. Check: every staged row arrived (expect 51 / 867 / 500 / 500 / 500)
--    and no residence label was left unmatched (expect 0)
-- ---------------------------------------------------------------------
SELECT 'Region' AS loaded_table, (SELECT COUNT(*) FROM stg_state) AS rows_in_csv, COUNT(*) AS rows_loaded FROM Region
UNION ALL
SELECT 'CostOfLiving', (SELECT COUNT(*) FROM stg_cost_of_living), COUNT(*) FROM CostOfLiving
UNION ALL
SELECT 'Household', (SELECT COUNT(*) FROM stg_brfss), COUNT(*) FROM Household
UNION ALL
SELECT 'Person', NULL, COUNT(*) FROM Person
UNION ALL
SELECT 'HealthMetrics', NULL, COUNT(*) FROM HealthMetrics;

SELECT COUNT(*) AS unmatched_residence_labels
FROM Household h
JOIN stg_brfss s ON s.SourceRecordKey = h.SourceRecordKey
WHERE s.ResidenceType <> '' AND h.ResidenceTypeID IS NULL;

DROP TEMPORARY TABLE stg_state, stg_cost_of_living, stg_brfss;
