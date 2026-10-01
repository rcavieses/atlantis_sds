# Descarga la capa de batimetria (bathymetry_mean, en metros) del dataset
# "terrain_characteristics" de Bio-ORACLE para el area de estudio del
# Golfo de California. A diferencia de las otras capas de Bio-ORACLE
# (data/biooracle_2010_2019/*.tif), este dataset no tiene dimension
# temporal real: solo un timestamp fijo (1970-01-01), ya que la
# batimetria es estatica.
#
# La salida se guarda junto a las demas capas Bio-ORACLE
# (data/biooracle_2010_2019/bathymetry.tif) para que
# build_fit_layers_biooracle.R la pueda incluir agregando "bathymetry"
# a su vector `vars`.

library(biooracler)
library(terra)

MIN_LON <- -117; MAX_LON <- -102
MIN_LAT <- 18; MAX_LAT <- 36
TIME <- c("1970-01-01T00:00:00Z", "1970-01-01T00:00:00Z")

out_dir <- "data/biooracle_2010_2019"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

constraints <- list(TIME, c(MIN_LAT, MAX_LAT), c(MIN_LON, MAX_LON))
names(constraints) <- c("time", "latitude", "longitude")

message("Downloading bathymetry_mean (Bio-Oracle terrain_characteristics)...")
r <- download_layers(
  dataset_id = "terrain_characteristics",
  variables = "bathymetry_mean",
  constraints = constraints,
  fmt = "raster",
  directory = out_dir,
  filename = "bathymetry",
  verbose = TRUE
)
names(r) <- "bathymetry"
writeRaster(r, file.path(out_dir, "bathymetry.tif"), overwrite = TRUE)
message("bathymetry -> ", file.path(out_dir, "bathymetry.tif"), " | dims: ",
        paste(dim(r)[1:2], collapse = "x"), " | res: ", paste(round(res(r), 5), collapse = ", "))
message("DONE")
