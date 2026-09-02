#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
  library(digest)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
audit_dir <- file.path(darcio_root, "outputs", "audit")
data_dir <- file.path(darcio_root, "outputs", "data")
log_dir <- file.path(darcio_root, "outputs", "logs")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

manifest_path <- file.path(audit_dir, "REGISTRY_EXTERNAL_ACQUISITION_MANIFEST.csv")
if (!file.exists(manifest_path)) stop("Run Darcio/src/04_acquire_registry_sidra.R first")
manifest <- fread(manifest_path)[status == "used"]

uf_sigla <- c(
  "11" = "RO", "12" = "AC", "13" = "AM", "14" = "RR", "15" = "PA", "16" = "AP", "17" = "TO",
  "21" = "MA", "22" = "PI", "23" = "CE", "24" = "RN", "25" = "PB", "26" = "PE", "27" = "AL",
  "28" = "SE", "29" = "BA", "31" = "MG", "32" = "ES", "33" = "RJ", "35" = "SP", "41" = "PR",
  "42" = "SC", "43" = "RS", "50" = "MS", "51" = "MT", "52" = "GO", "53" = "DF"
)

region_from_uf <- function(uf_code) {
  code <- as.integer(uf_code)
  fifelse(code %in% 11:17, "North",
    fifelse(code %in% 21:29, "Northeast",
      fifelse(code %in% 31:35, "Southeast",
        fifelse(code %in% 41:43, "South",
          fifelse(code %in% 50:53, "Central-West", NA_character_)
        )
      )
    )
  )
}

age_group_from_label <- function(label) {
  fcase(
    label == "Menos de 15 anos", "<15",
    label == "Idade ignorada", "unknown",
    grepl("^[0-9]+ anos$", label), sub(" anos$", "", label),
    default = NA_character_
  )
}

parse_sidra_value <- function(value) {
  normalized <- fifelse(value == "-", "0", value)
  normalized[normalized %in% c("...", "..", "X", "")] <- NA_character_
  suppressWarnings(as.numeric(normalized))
}

read_query_type <- function(type) {
  selected <- manifest[query_type == type]
  if (nrow(selected) != 12L) stop("Expected 12 annual files for query type ", type)
  rbindlist(lapply(seq_len(nrow(selected)), function(i) {
    path <- file.path(project_root, selected$relative_path[[i]])
    if (!identical(digest(path, algo = "sha256", file = TRUE), selected$sha256[[i]])) {
      stop("Registry external file hash mismatch: ", path)
    }
    x <- as.data.table(fromJSON(path, simplifyDataFrame = TRUE))
    if (!identical(x$V[[1L]], "Valor")) stop("Missing SIDRA header in ", path)
    header <- x[1L]
    data <- x[-1L]
    locate_dimension <- function(title) {
      name_columns <- grep("^D[0-9]+N$", names(header), value = TRUE)
      hit <- name_columns[vapply(name_columns, function(column) identical(header[[column]][[1L]], title), logical(1L))]
      if (length(hit) != 1L) stop("Could not uniquely locate SIDRA dimension '", title, "' in ", path)
      list(name = hit, code = sub("N$", "C", hit))
    }
    uf_dimension <- locate_dimension("Unidade da Federação")
    variable_dimension <- locate_dimension("Variável")
    year_dimension <- locate_dimension("Ano")
    first_age_dimension <- locate_dimension("Grupo de idade do primeiro cônjuge")
    second_age_dimension <- locate_dimension("Grupo de idade do segundo cônjuge")
    month_dimension <- locate_dimension("Mês do registro")
    data[, `:=`(
      sidra_uf_code = as.character(get(uf_dimension$code)),
      sidra_uf_label = as.character(get(uf_dimension$name)),
      sidra_variable_code = as.character(get(variable_dimension$code)),
      sidra_variable_label = as.character(get(variable_dimension$name)),
      sidra_year_code = as.character(get(year_dimension$code)),
      sidra_year_label = as.character(get(year_dimension$name)),
      sidra_first_age_code = as.character(get(first_age_dimension$code)),
      sidra_first_age_label = as.character(get(first_age_dimension$name)),
      sidra_second_age_code = as.character(get(second_age_dimension$code)),
      sidra_second_age_label = as.character(get(second_age_dimension$name)),
      sidra_month_code = as.character(get(month_dimension$code)),
      sidra_month_label = as.character(get(month_dimension$name)),
      source_file = basename(path)
    )]
    data
  }), use.names = TRUE, fill = TRUE)
}

