# =============================================================================
# CUSTOMER SEGMENTATION ANALYSIS: PURCHASING DATA
# Method: Latent Class Analysis (LCA) for categorical survey responses
#
# PURPOSE
#   1. Import, inspect, profile, and clean the Purchasing_data.xlsx survey.
#   2. Respect questionnaire routing rather than treating structural blanks as
#      ordinary missing values.
#   3. Segment eligible active credit-card users with five behavioural
#      indicators using latent class analysis.
#   4. Select the number of segments using BIC and membership diagnostics.
#   5. Profile and externally validate the segments using variables that were
#      not used to construct them.
#   6. Export reproducible tables, figures, assignments, and the fitted model.
#
# IMPORTANT METHOD NOTE
# LCA is used because the selected variables are categorical/ordinal survey
# responses. Unlike k-means, LCA does not require artificial monetary
# midpoints, Euclidean distance, or standardization. The integer values created
# below are category labels required by poLCA; they are not treated as measured
# continuous values in model estimation.
#


#  PACKAGE AND FILE SETUP ---------------------------------------------------

# Install missing packages once from the RStudio Console if necessary:
# install.packages(c(
#   "readxl", "dplyr", "tidyr", "stringr", "purrr", "tibble",
#   "readr", "ggplot2", "scales", "cluster", "poLCA"
# ))

required_packages <- c(
  "readxl", "dplyr", "tidyr", "stringr", "purrr", "tibble",
  "readr", "ggplot2", "scales", "cluster", "poLCA"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0L) {
  stop(
    "Install the following packages before running the script: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(purrr)
  library(tibble)
  library(readr)
  library(ggplot2)
  library(scales)
  library(cluster)
  library(poLCA)
})

SEED <- 123L
N_RESTARTS <- 50L
MAX_ITERATIONS <- 5000L
CANDIDATE_CLASSES <- 1:10

# This is an operational review flag for ambiguous assignments, not a model-
# selection rule or a claim that lower-confidence respondents are invalid.
UNCERTAINTY_THRESHOLD <- 0.60

if (!file.exists("Purchasing_data.xlsx")) {
  stop(
    "Purchasing_data.xlsx was not found in the current working directory.",
    call. = FALSE
  )
}

output_dir <- "segmentation_outputs"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Input file: Purchasing_data.xlsx")
message("Outputs will be written to: ", normalizePath(output_dir, winslash = "/"))


# 1. LOAD THE WORKBOOK AND PRESERVE THE DATA DICTIONARY ----------------------

# Reading every column as text prevents mixed survey categories such as 0 and
# "Credit card" from being interpreted inconsistently across computers.
data <- read_xlsx(
  "Purchasing_data.xlsx",
  sheet = "Sheet1",
  col_types = "text"
)

if (nrow(data) < 2L) {
  stop("The workbook does not contain a question row and respondent records.")
}

# Optional RStudio checks: highlight and run any line to inspect the import.
# dim(data)
# names(data)
# glimpse(data)
# head(data)

# Excel row 1 contains short variable names. After import, the first tibble row
# contains the full question wording; genuine respondent records start after it.
question_dictionary <- tibble(
  variable = names(data),
  question = as.character(unlist(data[1, ], use.names = FALSE))
)

dat <- data[-1, ]

# Remove leading/trailing spaces but preserve the wording inside responses.
dat <- dat %>%
  mutate(across(everything(), ~ na_if(str_trim(.x), "")))

# Verify the fields used by the text-quality corrections before referencing
# them, so a structurally different workbook fails with a clear message.
cleaning_required_columns <- c("Q01_8", "D08")
missing_cleaning_columns <- setdiff(cleaning_required_columns, names(dat))

if (length(missing_cleaning_columns) > 0L) {
  stop(
    "Required cleaning variables are missing from the workbook: ",
    paste(missing_cleaning_columns, collapse = ", "),
    call. = FALSE
  )
}

# Known text-quality corrections. The original workbook remains unchanged.
dat <- dat %>%
  mutate(
    Q01_8 = recode(Q01_8, "Paypal" = "PayPal"),
    D08 = if_else(D08 == "m", NA_character_, D08)
  ) %>%
  mutate(
    respondent_id = row_number(),
    source_excel_row = respondent_id + 2L,
    .before = 1
  )

required_columns <- c(
  "Q01_3", "Q01_8", "Q02", "Q03", "Q04", "Q05", "Q06", "Q10", "C1",
  "D08", "D09", "D11", "D15", "D16"
)

missing_columns <- setdiff(required_columns, names(dat))

if (length(missing_columns) > 0L) {
  stop(
    "Required variables are missing from the workbook: ",
    paste(missing_columns, collapse = ", "),
    call. = FALSE
  )
}


# 2. INITIAL DATA PROFILING AND EXPLORATION ---------------------------------

# These five variables are the proposed class-forming indicators. Additional
# variables are profiled here so the analyst understands the broader customer
# sample before fitting any segmentation model.
manifest_raw <- c("Q02", "Q03", "Q04", "Q05", "Q10")

key_profile_variables <- c(
  manifest_raw, "Q06", "C1", "D08", "D09", "D11", "D15", "D16"
)

dataset_overview <- tibble(
  measure = c(
    "Imported rows, including the question-text row",
    "Respondent records",
    "Questionnaire variables"
  ),
  value = c(nrow(data), nrow(dat), ncol(data))
)

# Produce one concise diagnostic row for every source variable. Missingness is
# reported separately from the most common valid response because many blanks
# are created intentionally by questionnaire routing.
profile_one_variable <- function(variable_name) {
  values <- dat[[variable_name]]
  valid_values <- values[!is.na(values)]
  response_counts <- sort(table(valid_values), decreasing = TRUE)

  most_common_response <- if (length(response_counts) > 0L) {
    names(response_counts)[[1]]
  } else {
    NA_character_
  }

  most_common_n <- if (length(response_counts) > 0L) {
    as.integer(response_counts[[1]])
  } else {
    0L
  }

  tibble(
    variable = variable_name,
    question = question_dictionary$question[
      match(variable_name, question_dictionary$variable)
    ],
    total_n = length(values),
    non_missing_n = length(valid_values),
    missing_n = sum(is.na(values)),
    missing_percent = round(100 * mean(is.na(values)), 2),
    unique_valid_responses = n_distinct(valid_values),
    most_common_response = most_common_response,
    most_common_n = most_common_n,
    most_common_percent_of_valid = if (length(valid_values) > 0L) {
      round(100 * most_common_n / length(valid_values), 2)
    } else {
      NA_real_
    }
  )
}

