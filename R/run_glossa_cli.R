#' Run a GLOSSA Analysis From File Paths, Without Shiny
#'
#' This function runs the same modeling pipeline used by the GLOSSA Shiny app
#' (\code{\link{glossa_analysis}}), but takes raw file paths as input and performs the
#' reading/validation steps that the app normally does interactively (file upload,
#' format checks, timestamp mapping, etc). It is meant to be called from a terminal
#' script (e.g. with \code{Rscript}) or from a batch R script, without launching Shiny.
#'
#' @param pa_files Character vector of paths to presence/(pseudo-)absence occurrence
#'   files (tab-separated by default), one file per species. If named, the names are
#'   used as species identifiers; otherwise species names are derived from the file
#'   names (mirroring the GLOSSA app).
#' @param fit_layers Path to a ZIP file with the environmental layers used for model fitting.
#' @param proj_layers Optional named character vector/list of paths to ZIP files with
#'   projection environmental layers, one per scenario. Names are used as scenario
#'   identifiers; if unnamed, scenario names are derived from the ZIP file names.
#'   Required if `"projections"` is included in `native_range` or `suitable_habitat`.
#' @param study_area_poly Optional path to a polygon file (GPKG, SHP, KML, or GeoJSON)
#'   defining the study area.
#' @param raster_timestamp_file Optional path to a text file with one column listing the
#'   timestamps that correspond to the ordered raster layers in `fit_layers`/`proj_layers`.
#' @param target_group_file Optional path to a tab-separated file with target-group
#'   occurrence points, required when `pseudoabsence_method = "target_group"`.
#' @param predictor_variables Optional named list of predictor variable names to use for
#'   each species (named by species, matching `pa_files`). Defaults to all covariates in
#'   `fit_layers` for every species.
#' @param export_dir Optional path to a directory where results are written to disk (see
#'   \code{\link{export_glossa_results}}). If `NULL` (default), nothing is written and only
#'   the results list is returned.
#' @param export_layer_format Raster file format used when exporting layers to `export_dir`.
#'   One of `"tif"`, `"asc"`, `"nc"`.
#' @param verbose Logical; if `TRUE` (default), progress messages are printed.
#' @inheritParams glossa_analysis
#'
#' @return (Invisibly) the same results list produced by \code{\link{glossa_analysis}}, with
#'   a `config` element added summarizing the call, and additionally exported to
#'   `export_dir` when provided.
#'
#' @export
run_glossa_cli <- function(pa_files,
                            fit_layers,
                            proj_layers = NULL,
                            study_area_poly = NULL,
                            raster_timestamp_file = NULL,
                            target_group_file = NULL,
                            predictor_variables = NULL,
                            thinning_method = NULL, thinning_value = NULL,
                            scale_layers = FALSE, buffer = NULL,
                            pseudoabsence_method = "random", pa_ratio = 1,
                            pa_buffer_distance = NULL,
                            native_range = NULL, suitable_habitat = NULL, other_analysis = NULL,
                            model_args = list(),
                            cv_methods = NULL, cv_folds = 5,
                            cv_block_source = "residuals_autocorrelation", cv_block_size = NULL,
                            seed = NULL,
                            export_dir = NULL, export_layer_format = "tif",
                            verbose = TRUE) {

  vmsg <- function(...) if (isTRUE(verbose)) message(...)

  stopifnot(is.character(pa_files), length(pa_files) > 0)
  stopifnot(is.character(fit_layers), length(fit_layers) == 1)

  # * Derive species names ----
  if (is.null(names(pa_files)) || any(names(pa_files) == "")) {
    names(pa_files) <- sub(" ", "_", sub("([^.]+)\\.[[:alnum:]]+$", "\\1", basename(pa_files)))
  }

  # * Raster timestamp mapping (optional) ----
  raster_timestamp <- NULL
  if (!is.null(raster_timestamp_file)) {
    vmsg("Reading raster timestamp mapping...")
    raster_timestamp <- utils::read.table(raster_timestamp_file, header = FALSE, stringsAsFactors = FALSE)[, 1]
  }

  # * Validate fit layers ----
  vmsg("Validating fit layers...")
  if (!isTRUE(validate_layers_zip(fit_layers, timestamp_mapping = raster_timestamp))) {
    stop("Invalid fit layers ZIP: ", fit_layers)
  }

  # * Validate projection layers (optional) ----
  if (!is.null(proj_layers)) {
    if (is.null(names(proj_layers)) || any(names(proj_layers) == "")) {
      names(proj_layers) <- sub("\\.zip$", "", basename(unlist(proj_layers)), ignore.case = TRUE)
    }
    for (scenario in names(proj_layers)) {
      path <- proj_layers[[scenario]]
      vmsg("Validating projection layers for scenario '", scenario, "'...")
      if (!isTRUE(validate_layers_zip(path))) {
        stop("Invalid projection layers ZIP for scenario '", scenario, "': ", path)
      }
      if (!isTRUE(validate_fit_projection_layers(fit_layers, path))) {
        stop("Projection layers for scenario '", scenario, "' do not match the fit layer covariates: ", path)
      }
    }
  } else if ("projections" %in% native_range || "projections" %in% suitable_habitat) {
    stop("`proj_layers` must be provided when `native_range` or `suitable_habitat` include 'projections'.")
  }

  # * Study area polygon (optional) ----
  study_area_poly_sf <- NULL
  if (!is.null(study_area_poly)) {
    vmsg("Reading study area polygon...")
    study_area_poly_sf <- read_extent_polygon(study_area_poly)
    if (is.null(study_area_poly_sf)) stop("Failed to read study area polygon: ", study_area_poly)
  }

  # * Presence/absence occurrence files ----
  vmsg("Reading presence/absence files...")
  pa_data <- lapply(names(pa_files), function(sp) {
    read_presences_absences_csv(pa_files[[sp]], sp, timestamp_mapping = raster_timestamp)
  })
  names(pa_data) <- names(pa_files)

  failed <- names(pa_data)[sapply(pa_data, is.null)]
  if (length(failed) > 0) {
    stop("Failed to read/validate occurrence file(s) for: ", paste(failed, collapse = ", "))
  }

  invalid_time <- names(pa_data)[!sapply(pa_data, function(x) validate_pa_fit_time(x, fit_layers))]
  if (length(invalid_time) > 0) {
    stop("Occurrence timestamps exceed the fit layers time period for: ", paste(invalid_time, collapse = ", "))
  }

  # * Target-group points (optional) ----
  target_group_points <- NULL
  if (identical(pseudoabsence_method, "target_group")) {
    if (is.null(target_group_file)) stop("`target_group_file` is required when `pseudoabsence_method = 'target_group'`.")
    vmsg("Reading target-group points...")
    target_group_points <- read_presences_absences_csv(target_group_file, timestamp_mapping = raster_timestamp)
    if (is.null(target_group_points)) stop("Failed to read target-group file: ", target_group_file)
  }

  # * Run analysis ----
  vmsg("Running GLOSSA analysis...")
  results <- glossa_analysis(
    pa_data = pa_data,
    fit_layers = fit_layers,
    proj_files = proj_layers,
    study_area_poly = study_area_poly_sf,
    predictor_variables = predictor_variables,
    thinning_method = thinning_method,
    thinning_value = thinning_value,
    scale_layers = scale_layers,
    buffer = buffer,
    native_range = native_range,
    suitable_habitat = suitable_habitat,
    other_analysis = other_analysis,
    model_args = model_args,
    cv_methods = cv_methods,
    cv_folds = cv_folds,
    cv_block_source = cv_block_source,
    cv_block_size = cv_block_size,
    pseudoabsence_method = pseudoabsence_method,
    pa_ratio = pa_ratio,
    target_group_points = target_group_points,
    pa_buffer_distance = pa_buffer_distance,
    seed = if (is.null(seed)) NA else seed,
    waiter = NULL
  )

  results$config <- list(
    timestamp = format(Sys.time(), "%Y%m%d_%H%M%S"),
    seed = seed,
    species = names(pa_data),
    file_inputs = list(
      pa_data = unname(pa_files),
      fit_layers = fit_layers,
      projections = if (!is.null(proj_layers)) unname(unlist(proj_layers)) else NULL,
      study_area_poly = study_area_poly,
      raster_timestamp_file = raster_timestamp_file
    ),
    preprocessing = list(
      thinning_method = thinning_method,
      thinning_value = thinning_value,
      scale_layers = scale_layers,
      buffer = buffer
    ),
    pseudo_absences = list(
      pseudoabsence_method = pseudoabsence_method,
      pa_ratio = pa_ratio,
      pa_buffer_distance = pa_buffer_distance,
      target_group_points = target_group_file
    ),
    modeling = list(
      predictor_variables = predictor_variables,
      native_range = native_range,
      suitable_habitat = suitable_habitat,
      other_analysis = other_analysis,
      model_args = model_args
    ),
    cross_validation = list(
      active = "cross_validation" %in% other_analysis,
      methods = cv_methods,
      folds = cv_folds,
      block_source = cv_block_source,
      block_size = cv_block_size
    )
  )

  # * Export (optional) ----
  if (!is.null(export_dir)) {
    vmsg("Exporting results to ", export_dir, "...")
    export_glossa_results(results, export_dir, layer_format = export_layer_format)
  }

  vmsg("Done.")
  invisible(results)
}


