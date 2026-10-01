# Empaqueta las covariables estaticas de Bio-ORACLE (climatologia
# 2010-2019, mean, depthsurf; mas bathymetry_mean del dataset
# terrain_characteristics) en el formato de ZIP que exige
# read_layers_zip() de GLOSSA: una carpeta por covariable con un
# archivo por timestamp. Como estas capas no tienen series anuales, se
# replica el mismo raster para cada uno de los 2000-2025 timestamps
# (26 anios), igual que fit_layers_primary_production.zip y
# fit_layers_sst.zip, para que las fuentes se puedan combinar en un
# unico fit_layers zip.

library(terra)

full_years <- 2000:2025
src_dir <- "data/biooracle_2010_2019"
out_dir <- "data/fit_layers_biooracle"
zip_path <- "data/fit_layers_biooracle.zip"

vars <- c("thetao", "so", "sws", "swd", "no3", "po4", "si", "o2", "dfe", "ph", "bathymetry")

# Template grid: same grid used for SST/CHL (0.05 deg, Golfo de California)
template <- rast(
  ext(-117, -102, 18, 36),
  resolution = 0.05,
  crs = "epsg:4326"
)

unlink(out_dir, recursive = TRUE)
dir.create(out_dir, recursive = TRUE)

for (v in vars) {
  message("Resampling and replicating ", v, " across ", length(full_years), " years...")
  r <- rast(file.path(src_dir, paste0(v, ".tif")))
  r <- resample(r, template, method = "bilinear")
  names(r) <- v

  var_dir <- file.path(out_dir, v)
  dir.create(var_dir, showWarnings = FALSE)
  for (i in seq_along(full_years)) {
    writeRaster(r, file.path(var_dir, sprintf("%s_%02d.tif", v, i)), overwrite = TRUE)
  }
}

old_wd <- getwd()
setwd(out_dir)
zip_contents <- list.files(".", recursive = TRUE)
if (file.exists(file.path(old_wd, zip_path))) file.remove(file.path(old_wd, zip_path))
utils::zip(file.path(old_wd, zip_path), zip_contents)
setwd(old_wd)
unlink(out_dir, recursive = TRUE)

message("Timestamp mapping (raster index -> year): ", paste(full_years, collapse = ", "))
message("(static covariate: same value repeated for every year)")
message("Wrote: ", zip_path)
