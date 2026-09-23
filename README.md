# Customer Segmentation Using Latent Class Analysis (LCA)

> **Behavioural customer segmentation of credit-card users using Latent Class Analysis in R, with rigorous data-quality auditing, probabilistic model selection, segment profiling, and marketing interpretation.**

## Project Overview

Traditional customer segmentation often relies on demographic categories or distance-based clustering techniques such as K-Means. However, customer behaviour is frequently captured through **categorical survey responses**, making conventional clustering methods less suitable.

This project develops a statistically grounded customer segmentation framework using **Latent Class Analysis (LCA)** to identify unobserved customer groups based on patterns in credit-card usage, repayment behaviour, purchasing activity, balance levels, and adoption of Buy Now, Pay Later (BNPL) services.

Rather than forcing categorical responses onto an artificial continuous scale, the analysis treats the survey responses as categorical indicators and estimates the probability that each respondent belongs to an underlying behavioural segment.

The complete workflow was developed in **R** and covers:

* data import and validation;
* survey-questionnaire interpretation;
* data-quality assessment;
* questionnaire-routing analysis;
* identification of the appropriate analytical population;
* categorical feature preparation;
* Latent Class Analysis;
* comparison of competing segmentation solutions;
* BIC-based model selection;
* convergence and stability checks;
* posterior membership assessment;
* segment profiling;
* local-independence diagnostics;
* demographic and behavioural enrichment; and
* translation of statistical classes into interpretable customer personas.

---

## Business Problem

Financial-service customers do not use credit products in the same way.

Two customers may both own a credit card while exhibiting completely different behaviours:

* one may use cards heavily but repay the entire balance every month;
* another may carry balances from month to month;
* another may use cards only occasionally;
* another may actively combine traditional credit cards with newer products such as BNPL.

Treating these customers as one homogeneous market can lead to poorly targeted campaigns, inefficient marketing expenditure, irrelevant product offers, and weak customer experiences.

The central business question therefore becomes:

> **Can customers be separated into meaningful behavioural segments using their observed credit and purchasing behaviours?**

The project addresses this question using Latent Class Analysis.

---

## Project Objectives

The analysis was designed to accomplish six major objectives:

1. **Understand and audit the original purchasing survey data.**
2. **Respect questionnaire-routing logic rather than incorrectly treating structural blanks as ordinary missing data.**
3. **Identify active credit-card users suitable for behavioural segmentation.**
4. **Estimate competing Latent Class models and determine an appropriate number of customer segments.**
5. **Profile the resulting segments using behavioural and demographic variables not directly used to construct them.**
6. **Translate statistical classes into commercially interpretable customer personas that could support marketing and customer-management decisions.**

---

# Why Latent Class Analysis?

## Why Not K-Means?

K-Means is highly useful when the variables being clustered are meaningfully numerical and distances between observations can be interpreted.

That assumption is problematic for much of this dataset.

For example, responses such as:

* `Never`
* `Rarely`
* `Sometimes`
* `Usually`
* `Always`

represent ordered categories, but the numerical distance between each response is not necessarily equal.

Similarly, categories such as:

* Less than $500
* $501–$1,000
* $1,001–$2,000
* More than $10,000

should not automatically be treated as equally spaced continuous observations.

Converting these responses to arbitrary numeric values and applying Euclidean-distance clustering could create artificial relationships that were never present in the original survey.

## Why LCA Is Appropriate

**Latent Class Analysis** is a model-based clustering technique designed for categorical data.

LCA assumes that an unobserved categorical variable — the **latent class** — helps explain the response patterns observed across several categorical indicators.

Conceptually:

```text
Observed Customer Behaviour
        │
        ├── Number of credit cards
        ├── Monthly card balance
        ├── Repayment behaviour
        ├── Share of purchases using credit cards
        └── BNPL behaviour
        │
        ▼
Unobserved Behavioural Segment
        │
        ├── Segment 1
        ├── Segment 2
        ├── Segment 3
        └── ...
```

Instead of measuring distance between customers, LCA estimates:

> **How likely is a particular response pattern within each hidden customer segment?**

Every customer receives a **posterior probability of belonging to each class**, making the segmentation probabilistic rather than purely deterministic.

---

# Dataset

The analysis uses:

```text
Purchasing_data.xlsx
```

The workbook contains survey responses describing purchasing behaviour, payment preferences, credit usage, BNPL behaviour, and customer characteristics.

An important structural feature of the dataset is that the workbook contains the **question wording within the data structure**, allowing the analysis to preserve a questionnaire dictionary linking variable codes to their underlying questions.

