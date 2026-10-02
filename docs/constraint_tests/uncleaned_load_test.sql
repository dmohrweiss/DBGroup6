-- =====================================================================
-- Constraint test: what if the BRFSS codes were loaded WITHOUT cleaning?
--
-- Run after the normal load, from the repository root:
--   mysql --local-infile=1 -u root -p -t < docs/constraint_tests/uncleaned_load_test.sql
--
-- 1. The raw extract (original BRFSS codes) is bulk-loaded into a staging table.
-- 2. For 13 columns, every cleaned value in the database is replaced by the raw
--    code with a naive 1:1 mapping (e.g. GENHLTH -> SelfReportedHealth).
--    A stored procedure does this one value at a time and catches each error,
--    because MySQL reports only the first violation of a multi-row statement.
-- 3. Report: which raw codes the constraints REJECTED, and which ones were
--    ACCEPTED although they differ from the correctly cleaned value.
-- Everything happens inside a transaction that is rolled back.
-- =====================================================================
USE healthcare_db;

-- ---------------------------------------------------------------------
-- 1. Raw extract -> staging
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS stg_raw, raw_test, raw_test_errors, accepted_but_wrong,
                               clean_household, clean_person, clean_healthmetrics;

CREATE TEMPORARY TABLE stg_raw (
  `_STATE` VARCHAR(2), SEQNO VARCHAR(10), IDATE VARCHAR(8), SEXVAR VARCHAR(1),
  `_AGEG5YR` VARCHAR(2), `_URBSTAT` VARCHAR(1), MSCODE VARCHAR(1), NUMADULT VARCHAR(2),
  HHADULT VARCHAR(2), CHILDREN VARCHAR(2), INCOME3 VARCHAR(2), GENHLTH VARCHAR(1),
  MENTHLTH VARCHAR(2), PRIMINS1 VARCHAR(2), `_BMI5` VARCHAR(4), `_SMOKER3` VARCHAR(1),
  EXERANY2 VARCHAR(1), EXEROFT1 VARCHAR(3),
  CVDINFR4 VARCHAR(1), CVDCRHD4 VARCHAR(1), CVDSTRK3 VARCHAR(1), ASTHMA3 VARCHAR(1),
  CHCCOPD3 VARCHAR(1), ADDEPEV3 VARCHAR(1), CHCKDNY2 VARCHAR(1), HAVARTH4 VARCHAR(1),
  CHCOCNC1 VARCHAR(1), DIABETE4 VARCHAR(1)
);

LOAD DATA LOCAL INFILE 'data/extract/brfss_2023_sample_raw.csv'
INTO TABLE stg_raw
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- One row per (respondent, tested column): the naive "no cleaning" mapping
CREATE TEMPORARY TABLE raw_test (
  SourceRecordKey VARCHAR(40),
  TargetTable     VARCHAR(20),
  TargetColumn    VARCHAR(30),
  RawVariable     VARCHAR(20),
  RawValue        VARCHAR(10)
);

INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'Household', 'ResidenceTypeID', '_URBSTAT', NULLIF(`_URBSTAT`, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'Household', 'HouseholdIncome', 'INCOME3', NULLIF(INCOME3, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'Household', 'HouseholdSize', 'NUMADULT/HHADULT', COALESCE(NULLIF(NUMADULT, ''), NULLIF(HHADULT, '')) FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'Household', 'ChildrenUnderLegalAge', 'CHILDREN', NULLIF(CHILDREN, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'Person', 'GenderID', 'SEXVAR', NULLIF(SEXVAR, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'Person', 'AgeGroup', '_AGEG5YR', NULLIF(`_AGEG5YR`, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'HealthMetrics', 'MeasurementDate', 'IDATE', NULLIF(IDATE, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'HealthMetrics', 'HasInsurance', 'PRIMINS1', NULLIF(PRIMINS1, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'HealthMetrics', 'BMI', '_BMI5', NULLIF(`_BMI5`, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'HealthMetrics', 'SelfReportedHealth', 'GENHLTH', NULLIF(GENHLTH, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'HealthMetrics', 'MentalHealthScore', 'MENTHLTH', NULLIF(MENTHLTH, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'HealthMetrics', 'SmokingStatus', '_SMOKER3', NULLIF(`_SMOKER3`, '') FROM stg_raw;
INSERT INTO raw_test SELECT CONCAT('BRFSS2023-', `_STATE`, '-', SEQNO), 'HealthMetrics', 'ExerciseDaysPerWeek', 'EXEROFT1', NULLIF(EXEROFT1, '') FROM stg_raw;

CREATE TEMPORARY TABLE raw_test_errors (
  TargetColumn VARCHAR(30),
  RawVariable  VARCHAR(20),
  RawValue     VARCHAR(10),
  Message      VARCHAR(512)
);

CREATE TEMPORARY TABLE accepted_but_wrong (
  TargetColumn VARCHAR(30),
  RawVariable  VARCHAR(20),
  WrongValues  INT
);

-- Copies of the correctly cleaned data, to compare against afterwards
CREATE TEMPORARY TABLE clean_household     AS SELECT * FROM Household;
CREATE TEMPORARY TABLE clean_person        AS SELECT * FROM Person;
CREATE TEMPORARY TABLE clean_healthmetrics AS SELECT * FROM HealthMetrics;

-- ---------------------------------------------------------------------
-- 2. Procedure: write every raw value into its target column, log errors
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS try_raw_values;
DELIMITER //
CREATE PROCEDURE try_raw_values()
BEGIN
  DECLARE done BOOLEAN DEFAULT FALSE;
  DECLARE v_key, v_table, v_column, v_variable VARCHAR(40);
  DECLARE v_raw VARCHAR(10);
  DECLARE cur CURSOR FOR
    SELECT SourceRecordKey, TargetTable, TargetColumn, RawVariable, RawValue FROM raw_test;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  OPEN cur;
  next_value: LOOP
    FETCH cur INTO v_key, v_table, v_column, v_variable, v_raw;
    IF done THEN
      LEAVE next_value;
    END IF;

    BEGIN
      -- A rejected value: remember the error message and continue with the next value
      DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
      BEGIN
        GET DIAGNOSTICS CONDITION 1 @error_message = MESSAGE_TEXT;
        INSERT INTO raw_test_errors VALUES (v_column, v_variable, v_raw, @error_message);
      END;

      SET @raw_value = v_raw, @record_key = v_key;
      SET @update_sql = CASE v_table
        WHEN 'Household' THEN
          CONCAT('UPDATE Household SET ', v_column, ' = ? WHERE SourceRecordKey = ?')
        WHEN 'Person' THEN
          CONCAT('UPDATE Person p JOIN Household h ON h.HouseholdID = p.HouseholdID ',
                 'SET p.', v_column, ' = ? WHERE h.SourceRecordKey = ?')
        ELSE
          CONCAT('UPDATE HealthMetrics m JOIN Person p ON p.PersonID = m.PersonID ',
                 'JOIN Household h ON h.HouseholdID = p.HouseholdID ',
                 'SET m.', v_column, ' = ? WHERE h.SourceRecordKey = ?')
      END;
      PREPARE update_stmt FROM @update_sql;
      EXECUTE update_stmt USING @raw_value, @record_key;
      DEALLOCATE PREPARE update_stmt;
    END;
  END LOOP;
  CLOSE cur;
END //
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3. Run the test inside a transaction, report, roll back
-- ---------------------------------------------------------------------
START TRANSACTION;

CALL try_raw_values();

-- Rejected by the database (values in the message are masked so equal errors group together)
SELECT TargetColumn,
       RawVariable,
       REGEXP_REPLACE(REPLACE(Message, ' at row 1', ''), 'value: \'[^\']*\'', 'value: <raw>') AS error_message,
       COUNT(*) AS rejected_values
FROM raw_test_errors
GROUP BY TargetColumn, RawVariable, error_message
ORDER BY rejected_values DESC;

SELECT COUNT(*) AS total_rejected_values FROM raw_test_errors;

-- Accepted by the database although different from the correctly cleaned value
INSERT INTO accepted_but_wrong SELECT 'ResidenceTypeID', '_URBSTAT', SUM(NOT (n.ResidenceTypeID <=> o.ResidenceTypeID)) FROM Household n JOIN clean_household o USING (HouseholdID);
INSERT INTO accepted_but_wrong SELECT 'HouseholdIncome', 'INCOME3', SUM(NOT (n.HouseholdIncome <=> o.HouseholdIncome)) FROM Household n JOIN clean_household o USING (HouseholdID);
INSERT INTO accepted_but_wrong SELECT 'HouseholdSize', 'NUMADULT/HHADULT', SUM(NOT (n.HouseholdSize <=> o.HouseholdSize)) FROM Household n JOIN clean_household o USING (HouseholdID);
INSERT INTO accepted_but_wrong SELECT 'ChildrenUnderLegalAge', 'CHILDREN', SUM(NOT (n.ChildrenUnderLegalAge <=> o.ChildrenUnderLegalAge)) FROM Household n JOIN clean_household o USING (HouseholdID);
INSERT INTO accepted_but_wrong SELECT 'GenderID', 'SEXVAR', SUM(NOT (n.GenderID <=> o.GenderID)) FROM Person n JOIN clean_person o USING (PersonID);
INSERT INTO accepted_but_wrong SELECT 'AgeGroup', '_AGEG5YR', SUM(NOT (n.AgeGroup <=> o.AgeGroup)) FROM Person n JOIN clean_person o USING (PersonID);
INSERT INTO accepted_but_wrong SELECT 'MeasurementDate', 'IDATE', SUM(NOT (n.MeasurementDate <=> o.MeasurementDate)) FROM HealthMetrics n JOIN clean_healthmetrics o USING (PersonID);
INSERT INTO accepted_but_wrong SELECT 'HasInsurance', 'PRIMINS1', SUM(NOT (n.HasInsurance <=> o.HasInsurance)) FROM HealthMetrics n JOIN clean_healthmetrics o USING (PersonID);
INSERT INTO accepted_but_wrong SELECT 'BMI', '_BMI5', SUM(NOT (n.BMI <=> o.BMI)) FROM HealthMetrics n JOIN clean_healthmetrics o USING (PersonID);
INSERT INTO accepted_but_wrong SELECT 'SelfReportedHealth', 'GENHLTH', SUM(NOT (n.SelfReportedHealth <=> o.SelfReportedHealth)) FROM HealthMetrics n JOIN clean_healthmetrics o USING (PersonID);
INSERT INTO accepted_but_wrong SELECT 'MentalHealthScore', 'MENTHLTH', SUM(NOT (n.MentalHealthScore <=> o.MentalHealthScore)) FROM HealthMetrics n JOIN clean_healthmetrics o USING (PersonID);
INSERT INTO accepted_but_wrong SELECT 'SmokingStatus', '_SMOKER3', SUM(NOT (n.SmokingStatus <=> o.SmokingStatus)) FROM HealthMetrics n JOIN clean_healthmetrics o USING (PersonID);
INSERT INTO accepted_but_wrong SELECT 'ExerciseDaysPerWeek', 'EXEROFT1', SUM(NOT (n.ExerciseDaysPerWeek <=> o.ExerciseDaysPerWeek)) FROM HealthMetrics n JOIN clean_healthmetrics o USING (PersonID);

SELECT * FROM accepted_but_wrong ORDER BY WrongValues DESC;

ROLLBACK;

DROP PROCEDURE try_raw_values;
DROP TEMPORARY TABLE stg_raw, raw_test, raw_test_errors, accepted_but_wrong,
                     clean_household, clean_person, clean_healthmetrics;