standardize <- function(x) {
  x[, `:=`(
    year = as.integer(sidra_year_code),
    uf_code = sidra_uf_code,
    uf = unname(uf_sigla[sidra_uf_code]),
    region = region_from_uf(sidra_uf_code),
    variable_code = sidra_variable_code,
    variable_label = sidra_variable_label,
    value_symbol = as.character(V),
    value = parse_sidra_value(as.character(V)),
    first_age_label = sidra_first_age_label,
    first_age_code = sidra_first_age_code,
    second_age_label = sidra_second_age_label,
    second_age_code = sidra_second_age_code,
    month_label = sidra_month_label,
    month_code = sidra_month_code
  )]
  x[, composition := fcase(
    variable_code == "221", "opposite_sex",
    variable_code == "4373", "male_same_sex",
    variable_code == "4374", "female_same_sex",
    default = NA_character_
  )]
  if (anyNA(x$value)) stop("Unexpected missing/suppressed SIDRA values after explicit symbol parsing")
  if (anyNA(x$uf) || anyNA(x$composition)) stop("Unexpected geography or composition code")
  x
}

first_annual <- standardize(read_query_type("first_age_annual"))
second_annual <- standardize(read_query_type("second_age_annual"))
joint_annual <- standardize(read_query_type("joint_under16_annual"))
totals_annual_raw <- standardize(read_query_type("total_annual"))
first_monthly <- standardize(read_query_type("first_age_monthly"))
second_monthly <- standardize(read_query_type("second_age_monthly"))

first_annual[, `:=`(
  age_group = age_group_from_label(first_age_label),
  sex = fifelse(variable_code %in% c("221", "4373"), "male", "female"),
  spouse_order = "first"
)]
second_annual[, `:=`(
  age_group = age_group_from_label(second_age_label),
  sex = fifelse(variable_code == "221", "female", fifelse(variable_code == "4373", "male", "female")),
  spouse_order = "second"
)]

annual_spouse_cells <- rbindlist(list(
  first_annual[, .(year, uf_code, uf, region, sex, spouse_order, age_group, composition, value)],
  second_annual[, .(year, uf_code, uf, region, sex, spouse_order, age_group, composition, value)]
))
annual_spouse_cells[, age := suppressWarnings(as.integer(age_group))]

annual_sex_specific <- annual_spouse_cells[, .(
  persons_married = sum(value),
  opposite_sex_people = sum(value[composition == "opposite_sex"]),
  same_sex_people = sum(value[composition != "opposite_sex"])
), by = .(year, uf_code, uf, region, sex, age_group, age)]
annual_combined <- annual_sex_specific[, .(
  persons_married = sum(persons_married),
  opposite_sex_people = sum(opposite_sex_people),
  same_sex_people = sum(same_sex_people)
), by = .(year, uf_code, uf, region, age_group, age)]
annual_combined[, sex := "combined"]
annual_people <- rbindlist(list(annual_sex_specific, annual_combined), use.names = TRUE)
setcolorder(annual_people, c(
  "year", "uf_code", "uf", "region", "sex", "age_group", "age",
  "persons_married", "opposite_sex_people", "same_sex_people"
))
setorder(annual_people, year, uf_code, sex, age_group)

month_codes <- as.character(5337:5348)
first_monthly[, `:=`(
  age_group = age_group_from_label(first_age_label),
  sex = fifelse(variable_code %in% c("221", "4373"), "male", "female"),
  spouse_order = "first",
  month = match(month_code, month_codes)
)]
second_monthly[, `:=`(
  age_group = age_group_from_label(second_age_label),
  sex = fifelse(variable_code == "221", "female", fifelse(variable_code == "4373", "male", "female")),
  spouse_order = "second",
  month = match(month_code, month_codes)
)]
if (anyNA(first_monthly$month) || anyNA(second_monthly$month)) stop("Unexpected registration-month code")