The original dataset is retained unchanged.

---

# Analytical Population

Not every survey respondent is appropriate for credit-card behavioural segmentation.

The workflow therefore explicitly distinguishes between respondents such as:

* active credit-card users;
* respondents reporting no credit-card use during the relevant period;
* customers with zero usual credit-card balance;
* customers reporting no recent credit-card purchasing activity;
* respondents with incomplete core responses; and
* records affected by other questionnaire-routing patterns.

Only respondents satisfying the defined behavioural eligibility criteria and containing complete responses across the five segmentation indicators are included in the LCA model.

This is an important methodological decision.

### Structural Missingness ≠ Random Missingness

Survey questionnaires frequently use skip logic.

A blank response may therefore mean:

> “This question did not apply to the respondent.”

rather than:

> “The respondent failed to answer.”

For this reason, the project does **not automatically impute structurally missing behavioural responses**.

Doing so could create artificial customer behaviour and distort the segmentation.

---

# Segmentation Variables

Five behavioural indicators form the core of the Latent Class Analysis.

| Variable | Behavioural Construct                      | Marketing Interpretation                                   |
| -------- | ------------------------------------------ | ---------------------------------------------------------- |
| **Q02**  | Number of credit cards                     | Relationship depth and breadth of card ownership           |
| **Q03**  | Usual monthly credit-card balance          | Level of credit activity/exposure                          |
| **Q04**  | Full-balance repayment behaviour           | Distinguishes transactors from customers carrying balances |
| **Q05**  | Share of purchases made using credit cards | Measures card engagement and share of wallet               |
| **Q10**  | BNPL awareness and usage                   | Captures openness to emerging digital-credit products      |

Together, these variables capture several complementary dimensions of financial behaviour rather than relying on a single measure of spending.

---

# Data Preparation

The data-preparation process was designed to preserve the original meaning of the survey.

## 1. Workbook Import

The Excel dataset is imported using `readxl`.

The script checks that the required file exists before proceeding:

```r
Purchasing_data.xlsx
```

This prevents the model from silently running without the expected input data.

---

## 2. Questionnaire Dictionary

The survey structure is used to build a dictionary connecting:

```text
Variable Code → Original Survey Question
```

This makes later outputs easier to interpret and improves traceability between the analysis and source questionnaire.

---

## 3. Text Standardization

Known text-quality issues are corrected programmatically.

For example, inconsistent labels such as:

```text
Paypal → PayPal
```

are standardized while the original workbook remains unchanged.

---

## 4. Respondent Identification

Unique respondent identifiers and original Excel row references are created so analytical outputs can be traced back to the source data when necessary.

---

## 5. Duplicate Assessment

Potential duplicate survey records are checked before modelling.

Identifier fields are excluded from the comparison so duplicate detection evaluates the substantive questionnaire responses.

---

## 6. Missingness Profiling

The workflow calculates, for each source variable:

* total observations;
* non-missing observations;
* number missing;
* percentage missing;
* number of unique valid responses;
* most common response; and
* frequency of the most common response.

This provides a systematic view of data quality before segmentation begins.

---

## 7. Questionnaire-Routing Audit

Respondents are classified according to their eligibility and questionnaire path.

This ensures that structural blanks generated by survey design are not treated as ordinary missing values.

---

# Categorical Encoding

The original behavioural categories are validated before conversion.

Examples include:

### Number of Credit Cards

```text
One
Two
Three
Four
Five
More than five
```

### Full-Balance Repayment

```text
Never
Rarely
Sometimes
Usually
Always
```

### Credit-Card Share of Purchases

```text
Less than 20 percent
20% to less than 40%
40% to less than 60%
60% to less than 80%
At least 80%
```

### BNPL Usage

```text
Have not heard of BNPL
Never
Once
A few times
Many times
```

These categories are converted to positive integers because `poLCA` requires categorical outcomes to be encoded numerically.

Importantly, these numbers are used as **category identifiers**, not continuous measurements.

The model does not assume that the distance between categories is numerically equal.

---

# Latent Class Modelling

The LCA model is estimated using the R package:

```r
poLCA
```

The general model specification is:

```r
cbind(
    cards_cat,
    balance_cat,
    payoff_cat,
    share_cat,
    bnpl_cat
) ~ 1
```

No covariates are used to form the classes directly.

This makes the primary segmentation **behaviour-driven**, allowing demographic and other variables to be used later for segment profiling and validation.

---

