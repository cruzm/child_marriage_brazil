#!/usr/bin/env Rscript

root <- file.path(normalizePath(getwd(), mustWork = TRUE), "Darcio")
local_library <- file.path(root, "library")
dir.create(local_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(local_library, .libPaths()))

required <- c(
  "data.table", "digest", "readxl", "DBI", "duckdb", "jsonlite",
  "arrow", "yaml", "survey", "fixest", "sandwich", "lmtest",
  "ggplot2", "scales", "patchwork", "xtable", "tidyselect"
)
installed <- rownames(installed.packages())
missing <- setdiff(required, installed)
if (length(missing) && identical(Sys.getenv("INSTALL_MISSING"), "1")) {
  install.packages(missing, repos = "https://cloud.r-project.org",
                   lib = local_library, Ncpus = min(4L, max(1L, parallel::detectCores() %/% 2L)))
  installed <- rownames(installed.packages())
  missing <- setdiff(required, installed)
}
if (length(missing)) {
  stop(
    "Missing R packages: ", paste(missing, collapse = ", "),
    ". Re-run with INSTALL_MISSING=1 and network access, or install them manually."
  )
}

commands <- c("curl", "unzip", "file", "sha256sum", "pdfinfo")
command_paths <- Sys.which(commands)
if (any(!nzchar(command_paths))) {
  stop("Missing system commands: ", paste(names(command_paths)[!nzchar(command_paths)], collapse = ", "))
}

versions <- data.frame(
  package = required,
  version = vapply(required, function(p) as.character(packageVersion(p)), character(1L)),
  library = vapply(required, function(p) dirname(find.package(p)), character(1L)),
  stringsAsFactors = FALSE
)
dir.create(file.path(root, "outputs", "audit"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(root, "outputs", "logs"), recursive = TRUE, showWarnings = FALSE)
data.table::fwrite(versions, file.path(root, "outputs", "audit", "DEPENDENCY_VERSIONS.csv"))
writeLines(c(
  sprintf("checked_at=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("R=%s", R.version.string),
  sprintf("packages=%d", nrow(versions)),
  sprintf("system_commands=%s", paste(sprintf("%s=%s", names(command_paths), command_paths), collapse = ";")),
  "status=pass"
), file.path(root, "outputs", "logs", "00_check_dependencies.log"))
cat(sprintf("dependencies_ok packages=%d commands=%d\n", length(required), length(commands)))

