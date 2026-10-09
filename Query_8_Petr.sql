USE healthcare_db;
-- The physical health gap caused by expensive basic goods
SELECT 
    CASE 
        WHEN h.HouseholdIncome < 50000 THEN 'Lower Income (<$50k)'
        ELSE 'Higher Income ($50k+)'
    END AS IncomeBracket,
    CASE 
        WHEN col.GoodsCostIndex >= 100 THEN 'High Goods Cost (>=100)'
        ELSE 'Low Goods Cost (<100)'
    END AS GoodsCostLevel,
    COUNT(p.PersonID) AS Respondents,
    ROUND(AVG(hm.BMI), 1) AS AvgBMI,
    ROUND(100 * AVG(CASE WHEN hm.BMI >= 30 THEN 1 ELSE 0 END), 1) AS PctObese,
    ROUND(AVG(hm.ExerciseDaysPerWeek), 1) AS AvgExerciseDays,
    ROUND(AVG(hm.ChronicConditionsCount), 2) AS AvgChronicConditions
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
WHERE h.HouseholdIncome IS NOT NULL 
  AND hm.BMI IS NOT NULL
GROUP BY IncomeBracket, GoodsCostLevel
ORDER BY IncomeBracket, GoodsCostLevel DESC;