# Competing Model Evaluation

A major strength of the project is that the number of customer segments is **not assumed beforehand**.

The workflow estimates models containing:

```text
1 to 10 latent classes
```

and evaluates them comparatively.

For the multi-class models, multiple randomized starting values are used to reduce the probability that the optimization process becomes trapped in a poor local solution.

The modelling configuration includes:

```text
Candidate classes: 1–10
Random starts:     50
Maximum iterations: 5,000
```

This provides a much stronger modelling process than simply fitting a single arbitrary number of clusters.

---

# Model Selection

Each candidate model is evaluated using several statistical measures.

## Bayesian Information Criterion — BIC

The primary model-selection criterion is **BIC**.

Conceptually:

```text
BIC = Model Fit + Complexity Penalty
```

Lower values are preferred.

BIC rewards improved model fit while penalizing models that become unnecessarily complicated simply because additional classes have been added.

The final class count is therefore selected using the:

> **Minimum-BIC solution**

rather than choosing a convenient number of segments manually.

---

## Additional Model Diagnostics

Model comparison also considers:

* **Log-likelihood**
* **AIC**
* **BIC**
* **Likelihood-ratio G²**
* **Pearson X²**
* **Residual degrees of freedom**
* **Normalized entropy**
* **Average maximum posterior probability**
* **Smallest class proportion**
* **Number of model iterations**
* **Frequency with which randomized starts reached the best solution**

These measures provide complementary information about model fit, separation, stability, and practical usefulness.

---

# Model Stability and Convergence

LCA likelihood functions may contain multiple local optima.

For this reason, a model can technically “converge” while still reaching an inferior solution.

The project addresses this risk by:

1. fitting models from multiple randomized starting points;
2. recording how often the best likelihood is reproduced;
3. checking whether models reach the maximum iteration threshold;
4. retaining numerical-restart warnings;
5. checking for very small latent classes; and
6. refitting the selected model using the best starting values before final interpretation.

These controls improve the reliability and reproducibility of the final segmentation.

---

# Customer Membership

LCA does not simply assign a customer to a segment without qualification.

For each respondent, the model produces probabilities such as:

```text
P(Class 1 | responses)
P(Class 2 | responses)
P(Class 3 | responses)
...
```

The customer is assigned to the class with the highest posterior probability.

The workflow additionally records:

```text
Maximum posterior probability
```

for every respondent.

This provides a measure of how clearly the model can classify each customer.

---

# Membership Uncertainty

The analysis uses an operational review threshold of:

```text
Maximum Posterior Probability < 0.60
```

Customers below this threshold are flagged as having relatively uncertain membership.

This does **not** mean those observations are invalid or should automatically be removed.

Instead, it identifies customers whose behaviour overlaps multiple segments and therefore warrants additional care when using hard segment assignments operationally.

This distinction is particularly important in marketing because real customers frequently exist between simplified persona boundaries.

---

# Business-Oriented Segment Labels

Latent classes are originally identified only by arbitrary numbers:

```text
Class 1
Class 2
Class 3
...
```

Those numbers have no intrinsic business meaning.

The project therefore derives segment labels from the estimated behavioural profiles rather than assuming that a particular class number always represents the same type of customer.

When the selected solution contains four behavioural classes, the framework maps them into the following interpretable personas:

### 1. High-Use Transactors

Customers characterized by stronger card engagement combined with comparatively strong full-balance repayment behaviour.

**Possible business interpretation:**

* active card users;
* potentially valuable transaction customers;
* likely to value convenience and rewards;
* opportunities may centre on loyalty, rewards, premium benefits, and maintaining share of wallet.

---

### 2. Light or Occasional Users

Customers with relatively weaker credit-card engagement compared with more active segments.

**Possible business interpretation:**

* lower card usage;
* potentially lower share of wallet;
* may require activation rather than retention campaigns;
* relevant strategies could include introductory incentives or category-specific promotions.

---

### 3. BNPL-Enabled Growth Users

Customers distinguished by stronger adoption or usage of BNPL products.

**Possible business interpretation:**

* receptive to alternative and emerging payment options;
* potentially attractive for digital-first product strategies;
* may respond to flexible-payment propositions;
* important group for monitoring changes in payment preferences.

---

### 4. Balance-Carrying Revolvers

Customers comparatively more associated with carrying balances rather than consistently paying their full balances.

**Possible business interpretation:**

* different repayment profile from transactors;
* potentially significant from a lending perspective;
* requires responsible targeting;
* affordability, credit risk, and customer financial well-being should be considered alongside commercial opportunities.

