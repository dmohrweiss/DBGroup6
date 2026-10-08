-- Query 2: Compare income and health outcomes across states.
SELECT
    r.StateName,
    COUNT(p.PersonID) AS Respondents,
    ROUND(AVG(h.HouseholdIncome), 2) AS AvgHouseholdIncome,
    ROUND(AVG(h.HouseholdIncome / (col.CostIndex / 100)), 2) AS AvgPriceAdjustedIncome,
    ROUND(AVG(hm.ChronicConditionsCount), 2) AS AvgChronicConditions,
    ROUND(100 * AVG(hm.HasInsurance), 1) AS PctInsured
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
JOIN Region r ON col.StateID = r.StateID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
GROUP BY r.StateName
ORDER BY AvgPriceAdjustedIncome DESC;