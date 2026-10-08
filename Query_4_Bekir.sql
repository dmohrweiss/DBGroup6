-- Query 4: Assess the impact of housing costs on family health (households with vs. without children) across economic regions.
-- Author: Bekir
SELECT
    bea.RegionName AS EconomicRegion,
    CASE
        WHEN h.ChildrenUnderLegalAge > 0 THEN 'With Children'
        ELSE 'No Children'
    END AS FamilyStatus,
    COUNT(p.PersonID) AS Respondents,
    ROUND(AVG(col.HousingCostIndex), 1) AS AvgHousingCostIndex,
    ROUND(AVG(hm.MentalHealthScore), 2) AS AvgMentalHealthScore,
    ROUND(AVG(hm.BMI), 1) AS AvgBMI,
    ROUND(100 * AVG(hm.SmokingStatus), 1) AS PctSmokers
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
JOIN Region r ON col.StateID = r.StateID
JOIN BEARegion bea ON r.BEARegionCode = bea.BEARegionCode
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
GROUP BY bea.RegionName, FamilyStatus
ORDER BY bea.RegionName, AvgHousingCostIndex DESC, FamilyStatus;