---

# Segment Profiling

Segment creation is only the first stage.

The project includes a reusable profiling function:

```r
profile_by_segment()
```

This allows any source variable to be compared across the estimated customer segments.

For example:

```r
profile_by_segment("Q06")
profile_by_segment("D08")
profile_by_segment("D11")
```

The resulting output contains:

* segment;
* response category;
* number of respondents;
* segment size; and
* percentage within the segment.

This structure makes the segmentation framework reusable rather than limiting the analysis to a fixed set of manually created tables.

---

# External Segment Enrichment

A particularly important modelling choice is that several variables are **not used to create the latent classes**.

Instead, they are brought in after estimation to better understand who belongs to each class.

This separation helps avoid defining a segment and then “discovering” the same variables that were already used to create it.

Potential enrichment dimensions include:

```text
Q06
C1
D08
D09
D11
D15
D16
```

These can provide additional behavioural or demographic context to the statistically derived classes.

---

# Conditional-Probability Profiles

A core LCA output is the class-specific probability of selecting each response.

For example:

```text
P("Always pays in full" | Segment A)
```

or:

```text
P("Many BNPL uses" | Segment B)
```

These **class-conditional probabilities** form the statistical basis for interpreting the segments.

The project restructures these probabilities into a long-format profile containing:

* latent class;
* segment label;
* model variable;
* original behavioural description;
* response category; and
* conditional probability.

This allows each customer segment to be interpreted based on its complete probability profile rather than a single average.

---

# Local Independence

One of the central assumptions of standard Latent Class Analysis is **local independence**.

In simple terms:

> Once the underlying customer segment is known, the observed segmentation indicators should not retain strong unexplained relationships with one another.

The project evaluates this assumption using **bivariate residual diagnostics** for pairs of manifest variables.

For each pair, the workflow calculates measures including:

* observed versus expected response combinations;
* bivariate residual statistic;
* degrees of freedom;
* residual-to-degrees-of-freedom ratio;
* p-value;
* minimum expected count; and
* Holm-adjusted p-value.

Because multiple variable pairs are evaluated, **Holm adjustment** is used to reduce the risk of incorrectly flagging relationships simply because many tests were performed.

This moves the analysis beyond simply fitting an LCA model and reporting the resulting customer groups.

---

# Analysis Workflow

The overall analytical pipeline can be summarized as:

```text
Purchasing_data.xlsx
        │
        ▼
Import Survey Data
        │
        ▼
Preserve Questionnaire Dictionary
        │
        ▼
Clean Known Text Issues
        │
        ▼
Profile Variables & Missingness
        │
        ▼
Audit Questionnaire Routing
        │
        ▼
Identify Eligible Active Card Users
        │
        ▼
Validate Behavioural Categories
        │
        ▼
Encode Five Manifest Variables
        │
        ▼
Fit 1–10 Latent Class Models
        │
        ▼
Compare BIC / AIC / Entropy / Stability
        │
        ▼
Select Minimum-BIC Solution
        │
        ▼
Refit & Validate Final Model
        │
        ▼
Calculate Posterior Membership
        │
        ▼
Flag Ambiguous Membership
        │
        ▼
Interpret Latent Classes
        │
        ▼
Profile Behavioural & Demographic Variables
        │
        ▼
Evaluate Local Independence
        │
        ▼
Translate Findings into Marketing Insights
```

---

# Repository Structure

```text
Customer_Segmentation_LCA/
│
├── Customer_Segmentation_LCA.R
│   └── Complete reproducible R analysis
│
├── Purchasing_data.xlsx
│   └── Original purchasing survey dataset
│
├── Customer_Data_Enrichment_and_Segmentation_Report.pdf
│   └── Written analysis, interpretation, and business discussion
│
└── README.md
    └── Project documentation
```

---

# Technologies Used

## Language

* **R**

## Main Packages

| Package   | Purpose                                              |
| --------- | ---------------------------------------------------- |
| `readxl`  | Importing Excel data                                 |
| `dplyr`   | Data manipulation                                    |
| `tidyr`   | Data reshaping                                       |
| `stringr` | String cleaning                                      |
| `purrr`   | Functional programming and repeated model estimation |
| `tibble`  | Structured data frames                               |
| `readr`   | Data import/export utilities                         |
| `ggplot2` | Data visualization                                   |
| `scales`  | Plot formatting                                      |
| `cluster` | Supporting clustering/segmentation utilities         |
| `poLCA`   | Latent Class Analysis                                |

