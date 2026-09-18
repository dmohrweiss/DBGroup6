DROP SCHEMA IF EXISTS healthcare_db;
CREATE SCHEMA healthcare_db;
USE healthcare_db;

CREATE TABLE ResidenceType (
  ResidenceTypeID INT PRIMARY KEY,
  Label VARCHAR(30),
  Description VARCHAR(255) 
);

CREATE TABLE Gender (
  GenderID INT PRIMARY KEY,
  Label VARCHAR(10),
  Code INT 
);

CREATE TABLE Region (
  StateID INT PRIMARY KEY,
  StateName VARCHAR(50)
);

CREATE TABLE HealthLabel (
  HealthLabelID INT PRIMARY KEY,
  CategoryLabelName VARCHAR(30),
  Description VARCHAR(255)
);

CREATE TABLE CostOfLiving (
  CostOfLivingID INT PRIMARY KEY,
  StateID INT,
  RegionCode VARCHAR(10),
  CostIndex DECIMAL(6,2),
  HousingCostIndex DECIMAL(6,2),
  GroceryCostIndex DECIMAL(6,2),
  HealthcareCostIndex DECIMAL(6,2),
  TransportCostIndex DECIMAL(6,2),
  FOREIGN KEY (StateID) REFERENCES Region(StateID)
);

CREATE TABLE Household (
  HouseholdID INT PRIMARY KEY,
  ResidenceTypeID INT,
  CostOfLivingID INT,
  HouseholdIncome DECIMAL(10,2),
  HouseholdSize INT,
  NumEarners INT,
  ChildrenUnderLegalAge INT,
  FOREIGN KEY (ResidenceTypeID) REFERENCES ResidenceType(ResidenceTypeID),
  FOREIGN KEY (CostOfLivingID) REFERENCES CostOfLiving(CostOfLivingID)
);

CREATE TABLE Person (
  PersonID INT PRIMARY KEY,
  HouseholdID INT,
  GenderID INT,
  FirstName VARCHAR(30),
  LastName VARCHAR(30),
  DOB DATE,
  IndividualIncome DECIMAL(10,2),
  Debt BOOLEAN,
  FOREIGN KEY (HouseholdID) REFERENCES Household(HouseholdID),
  FOREIGN KEY (GenderID) REFERENCES Gender(GenderID)
);

CREATE TABLE HealthMetrics (
  PersonID INT PRIMARY KEY,
  HealthLabelID INT,
  DistanceToCareKM DECIMAL(6,2),
  HasInsurance BOOLEAN,
  BMI DECIMAL(4,1),
  ChronicConditionsCount INT,
  SelfReportedHealth INT,
  MentalHealthScore INT,
  SmokingStatus BOOLEAN,
  ExerciseDaysPerWeek INT,
  FOREIGN KEY (PersonID) REFERENCES Person(PersonID),
  FOREIGN KEY (HealthLabelID) REFERENCES HealthLabel(HealthLabelID)
);
