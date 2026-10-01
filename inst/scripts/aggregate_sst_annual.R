# Agrega la capa de SST de resolucion mensual a resolucion anual y la
# empaqueta en el formato de ZIP que exige `read_layers_zip()` de GLOSSA,
# igual que aggregate_primary_production_annual.R.

library(terra)

nc_path <- "data/glossa_sst_monthly_golfo_california.nc"
out_dir <- "data/fit_layers_sst"
zip_path <- "data/fit_layers_sst.zip"

r <- rast(nc_path)
years <- 2000:2025
v <- "SST"

unlink(out_dir, recursive = TRUE)
dir.create(out_dir, recursive = TRUE)

message("Aggregating ", v, " to annual means...")
layer_years <- format(time(r), "%Y")
stopifnot(length(layer_years) == length(years) * 12)

annual <- tapp(r, index = layer_years, fun = "mean", na.rm = TRUE)
stopifnot(nlyr(annual) == length(years))
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

old_wd <- getwd()
setwd(out_dir)
zip_contents <- list.files(".", recursive = TRUE)
if (file.exists(file.path(old_wd, zip_path))) file.remove(file.path(old_wd, zip_path))
utils::zip(file.path(old_wd, zip_path), zip_contents)
setwd(old_wd)

unlink(out_dir, recursive = TRUE)

message("Timestamp mapping (raster index -> year): ", paste(years, collapse = ", "))
message("Wrote: ", zip_path)
