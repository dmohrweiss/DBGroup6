-- Query 3: Analyze healthcare access and mental health outcomes by residence type.
-- Author: Bekir
SELECT
    rt.Label AS ResidenceType,
    COUNT(p.PersonID) AS TotalRespondents,
    ROUND(AVG(hm.DistanceToCareKM), 2) AS AvgDistanceToCareKM,
    ROUND(100 * AVG(CASE WHEN hm.HasInsurance = 0 THEN 1 ELSE 0 END), 1) AS PctUninsured,
    ROUND(AVG(hm.MentalHealthScore), 2) AS AvgMentalHealthScore,
    ROUND(AVG(hm.ChronicConditionsCount), 2) AS AvgChronicConditions
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN ResidenceType rt ON h.ResidenceTypeID = rt.ResidenceTypeID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
WHERE h.ResidenceTypeID IS NOT NULL
GROUP BY rt.Label
ORDER BY AvgDistanceToCareKM DESC;