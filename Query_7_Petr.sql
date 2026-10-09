USE healthcare_db;
-- Impact of living alone vs living with others on mental health, etc.
SELECT 
    CASE 
        WHEN h.HouseholdSize = 1 THEN 'Living Alone'
        ELSE 'Living with Others'
    END AS LivingSituation,
    CASE 
        WHEN col.CostIndex >= 100 THEN 'High Cost of Living (>=100)'
        ELSE 'Low Cost of Living (<100)'
    END AS StateCostLevel,
    COUNT(p.PersonID) AS Respondents,
    ROUND(100 * AVG(CASE WHEN hm.MentalHealthScore <= 2 THEN 1 ELSE 0 END), 1) AS PctFrequentMentalDistress,
    ROUND(100 * AVG(CASE WHEN hm.HasInsurance = 0 THEN 1 ELSE 0 END), 1) AS PctUninsured,
    ROUND(AVG(hm.ChronicConditionsCount), 2) AS AvgChronicConditions
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
WHERE h.HouseholdSize IS NOT NULL
GROUP BY LivingSituation, StateCostLevel
ORDER BY LivingSituation, StateCostLevel DESC;