dataset_profile <- map_dfr(
  setdiff(names(dat), c("respondent_id", "source_excel_row")),
  profile_one_variable
)

# This function makes frequency tables that can be rerun for any variable.
# Missing or skipped responses remain visible rather than being silently lost.
make_frequency_profile <- function(
    data_frame,
    variable_names,
    sample_name
) {
  missing_label <- "Missing / not asked"

  map_dfr(variable_names, function(variable_name) {
    if (!variable_name %in% names(data_frame)) {
      stop("Variable not found: ", variable_name, call. = FALSE)
    }

    response_data <- tibble(
      response = replace_na(
        as.character(data_frame[[variable_name]]),
        missing_label
      )
    ) %>%
      count(response, name = "n")

    valid_n <- sum(
      response_data$n[response_data$response != missing_label]
    )

    response_data %>%
      mutate(
        sample = sample_name,
        variable = variable_name,
        question = question_dictionary$question[
          match(variable_name, question_dictionary$variable)
        ],
        percent_of_sample = round(100 * n / sum(n), 2),
        percent_of_valid = case_when(
          response == missing_label ~ NA_real_,
          valid_n == 0L ~ NA_real_,
          TRUE ~ round(100 * n / valid_n, 2)
        )
      ) %>%
      dplyr::select(
        sample, variable, question, response, n,
        percent_of_sample, percent_of_valid
      )
  })
}

# Convenience function for interactive exploration. Examples:
# profile_variable("D11")
# profile_variable("Q05")
profile_variable <- function(
    variable_name,
    data_frame = dat,
    sample_name = "Full respondent sample"
) {
  make_frequency_profile(data_frame, variable_name, sample_name)
}

full_sample_key_distributions <- make_frequency_profile(
  dat,
  key_profile_variables,
  "Full respondent sample"
)

cat("\n", strrep("-", 72), "\n", sep = "")
cat("STEP 2: INITIAL DATA PROFILE\n")
cat(strrep("-", 72), "\n", sep = "")
print(dataset_overview)
cat("\nProfile of the proposed segmentation variables:\n")
print(
  dataset_profile %>%
    dplyr::filter(variable %in% manifest_raw) %>%
    dplyr::select(
      variable, non_missing_n, missing_n, missing_percent,
      unique_valid_responses, most_common_response,
      most_common_percent_of_valid
    )
)
cat(
  "\nObjects available for inspection: dataset_profile, ",
  "full_sample_key_distributions.\n",
  "Run profile_variable(\"variable_name\") for any source variable.\n",
  sep = ""
)


# 3. DATA-QUALITY AND QUESTIONNAIRE-ROUTING AUDIT ----------------------------

# respondent_id and source_excel_row are excluded from the duplicate test.
duplicate_count <- dat %>%
  dplyr::select(-respondent_id, -source_excel_row) %>%
  duplicated() %>%
  sum()

missingness_by_variable <- dat %>%
  dplyr::summarise(across(-c(respondent_id, source_excel_row), ~ sum(is.na(.x)))) %>%
  pivot_longer(
    cols = everything(),
    names_to = "variable",
    values_to = "missing_n"
  ) %>%
  mutate(
    total_n = nrow(dat),
    missing_percent = 100 * missing_n / total_n
  ) %>%
  arrange(desc(missing_n), variable)

# The categories below are mutually exclusive and explain the analytical flow.
dat <- dat %>%
  mutate(
    eligibility_group = case_when(
      Q01_3 == "0" ~ "No credit-card use in the past 12 months",
      Q01_3 == "Credit card" & (is.na(Q02) | is.na(Q03)) ~
        "Card selected but core responses are incomplete",
      Q03 == "Zero" ~ "Zero usual monthly credit-card balance",
      Q05 == "Never used credit card" ~
        "No recent credit-card purchase use",
      Q01_3 == "Credit card" &
        if_all(all_of(manifest_raw), ~ !is.na(.x)) ~
        "Eligible active credit-card users",
      TRUE ~ "Other incomplete routing pattern"
    )
  )

sample_flow <- dat %>%
  count(eligibility_group, name = "respondents") %>%
  mutate(percent = 100 * respondents / sum(respondents)) %>%
  arrange(desc(respondents))

if (sum(sample_flow$respondents) != nrow(dat)) {
  stop("Sample-flow categories do not reconcile to the respondent total.")
}

other_incomplete_n <- sample_flow %>%
  filter(eligibility_group == "Other incomplete routing pattern") %>%
  pull(respondents)

if (length(other_incomplete_n) == 1L && other_incomplete_n > 0L) {
  warning(
    other_incomplete_n,
    " records have a routing pattern that requires manual investigation."
  )
}

data_quality_summary <- tibble(
  metric = c(
    "Respondents in source data",
    "Variables in source data",
    "Exact duplicate records",
    "Eligible records for LCA",
    "Eligible percentage of source data"
  ),
  value = c(
    nrow(dat),
    ncol(data),
    duplicate_count,
    sum(dat$eligibility_group == "Eligible active credit-card users"),
    round(
      100 * mean(
        dat$eligibility_group == "Eligible active credit-card users"
      ),
      2
    )
  )
)

# Structural blanks are not imputed. Imputing card behaviour for respondents
# who were intentionally routed past those questions would fabricate answers.
analysis <- dat %>%
  filter(eligibility_group == "Eligible active credit-card users")

