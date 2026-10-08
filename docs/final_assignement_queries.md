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