---

# How to Run the Project

## 1. Clone the Repository

```bash
git clone https://github.com/Yusuf-W-Musa/Customer_Segmentation_LCA.git
```

Move into the project directory:

```bash
cd Customer_Segmentation_LCA
```

---

## 2. Open the Project in RStudio

Ensure that the following files remain in the same working directory:

```text
Customer_Segmentation_LCA.R
Purchasing_data.xlsx
```

The analysis intentionally uses the filename directly rather than relying on a machine-specific absolute file path.

---

## 3. Install Required Packages

If the packages are not already installed:

```r
install.packages(c(
  "readxl",
  "dplyr",
  "tidyr",
  "stringr",
  "purrr",
  "tibble",
  "readr",
  "ggplot2",
  "scales",
  "cluster",
  "poLCA"
))
```

---

## 4. Run the Analysis

Run:

```r
source("Customer_Segmentation_LCA.R")
```

or open the R file in RStudio and execute it section by section.

Running section by section is particularly useful for studying:

* data-quality outputs;
* model-comparison statistics;
* class profiles;
* posterior probabilities; and
* diagnostic results.

---

# Reproducibility

Several design choices improve reproducibility:

* source data are retained separately from analytical transformations;
* required columns are validated;
* expected survey-response categories are validated;
* model settings are explicitly defined;
* random seeds are controlled for LCA estimation;
* competing model specifications are generated programmatically;
* repeated randomized starts are used;
* model-selection statistics are retained;
* convergence conditions are checked;
* posterior probabilities are preserved;
* segment labels are generated from estimated profiles instead of assumed class numbers; and
* original source-row references are retained.

As a result, the segmentation process can be rerun systematically if the source dataset is updated.

---

# Key Analytical Strengths

## 1. Method matches the data

LCA was selected because the segmentation variables are categorical survey responses.

The method therefore aligns with the measurement structure of the dataset instead of forcing the data into a clustering algorithm designed primarily for continuous measurements.

---

## 2. Segment count is data-driven

The number of segments is not chosen because four or five personas “sound reasonable.”

Models containing 1 through 10 latent classes are compared and the final choice is driven primarily by BIC alongside diagnostic evidence.

---

## 3. Multiple random starts are used

Repeated starting values reduce the chance that the selected solution represents a poor local optimum.

---

## 4. Membership uncertainty is preserved

The analysis does not pretend that every customer perfectly belongs to one discrete persona.

Posterior probabilities provide visibility into ambiguous customers.

---

## 5. Structural missingness is handled appropriately

Survey-routing blanks are treated according to the questionnaire design instead of being indiscriminately imputed.

---

## 6. Segment creation and enrichment are separated

Core behavioural variables create the segments.

Additional customer variables are subsequently used to describe and validate them.

---

## 7. LCA assumptions are examined

The workflow includes local-independence diagnostics instead of assuming that the fitted model is automatically adequate.

---

## 8. Statistical classes are translated into business language

Model classes are mapped to interpretable customer personas based on the estimated behaviour of each class rather than arbitrary class numbers.

---

# Potential Business Applications

The segmentation framework could support several practical decisions.

### Targeted Marketing

Campaigns can be differentiated according to customer behaviour rather than applying a single offer to the entire market.

### Customer Activation

Light users could be distinguished from highly engaged customers and targeted with different activation strategies.

### Rewards Strategy

High-use transactors may respond differently to rewards, loyalty programmes, and premium benefits than balance-carrying customers.

### Product Development

BNPL-oriented customers may provide insight into changing preferences toward alternative payment products.

### Cross-Selling

Customer needs can be assessed at the segment level before recommending additional products.

### Customer Retention

Behavioural profiles can help identify which value propositions may be most relevant to maintaining customer engagement.

### Responsible Credit Marketing

Balance-carrying behaviour should be considered alongside affordability, risk management, and responsible-lending principles rather than treated purely as a commercial opportunity.

---

# Important Interpretation Considerations

Latent classes should not be interpreted as absolute customer identities.

They are statistical representations of recurring response patterns.

A customer assigned to a segment may still exhibit characteristics associated with another group.

For this reason:

> **Segments should support decision-making, not replace individual-level customer information.**

Posterior membership probabilities are particularly valuable when segmentation is applied operationally.

---

# Limitations

Like any segmentation study, this analysis has limitations.

## Self-Reported Survey Data

The source variables represent respondent answers rather than directly observed transaction histories.

Survey responses may therefore contain recall error, perception bias, or response bias.

