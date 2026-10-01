# Agrega la capa de producción primaria (PFT) de resolución mensual a
# resolución anual y la empaqueta en el formato de ZIP que exige
# `read_layers_zip()` de GLOSSA: un ZIP con una subcarpeta por covariable,
# y dentro un archivo raster por timestamp (ordenado cronologicamente).
#
# Las ocurrencias (data/occurrence_data_revised_taxonomy.csv) solo traen
# resolucion "year", por lo que las capas de ajuste deben tener un layer
# por año (no por mes) para poder alinear timestamp_mapping = 2000:2024.

library(terra)

nc_path <- "data/glossa_primary_production_monthly_golfo_california.nc"
out_dir <- "data/fit_layers_primary_production"
zip_path <- "data/fit_layers_primary_production.zip"

r <- rast(nc_path)
variables <- unique(sub("_[0-9]+$", "", names(r)))
years <- 2000:2025

unlink(out_dir, recursive = TRUE)
dir.create(out_dir, recursive = TRUE)

for (v in variables) {
  message("Aggregating ", v, " to annual means...")
  v_layers <- r[[grepl(paste0("^", v, "_[0-9]+$"), names(r))]]

  layer_years <- format(time(v_layers), "%Y")
  stopifnot(length(layer_years) == length(years) * 12)

  annual <- tapp(v_layers, index = layer_years, fun = "mean", na.rm = TRUE)
  stopifnot(nlyr(annual) == length(years))
  # tapp orders groups alphabetically, which for 4-digit years is chronological
  names(annual) <- years

  var_dir <- file.path(out_dir, v)
  dir.create(var_dir, showWarnings = FALSE)
  for (i in seq_along(years)) {
    writeRaster(
      annual[[i]],
      file.path(var_dir, sprintf("%s_%02d.tif", v, i)),
      overwrite = TRUE
    )
  }
}

# Zip so that the archive root contains one folder per covariate, as
# required by read_layers_zip()/validate_layers_zip().
old_wd <- getwd()
setwd(out_dir)
zip_contents <- list.files(".", recursive = TRUE)
if (file.exists(file.path(old_wd, zip_path))) file.remove(file.path(old_wd, zip_path))
utils::zip(file.path(old_wd, zip_path), zip_contents)
setwd(old_wd)
unlink(out_dir, recursive = TRUE)

message("Timestamp mapping (raster index -> year): ", paste(years, collapse = ", "))
message("Wrote: ", zip_path)
