-- =====================================================================
-- Referential-action demo (run after the clean load). Everything is rolled back.
-- =====================================================================
USE healthcare_db;
START TRANSACTION;

-- 1. ON DELETE CASCADE: deleting a person also deletes their HealthMetrics row
SELECT COUNT(*) AS health_rows_before FROM HealthMetrics WHERE PersonID = 1;
DELETE FROM Person WHERE PersonID = 1;
SELECT COUNT(*) AS health_rows_after FROM HealthMetrics WHERE PersonID = 1;

-- 2. ON DELETE RESTRICT: a household that still has members cannot be deleted
DELETE FROM Household WHERE HouseholdID = 2;

-- 3. ON DELETE RESTRICT: a lookup value in use cannot be deleted
DELETE FROM ResidenceType WHERE Label = 'Rural';

-- 4. Foreign key: a person cannot reference a non-existent gender
INSERT INTO Person (HouseholdID, GenderID) VALUES (2, 99);

-- 5. ON UPDATE CASCADE: renumbering a lookup key propagates to the children
SELECT COUNT(*) AS rural_households_before FROM Household WHERE ResidenceTypeID = 3;
UPDATE ResidenceType SET ResidenceTypeID = 30 WHERE ResidenceTypeID = 3;
SELECT COUNT(*) AS rural_households_after FROM Household WHERE ResidenceTypeID = 30;

-- 6. UNIQUE: the same BRFSS interview cannot be loaded twice
INSERT INTO Household (CostOfLivingID, SourceRecordKey)
SELECT CostOfLivingID, SourceRecordKey FROM Household WHERE HouseholdID = 2;

-- 7. UNIQUE (StateID, Year): one price record per state per year
INSERT INTO CostOfLiving (StateID, Year, CostIndex) VALUES (6, 2023, 100);

ROLLBACK;