## Cross-Sectional Segmentation

The analysis primarily represents customers at the time of survey collection.

Customer behaviour may change over time.

## Conditional Independence

Standard LCA assumes that the manifest indicators become independent once latent-class membership is accounted for.

The project evaluates this assumption, but residual dependence can still affect class interpretation.

## Model Selection Is Not Purely Mechanical

Although BIC provides a principled selection criterion, a useful segmentation solution must also be:

* statistically stable;
* adequately separated;
* sufficiently large to be actionable; and
* commercially interpretable.

## Hard Assignment Loses Information

Assigning each respondent to one class simplifies operational use but discards part of the posterior-probability information.

## External Validation

The strongest business validation would involve connecting the segments to future outcomes such as:

* actual transaction value;
* retention;
* profitability;
* response to campaigns;
* delinquency;
* product adoption; or
* lifetime value.

---

# Future Enhancements

Several extensions could further strengthen the project.

### 1. Longitudinal Validation

Track whether customers remain within the same behavioural segment over time.

### 2. Transactional Enrichment

Combine survey-derived classes with actual purchase and payment histories.

### 3. Customer Lifetime Value

Compare CLV across the discovered behavioural groups.

### 4. Campaign Response Modelling

Evaluate whether segment membership predicts marketing-response differences.

### 5. Latent Class Regression

Introduce carefully selected covariates to model the probability of class membership.

### 6. Holdout Validation

Evaluate whether the discovered segmentation structure reproduces in an independent customer sample.

### 7. Alternative Segmentation Methods

Compare LCA with methods such as:

* hierarchical clustering;
* K-Modes;
* Gower-distance clustering;
* mixture models; or
* model-based ordinal clustering.

The goal would not simply be to identify which algorithm returns clusters, but which method generates the most **stable, interpretable, and actionable customer structure**.

### 8. Interactive Dashboard

The segment outputs could be connected to Power BI, Tableau, or Shiny to create an interactive segmentation dashboard for business users.

---

# Skills Demonstrated

This project demonstrates practical experience with:

**Customer Analytics**

* Customer segmentation
* Behavioural profiling
* Marketing interpretation
* Persona development

**Statistical Modelling**

* Latent Class Analysis
* Probabilistic clustering
* Model comparison
* Bayesian Information Criterion
* Entropy
* Posterior probabilities
* Local-independence diagnostics

**Data Analytics**

* Exploratory data analysis
* Data-quality auditing
* Missing-data interpretation
* Survey-routing analysis
* Categorical data preparation
* Reproducible analytical pipelines

**R Programming**

* `dplyr`
* `tidyr`
* `purrr`
* `ggplot2`
* `poLCA`
* functional programming
* custom analytical functions
* validation checks
* automated model estimation

**Business Analytics**

* Translating statistical results into customer personas
* Marketing strategy development
* Customer targeting
* Product adoption analysis
* Responsible interpretation of consumer-credit behaviour

---

# Project Deliverables

### Full R Analysis

[`Customer_Segmentation_LCA.R`](Customer_Segmentation_LCA.R)

Contains the complete data-preparation, modelling, validation, profiling, and diagnostic workflow.

### Dataset

[`Purchasing_data.xlsx`](Purchasing_data.xlsx)

Original survey dataset used for the project.

### Analytical Report

[`Customer_Data_Enrichment_and_Segmentation_Report.pdf`](Customer_Data_Enrichment_and_Segmentation_Report.pdf)

Contains the detailed written interpretation of the customer segmentation analysis and its business implications.

---

# Key Takeaway

This project demonstrates that customer segmentation should not begin by arbitrarily selecting a clustering algorithm or predetermined number of groups.

Instead, the analysis:

> **matches the modelling method to the structure of the data, evaluates competing segmentation solutions, preserves uncertainty, validates model assumptions, and only then translates statistical patterns into actionable customer personas.**

The result is a more defensible approach to behavioural segmentation — one that connects **statistical modelling, customer analytics, and practical marketing decision-making**.

---

## Author

**Yusuf Musa**

Data Analytics | Machine Learning | Business Intelligence | Customer & Marketing Analytics

GitHub: [Yusuf-W-Musa](https://github.com/Yusuf-W-Musa)

---

## Repository

[Customer_Segmentation_LCA](https://github.com/Yusuf-W-Musa/Customer_Segmentation_LCA)

---

### If you found this project useful

Feel free to explore the analysis, review the methodology, or adapt the modelling framework to other categorical customer-segmentation problems.
