USE healthcare_db;

-- Week 5: the Week-3 queries, adapted after running them on real-world data
-- (CDC BRFSS 2023 + BEA Regional Price Parities). The original versions are in
-- commit b10c2e8 (git tag `week3-mock-data` locally); why each change was needed is explained in
-- docs/week5_real_data_integration.md. Results: docs/query_results/.


-- QUERY 1: Regional & Housing Type Socioeconomic Health Profile
-- Multi-table JOINs (5 tables), GROUP BY, HAVING, Aggregates (AVG, SUM, COUNT)
-- Evaluates how average household income, BMI, the local price level and insurance coverage vary across states and residence types.
-- Week-5 changes: HAVING >= 10 (groups of 2-3 respondents gave meaningless averages);
--   DistanceToCareKM replaced by the BEA price indexes (no open source reports distance);
--   income also shown price-adjusted (income / RPP * 100) so states can be compared;
--   uninsured shown as a percentage of respondents who answered (NULL = unknown is excluded).

SELECT
    r.StateName,
    rt.Label AS ResidenceType,
    COUNT(p.PersonID) AS TotalResidents,
    ROUND(AVG(h.HouseholdIncome), 2) AS AvgHouseholdIncome,
    ROUND(AVG(h.HouseholdIncome / (col.CostIndex / 100)), 2) AS AvgPriceAdjustedIncome,
    col.HousingCostIndex,
    ROUND(AVG(hm.BMI), 1) AS AvgBMI,
    SUM(CASE WHEN hm.HasInsurance = FALSE THEN 1 ELSE 0 END) AS UninsuredCount,
    ROUND(100 * AVG(CASE WHEN hm.HasInsurance IS NULL THEN NULL WHEN hm.HasInsurance = FALSE THEN 1 ELSE 0 END), 1) AS UninsuredPct
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN ResidenceType rt ON h.ResidenceTypeID = rt.ResidenceTypeID
JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
JOIN Region r ON col.StateID = r.StateID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
GROUP BY r.StateName, rt.Label, col.CostIndex, col.HousingCostIndex
HAVING COUNT(p.PersonID) >= 10
ORDER BY AvgPriceAdjustedIncome ASC;


-- QUERY 2: High Health-Risk Individuals in Socioeconomically Deprived Households
-- Common Table Expression (CTE), Subqueries in WHERE, JOINs
-- Pinpoints individuals living in below-average income households who simultaneously suffer from an above-average number of chronic health conditions.
-- Week-5 changes: "below-average income" is now judged on PRICE-ADJUSTED income, because
--   $40,000 buys far less in California (RPP 112) than in Mississippi (RPP 87);
--   survey respondents are anonymous, so FullName falls back to the survey record key;
--   DistanceToCareKM (always NULL) replaced by state and insurance status.

WITH AdjustedHouseholds AS (
    SELECT h.HouseholdID,
           h.SourceRecordKey,
           h.HouseholdIncome,
           h.HouseholdIncome / (col.CostIndex / 100) AS PriceAdjustedIncome,
           col.StateID
    FROM Household h
    JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
),
DeprivedHouseholds AS (
    SELECT *
    FROM AdjustedHouseholds
    WHERE PriceAdjustedIncome < (SELECT AVG(PriceAdjustedIncome) FROM AdjustedHouseholds)
)
SELECT
    p.PersonID,
    COALESCE(CONCAT(p.FirstName, ' ', p.LastName), dh.SourceRecordKey) AS FullName,
    r.StateAbbrev AS State,
    dh.HouseholdIncome,
    ROUND(dh.PriceAdjustedIncome, 2) AS PriceAdjustedIncome,
    hm.ChronicConditionsCount,
    hm.HasInsurance,
    hl.CategoryLabelName AS RiskCategory
FROM Person p
JOIN DeprivedHouseholds dh ON p.HouseholdID = dh.HouseholdID
JOIN Region r ON dh.StateID = r.StateID
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
JOIN HealthLabel hl ON hm.HealthLabelID = hl.HealthLabelID
WHERE hm.ChronicConditionsCount >= (
    SELECT AVG(ChronicConditionsCount) FROM HealthMetrics
)
ORDER BY hm.ChronicConditionsCount DESC, dh.PriceAdjustedIncome ASC, p.PersonID;



