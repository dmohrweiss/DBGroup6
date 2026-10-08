USE healthcare_db;

-- Basic DML examples on the real-world data.
-- Week-5 review of the two Week-3 UPDATE statements (run on real data, see
-- docs/query_results/week3_basicsql_on_real_data_UNCHANGED.txt):
-- UPDATE 1 set 'Critical Risk' for people with a GOOD mental health score (> 3) living close to care;
-- UPDATE 2 lowered the official BEA housing index of every state with a household earning > $10,000
-- Both are replaced below. The script runs in a transaction and ends with ROLLBACK so the

START TRANSACTION;

-- UPDATE 1.
UPDATE HealthMetrics
SET HealthLabelID = (SELECT HealthLabelID FROM HealthLabel WHERE CategoryLabelName = 'Critical Risk')
WHERE MentalHealthScore <= 2
  AND ChronicConditionsCount >= 3;

-- UPDATE 2
UPDATE Household
SET HouseholdIncome = 42500.00
WHERE SourceRecordKey = 'BRFSS2023-06-2023005145';

INSERT INTO Household (ResidenceTypeID, CostOfLivingID, HouseholdIncome, HouseholdSize, ChildrenUnderLegalAge)
VALUES ((SELECT ResidenceTypeID FROM ResidenceType WHERE Label = 'Rural'),
        (SELECT CostOfLivingID FROM CostOfLiving WHERE StateID = 54 AND Year = 2023),
        30000.00, 3, 1);
INSERT INTO Person (HouseholdID, GenderID, FirstName, LastName, DOB)
VALUES (LAST_INSERT_ID(), (SELECT GenderID FROM Gender WHERE Label = 'Female'), 'Jane', 'Example', '1980-05-01');
INSERT INTO HealthMetrics (PersonID, HealthLabelID, MeasurementDate, HasInsurance, BMI, ChronicConditionsCount)
VALUES (LAST_INSERT_ID(), (SELECT HealthLabelID FROM HealthLabel WHERE CategoryLabelName = 'Moderate Risk'),
        '2023-10-01', 0, 29.4, 1);

-- DELETE: removing the person also removes their HealthMetrics row (ON DELETE CASCADE).
DELETE FROM Person WHERE FirstName = 'Jane' AND LastName = 'Example';

ROLLBACK;
