UPDATE HealthMetrics
SET HealthLableID = 4
WHERE MentalHealthScore > 3 AND DistanceToCareKM < 50;

UPDATE CostOfLiving
SET HousingCostIndex = HousingCostIndex - 0.1
WHERE CostOfLivingID IN (
    SELECT h.CostOfLivingID
    FROM Household h
    JOIN Person p ON h.HouseholdID = p.HouseholdID
    WHERE h.HouseholdIncome > 10000
);

