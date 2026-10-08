-- Active: 1788875849027@@127.0.0.1@3306@mysql
USE healthcare_db;

-- Query 1: Compare health outcomes across price-adjusted income groups.
SELECT
    CASE
        WHEN h.HouseholdIncome / (col.CostIndex / 100) < 25000 THEN 'Under $25,000'
        WHEN h.HouseholdIncome / (col.CostIndex / 100) < 50000 THEN '$25,000-$49,999'
        WHEN h.HouseholdIncome / (col.CostIndex / 100) < 75000 THEN '$50,000-$74,999'
        ELSE '$75,000 or more'
    END AS IncomeGroup,
    COUNT(p.PersonID) AS Respondents,
    ROUND(AVG(hm.ChronicConditionsCount), 2) AS AvgChronicConditions,
    ROUND(100 * AVG(CASE
        WHEN hm.SelfReportedHealth <= 2 THEN 1
        WHEN hm.SelfReportedHealth > 2 THEN 0
    END), 1) AS PctFairOrPoorHealth,
    ROUND(100 * AVG(CASE
        WHEN hm.HasInsurance = 0 THEN 1
        WHEN hm.HasInsurance = 1 THEN 0
    END), 1) AS PctUninsured,
    ROUND(100 * AVG(hm.SmokingStatus), 1) AS PctSmokers
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
WHERE h.HouseholdIncome IS NOT NULL
GROUP BY IncomeGroup
ORDER BY MIN(h.HouseholdIncome / (col.CostIndex / 100));