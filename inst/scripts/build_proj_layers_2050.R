# Empaqueta los ZIP de capas de proyeccion (glossa_analysis(proj_files=...))
# para el horizonte 2050 bajo los escenarios ssp126 (~RCP2.6) y ssp585
# (~RCP8.5), usando las capas futuras de Bio-ORACLE descargadas por
# inst/scripts/download_biooracle_future_layers.R.
#
# read_layers_zip() exige que el ZIP de proyeccion tenga exactamente
# las mismas 22 covariables (mismo nombre y orden) que
# fit_layers_2015_2025.zip, asi que:
#   - thetao (futuro) -> carpeta "SST"  (Bio-ORACLE no publica
#     proyecciones futuras del SST de Copernicus usado en el ajuste;
#     thetao es el sustituto mas cercano)
#   - chl (futuro)    -> carpeta "CHL"  (sustituto de produccion
#     primaria/Copernicus)
#   - so, o2, ph (futuro) -> mismas carpetas, directo
#   - el resto de covariables (bathymetry + PFTs de Copernicus + otras
#     de Bio-ORACLE no usadas como predictor: dfe, no3, po4, si, swd,
#     sws, thetao "crudo") no cambian con el escenario para las
#     especies de este analisis (no estan en predictor_variables), asi
#     que se reutiliza directamente el ultimo timestamp (2025) del ZIP
#     de ajuste, ya alineado a la misma grilla.
#
# Cada covariable queda con un unico archivo (timestamp 1 = "2050").
#
# Uso: Rscript inst/scripts/build_proj_layers_2050.R

library(terra)

scenarios <- c("ssp126", "ssp585")

# Bio-ORACLE variable -> target covariate folder name (must match
# fit_layers_2015_2025.zip covariate names exactly)
future_var_map <- c(thetao = "SST", chl = "CHL", so = "so", o2 = "o2", ph = "ph")

# 1. Extract fit_layers_2015_2025.zip to get the template grid and the
#    static/unused covariates ----
fit_tmp <- tempfile("fit_layers_src")
dir.create(fit_tmp)
utils::unzip("data/fit_layers_2015_2025.zip", exdir = fit_tmp)

all_covs <- list.dirs(fit_tmp, full.names = FALSE, recursive = FALSE)
template <- rast(file.path(fit_tmp, "SST", "SST_01.tif"))

unused_covs <- setdiff(all_covs, future_var_map)
stopifnot(length(unused_covs) + length(future_var_map) == length(all_covs))

for (scenario in scenarios) {
  message("=== Building proj layers for ", scenario, " (2050) ===")
  out_dir <- file.path("data", paste0("proj_layers_", scenario, "_2050"))
  unlink(out_dir, recursive = TRUE)
  dir.create(out_dir, recursive = TRUE)

  # Future covariates (resampled to fit template grid)
  for (bo_var in names(future_var_map)) {
    target_name <- future_var_map[[bo_var]]
    src_file <- file.path("data/biooracle_future", scenario, paste0(bo_var, ".tif"))
    stopifnot(file.exists(src_file))
    r <- rast(src_file)
    r <- resample(r, template, method = "bilinear")
    names(r) <- target_name

    var_dir <- file.path(out_dir, target_name)
    dir.create(var_dir, showWarnings = FALSE)
    writeRaster(r, file.path(var_dir, paste0(target_name, "_01.tif")), overwrite = TRUE)
  }

  # Unused covariates: reuse the 2025 (last) fit-layer raster as-is
  for (cov in unused_covs) {
    src_file <- file.path(fit_tmp, cov, paste0(cov, "_11.tif"))
    stopifnot(file.exists(src_file))
    var_dir <- file.path(out_dir, cov)
    dir.create(var_dir, showWarnings = FALSE)
    file.copy(src_file, file.path(var_dir, paste0(cov, "_01.tif")))
  }

  # Zip
  old_wd <- getwd()
  setwd(out_dir)
  zip_contents <- list.files(".", recursive = TRUE)
  zip_path <- file.path(old_wd, "data", paste0("proj_layers_", scenario, "_2050.zip"))
  if (file.exists(zip_path)) file.remove(zip_path)
  utils::zip(zip_path, zip_contents)
  setwd(old_wd)

  unlink(out_dir, recursive = TRUE)
  message("Wrote: ", zip_path)
}

unlink(fit_tmp, recursive = TRUE)
message("DONE")
