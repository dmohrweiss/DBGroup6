USE healthcare_db;

WITH IncomePerMember AS (
    SELECT
        -- price-adjusted household income divided by the square root of the household size
        -- (OECD equivalence scale: a household of 4 needs about twice the income of 1 person)
        h.HouseholdIncome / (col.CostIndex / 100) / SQRT(h.HouseholdSize) AS IncomePerMember,
        h.HouseholdSize,
        hm.MentalHealthScore,
        hm.SelfReportedHealth,
        hm.ExerciseDaysPerWeek
    FROM Person p
    JOIN Household h ON p.HouseholdID = h.HouseholdID
    JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
    JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
    WHERE h.HouseholdIncome IS NOT NULL
      AND h.HouseholdSize IS NOT NULL
),
Quarters AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY IncomePerMember) AS IncomeQuarter
    FROM IncomePerMember
)
SELECT
    IncomeQuarter,
    COUNT(*) AS Respondents,
    ROUND(MIN(IncomePerMember), 0) AS FromIncomePerMember,
    ROUND(MAX(IncomePerMember), 0) AS ToIncomePerMember,
    ROUND(AVG(HouseholdSize), 1) AS AvgHouseholdSize,
    ROUND(100 * AVG(CASE WHEN MentalHealthScore <= 2 THEN 1 WHEN MentalHealthScore > 2 THEN 0 END), 1) AS PctFrequentMentalDistress,
    ROUND(100 * AVG(CASE WHEN SelfReportedHealth <= 2 THEN 1 WHEN SelfReportedHealth > 2 THEN 0 END), 1) AS PctFairOrPoorHealth,
    ROUND(AVG(ExerciseDaysPerWeek), 1) AS AvgExerciseDaysPerWeek
FROM Quarters
GROUP BY IncomeQuarter
ORDER BY IncomeQuarter;
