USE healthcare_db;


WITH Respondent AS (
    SELECT
        CASE
            WHEN p.AgeGroup IN ('18-24', '25-29', '30-34', '35-39', '40-44') THEN '18-44'
            WHEN p.AgeGroup IN ('45-49', '50-54', '55-59', '60-64') THEN '45-64'
            WHEN p.AgeGroup IS NOT NULL THEN '65+'
        END AS AgeBand,
        h.HouseholdIncome / (col.CostIndex / 100) AS PriceAdjustedIncome,
        hm.HasInsurance,
        hm.SelfReportedHealth
    FROM Person p
    JOIN Household h ON p.HouseholdID = h.HouseholdID
    JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
    JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
    WHERE p.AgeGroup IS NOT NULL
      AND h.HouseholdIncome IS NOT NULL
)
SELECT
    AgeBand,
    CASE
        WHEN PriceAdjustedIncome < 50000 THEN 'Under $50,000'
        ELSE '$50,000 or more'
    END AS PriceAdjustedIncomeGroup,
    COUNT(*) AS Respondents,
    ROUND(100 * AVG(CASE WHEN HasInsurance = 0 THEN 1 WHEN HasInsurance = 1 THEN 0 END), 1) AS PctUninsured,
    ROUND(100 * AVG(CASE WHEN SelfReportedHealth <= 2 THEN 1 WHEN SelfReportedHealth > 2 THEN 0 END), 1) AS PctFairOrPoorHealth
FROM Respondent
GROUP BY AgeBand, PriceAdjustedIncomeGroup
ORDER BY AgeBand, PriceAdjustedIncomeGroup DESC;
