
-- QUERY 1: Regional & Housing Type Socioeconomic Health Profile
-- Multi-table JOINs (5 tables), GROUP BY, HAVING, Aggregates (AVG, SUM, COUNT)
-- Evaluates how average household income, BMI, distance to health facilities, and insurance coverage vary across state regions and residence types.

SELECT 
    r.StateName,
    rt.Label AS ResidenceType,
    COUNT(p.PersonID) AS TotalResidents,
    ROUND(AVG(h.HouseholdIncome), 2) AS AvgHouseholdIncome,
    ROUND(AVG(hm.BMI), 1) AS AvgBMI,
    ROUND(AVG(hm.DistanceToCareKM), 2) AS AvgDistanceToCareKM,
    SUM(CASE WHEN hm.HasInsurance = FALSE THEN 1 ELSE 0 END) AS UninsuredCount
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN ResidenceType rt ON h.ResidenceTypeID = rt.ResidenceTypeID
JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
JOIN Region r ON col.StateID = r.StateID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
GROUP BY r.StateName, rt.Label
HAVING COUNT(p.PersonID) >= 1
ORDER BY AvgHouseholdIncome ASC;


-- QUERY 2: High Health-Risk Individuals in Socioeconomically Deprived Households
-- Common Table Expression (CTE), Subqueries in WHERE, JOINs
-- Pinpoints individuals living in below-average income households who simultaneously suffer from an above-average number of chronic health conditions.

WITH DeprivedHouseholds AS (
    SELECT HouseholdID, HouseholdIncome
    FROM Household
    WHERE HouseholdIncome < (SELECT AVG(HouseholdIncome) FROM Household)
)
SELECT 
    p.PersonID,
    CONCAT(p.FirstName, ' ', p.LastName) AS FullName,
    dh.HouseholdIncome,
    hm.ChronicConditionsCount,
    hm.DistanceToCareKM,
    hl.CategoryLabelName AS RiskCategory
FROM Person p
JOIN DeprivedHouseholds dh ON p.HouseholdID = dh.HouseholdID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
JOIN HealthLabel hl ON hm.HealthLabelID = hl.HealthLabelID
WHERE hm.ChronicConditionsCount >= (
    SELECT AVG(ChronicConditionsCount) FROM HealthMetrics
)
ORDER BY hm.ChronicConditionsCount DESC, dh.HouseholdIncome ASC;



-- QUERY 3: State-Level Health Deprivation Ranking Using Window Functions
-- Window Function (DENSE_RANK() OVER PARTITION BY), Multi-table JOINs
-- Ranks individuals within their respective State based on multi-factor health risk indicators (chronic conditions count, distance to care, and mental health score).
-- -----------------------------------------------------------------------------
SELECT 
    r.StateName,
    CONCAT(p.FirstName, ' ', p.LastName) AS FullName,
    hm.ChronicConditionsCount,
    hm.DistanceToCareKM,
    hm.MentalHealthScore,
    DENSE_RANK() OVER (
        PARTITION BY r.StateID 
        ORDER BY hm.ChronicConditionsCount DESC, hm.DistanceToCareKM DESC, hm.MentalHealthScore ASC
    ) AS StateHealthDeprivationRank
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
JOIN Region r ON col.StateID = r.StateID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID;
