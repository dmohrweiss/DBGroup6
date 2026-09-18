# Database Installation and Population Guide
# Step 1: Clone the Repository
Open your terminal or command prompt and clone the project repository using Git:
git clone https://github.com/dmohrweiss/DBGroup6.git
cd DBGroup6
# Step 2: Create the Database
CREATE DATABASE DBGroup6;
# Step 3: Execute Schema Creation Scripts
Run the folowing script 
psql -U your_username -d DBGroup6 -f path/to/CreateTable.sql
# Step 4: Populate the Database
psql -U your_username -d DBGroup6 -f path/to/Data.sql
