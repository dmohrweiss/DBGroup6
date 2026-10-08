
-- healthcare_db: schema 
--
-- Week 5 revision. Every change against the Week-3 schema is motivated
-- by the Week-3 feedback or by a mismatch found in the real-world data,
-- see docs/design_report.md and docs/week5_real_data_integration.md.
--
-- Load order:  healthcare_db_schema.sql then healthcare_db_lookup.sql
--              then healthcare_db_load_data.sql
DROP SCHEMA IF EXISTS healthcare_db;
CREATE SCHEMA healthcare_db;
USE healthcare_db;


CREATE TABLE ResidenceType (
  ResidenceTypeID INT AUTO_INCREMENT PRIMARY KEY,
  Label           VARCHAR(30)  NOT NULL UNIQUE,
  Description     VARCHAR(255) NULL
);

CREATE TABLE Gender (
  GenderID INT AUTO_INCREMENT PRIMARY KEY,
  Label    VARCHAR(10) NOT NULL UNIQUE
);

CREATE TABLE HealthLabel (
  HealthLabelID     INT AUTO_INCREMENT PRIMARY KEY,
  CategoryLabelName VARCHAR(30)  NOT NULL UNIQUE,
  Description       VARCHAR(255) NULL
);

-- BEA economic region. Its name depends only on the region
-- code, so it lives in its own table instead of on every state
CREATE TABLE BEARegion (
  BEARegionCode INT PRIMARY KEY,                 -- code published by BEA (1-8)
  RegionName    VARCHAR(30) NOT NULL UNIQUE,
  CONSTRAINT chk_bearegion_code CHECK (BEARegionCode BETWEEN 1 AND 8)
);

-- One row per US state. StateID is the official FIPS state code:
-- the natural key both real-world sources use.
CREATE TABLE Region (
  StateID       INT PRIMARY KEY,
  StateName     VARCHAR(50) NOT NULL UNIQUE,
  StateAbbrev   CHAR(2)     NOT NULL UNIQUE,
  BEARegionCode INT         NOT NULL,
  CONSTRAINT chk_region_fips CHECK (StateID BETWEEN 1 AND 78),
  CONSTRAINT fk_region_bearegion FOREIGN KEY (BEARegionCode)
    REFERENCES BEARegion(BEARegionCode) ON DELETE RESTRICT ON UPDATE CASCADE
);


-- Cost of living: BEA Regional Price Parities, one row per state per year

