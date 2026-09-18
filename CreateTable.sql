DROP SCHEMA IF EXISTS healthcare_db;
CREATE SCHEMA healthcare_db;
USE healthcare_db;

CREATE TABLE ResidenceType (
  PK_ResidenceTypeID INT PRIMARY KEY,
  Label VARCHAR(30),
  Description VARCHAR(255) 
);

CREATE TABLE Gender (
  PK_GenderID INT PRIMARY KEY,
  Label VARCHAR(10),
  Code INT 
);

CREATE TABLE Region (
  PK_StateID INT PRIMARY KEY,
  StateName VARCHAR(50)
);

CREATE TABLE HealthLabel (
  PK_HealthLabelID INT PRIMARY KEY,
  CategoryLabelName VARCHAR(30),
  Description VARCHAR(255)
);

CREATE TABLE CostOfLiving (
  PK_CostOfLivingID INT PRIMARY KEY,
  FK_StateID INT,
  RegionCode VARCHAR(10),
  CostIndex DECIMAL(6,2),
  HousingCostIndex DECIMAL(6,2),
  GroceryCostIndex DECIMAL(6,2),
  HealthcareCostIndex DECIMAL(6,2),
  TransportCostIndex DECIMAL(6,2),
  FOREIGN KEY (FK_StateID) REFERENCES Region(PK_StateID)
);

CREATE TABLE Household (
  PK_HouseholdID INT PRIMARY KEY,
  FK_ResidenceTypeID INT,
  FK_CostOfLivingID INT,
  HouseholdIncome DECIMAL(10,2),
  HouseholdSize INT,
  NumEarners INT,
  ChildrenUnderLegalAge INT,
  FOREIGN KEY (FK_ResidenceTypeID) REFERENCES ResidenceType(PK_ResidenceTypeID),
  FOREIGN KEY (FK_CostOfLivingID) REFERENCES CostOfLiving(PK_CostOfLivingID)
);

CREATE TABLE Person (
  PK_PersonID INT PRIMARY KEY,
  FK_HouseholdID INT,
  FK_GenderID INT,
  FirstName VARCHAR(30),
  LastName VARCHAR(30),
  DOB DATE,
  IndividualIncome DECIMAL(10,2),
  Debt BOOLEAN,
  FOREIGN KEY (FK_HouseholdID) REFERENCES Household(PK_HouseholdID),
  FOREIGN KEY (FK_GenderID) REFERENCES Gender(PK_GenderID)
);

CREATE TABLE HealthMetrics (
  PK_FK_PersonID INT PRIMARY KEY,
  FK_HealthLabelID INT,
  DistanceToCareKM DECIMAL(6,2),
  HasInsurance BOOLEAN,
  BMI DECIMAL(4,1),
  ChronicConditionsCount INT,
  SelfReportedHealth INT,
  MentalHealthScore INT,
  SmokingStatus BOOLEAN,
  ExerciseDaysPerWeek INT,
  FOREIGN KEY (PK_FK_PersonID) REFERENCES Person(PK_PersonID),
  FOREIGN KEY (FK_HealthLabelID) REFERENCES HealthLabel(PK_HealthLabelID)
);