if (nrow(analysis) == 0L) {
  stop("No complete eligible records remain for latent class analysis.")
}


eligible_manifest_distributions <- make_frequency_profile(
  analysis,
  manifest_raw,
  "Eligible active-credit-card sample"
)

cat("\n", strrep("-", 72), "\n", sep = "")
cat("STEP 3: DATA QUALITY AND ANALYTICAL SAMPLE\n")
cat(strrep("-", 72), "\n", sep = "")
print(data_quality_summary)
cat("\nQuestionnaire-routing and sample flow:\n")
print(sample_flow)
cat("\nEligible-sample distributions of the five model variables:\n")
print(
  eligible_manifest_distributions %>%
    dplyr::select(variable, response, n, percent_of_sample),
  n = Inf
)


# 4. DEFINE AND VALIDATE THE FIVE MANIFEST VARIABLES -------------------------

q02_levels <- c(
  "One", "Two", "Three", "Four", "Five", "More than five"
)

q03_levels <- c(
  "Less than $500",
  "$501 to $1,000",
  "$1,001 to $2,000",
  "$2,001 to $3,000",
  "$3,001 to $4,000",
  "$4,001 to $5,000",
  "$5,001 to $7,000",
  "$7,001 to $10,000",
  "More than $10,000"
)

q04_levels <- c(
  "Never", "Rarely", "Sometimes", "Usually", "Always"
)

q05_levels <- c(
  "Less than 20 percent",
  "At least 20 percent but less than 40 percent",
  "At least 40 percent but less than 60 percent",
  "At least 60 percent but less than 80 percent",
  "At least 80 percent"
)

q10_levels <- c(
  "I have not heard of BNPL.",
  "Never",
  "Once",
  "A few times",
  "Many times"
)

