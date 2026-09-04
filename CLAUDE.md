# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

GLOSSA (Global Ocean Species Spatio-temporal Analysis) is an R package providing a Shiny application (`bs4Dash`) for Bayesian species distribution modeling of marine species using BART (Bayesian Additive Regression Trees, via `dbarts`). Users upload presence/(pseudo-)absence occurrence data and environmental raster layers, fit models, project distributions across scenarios/time, and export results — all through the GUI.

## Common commands

Development is done via standard R package tooling (run from an R console, e.g. `R -e "..."` or `Rscript -e "..."`):

- Load package for interactive dev: `devtools::load_all()`
- Run the app locally: `devtools::load_all(); glossa::run_glossa()`
- Run all tests: `devtools::test()`
- Run a single test file: `devtools::test_active_file("tests/testthat/test-bart_functions.R")` or `testthat::test_file("tests/testthat/test-bart_functions.R")`
- Run a single test by name: `testthat::test_file("tests/testthat/test-utils.R", filter = "some name fragment")`
- Full package check (mirrors CI): `devtools::check()` (or `rcmdcheck::rcmdcheck()`)
- Regenerate documentation/NAMESPACE from roxygen comments: `devtools::document()`
- Update README.md from README.Rmd after editing README.Rmd: `devtools::build_readme()` (or `rmarkdown::render("README.Rmd")`)

CI (`.github/workflows/R-CMD-check.yaml`) runs `R CMD check` across macOS/Windows/Ubuntu and R release/devel/oldrel. It installs `flexsdm` from GitHub (`sjevelazco/flexsdm`) as an extra dependency since it's not on CRAN and is only used conditionally.

## Architecture

### Package vs. app split

- `R/` contains the installable package: exported helper functions (data validation, spatial processing, BART modeling, cross-validation, plotting, export) plus two Shiny module pairs (`mod_file_input_area.R`, `mod_export_plot.R`) used by the app.
- `inst/app/` is the actual Shiny application (not itself an R package target): `global.R` (library loads + options), `ui.R` (single-file `bs4Dash` UI describing Home/New analysis/Reports/Exports/Documentation tabs), `server.R` (all reactive logic), and `Rmd/` (static markdown content for the Documentation/Contact/Citation/Updates tabs, rendered via `includeMarkdown`).
- `run_glossa()` (`R/run_glossa.R`) is the sole entry point: it sets `shiny.maxRequestSize`, then calls `shiny::runApp(system.file("app", package = "glossa"))`. There is no separate `golem`/`shinyApp()` object — the app is a classic `ui.R`/`server.R`/`global.R` trio.

### Core analysis pipeline

`glossa_analysis()` in `R/glossa_analysis.R` is the single orchestrating function called from `server.R` when the user clicks "Run Job". It is a long, numbered, sequential pipeline (see in-file `# N. Section ----` headers) rather than a set of independently-composed steps:

1. Validate inputs / read fit & projection ZIP layers (`read_layers_zip`) and study-area polygon.
2. Clean occurrence coordinates (dedupe, spatial thinning, study-area filtering) via `clean_coordinates`.
3. Process covariate layers: mask to study area, optionally z-score standardize continuous variables using fit-layer mean/sd (categorical variables are handled separately and never scaled), aggregate fit layers across time (mean for continuous, mode for categorical) into a single prediction raster.
4. Extract non-NA covariate values at occurrence points (`extract_noNA_cov_values`) to build the model matrix.
5. Generate pseudo-absences when a species dataset is presence-only (`generate_pseudo_absences.R`; methods: random, target-group, buffer-restricted, environmental-space via optional `flexsdm`).
6. **Native range** models: BART fit including `grid_long`/`grid_lat` coordinate layers (`create_coords_layer`) as covariates, for spatial smoothing.
7. **Suitable habitat** models: BART fit using only environmental covariates (no coordinates).
8. Optional extras gated by `other_analysis`: functional responses (partial-dependence style response curves, `response_curve_bart`), permutation-based variable importance, and cross-validation (`generate_cv_folds` + `cross_validate_model`, supporting k-fold / spatial blocks via `blockCV` / temporal blocks).

Both native-range and suitable-habitat sections independently repeat the same fit → optimal-cutoff (`pa_optimal_cutoff`) → diagnostics (`evaluation_metrics`: AUC, TSS, F-score, CBI) → fit-layer prediction → optional future-scenario projection pattern — when modifying one, check whether the parallel change is needed in the other.

Every step is wrapped in `tryCatch` that logs via `message()`/`warning()` and returns `NULL` on failure rather than halting the whole analysis, so downstream code must tolerate `NULL` entries in per-species result lists. A `waiter` object (Shiny progress overlay) is threaded through the whole function and updated at each stage; when adding pipeline stages, update the corresponding `waiter$update()` call too.

The result is a single deeply-nested list with a consistent, load-bearing shape used throughout `server.R` and export code:
```
list(presence_absence_list, covariate_list, projections_results, other_results, pa_cutoff, habitat_suitability)
```
Each of `covariate_list`, `projections_results`, `habitat_suitability` is keyed first by `fit_layers`/`projections`, then (where applicable) by scenario name and timestamp index, then by `native_range`/`suitable_habitat`, then by species name. Changing this nesting requires updating both `glossa_export()` (`R/utils.R`) and the many `server.R` reactives/pickers that index into it positionally by name.

### Key module files

- `R/read_validate_files.R` — reading and validating uploaded TSV occurrence files and ZIP raster archives (`read_presences_absences_csv`, `read_layers_zip`, `validate_layers_zip`, `validate_fit_projection_layers`, `validate_pa_fit_time`, `read_extent_polygon`).
- `R/process_presence_absence.R` — coordinate cleaning/deduplication/thinning (`clean_coordinates`, `remove_duplicate_points`, `remove_points_polygon`).
- `R/process_layers.R` — raster masking against the study-area polygon (`layer_mask`).
- `R/process_polygon.R` — polygon buffering/inversion for masking and plotting (`buffer_polygon`, `invert_polygon`).
- `R/generate_pseudo_absences.R` — the four pseudo-absence generation strategies, dispatched by name.
- `R/bart_functions.R` — `fit_bart_model`, `predict_bart`, `pa_optimal_cutoff`, `variable_importance`, `response_curve_bart`, `cross_validate_model`.
- `R/utils.R` — the largest file; a grab-bag of covariate extraction, CV fold generation (`generate_cv_folds`), evaluation metrics (several vendored from the `InformationValue` and `enmSdm` packages — see their `@details`/`@note` roxygen tags before modifying), `glossa_export` (writes results to disk as rasters/TSVs for the Exports tab), and ggplot-based plotting helpers used by `server.R`.
- `R/mod_file_input_area.R` / `R/mod_export_plot.R` — reusable Shiny modules (UI+server pairs) for file upload widgets and per-plot PNG/SVG export buttons, used repeatedly across the app.

### Conventions to preserve

- Exported functions use roxygen2 comments (`RoxygenNote: 7.3.2`); after adding/editing any `@param`/`@export`, run `devtools::document()` rather than hand-editing `NAMESPACE` or `man/*.Rd`.
- `predictor_variables` and other per-species arguments are lists keyed/ordered by species name, aligned with `names(pa_data)` — keep this alignment when adding new per-species logic.
- Long-running pipeline code reports progress via `waiter$update()` and `message()`; keep this pattern for consistency with the rest of `glossa_analysis()`.
- `flexsdm` is an optional (`Suggests`) dependency guarded with `requireNamespace()` — never move it to `Imports`/`Depends`, since it's not on CRAN.