-- QUERY 3: State-Level Health Deprivation Ranking Using Window Functions
-- Window Function (DENSE_RANK() OVER PARTITION BY), CTE, Multi-table JOINs
-- Ranks individuals within their respective State based on multi-factor health risk indicators (chronic conditions count, self-reported health, and mental health score).
-- Week-5 changes: only the 5 worst-off ranks per state are shown (500 rows were unreadable);
--   DistanceToCareKM (always NULL) replaced by SelfReportedHealth in the ranking;
--   unknown (NULL) scores are sorted last: MySQL sorts NULL FIRST in ascending order,
--   which would otherwise rank people who did not answer as the most deprived.

WITH RankedResidents AS (
    SELECT
        r.StateName,
        COALESCE(CONCAT(p.FirstName, ' ', p.LastName), h.SourceRecordKey) AS FullName,
        hm.ChronicConditionsCount,
        hm.SelfReportedHealth,
        hm.MentalHealthScore,
        DENSE_RANK() OVER (
            PARTITION BY r.StateID
            ORDER BY hm.ChronicConditionsCount DESC,
                     hm.SelfReportedHealth IS NULL, hm.SelfReportedHealth ASC,
                     hm.MentalHealthScore IS NULL, hm.MentalHealthScore ASC
        ) AS StateHealthDeprivationRank
    FROM Person p
    JOIN Household h ON p.HouseholdID = h.HouseholdID
    JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
    JOIN Region r ON col.StateID = r.StateID
    JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
)
SELECT *
FROM RankedResidents
WHERE StateHealthDeprivationRank <= 5
ORDER BY StateName, StateHealthDeprivationRank, FullName;


-- QUERY 4 (new in Week 5): Cost of Living versus Health Outcomes per State
-- Combines BOTH real-world sources: BEA price levels (dataset B) with BRFSS health data (dataset A)
-- GROUP BY, conditional aggregation, RANK() window function
-- Tests whether states where housing is expensive show different insurance coverage and health burden
-- once income is corrected for the local price level.

SELECT
    r.StateName,
    br.RegionName AS BEARegion,
    col.CostIndex AS PriceLevel,
    col.HousingCostIndex,
    COUNT(*) AS Respondents,
    ROUND(AVG(h.HouseholdIncome / (col.CostIndex / 100)), 0) AS AvgPriceAdjustedIncome,
    ROUND(AVG(hm.ChronicConditionsCount), 2) AS AvgChronicConditions,
    ROUND(100 * AVG(hm.SelfReportedHealth <= 2), 1) AS PctFairOrPoorHealth,
    ROUND(100 * AVG(hm.HasInsurance = 0), 1) AS PctUninsured,
    ROUND(100 * AVG(hm.SmokingStatus), 1) AS PctSmokers,
    RANK() OVER (ORDER BY AVG(hm.ChronicConditionsCount) DESC) AS HealthBurdenRank
FROM Person p
JOIN Household h ON p.HouseholdID = h.HouseholdID
JOIN CostOfLiving col ON h.CostOfLivingID = col.CostOfLivingID
JOIN Region r ON col.StateID = r.StateID
JOIN BEARegion br ON r.BEARegionCode = br.BEARegionCode
JOIN HealthMetrics hm ON p.PersonID = hm.PersonID
GROUP BY r.StateName, br.RegionName, col.CostIndex, col.HousingCostIndex
ORDER BY col.CostIndex DESC;


-- QUERY 5 (new in Week 5): Relative Housing Price Level Over Time (2008-2024)
-- Uses the time dimension of dataset B: CTE, Window functions LAG() and FIRST_VALUE()
-- Shows, for the five study states, the housing price index (US average = 100) per year and
-- its change versus the previous year and versus 2008, i.e. whether the gap between
-- expensive and cheap states is growing or shrinking.
-- The window is computed over ALL years first and filtered afterwards; filtering in the
-- same SELECT would make LAG() compare with the previous *shown* year instead.

WITH HousingTrend AS (
    SELECT
        r.StateAbbrev AS State,
        col.Year,
        col.HousingCostIndex,
        ROUND(col.HousingCostIndex - LAG(col.HousingCostIndex) OVER w, 3) AS ChangeVsPrevYear,
        ROUND(col.HousingCostIndex - FIRST_VALUE(col.HousingCostIndex) OVER w, 3) AS ChangeSince2008
    FROM CostOfLiving col
    JOIN Region r ON col.StateID = r.StateID
    WHERE r.StateAbbrev IN ('CA', 'NY', 'IL', 'WV', 'MS')
    WINDOW w AS (PARTITION BY col.StateID ORDER BY col.Year)
)
SELECT *
FROM HousingTrend
WHERE Year IN (2008, 2012, 2016, 2020, 2022, 2023, 2024)
ORDER BY State, Year;