validate_levels <- function(x, expected_levels, variable_name) {
  unexpected <- setdiff(unique(na.omit(x)), expected_levels)

  if (length(unexpected) > 0L) {
    stop(
      "Unexpected response level(s) in ", variable_name, ": ",
      paste(unexpected, collapse = " | "),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_levels(analysis$Q02, q02_levels, "Q02")
validate_levels(analysis$Q03, q03_levels, "Q03")
validate_levels(analysis$Q04, q04_levels, "Q04")
validate_levels(analysis$Q05, q05_levels, "Q05")
validate_levels(analysis$Q10, q10_levels, "Q10")

# poLCA requires response categories to be positive integers beginning at 1.
# These are categorical labels; their numerical spacing is not used as a
# Euclidean distance or a continuous measurement scale.
analysis <- analysis %>%
  mutate(
    cards_cat = match(Q02, q02_levels),
    balance_cat = match(Q03, q03_levels),
    payoff_cat = match(Q04, q04_levels),
    share_cat = match(Q05, q05_levels),
    bnpl_cat = match(Q10, q10_levels)
  )

manifest_coded <- c(
  "cards_cat", "balance_cat", "payoff_cat", "share_cat", "bnpl_cat"
)

if (anyNA(analysis[manifest_coded])) {
  stop("At least one manifest-variable response was not coded successfully.")
}

selected_variables <- tibble(
  source_variable = manifest_raw,
  model_variable = manifest_coded,
  construct = c(
    "Credit-card portfolio breadth",
    "Usual monthly balance intensity",
    "Full-balance repayment behaviour",
    "Credit-card share of purchases",
    "BNPL awareness and adoption"
  ),
  marketing_relevance = c(
    "Shows relationship depth and competitive card ownership.",
    "Distinguishes low-balance activity from high credit exposure.",
    "Separates full-paying transactors from balance-carrying customers.",
    "Measures card engagement and share of wallet.",
    "Captures openness to newer digital-credit products."
  )
)

cat("\n", strrep("-", 72), "\n", sep = "")
cat("STEP 4: SELECTED SEGMENTATION VARIABLES\n")
cat(strrep("-", 72), "\n", sep = "")
print(selected_variables)

lca_data <- analysis %>%
  dplyr::select(all_of(manifest_coded)) %>%
  as.data.frame()


# 5. FIT COMPETING LATENT CLASS MODELS ---------------------------------------

lca_formula <- cbind(
  cards_cat,
  balance_cat,
  payoff_cat,
  share_cat,
  bnpl_cat
) ~ 1

fit_lca_model <- function(k) {
  
  # A one-class model does not need repeated randomized starts.
  # Models containing 2–10 classes will still use N_RESTARTS = 50.
  starts_for_model <- if (k == 1L) 1L else N_RESTARTS
  
  start_time <- Sys.time()
  
  message(
    "\nStarting ", k, "-class model with ",
    starts_for_model, " randomized start(s) at ",
    format(start_time, "%H:%M:%S")
  )
  
  flush.console()
  
  set.seed(SEED + k)
  
  fitted_model <- tryCatch(
    poLCA(
      formula = lca_formula,
      data = lca_data,
      nclass = k,
      nrep = starts_for_model,
      maxiter = MAX_ITERATIONS,
      graphs = FALSE,
      verbose = FALSE,
      calc.se = FALSE
    ),
    error = function(error_message) {
      stop(
        "The LCA failed while fitting the ",
        k,
        "-class model: ",
        conditionMessage(error_message),
        call. = FALSE
      )
    }
  )
  
  elapsed_minutes <- as.numeric(
    difftime(
      Sys.time(),
      start_time,
      units = "mins"
    )
  )
  
  message(
    "Completed ", k, "-class model",
    " | BIC = ", round(fitted_model$bic, 2),
    " | Log-likelihood = ", round(fitted_model$llik, 2),
    " | Time = ", round(elapsed_minutes, 2), " minute(s)"
  )
  
  flush.console()
  
  fitted_model
}


message(
  "\nFitting ",
  length(CANDIDATE_CLASSES),
  " competing latent-class models."
)


lca_models <- purrr::map(
  CANDIDATE_CLASSES,
  fit_lca_model
)


names(lca_models) <- paste0(
  "classes_",
  CANDIDATE_CLASSES
)


message(
  "\nAll competing latent-class models have been fitted successfully."
)

normalized_entropy <- function(posterior, k) {
  if (k <= 1L) {
    return(NA_real_)
  }

  p <- pmax(posterior, .Machine$double.eps)
  1 + sum(p * log(p)) / (nrow(p) * log(k))
}

model_selection <- map2_dfr(
  lca_models,
  CANDIDATE_CLASSES,
  function(model, k) {
    attempt_values <- model$attempts
    repeated_optimum <- if (is.null(attempt_values)) {
      NA_integer_
    } else {
      sum(abs(attempt_values - model$llik) < 1e-6)
    }

    tibble(
      classes = k,
      log_likelihood = model$llik,
      parameters = model$npar,
      AIC = model$aic,
      BIC = model$bic,
      likelihood_ratio_G2 = model$Gsq,
      pearson_X2 = model$Chisq,
      residual_df = model$resid.df,
      normalized_entropy = normalized_entropy(model$posterior, k),
      average_max_posterior = mean(apply(model$posterior, 1, max)),
      smallest_class_share = min(model$P),
      iterations = model$numiter,
      starts_reaching_best_solution = repeated_optimum
    )
  }
)

best_row <- which.min(model_selection$BIC)
best_k <- model_selection$classes[[best_row]]
best_candidate <- lca_models[[best_row]]

message("BIC-selected number of latent classes: ", best_k)

cat("\n", strrep("-", 72), "\n", sep = "")
cat("STEP 5: LATENT-CLASS MODEL COMPARISON\n")
cat(strrep("-", 72), "\n", sep = "")
print(
  model_selection %>%
    dplyr::select(
      classes, log_likelihood, AIC, BIC, normalized_entropy,
      average_max_posterior, smallest_class_share
    )
)
cat("\nMinimum-BIC solution: ", best_k, " classes.\n", sep = "")

# Refit the selected solution from its best starting values so standard errors
# are calculated without changing the selected optimum.
set.seed(SEED + 1000L)

final_lca <- poLCA(
  formula = lca_formula,
  data = lca_data,
  nclass = best_k,
  probs.start = best_candidate$probs.start,
  nrep = 1,
  maxiter = MAX_ITERATIONS,
  graphs = FALSE,
  verbose = FALSE,
  calc.se = TRUE
)

if (abs(final_lca$llik - best_candidate$llik) > 1e-4) {
  warning(
    "The standard-error refit did not reproduce the model-selection ",
    "log-likelihood exactly. Inspect the model before reporting results."
  )
}

if (any(map_lgl(lca_models, ~ .x$numiter >= MAX_ITERATIONS))) {
  warning(
    "At least one candidate model reached the iteration limit. Review the ",
    "model-selection output before reporting the selected solution."
  )
}

if (final_lca$numiter >= MAX_ITERATIONS) {
  stop(
    "The selected model reached the maximum iteration limit and should not ",
    "be interpreted until convergence is achieved.",
    call. = FALSE
  )
}

if (isTRUE(final_lca$eflag)) {
  warning(
    "poLCA automatically restarted after a numerical issue. The final run ",
    "converged, but the event is retained as a diagnostic warning."
  )
}

if (min(final_lca$P) < 0.05) {
  warning(
    "The selected solution contains a class smaller than 5% of the analytical ",
    "sample. Confirm that it is stable and commercially meaningful."
  )
}


# 6. ASSIGN MEMBERSHIP AND CREATE REPRODUCIBLE BUSINESS LABELS ---------------

posterior_df <- as.data.frame(final_lca$posterior)
names(posterior_df) <- paste0("posterior_class_", seq_len(best_k))

analysis <- bind_cols(analysis, posterior_df) %>%
  mutate(
    class_id = final_lca$predclass,
    max_posterior = apply(final_lca$posterior, 1, max),
    uncertain_membership = max_posterior < UNCERTAINTY_THRESHOLD
  )

# Expected category positions are used only to summarize and label classes.
expected_category_score <- function(probability_matrix) {
  as.vector(
    probability_matrix %*% seq_len(ncol(probability_matrix))
  )
}

class_scores <- tibble(
  class_id = seq_len(best_k),
  cards_score = expected_category_score(final_lca$probs$cards_cat),
  balance_score = expected_category_score(final_lca$probs$balance_cat),
  payoff_score = expected_category_score(final_lca$probs$payoff_cat),
  share_score = expected_category_score(final_lca$probs$share_cat),
  bnpl_score = expected_category_score(final_lca$probs$bnpl_cat)
)

# Latent class numbers are arbitrary. If four classes are selected, labels are
# assigned from their empirical profiles rather than hardcoded class numbers.
if (best_k == 4L) {
  all_ids <- class_scores$class_id

  bnpl_id <- class_scores$class_id[which.max(class_scores$bnpl_score)]
  remaining_ids <- setdiff(all_ids, bnpl_id)

  revolver_id <- remaining_ids[
    which.min(
      class_scores$payoff_score[
        match(remaining_ids, class_scores$class_id)
      ]
    )
  ]
  remaining_ids <- setdiff(remaining_ids, revolver_id)

  transactor_index <-
    class_scores$payoff_score[match(remaining_ids, class_scores$class_id)] +
    class_scores$share_score[match(remaining_ids, class_scores$class_id)]

  transactor_id <- remaining_ids[which.max(transactor_index)]
  light_user_id <- setdiff(remaining_ids, transactor_id)

  segment_map <- tibble(
    class_id = c(transactor_id, light_user_id, bnpl_id, revolver_id),
    segment = c(
      "High-Use Transactors",
      "Light or Occasional Users",
      "BNPL-Enabled Growth Users",
      "Balance-Carrying Revolvers"
    )
  )
} else {
  warning(
    "BIC did not select four classes. Generic labels are being retained; ",
    "review the class profiles before assigning business personas."
  )

  segment_map <- tibble(
    class_id = seq_len(best_k),
    segment = paste("Segment", seq_len(best_k))
  )
}

segment_order <- segment_map$segment

analysis <- analysis %>%
  left_join(segment_map, by = "class_id") %>%
  mutate(segment = factor(segment, levels = segment_order))

class_scores <- class_scores %>%
  left_join(segment_map, by = "class_id") %>%
  mutate(segment = factor(segment, levels = segment_order))

segment_sizes <- analysis %>%
  count(class_id, segment, name = "assigned_n") %>%
  mutate(
    assigned_percent = 100 * assigned_n / sum(assigned_n),
    model_estimated_share = final_lca$P[class_id],
    average_max_posterior = map_dbl(
      class_id,
      ~ mean(analysis$max_posterior[analysis$class_id == .x])
    ),
    uncertain_n = map_int(
      class_id,
      ~ sum(analysis$uncertain_membership[analysis$class_id == .x])
    ),
    uncertain_percent = 100 * uncertain_n / assigned_n
  )


# 7. FLEXIBLE PROFILING OF ANY VARIABLE BY SEGMENT ---------------------------

# Use this function after the model has been fitted to examine any original
# survey variable across the customer segments. It returns both counts and
# within-segment percentages and keeps missing responses visible.
profile_by_segment <- function(variable_name) {
  if (length(variable_name) != 1L || !variable_name %in% names(analysis)) {
    stop(
      "Supply one valid variable name from the analysis data.",
      call. = FALSE
    )
  }

  analysis %>%
    transmute(
      segment,
      response = replace_na(
        as.character(.data[[variable_name]]),
        "Missing"
      )
    ) %>%
    count(segment, response, name = "n") %>%
    group_by(segment) %>%
    mutate(
      segment_n = sum(n),
      percent_within_segment = round(100 * n / segment_n, 2)
    ) %>%
    ungroup() %>%
    mutate(
      variable = variable_name,
      question = question_dictionary$question[
        match(variable_name, question_dictionary$variable)
      ],
      .before = response
    ) %>%
    arrange(segment, desc(n))
}

segment_profile_variables <- unique(c(
  manifest_raw, "Q06", "C1", "D08", "D09", "D11", "D15", "D16"
))

segment_variable_profiles <- map_dfr(
  segment_profile_variables,
  profile_by_segment
)

# Ready-to-run examples retained as separate objects in the Global Environment.
profile_Q06 <- profile_by_segment("Q06")
profile_D08 <- profile_by_segment("D08")
profile_D11 <- profile_by_segment("D11")

cat("\n", strrep("-", 72), "\n", sep = "")
cat("STEP 7: INITIAL CUSTOMER-SEGMENT PROFILE\n")
cat(strrep("-", 72), "\n", sep = "")
print(segment_sizes)
cat("\nExample: change in credit-card use (Q06) by segment:\n")
print(profile_Q06, n = Inf)
cat(
  "\nRun profile_by_segment(\"D08\"), profile_by_segment(\"D11\"), ",
  "or any other source variable to see its segment profile.\n",
  sep = ""
)


# 8. CLASS-CONDITIONAL PROBABILITY PROFILES ---------------------------------

category_labels <- list(
  cards_cat = q02_levels,
  balance_cat = q03_levels,
  payoff_cat = q04_levels,
  share_cat = q05_levels,
  bnpl_cat = q10_levels
)

variable_labels <- c(
  cards_cat = "Number of credit cards",
  balance_cat = "Usual monthly balance",
  payoff_cat = "Pays full balance",
  share_cat = "Credit-card share of purchases",
  bnpl_cat = "BNPL awareness and use"
)

probability_profiles <- imap_dfr(
  final_lca$probs,
  function(probability_matrix, variable_name) {
    labels <- category_labels[[variable_name]]

    if (length(labels) != ncol(probability_matrix)) {
      stop(
        "Category labels do not match the fitted probabilities for ",
        variable_name,
        call. = FALSE
      )
    }

    probability_df <- as.data.frame(probability_matrix)
    names(probability_df) <- labels
    probability_df$class_id <- seq_len(nrow(probability_df))

    probability_df %>%
      pivot_longer(
        cols = -class_id,
        names_to = "response_category",
        values_to = "conditional_probability"
      ) %>%
      mutate(
        model_variable = variable_name,
        variable = unname(variable_labels[[variable_name]]),
        .before = response_category
      )
  }
) %>%
  left_join(segment_map, by = "class_id") %>%
  mutate(segment = factor(segment, levels = segment_order))


# 8A. CHECK THE LCA LOCAL-INDEPENDENCE ASSUMPTION ----------------------------

# Under local independence, each pair of manifest variables should be
# independent after conditioning on latent class. The bivariate-residual (BVR)
# diagnostic compares observed two-way counts with counts expected by the
# fitted LCA. Holm-adjusted p-values are included because ten pairs are tested.
manifest_pairs <- combn(manifest_coded, 2, simplify = FALSE)

calculate_bivariate_residual <- function(variable_pair) {
  variable_1 <- variable_pair[[1]]
  variable_2 <- variable_pair[[2]]

  observed <- table(lca_data[[variable_1]], lca_data[[variable_2]])

  expected_probability <- matrix(
    0,
    nrow = ncol(final_lca$probs[[variable_1]]),
    ncol = ncol(final_lca$probs[[variable_2]])
  )

  for (class_number in seq_len(best_k)) {
    expected_probability <- expected_probability +
      final_lca$P[[class_number]] *
      outer(
        final_lca$probs[[variable_1]][class_number, ],
        final_lca$probs[[variable_2]][class_number, ]
      )
  }

  expected <- nrow(lca_data) * expected_probability
  bvr <- sum((observed - expected)^2 / pmax(expected, .Machine$double.eps))
  df <- (nrow(observed) - 1L) * (ncol(observed) - 1L)

  tibble(
    variable_1 = variable_1,
    variable_2 = variable_2,
    bivariate_residual = bvr,
    df = df,
    bvr_to_df_ratio = bvr / df,
    p_value = pchisq(bvr, df = df, lower.tail = FALSE),
    minimum_expected_count = min(expected)
  )
}

local_independence_diagnostics <- map_dfr(
  manifest_pairs,
  calculate_bivariate_residual
) %>%
  mutate(
    p_value_adjusted_holm = p.adjust(p_value, method = "holm"),
    flagged_after_adjustment = p_value_adjusted_holm < 0.05
  ) %>%
  arrange(desc(bvr_to_df_ratio))

# Convert expected category positions to comparable 0-100 profile indices.
# These indices visualize relative position within each variable's categories;
# they are not monetary values or percentages from the original questions.
profile_heatmap_data <- class_scores %>%
  transmute(
    class_id,
    segment,
    `Number of credit cards` = 100 * (cards_score - 1) / 5,
    `Usual monthly balance` = 100 * (balance_score - 1) / 8,
    `Pays full balance` = 100 * (payoff_score - 1) / 4,
    `Credit-card share of purchases` = 100 * (share_score - 1) / 4,
    `BNPL awareness and use` = 100 * (bnpl_score - 1) / 4
  ) %>%
  pivot_longer(
    cols = -c(class_id, segment),
    names_to = "indicator",
    values_to = "relative_index"
  )


# 9. EXTERNAL PROFILING AND VALIDATION ---------------------------------------

# These variables were not used to construct the latent classes. They are used
# after segmentation to assess whether the classes differ on relevant customer
# characteristics. Results are descriptive associations, not causal effects.
analysis <- analysis %>%
  mutate(
    usage_increased = Q06 %in% c(
      "Increased somewhat", "Increased significantly"
    ),
    high_income = D11 %in% c(
      "Between $75,000 and $99,999", "More than $100,000"
    ),
    high_credit_score = case_when(
      C1 %in% c("751 to 800", "801 to 850") ~ TRUE,
      C1 == "I do not know/am not sure" ~ NA,
      !is.na(C1) ~ FALSE,
      TRUE ~ NA
    ),
    age_65_plus = D08 == "65 or older",
    graduate_degree = D09 == "Graduate or professional degree",
    financial_strain = D15 == paste(
      "I live paycheck to paycheck and have difficulty paying",
      "my bills each month."
    ),
    high_emergency_savings = D16 == "More than $25,000"
  )

external_profile <- analysis %>%
  group_by(class_id, segment) %>%
  summarise(
    respondents = n(),
    pct_usage_increased = 100 * mean(usage_increased, na.rm = TRUE),
    pct_high_income = 100 * mean(high_income, na.rm = TRUE),
    pct_high_credit_score = 100 * mean(
      high_credit_score,
      na.rm = TRUE
    ),
    pct_age_65_plus = 100 * mean(age_65_plus, na.rm = TRUE),
    pct_graduate_degree = 100 * mean(graduate_degree, na.rm = TRUE),
    pct_financial_strain = 100 * mean(financial_strain, na.rm = TRUE),
    pct_high_emergency_savings = 100 * mean(
      high_emergency_savings,
      na.rm = TRUE
    ),
    .groups = "drop"
  ) %>%
  mutate(across(starts_with("pct_"), ~ round(.x, 1)))

association_test <- function(data, variable_name, simulation_seed) {
  test_data <- data %>%
    dplyr::select(segment, all_of(variable_name)) %>%
    drop_na() %>%
    mutate(segment = droplevels(segment))

  contingency_table <- table(
    test_data$segment,
    test_data[[variable_name]]
  )

  asymptotic_test <- suppressWarnings(
    chisq.test(contingency_table, correct = FALSE)
  )

  sparse_expected_counts <- any(asymptotic_test$expected < 5)

  if (sparse_expected_counts) {
    set.seed(simulation_seed)
    reported_test <- suppressWarnings(
      chisq.test(
        contingency_table,
        simulate.p.value = TRUE,
        B = 10000
      )
    )
    p_method <- "Monte Carlo chi-square p-value (10,000 replicates)"
  } else {
    reported_test <- asymptotic_test
    p_method <- "Asymptotic Pearson chi-square p-value"
  }

  n_total <- sum(contingency_table)
  minimum_dimension <- min(dim(contingency_table) - 1L)

  cramers_v <- if (minimum_dimension > 0L) {
    sqrt(
      as.numeric(asymptotic_test$statistic) /
        (n_total * minimum_dimension)
    )
  } else {
    NA_real_
  }

  tibble(
    external_variable = variable_name,
    n = n_total,
    chi_square = as.numeric(asymptotic_test$statistic),
    df = as.numeric(asymptotic_test$parameter),
    p_value = reported_test$p.value,
    cramers_v = cramers_v,
    minimum_expected_count = min(asymptotic_test$expected),
    p_value_method = p_method
  )
}

external_validation_variables <- c(
  "Q06", "D11", "D15", "D16", "D08", "D09", "C1"
)

external_validation <- map2_dfr(
  external_validation_variables,
  SEED + seq_along(external_validation_variables),
  ~ association_test(analysis, .x, .y)
) %>%
  mutate(
    p_value_adjusted_holm = p.adjust(p_value, method = "holm"),
    significant_after_adjustment = p_value_adjusted_holm < 0.05
  )


# 9A. K-MEANS SENSITIVITY CHECK ----------------------------------------------

# K-means is not the primary method because these are categorical indicators.
# It is fitted only as a robustness comparison using the same ordered category
# codes, the same number of groups, standardization, and many random starts.
kmeans_input <- scale(analysis[manifest_coded])

set.seed(SEED)
kmeans_sensitivity <- kmeans(
  kmeans_input,
  centers = best_k,
  nstart = 100,
  iter.max = 100
)

kmeans_silhouette <- mean(
  cluster::silhouette(
    kmeans_sensitivity$cluster,
    dist(kmeans_input)
  )[, "sil_width"]
)

adjusted_rand_index <- function(labels_1, labels_2) {
  contingency <- table(labels_1, labels_2)
  choose_two <- function(x) x * (x - 1) / 2

  observed_index <- sum(choose_two(contingency))
  row_index <- sum(choose_two(rowSums(contingency)))
  column_index <- sum(choose_two(colSums(contingency)))
  total_pairs <- choose_two(sum(contingency))

  expected_index <- row_index * column_index / total_pairs
  maximum_index <- 0.5 * (row_index + column_index)
  denominator <- maximum_index - expected_index

  if (denominator == 0) {
    return(NA_real_)
  }

  (observed_index - expected_index) / denominator
}

kmeans_comparison <- tibble(
  latent_classes = best_k,
  kmeans_average_silhouette = kmeans_silhouette,
  adjusted_rand_index_vs_lca = adjusted_rand_index(
    analysis$class_id,
    kmeans_sensitivity$cluster
  ),
  interpretation = paste(
    "A sensitivity analysis only; LCA remains primary because the",
    "manifest variables are categorical."
  )
)


# 10. PUBLICATION-QUALITY VISUALIZATIONS -------------------------------------

segment_palette <- c(
  "High-Use Transactors" = "#0072B2",
  "Light or Occasional Users" = "#999999",
  "BNPL-Enabled Growth Users" = "#E69F00",
  "Balance-Carrying Revolvers" = "#D55E00"
)

if (best_k != 4L) {
  generic_colours <- grDevices::hcl.colors(best_k, palette = "Dark 3")
  segment_palette <- setNames(generic_colours, segment_order)
}

report_theme <- theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    plot.subtitle = element_text(colour = "#4B5563"),
    panel.grid.minor = element_blank(),
    legend.position = "bottom"
  )

# Figure 1: statistical evidence for the selected number of classes.
bic_plot <- ggplot(
  model_selection,
  aes(x = classes, y = BIC)
) +
  geom_line(linewidth = 0.8, colour = "#4B5563") +
  geom_point(size = 2.8, colour = "#4B5563") +
  geom_point(
    data = filter(model_selection, classes == best_k),
    size = 4,
    colour = "#D55E00"
  ) +
  geom_text(
    data = filter(model_selection, classes == best_k),
    aes(label = paste0("Selected: ", classes, " classes")),
    vjust = -1,
    colour = "#D55E00",
    fontface = "bold",
    size = 3.7
  ) +
  scale_x_continuous(breaks = CANDIDATE_CLASSES) +
  labs(
    title = "Latent Class Model Selection",
    subtitle = "The preferred solution minimizes the Bayesian Information Criterion (BIC)",
    x = "Number of latent classes",
    y = "BIC (lower is better)"
  ) +
  report_theme

# Figure 2: number and share of customers assigned to each segment.
segment_size_plot <- ggplot(
  segment_sizes,
  aes(x = segment, y = assigned_n, fill = segment)
) +
  geom_col(width = 0.70, show.legend = FALSE) +
  geom_text(
    aes(
      label = paste0(
        scales::comma(assigned_n),
        " (", round(assigned_percent, 1), "%)"
      )
    ),
    vjust = -0.5,
    size = 3.6
  ) +
  scale_fill_manual(values = segment_palette) +
  scale_y_continuous(
    labels = scales::comma,
    expand = expansion(mult = c(0, 0.14))
  ) +
  labs(
    title = "Customer Segment Sizes",
    subtitle = paste0(
      "Modal class assignments among ",
      scales::comma(nrow(analysis)),
      " eligible respondents"
    ),
    x = NULL,
    y = "Customers"
  ) +
  report_theme +
  theme(axis.text.x = element_text(angle = 18, hjust = 1))

# Figure 3: compact comparison of the five class-defining indicators.
profile_heatmap <- ggplot(
  profile_heatmap_data,
  aes(x = indicator, y = segment, fill = relative_index)
) +
  geom_tile(colour = "white", linewidth = 0.8) +
  geom_text(
    aes(label = round(relative_index)),
    colour = "white",
    fontface = "bold",
    size = 3.6
  ) +
  scale_fill_gradient(
    low = "#BFD7E5",
    high = "#084C7A",
    limits = c(0, 100),
    name = "Relative\nindex"
  ) +
  labs(
    title = "Behavioural Profile of the Customer Segments",
    subtitle = "Higher values indicate a higher expected position within each survey scale",
    x = NULL,
    y = NULL
  ) +
  report_theme +
  theme(axis.text.x = element_text(angle = 28, hjust = 1))

# Figure 4: uncertainty is retained rather than hidden.
membership_plot <- ggplot(
  analysis,
  aes(x = segment, y = max_posterior, fill = segment)
) +
  geom_boxplot(alpha = 0.85, outlier.alpha = 0.20, show.legend = FALSE) +
  geom_hline(
    yintercept = UNCERTAINTY_THRESHOLD,
    linetype = "dashed",
    colour = "#D55E00"
  ) +
  scale_fill_manual(values = segment_palette) +
  scale_y_continuous(
    limits = c(0, 1),
    labels = scales::percent_format(accuracy = 1)
  ) +
  labs(
    title = "Confidence in Segment Assignment",
    subtitle = paste0(
      "Dashed line indicates the ",
      scales::percent(UNCERTAINTY_THRESHOLD),
      " uncertainty threshold"
    ),
    x = NULL,
    y = "Maximum posterior membership probability"
  ) +
  report_theme +
  theme(axis.text.x = element_text(angle = 18, hjust = 1))

# Figure 5: selected external variables that did not form the classes.
external_plot_data <- external_profile %>%
  dplyr::select(
    segment,
    pct_usage_increased,
    pct_high_income,
    pct_financial_strain,
    pct_high_emergency_savings
  ) %>%
  pivot_longer(
    cols = -segment,
    names_to = "metric",
    values_to = "percent"
  ) %>%
  mutate(
    metric = recode(
      metric,
      pct_usage_increased = "Credit-card usage increased",
      pct_high_income = "Income of $75,000 or more",
      pct_financial_strain = "Difficulty paying monthly bills",
      pct_high_emergency_savings = "Emergency savings above $25,000"
    )
  )

external_profile_plot <- ggplot(
  external_plot_data,
  aes(x = segment, y = percent, fill = segment)
) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = paste0(percent, "%")), hjust = -0.1, size = 3) +
  facet_wrap(~ metric, ncol = 2, scales = "free_y") +
  coord_flip() +
  scale_fill_manual(values = segment_palette) +
  scale_y_continuous(
    limits = c(0, NA),
    expand = expansion(mult = c(0, 0.16))
  ) +
  labs(
    title = "External Profile of the Customer Segments",
    subtitle = "These characteristics were not used to construct the latent classes",
    x = NULL,
    y = "Percentage of segment"
  ) +
  report_theme

