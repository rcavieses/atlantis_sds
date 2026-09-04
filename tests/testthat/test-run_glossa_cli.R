# Run GLOSSA analysis from file paths (no Shiny)

test_that("run_glossa_cli runs end-to-end from file paths and exports results", {
  skip_on_cran()

  file1 <- system.file("extdata", "sp1.txt", package = "glossa")
  file2 <- system.file("extdata", "sp2.csv", package = "glossa")
  file3 <- system.file("extdata", "fit_layers.zip", package = "glossa")
  file4 <- system.file("extdata", "project_layers_1.zip", package = "glossa")
  file5 <- system.file("extdata", "oceania.gpkg", package = "glossa")

  export_dir <- file.path(tempdir(), "glossa_cli_test_export")
  on.exit(unlink(export_dir, recursive = TRUE), add = TRUE)

  results <- suppressWarnings(run_glossa_cli(
    pa_files = c(sp1 = file1, sp2 = file2),
    fit_layers = file3,
    proj_layers = c(proj1 = file4),
    study_area_poly = file5,
    predictor_variables = list(sp1 = c("x1", "x2"), sp2 = c("x3", "x4")),
    thinning_method = "precision",
    thinning_value = 4,
    scale_layers = TRUE,
    buffer = 0.1,
    native_range = c("fit_layers", "projections"),
    suitable_habitat = c("fit_layers", "projections"),
    other_analysis = "variable_importance",
    seed = 123,
    export_dir = export_dir,
    verbose = FALSE
  ))

  expect_type(results, "list")
  expect_s3_class(results$presence_absence_list$model_pa[["sp1"]], "data.frame")
  expect_s4_class(results$projections_results$fit_layers$suitable_habitat[["sp1"]], "SpatRaster")
  expect_equal(results$config$species, c("sp1", "sp2"))

  expect_true(dir.exists(file.path(export_dir, "sp1")))
  expect_true(dir.exists(file.path(export_dir, "sp2")))
  expect_true(file.exists(file.path(export_dir, "glossa_config.json")))
})

test_that("run_glossa_cli fails fast on invalid or missing inputs", {
  skip_on_cran()

  file1 <- system.file("extdata", "sp1.txt", package = "glossa")
  file3 <- system.file("extdata", "fit_layers.zip", package = "glossa")

  expect_error(
    run_glossa_cli(
      pa_files = c(sp1 = file1),
      fit_layers = file3,
      native_range = "projections",
      verbose = FALSE
    ),
    "proj_layers"
  )

  expect_error(
    run_glossa_cli(
      pa_files = c(sp1 = "does/not/exist.tsv"),
      fit_layers = file3,
      verbose = FALSE
    ),
    "Failed to read"
  )
})
