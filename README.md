# Database Installation and Population Guide
# Step 1: Clone the Repository
Open your terminal or command prompt and clone the project repository using Git:
git clone https://github.com/dmohrweiss/DBGroup6.git
cd DBGroup6
# Step 3: Execute Schema Creation Scripts
Run the following script:
mysql -u your_username -p DBGroup6 < path/to/CreateTable.sql
# Step 4: Populate the Database
mysql -u your_username -p DBGroup6 < path/to/Data.sql