print(bic_plot)
print(segment_size_plot)
print(profile_heatmap)
print(membership_plot)
print(external_profile_plot)


# 11. EXPORT TABLES, FIGURES, ASSIGNMENTS, AND MODEL --------------------------

write_csv(question_dictionary, file.path(output_dir, "question_dictionary.csv"))
write_csv(dataset_overview, file.path(output_dir, "dataset_overview.csv"))
write_csv(dataset_profile, file.path(output_dir, "dataset_profile.csv"))
write_csv(
  full_sample_key_distributions,
  file.path(output_dir, "full_sample_key_variable_distributions.csv")
)
write_csv(data_quality_summary, file.path(output_dir, "data_quality_summary.csv"))
write_csv(missingness_by_variable, file.path(output_dir, "missingness_by_variable.csv"))
write_csv(sample_flow, file.path(output_dir, "sample_flow.csv"))
write_csv(
  eligible_manifest_distributions,
  file.path(output_dir, "eligible_manifest_variable_distributions.csv")
)
write_csv(selected_variables, file.path(output_dir, "selected_variables.csv"))
write_csv(model_selection, file.path(output_dir, "lca_model_selection.csv"))
write_csv(segment_map, file.path(output_dir, "segment_label_map.csv"))
write_csv(segment_sizes, file.path(output_dir, "segment_sizes.csv"))
write_csv(
  segment_variable_profiles,
  file.path(output_dir, "segment_variable_profiles.csv")
)
write_csv(class_scores, file.path(output_dir, "class_expected_scores.csv"))
write_csv(
  probability_profiles,
  file.path(output_dir, "class_conditional_probabilities.csv")
)
write_csv(
  local_independence_diagnostics,
  file.path(output_dir, "lca_local_independence_diagnostics.csv")
)
write_csv(external_profile, file.path(output_dir, "external_segment_profiles.csv"))
write_csv(
  external_validation,
  file.path(output_dir, "external_validation_tests.csv")
)
write_csv(
  kmeans_comparison,
  file.path(output_dir, "kmeans_sensitivity_comparison.csv")
)