#' Export GLOSSA Analysis Results to Disk
#'
#' Writes the results of \code{\link{glossa_analysis}} (or \code{\link{run_glossa_cli}}) to a
#' directory on disk, without requiring a running Shiny session. This is a thin wrapper around
#' the same internal exporter used by the app's "Save GLOSSA results" download handler, except
#' that it copies the resulting files/folders directly into `export_dir` instead of zipping them.
#'
#' @param results A results list as returned by \code{\link{glossa_analysis}} or
#'   \code{\link{run_glossa_cli}}.
#' @param export_dir Directory to write results into. Created if it does not already exist.
#' @param species Character vector of species to export. Defaults to all species present in `results`.
#' @param models Character vector of model types to export (`"native_range"`, `"suitable_habitat"`).
#'   Defaults to whichever are present in `results`.
#' @param layer_results Character vector of `"fit_layers"`/`"projections"` to export. Defaults to
#'   whichever are present in `results`.
#' @param fields Character vector of raster fields to export.
#' @param layer_format Raster file format for exported layers: one of `"tif"`, `"asc"`, `"nc"`.
#' @param model_data,model_summary,varimp,fr,cross_val,prob_cut Logical switches for which auxiliary
#'   results to export. Default (`NULL`) exports each when the corresponding result is present.
#'
#' @return (Invisibly) the character vector of file/directory paths written into `export_dir`.
#' @export
export_glossa_results <- function(results,
                                   export_dir,
                                   species = NULL,
                                   models = NULL,
                                   layer_results = NULL,
                                   fields = c("mean", "median", "sd", "q0.025", "q0.975", "diff", "potential_presences"),
                                   layer_format = "tif",
                                   model_data = NULL,
                                   model_summary = NULL,
                                   varimp = NULL,
                                   fr = NULL,
                                   cross_val = NULL,
                                   prob_cut = NULL) {

  presence_absence_list <- results$presence_absence_list
  projections_results <- results$projections_results
  other_results <- results$other_results
  pa_cutoff <- results$pa_cutoff
  config <- results$config

  if (is.null(species)) species <- names(presence_absence_list$model_pa)
  if (is.null(models)) models <- names(projections_results$fit_layers)[!sapply(projections_results$fit_layers, is.null)]
  if (is.null(layer_results)) layer_results <- names(projections_results)[!sapply(projections_results, is.null)]

  if (is.null(model_data)) model_data <- !is.null(presence_absence_list$model_pa)
  if (is.null(model_summary)) model_summary <- !is.null(other_results$model_diagnostic)
  if (is.null(varimp)) varimp <- !is.null(other_results$variable_importance)
  if (is.null(fr)) fr <- !is.null(other_results$response_curve)
  if (is.null(cross_val)) cross_val <- !is.null(other_results$cross_validation)
  if (is.null(prob_cut)) prob_cut <- !all(sapply(pa_cutoff, is.null))

  export_files <- glossa_export(
    species = species, models = models, layer_results = layer_results, fields = fields,
    model_data = model_data, model_summary = model_summary, fr = fr, prob_cut = prob_cut,
    varimp = varimp, cross_val = cross_val, layer_format = layer_format,
    projections_results = projections_results, presence_absence_list = presence_absence_list,
    other_results = other_results, pa_cutoff = pa_cutoff, config_snapshot = config
  )

  if (!dir.exists(export_dir)) dir.create(export_dir, recursive = TRUE)

  written <- file.path(export_dir, basename(export_files))
  for (i in seq_along(export_files)) {
    if (dir.exists(export_files[i])) {
      dir.create(written[i], showWarnings = FALSE)
      file.copy(list.files(export_files[i], full.names = TRUE), written[i], recursive = TRUE, overwrite = TRUE)
    } else {
      file.copy(export_files[i], written[i], overwrite = TRUE)
    }
  }
  unlink(export_files, recursive = TRUE)

  invisible(written)
}
