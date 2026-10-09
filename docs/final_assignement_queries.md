# Final Assignement : Query Documentation

**Group 6** · Repository: <https://github.com/dmohrweiss/DBGroup6> · Database: MySQL 8.4

This report integrates all the documentation of the queries added for the final assignement

## Query 1 : Price-Adjusted Income and Health Outcomes (Author : Daniel)

This query answers the question : How do chronic disease, self-reported health, insurance coverage, and smoking rates changes through different levels of real buying power after changing income for local cost of living?

This analysis focuses on the gap between one person household income and the income a household can spend in the local economy. By changing household income using the `CostIndex`, the query identifies if residents with lower real incomes also have worse health outcomes, including chronic conditions, higher rates of fair or poor health, less coverage, and greater smoking prevalence. This makes it possible to separate economic hardship from simple regional differences in wages and costs.

## Query 2 : State-Level Income and Health Comparison (Author : Daniel)

This query answers the question : Which states combine higher average incomes with better health outcomes, and how do differences in insurance coverage and chronic disease burden vary across the country?

This query builds a comparison of how income and health outcomes are diferent from one state to another. It shows average household income, average price-adjusted income, chronic disease, and insurance coverage for each state. By comparing states the analysis reveals whether high single income translates into economic advantage after taking into account local CoL, and if this is goes alongside by better health protection and access to care.

## Query 3 : Healthcare Access and Mental Health by Residence Type (Author : Bekir)

This query answers the question : How do healthcare access metrics—specifically the physical distance to care and insurance coverage rates—and average mental health scores differ among urban, suburban, and rural populations?

While Daniel's first query focused on the relationship between price-adjusted income and health outcomes, this query targets geographic disparities. Highlighting the differences in physical barriers (`DistanceToCareKM`) and insurance rates across residence types identifies underserved communities. This helps public health officials determine if rural or suburban areas require localized interventions, mobile clinics, or targeted mental health resources to address geographic inequalities.

## Query 4 : Impact of Regional Housing Costs on Family Health (Author : Bekir)

This query answers the question : Does the combination of high regional housing costs and the presence of minor children in a household correlate with worsened stress levels (measured by `MentalHealthScore`) or negative health behaviors (BMI and smoking rates) across different BEA economic regions?

Daniel’s second query provided a broad state-level comparison of general health and income. This query deepens the analysis of the societal problem by isolating one of the most significant financial burdens: housing costs. By comparing households with children against those without, the query reveals whether the compounded financial strain of raising a family in expensive economic regions translates directly into measurable mental and physical health declines.

## Query 5 : Who Falls Through the Insurance Safety Net? (Author : Khalid, GitHub: KhalidWRamadan)

File: [`Query_5_Khalid.sql`](../Query_5_Khalid.sql)

This query answers the question : Within each age group (18-44, 45-64, 65+), how much more often are people with a low price-adjusted income (under $50,000) uninsured or in fair or poor health than people of the same age with a higher income?

Our problem statement says that rising living costs push vulnerable people to arrive at hospitals more unwell. People without insurance tend to delay care until a problem becomes serious, so the useful question is not only *whether* low income goes with less insurance, but *for whom*. Splitting by age shows where the safety net has gaps. In our data, 21.0% of low-income 18-44 year olds are uninsured against 8.5% of higher-income people of the same age, while almost everyone aged 65+ is covered (Medicare). Low-income 45-64 year olds are covered more often, but 52.9% of them rate their health as fair or poor (10.8% with higher income). This tells policymakers which group to target: coverage support for young low-income adults, and health care for low-income adults before retirement age.

## Query 6 : Income per Household Member and Mental Distress (Author : Khalid, GitHub: KhalidWRamadan)

File: [`Query_6_Khalid.sql`](../Query_6_Khalid.sql)

This query answers the question : When respondents are split into four equal groups by price-adjusted income *per household member*, how do frequent mental distress, fair or poor health and exercise change from the lowest to the highest group?

The same household income has to cover more people in a larger family, and costs more to live on in an expensive state. The query therefore corrects income for both: it divides by the state price level (`CostIndex`) and by the square root of the household size (the OECD equivalence scale). It then uses the window function `NTILE(4)` to form four equal groups. This tests an assumption from our stakeholder video, that economic strain is shared equally by all household members, by measuring strain *per member*. The result links economic strain directly to mental health. In the lowest quarter (households are also the largest, 2.9 people on average) 23.5% report frequent mental distress, meaning 14 or more bad days a month, and 40.0% report fair or poor health. In the highest quarter these figures are 8.7% and 8.7%. Mental-health support and cost-of-living relief are therefore most needed where income must stretch over the most people.

## Query 7 : The correlation between Living Alone and Mental Distress in High Cost of living (Author : Petr)

File: [`Query_7_Petr.sql`](../Query_7_Petr.sql)

This query answers the question of whether liiving alone in high-cost states affects the mental distress of a person, lack of insurance and chronic conditions
compared to other people living together in more affordable districts?

Single adults face the full burden of living costs without a second earner to help. This query groups respondents by whether they live alone (HouseholdSize = 1) and cross-references this with the state's price level (CostIndex). It tests whether the financial strain of living alone in an expensive region directly worsens mental health and healthcare access. For example, [16.7]% of people living alone in high-cost states report frequent mental distress, compared to only [14.8]% of people living with others in low-cost states. The difference in those 2 numbers is not significant, but surprisingly, only [10.7]% of people suffer from mental distress in high-cost states who live in family. This shows exactly where financial and mental health safety nets are needed most.

## Query 8 : The nutritional difference: correlation between high-cost goods & obesity and physical health (Author : Petr)

File: [`Query_8_Petr.sql`](../Query_8_Petr.sql)

This query answers the question of whether the high cost for goods forces the low-income households rely on cheap food and, as a result, have physical health problems

When cost of living is high, the health inequality can simply be shown by what food people eat. This query groups participants by their income (HouseholdIncome under or over $50,000) and the local cost of products (GoodsCostIndex above or below the 100 national baseline). It tests whether this daily economic correlates directly with factors like obesity (BMI >= 30) or chronic diseases. For example, lower-income people tend to have much more chronic conditions on average, (1.97 and 1.19) to (0.93 and 0.96). Interestingly, the obesity rates are very high at the states with low cost of goods, not depending on the income.