assignment_columns <- c(
  "respondent_id", "source_excel_row",
  "Q02", "Q03", "Q04", "Q05", "Q10",
  "class_id", "segment", "max_posterior", "uncertain_membership",
  names(posterior_df)
)

customer_assignments <- analysis %>%
  dplyr::select(all_of(assignment_columns))

write_csv(
  customer_assignments,
  file.path(output_dir, "customer_segment_assignments.csv")
)

saveRDS(final_lca, file.path(output_dir, "final_lca_model.rds"))

ggsave(
  file.path(output_dir, "figure_1_bic_model_selection.png"),
  bic_plot,
  width = 8,
  height = 5,
  units = "in",
  dpi = 300,
  bg = "white"
)

ggsave(
  file.path(output_dir, "figure_2_segment_sizes.png"),
  segment_size_plot,
  width = 9,
  height = 5.5,
  units = "in",
  dpi = 300,
  bg = "white"
)

ggsave(
  file.path(output_dir, "figure_3_segment_profile_heatmap.png"),
  profile_heatmap,
  width = 10,
  height = 5.5,
  units = "in",
  dpi = 300,
  bg = "white"
)

ggsave(
  file.path(output_dir, "figure_4_membership_confidence.png"),
  membership_plot,
  width = 9,
  height = 5.5,
  units = "in",
  dpi = 300,
  bg = "white"
)