CREATE TABLE CostOfLiving (
  CostOfLivingID         INT AUTO_INCREMENT PRIMARY KEY,
  StateID                INT          NOT NULL,
  Year                   SMALLINT     NOT NULL,
  CostIndex              DECIMAL(7,3) NOT NULL,   -- RPP all items
  GoodsCostIndex         DECIMAL(7,3) NULL,
  HousingCostIndex       DECIMAL(7,3) NULL,
  UtilitiesCostIndex     DECIMAL(7,3) NULL,
  OtherServicesCostIndex DECIMAL(7,3) NULL,
  CONSTRAINT uq_col_state_year UNIQUE (StateID, Year),
  CONSTRAINT chk_col_year     CHECK (Year BETWEEN 2000 AND 2100),
  CONSTRAINT chk_col_index    CHECK (CostIndex > 0),
  CONSTRAINT chk_col_goods    CHECK (GoodsCostIndex > 0),
  CONSTRAINT chk_col_housing  CHECK (HousingCostIndex > 0),
  CONSTRAINT chk_col_util     CHECK (UtilitiesCostIndex > 0),
  CONSTRAINT chk_col_other    CHECK (OtherServicesCostIndex > 0),
  CONSTRAINT fk_col_region FOREIGN KEY (StateID)
    REFERENCES Region(StateID) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Household, Person, HealthMetrics
CREATE TABLE Household (
  HouseholdID           INT AUTO_INCREMENT PRIMARY KEY,
  SourceRecordKey       VARCHAR(40)   NULL UNIQUE, -- survey interview, e.g. BRFSS2023-06-2023005145
  ResidenceTypeID       INT           NULL,      -- NULL: county could not be classified
  CostOfLivingID        INT           NOT NULL,  -- state + year the household is observed in
  HouseholdIncome       DECIMAL(10,2) NULL,      -- NULL: respondent did not know / refused
  HouseholdSize         INT           NULL,
  NumEarners            INT           NULL,
  ChildrenUnderLegalAge INT           NULL,
  CONSTRAINT chk_hh_income   CHECK (HouseholdIncome >= 0),
  CONSTRAINT chk_hh_size     CHECK (HouseholdSize BETWEEN 1 AND 99),
  CONSTRAINT chk_hh_earners  CHECK (NumEarners >= 0 AND NumEarners <= HouseholdSize),
  CONSTRAINT chk_hh_children CHECK (ChildrenUnderLegalAge >= 0 AND ChildrenUnderLegalAge < HouseholdSize),
  CONSTRAINT fk_hh_residence FOREIGN KEY (ResidenceTypeID)
    REFERENCES ResidenceType(ResidenceTypeID) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_hh_col FOREIGN KEY (CostOfLivingID)
    REFERENCES CostOfLiving(CostOfLivingID) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE Person (
  PersonID         INT AUTO_INCREMENT PRIMARY KEY,
  HouseholdID      INT           NOT NULL,
  GenderID         INT           NOT NULL,
  FirstName        VARCHAR(30)   NULL,          -- survey data is de-identified
  LastName         VARCHAR(30)   NULL,
  DOB              DATE          NULL,
  AgeGroup         VARCHAR(10)   NULL,          -- used when only an age band is known
  IndividualIncome DECIMAL(10,2) NULL,
  Debt             BOOLEAN       NULL,
  CONSTRAINT chk_person_dob    CHECK (DOB >= '1900-01-01'),
  CONSTRAINT chk_person_income CHECK (IndividualIncome >= 0),
  CONSTRAINT fk_person_household FOREIGN KEY (HouseholdID)
    REFERENCES Household(HouseholdID) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_person_gender FOREIGN KEY (GenderID)
    REFERENCES Gender(GenderID) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- 1:1 with Person (weak entity): a person's health record is deleted with the person.
CREATE TABLE HealthMetrics (
  PersonID               INT          PRIMARY KEY,
  HealthLabelID          INT          NOT NULL,
  MeasurementDate        DATE         NULL,
  DistanceToCareKM       DECIMAL(6,2) NULL,
  HasInsurance           BOOLEAN      NULL,
  BMI                    DECIMAL(4,1) NULL,
  ChronicConditionsCount INT          NOT NULL DEFAULT 0,
  SelfReportedHealth     TINYINT      NULL,   -- 1 = poor ... 5 = excellent
  MentalHealthScore      TINYINT      NULL,   -- 1 = worst ... 5 = best
  SmokingStatus          BOOLEAN      NULL,   -- 1 = current smoker
  ExerciseDaysPerWeek    TINYINT      NULL,
  CONSTRAINT chk_hm_distance  CHECK (DistanceToCareKM >= 0),
  CONSTRAINT chk_hm_insurance CHECK (HasInsurance IN (0, 1)),
  CONSTRAINT chk_hm_bmi       CHECK (BMI BETWEEN 10 AND 100),
  CONSTRAINT chk_hm_chronic   CHECK (ChronicConditionsCount BETWEEN 0 AND 20),
  CONSTRAINT chk_hm_srh       CHECK (SelfReportedHealth BETWEEN 1 AND 5),
  CONSTRAINT chk_hm_mental    CHECK (MentalHealthScore BETWEEN 1 AND 5),
  CONSTRAINT chk_hm_smoking   CHECK (SmokingStatus IN (0, 1)),
  CONSTRAINT chk_hm_exercise  CHECK (ExerciseDaysPerWeek BETWEEN 0 AND 7),
  CONSTRAINT fk_hm_person FOREIGN KEY (PersonID)
    REFERENCES Person(PersonID) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_hm_label FOREIGN KEY (HealthLabelID)
    REFERENCES HealthLabel(HealthLabelID) ON DELETE RESTRICT ON UPDATE CASCADE
);