monthly_spouse_cells <- rbindlist(list(
  first_monthly[, .(year, month, month_code, month_label, uf_code, uf, region, sex, spouse_order, age_group, composition, value)],
  second_monthly[, .(year, month, month_code, month_label, uf_code, uf, region, sex, spouse_order, age_group, composition, value)]
))
monthly_spouse_cells[, age := as.integer(age_group)]
monthly_sex_specific <- monthly_spouse_cells[, .(
  persons_married = sum(value),
  opposite_sex_people = sum(value[composition == "opposite_sex"]),
  same_sex_people = sum(value[composition != "opposite_sex"])
), by = .(year, month, month_label, uf_code, uf, region, sex, age_group, age)]
monthly_combined <- monthly_sex_specific[, .(
  persons_married = sum(persons_married),
  opposite_sex_people = sum(opposite_sex_people),
  same_sex_people = sum(same_sex_people)
), by = .(year, month, month_label, uf_code, uf, region, age_group, age)]
monthly_combined[, sex := "combined"]
monthly_people <- rbindlist(list(monthly_sex_specific, monthly_combined), use.names = TRUE)
setcolorder(monthly_people, c(
  "year", "month", "month_label", "uf_code", "uf", "region", "sex", "age_group", "age",
  "persons_married", "opposite_sex_people", "same_sex_people"
))
setorder(monthly_people, year, month, uf_code, sex, age)

first_annual[, below_15 := first_age_label == "Menos de 15 anos"]
first_annual[, below_16 := below_15 | first_age_label == "15 anos"]
second_annual[, below_15 := second_age_label == "Menos de 15 anos"]
second_annual[, below_16 := below_15 | second_age_label == "15 anos"]
joint_annual[, `:=`(
  first_below_15 = first_age_label == "Menos de 15 anos",
  second_below_15 = second_age_label == "Menos de 15 anos",
  first_below_16 = first_age_label %in% c("Menos de 15 anos", "15 anos"),
  second_below_16 = second_age_label %in% c("Menos de 15 anos", "15 anos")
)]

keys <- c("year", "uf_code", "uf", "region", "variable_code", "composition")
first_marginal <- first_annual[, .(
  first_below_15 = sum(value[below_15]),
  first_below_16 = sum(value[below_16])
), by = keys]
second_marginal <- second_annual[, .(
  second_below_15 = sum(value[below_15]),
  second_below_16 = sum(value[below_16])
), by = keys]
joint_marginal <- joint_annual[, .(
  both_below_15 = sum(value[first_below_15 & second_below_15]),
  both_below_16 = sum(value[first_below_16 & second_below_16])
), by = keys]
total_by_composition <- totals_annual_raw[, .(total_marriages = sum(value)), by = keys]

affected <- Reduce(function(x, y) merge(x, y, by = keys, all = TRUE),
                   list(first_marginal, second_marginal, joint_marginal, total_by_composition))
affected[, `:=`(
  marriages_at_least_one_below_15 = first_below_15 + second_below_15 - both_below_15,
  affected_marriages_below_16 = first_below_16 + second_below_16 - both_below_16
)]
affected[, `:=`(
  share_at_least_one_below_15 = marriages_at_least_one_below_15 / total_marriages,
  affected_share_below_16 = affected_marriages_below_16 / total_marriages
)]
affected_all <- affected[, .(
  first_below_15 = sum(first_below_15),
  second_below_15 = sum(second_below_15),
  both_below_15 = sum(both_below_15),
  first_below_16 = sum(first_below_16),
  second_below_16 = sum(second_below_16),
  both_below_16 = sum(both_below_16),
  marriages_at_least_one_below_15 = sum(marriages_at_least_one_below_15),
  affected_marriages_below_16 = sum(affected_marriages_below_16),
  total_marriages = sum(total_marriages)
), by = .(year, uf_code, uf, region)]
affected_all[, `:=`(
  variable_code = "all",
  composition = "all",
  share_at_least_one_below_15 = marriages_at_least_one_below_15 / total_marriages,
  affected_share_below_16 = affected_marriages_below_16 / total_marriages
)]
affected_output <- rbindlist(list(affected, affected_all), use.names = TRUE, fill = TRUE)
setorder(affected_output, year, uf_code, composition)