ggsave(
  file.path(output_dir, "figure_5_external_profiles.png"),
  external_profile_plot,
  width = 11,
  height = 7,
  units = "in",
  dpi = 300,
  bg = "white"
)

capture.output(
  sessionInfo(),
  file = file.path(output_dir, "session_information.txt")
)


# 12. CONCISE CONSOLE SUMMARY ------------------------------------------------

overall_average_confidence <- mean(analysis$max_posterior)
overall_uncertain_percent <- 100 * mean(analysis$uncertain_membership)

cat("\n", strrep("=", 72), "\n", sep = "")
cat("CUSTOMER SEGMENTATION ANALYSIS COMPLETED\n")
cat(strrep("=", 72), "\n", sep = "")
cat("Source respondents: ", scales::comma(nrow(dat)), "\n", sep = "")
cat("Eligible LCA respondents: ", scales::comma(nrow(analysis)), "\n", sep = "")
cat("BIC-selected classes: ", best_k, "\n", sep = "")
cat(
  "Average maximum membership probability: ",
  scales::percent(overall_average_confidence, accuracy = 0.1),
  "\n",
  sep = ""
)
cat(
  "Assignments below ",
  scales::percent(UNCERTAINTY_THRESHOLD),
  " confidence: ",
  round(overall_uncertain_percent, 1),
  "%\n",
  sep = ""
)
cat("\nSegment sizes:\n")
print(
  segment_sizes %>%
    dplyr::select(segment, assigned_n, assigned_percent, average_max_posterior)
)
cat("\nModel-selection table:\n")
print(
  model_selection %>%
    dplyr::select(
      classes, log_likelihood, AIC, BIC,
      normalized_entropy, average_max_posterior,
      smallest_class_share
    )
)
cat("\nAll outputs saved in: ", output_dir, "\n", sep = "")
cat(
  "Interactive profiling examples:\n",
  "  profile_variable(\"D11\")\n",
  "  profile_by_segment(\"D11\")\n",
  sep = ""
)
