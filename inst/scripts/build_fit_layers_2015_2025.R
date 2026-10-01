# Combina fit_layers_primary_production.zip, fit_layers_sst.zip y
# fit_layers_biooracle.zip en un unico ZIP de covariables (fit_layers en
# glossa_analysis() acepta un solo archivo), restringido a los
# timestamps 2015-2025 (11 anios).
#
# Las capas PFT (0.04167 deg) y SST (0.05 deg) no comparten grid: la
# relacion de resolucion (0.05/0.04167 ~= 1.2) no es un entero, por lo que
# el aggregate() interno de read_layers_zip() no logra conciliarlas
# (error "number of rows and/or columns do not match"). Se resamplean
# aqui las capas PFT a la malla de SST (mas gruesa) antes de empaquetar,
# para que todas las covariables compartan exactamente extent/res/dim.

library(terra)

full_years <- 2000:2025
target_years <- 2015:2025
idx <- match(target_years, full_years)
stopifnot(!anyNA(idx))

tmp_extract <- tempfile("fit_layers_src")
dir.create(tmp_extract)
utils::unzip("data/fit_layers_primary_production.zip", exdir = file.path(tmp_extract, "pft"))
utils::unzip("data/fit_layers_sst.zip", exdir = file.path(tmp_extract, "sst"))
utils::unzip("data/fit_layers_biooracle.zip", exdir = file.path(tmp_extract, "bo"))

# Template grid = SST grid (coarser: 0.05 deg, 360x300)
template <- rast(file.path(tmp_extract, "sst", "SST", sprintf("SST_%02d.tif", idx[1])))

out_dir <- "data/fit_layers_2015_2025"
unlink(out_dir, recursive = TRUE)
dir.create(out_dir, recursive = TRUE)

copy_var_from <- function(src_root, var) {
  var_dir <- file.path(out_dir, var)
  dir.create(var_dir, showWarnings = FALSE)
  for (new_i in seq_along(target_years)) {
    src_file <- file.path(src_root, var, sprintf("%s_%02d.tif", var, idx[new_i]))
    stopifnot(file.exists(src_file))
    file.copy(src_file, file.path(var_dir, sprintf("%s_%02d.tif", var, new_i)))
  }
}

resample_pft_var <- function(var) {
  var_dir <- file.path(out_dir, var)
  dir.create(var_dir, showWarnings = FALSE)
  for (new_i in seq_along(target_years)) {
    src_file <- file.path(tmp_extract, "pft", var, sprintf("%s_%02d.tif", var, idx[new_i]))
    stopifnot(file.exists(src_file))
    r <- rast(src_file)
    r <- resample(r, template, method = "bilinear")
    names(r) <- var
    writeRaster(r, file.path(var_dir, sprintf("%s_%02d.tif", var, new_i)), overwrite = TRUE)
  }
}

pft_vars <- list.dirs(file.path(tmp_extract, "pft"), full.names = FALSE, recursive = FALSE)
for (v in pft_vars) resample_pft_var(v)
copy_var_from(file.path(tmp_extract, "sst"), "SST")

bo_vars <- list.dirs(file.path(tmp_extract, "bo"), full.names = FALSE, recursive = FALSE)
for (v in bo_vars) copy_var_from(file.path(tmp_extract, "bo"), v)

old_wd <- getwd()
setwd(out_dir)
zip_contents <- list.files(".", recursive = TRUE)
zip_path <- file.path(old_wd, "data/fit_layers_2015_2025.zip")
if (file.exists(zip_path)) file.remove(zip_path)
utils::zip(zip_path, zip_contents)
setwd(old_wd)

unlink(out_dir, recursive = TRUE)
unlink(tmp_extract, recursive = TRUE)

message("Timestamp mapping (raster index -> year): ", paste(target_years, collapse = ", "))
message("Wrote: ", zip_path)