total_output <- rbindlist(list(
  total_by_composition,
  total_by_composition[, .(total_marriages = sum(total_marriages)), by = .(year, uf_code, uf, region)][,
    `:=`(variable_code = "all", composition = "all")]
), use.names = TRUE)
setorder(total_output, year, uf_code, composition)

fwrite(annual_people, file.path(data_dir, "REGISTRY_PERSON_EVENTS_ANNUAL.csv"))
write_parquet(annual_people, file.path(data_dir, "REGISTRY_PERSON_EVENTS_ANNUAL.parquet"), compression = "zstd")
fwrite(monthly_people, file.path(data_dir, "REGISTRY_PERSON_EVENTS_MONTHLY.csv"))
write_parquet(monthly_people, file.path(data_dir, "REGISTRY_PERSON_EVENTS_MONTHLY.parquet"), compression = "zstd")
fwrite(affected_output, file.path(data_dir, "REGISTRY_AFFECTED_MARRIAGES_ANNUAL.csv"))
write_parquet(affected_output, file.path(data_dir, "REGISTRY_AFFECTED_MARRIAGES_ANNUAL.parquet"), compression = "zstd")
fwrite(total_output, file.path(data_dir, "REGISTRY_TOTAL_MARRIAGES_ANNUAL.csv"))

# Local complete-table cache validation. Exact agreement also identifies first spouse as male
# and second spouse as female for variable 221 in the official male-female table.
local_people_path <- file.path(audit_dir, "REGISTRY_SPOUSE_AGE_COUNTS.csv")
if (!file.exists(local_people_path)) stop("Run source audit before registry build")
local_people <- fread(local_people_path)[year %between% c(2013L, 2022L) &
  sex %in% c("male", "female") & age_group %in% c("<15", "15", "16", "17", "18", "19", "unknown")]
official_opposite <- annual_people[
  year %between% c(2013L, 2022L) & sex %in% c("male", "female"),
  .(year, uf, sex, age_group, official_opposite_sex_people = opposite_sex_people)
]
local_validation <- merge(
  official_opposite,
  local_people[, .(year, uf, sex, age_group, local_opposite_sex_people = persons_married)],
  by = c("year", "uf", "sex", "age_group"), all = TRUE
)
local_validation[, difference := official_opposite_sex_people - local_opposite_sex_people]
local_validation[, exact_match := !is.na(difference) & difference == 0]
fwrite(local_validation, file.path(audit_dir, "REGISTRY_LOCAL_OFFICIAL_VALIDATION.csv"))

local_total <- fread(file.path(audit_dir, "REGISTRY_VALIDATION_BY_YEAR.csv"))[
  year %between% c(2013L, 2022L), .(year, local_total_opposite_sex = total_opposite_sex_marriages)
]
official_total <- total_output[composition == "opposite_sex", .(
  official_total_opposite_sex = sum(total_marriages)
), by = year]
total_validation <- merge(local_total, official_total, by = "year", all = FALSE)
total_validation[, `:=`(
  difference = official_total_opposite_sex - local_total_opposite_sex,
  exact_match = official_total_opposite_sex == local_total_opposite_sex
)]
fwrite(total_validation, file.path(audit_dir, "REGISTRY_TOTALS_LOCAL_OFFICIAL_VALIDATION.csv"))

monthly_annualized <- monthly_people[sex %in% c("male", "female"), .(
  monthly_sum_persons = sum(persons_married),
  monthly_sum_opposite = sum(opposite_sex_people),
  monthly_sum_same_sex = sum(same_sex_people)
), by = .(year, uf, sex, age_group)]
annual_for_monthly <- annual_people[sex %in% c("male", "female") & age %between% c(15L, 19L), .(
  year, uf, sex, age_group,
  annual_persons = persons_married,
  annual_opposite = opposite_sex_people,
  annual_same_sex = same_sex_people
)]
monthly_validation <- merge(monthly_annualized, annual_for_monthly,
                            by = c("year", "uf", "sex", "age_group"), all = TRUE)
