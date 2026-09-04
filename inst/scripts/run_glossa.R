#!/usr/bin/env Rscript
#
# Command-line entry point for GLOSSA, running the same pipeline as the Shiny app
# (glossa::run_glossa_cli()) without launching a browser or a Shiny session.
#
# Usage:
#   Rscript run_glossa.R \
#     --pa sp1=occurrences/sp1.tsv --pa sp2=occurrences/sp2.tsv \
#     --fit_layers env/fit_layers.zip \
#     --proj_layers ssp126=env/proj_ssp126.zip --proj_layers ssp585=env/proj_ssp585.zip \
#     --study_area area/study_area.gpkg \
#     --native_range fit_layers,projections \
#     --suitable_habitat fit_layers,projections \
#     --other variable_importance,functional_responses,cross_validation \
#     --thinning_method distance --thinning_value 10000 \
#     --scale_layers \
#     --pseudoabsence_method random --pa_ratio 1 \
#     --seed 123 \
#     --export_dir out/
#
# Run `Rscript run_glossa.R --help` for the full list of options.

suppressPackageStartupMessages({
  if (!requireNamespace("glossa", quietly = TRUE)) {
    stop("The 'glossa' package must be installed to use this script (devtools::install_github(\"iMARES-group/glossa\")).")
  }
})

# ---------------------------------------------------------------------------
# Minimal --flag value / --flag (boolean) argv parser.
# Flags listed in `repeatable` accumulate into a named/unnamed character vector
# across repeated uses (e.g. --pa sp1=a.tsv --pa sp2=b.tsv).
# ---------------------------------------------------------------------------
parse_cli_args <- function(args) {
  boolean_flags <- c("scale_layers", "quiet", "help")
  repeatable <- c("pa", "proj_layers")

  out <- list()
  i <- 1
  while (i <= length(args)) {
    arg <- args[[i]]
    if (!startsWith(arg, "--")) stop("Unexpected argument: ", arg)
    flag <- sub("^--", "", arg)

    if (flag %in% boolean_flags) {
      out[[flag]] <- TRUE
      i <- i + 1
      next
    }

    if (i == length(args)) stop("Missing value for --", flag)
    value <- args[[i + 1]]

    if (flag %in% repeatable) {
      out[[flag]] <- c(out[[flag]], value)
    } else {
      out[[flag]] <- value
    }
    i <- i + 2
  }
  out
}

# Splits "name=value" into a length-1 named character vector; falls back to an
# unnamed value (name derived downstream) if there is no "=".
split_named <- function(x) {
  has_name <- grepl("=", x, fixed = TRUE)
  vals <- ifelse(has_name, sub("^[^=]+=", "", x), x)
  names(vals) <- ifelse(has_name, sub("=.*$", "", x), "")
  vals
}

split_csv <- function(x) if (is.null(x)) NULL else trimws(strsplit(x, ",")[[1]])

help_text <- "
GLOSSA command-line runner

Required:
  --pa NAME=PATH            Occurrence file for one species (repeatable). NAME is optional;
                             if omitted, it is derived from the file name.
  --fit_layers PATH         ZIP file with model-fitting environmental layers.

Optional inputs:
  --proj_layers NAME=PATH   Projection layers ZIP for one scenario (repeatable).
  --study_area PATH         Study area polygon (GPKG/SHP/KML/GeoJSON).
  --raster_timestamp PATH   Text file mapping raster layer order to real timestamps.
  --target_group PATH       Target-group occurrence file (for pseudoabsence_method=target_group).

Preprocessing:
  --thinning_method STR     none|distance|grid|precision
  --thinning_value NUM
  --scale_layers             (flag) standardize continuous covariates
  --buffer NUM               study area buffer, in arc degrees

Pseudo-absences:
  --pseudoabsence_method STR random|target_group|buffer_out|env_space_flexsdm
  --pa_ratio NUM
  --pa_buffer_distance NUM

Modeling:
  --native_range LIST        comma-separated subset of fit_layers,projections
  --suitable_habitat LIST    comma-separated subset of fit_layers,projections
  --other LIST                comma-separated subset of functional_responses,variable_importance,cross_validation
  --ntree NUM                 dbarts::bart ntree
  --bart_k NUM                 dbarts::bart end-node shrinkage prior k

Cross-validation (requires --other to include cross_validation):
  --cv_methods LIST            comma-separated subset of k-fold,spatial_blocks,temporal_blocks
  --cv_folds NUM
  --cv_block_source STR        residuals_autocorrelation|predictors_autocorrelation|manual
  --cv_block_size NUM

Other:
  --seed NUM
  --export_dir PATH           write results to disk here (default: results are discarded after run)
  --export_layer_format STR   tif|asc|nc
  --quiet                      (flag) suppress progress messages
  --help                       (flag) show this help and exit
"

args <- parse_cli_args(commandArgs(trailingOnly = TRUE))

if (isTRUE(args$help) || length(args) == 0) {
  cat(help_text)
  quit(save = "no", status = 0)
}

if (is.null(args$pa) || is.null(args$fit_layers)) {
  stop("--pa and --fit_layers are required. Run with --help for usage.")
}

pa_files <- split_named(args$pa)
proj_layers <- if (!is.null(args$proj_layers)) split_named(args$proj_layers) else NULL

model_args <- list()
if (!is.null(args$ntree)) model_args$ntree <- as.numeric(args$ntree)
if (!is.null(args$bart_k)) model_args$k <- as.numeric(args$bart_k)

results <- glossa::run_glossa_cli(
  pa_files = pa_files,
  fit_layers = args$fit_layers,
  proj_layers = proj_layers,
  study_area_poly = args$study_area,
  raster_timestamp_file = args$raster_timestamp,
  target_group_file = args$target_group,
  thinning_method = args$thinning_method,
  thinning_value = if (!is.null(args$thinning_value)) as.numeric(args$thinning_value) else NULL,
  scale_layers = isTRUE(args$scale_layers),
  buffer = if (!is.null(args$buffer)) as.numeric(args$buffer) else NULL,
  pseudoabsence_method = if (!is.null(args$pseudoabsence_method)) args$pseudoabsence_method else "random",
  pa_ratio = if (!is.null(args$pa_ratio)) as.numeric(args$pa_ratio) else 1,
  pa_buffer_distance = if (!is.null(args$pa_buffer_distance)) as.numeric(args$pa_buffer_distance) else NULL,
  native_range = split_csv(args$native_range),
  suitable_habitat = split_csv(args$suitable_habitat),
  other_analysis = split_csv(args$other),
  model_args = model_args,
  cv_methods = split_csv(args$cv_methods),
  cv_folds = if (!is.null(args$cv_folds)) as.numeric(args$cv_folds) else 5,
  cv_block_source = if (!is.null(args$cv_block_source)) args$cv_block_source else "residuals_autocorrelation",
  cv_block_size = if (!is.null(args$cv_block_size)) as.numeric(args$cv_block_size) else NULL,
  seed = if (!is.null(args$seed)) as.numeric(args$seed) else NULL,
  export_dir = args$export_dir,
  export_layer_format = if (!is.null(args$export_layer_format)) args$export_layer_format else "tif",
  verbose = !isTRUE(args$quiet)
)

invisible(results)