monthly_validation[, `:=`(
  persons_difference = monthly_sum_persons - annual_persons,
  opposite_difference = monthly_sum_opposite - annual_opposite,
  same_sex_difference = monthly_sum_same_sex - annual_same_sex
)]
monthly_validation[, exact_match := persons_difference == 0 & opposite_difference == 0 & same_sex_difference == 0]
fwrite(monthly_validation, file.path(audit_dir, "REGISTRY_MONTHLY_ANNUAL_VALIDATION.csv"))

validation_summary <- data.table(
  test = c(
    "local complete-table age-sex cells equal official SIDRA", "local annual opposite-sex totals equal official SIDRA",
    "monthly age-sex sums equal annual official SIDRA", "annual UF coverage", "monthly UF coverage",
    "negative annual person cells", "negative affected marriages", "affected marriages exceed total"
  ),
  checked = c(
    nrow(local_validation), nrow(total_validation), nrow(monthly_validation),
    nrow(annual_people), nrow(monthly_people), nrow(annual_people), nrow(affected_output), nrow(affected_output)
  ),
  failures = c(
    sum(is.na(local_validation$exact_match) | !local_validation$exact_match),
    sum(is.na(total_validation$exact_match) | !total_validation$exact_match),
    sum(is.na(monthly_validation$exact_match) | !monthly_validation$exact_match),
    sum(annual_people[, .(n_ufs = uniqueN(uf_code)), by = year]$n_ufs != 27L),
    sum(monthly_people[, .(n_ufs = uniqueN(uf_code)), by = year]$n_ufs != 27L),
    sum(annual_people$persons_married < 0), sum(affected_output$affected_marriages_below_16 < 0),
    sum(affected_output$affected_marriages_below_16 > affected_output$total_marriages)
  )
)
validation_summary[, passed := failures == 0]
fwrite(validation_summary, file.path(audit_dir, "REGISTRY_BUILD_TESTS.csv"))
if (any(!validation_summary$passed)) stop("Registry build validation failed; inspect REGISTRY_BUILD_TESTS.csv")

schema <- data.table(
  artifact = c(
    rep("REGISTRY_PERSON_EVENTS_ANNUAL", 5), rep("REGISTRY_PERSON_EVENTS_MONTHLY", 2),
    rep("REGISTRY_AFFECTED_MARRIAGES_ANNUAL", 3)
  ),
  field = c(
    "persons_married", "opposite_sex_people", "same_sex_people", "age_group", "geography",
    "month", "persons_married", "affected_marriages_below_16", "marriages_at_least_one_below_15", "total_marriages"
  ),
  unit = c(
    "persons", "persons", "persons", "completed-year category", "place of registration",
    "registration month", "persons", "marriages", "marriages", "marriages"
  ),
  construction = c(
    "sum of one spouse contribution per person cell; no row expansion", "variable 221, correct spouse order",
    "both spouse orders from variables 4373/4374", "<15, exact 15-19, unknown", "UF of registry office",
    "SIDRA registration month; not month of occurrence", "annual population denominator is not divided by 12",
    "first<16 + second<16 - both<16", "first<15 + second<15 - both<15", "sum of composition-specific marriages"
  ),
  source = "IBGE SIDRA table 4406, official API"
)
fwrite(schema, file.path(data_dir, "REGISTRY_SCHEMAS.csv"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("annual_person_cells=%s", format(nrow(annual_people), scientific = FALSE)),
  sprintf("monthly_person_cells=%s", format(nrow(monthly_people), scientific = FALSE)),
  sprintf("affected_marriage_cells=%s", format(nrow(affected_output), scientific = FALSE)),
  sprintf("local_validation_cells=%s", format(nrow(local_validation), scientific = FALSE)),
  sprintf("local_validation_failures=%d", sum(!local_validation$exact_match)),
  sprintf("monthly_annual_validation_failures=%d", sum(!monthly_validation$exact_match)),
  "first_spouse_male_orientation=validated against local complete tables for variable 221",
  "frequency_weights_expanded=false",
  "raw_files_modified=0",
  "max_parallel_processes=1"
)
writeLines(log_lines, file.path(log_dir, "05_build_registry.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
