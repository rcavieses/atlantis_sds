# Descarga las 9 covariables adicionales de Bio-ORACLE (climatologia
# decadal 2010-2019, estadistico "mean", profundidad superficial) para
# el area de estudio del Golfo de California, y las deja listas para
# empaquetar en el ZIP de fit_layers de GLOSSA.
#
# Bio-ORACLE no ofrece series anuales: solo publica 2 cortes decadales
# (2000-01-01 y 2010-01-01). Usamos el corte 2010-01-01 (2010-2019,
# "current") como covariable ESTATICA, igual para todos los anios del
# modelo.

library(biooracler)
library(terra)

MIN_LON <- -117; MAX_LON <- -102
MIN_LAT <- 18; MAX_LAT <- 36
TIME <- c("2010-01-01T00:00:00Z", "2010-01-01T00:00:00Z")

vars <- c(
  thetao = "Ocean temperature",
  so     = "Salinity",
  sws    = "Sea water velocity",
  swd    = "Sea water direction",
  no3    = "Nitrate",
  po4    = "Phosphate",
  si     = "Silicate",
  o2     = "Dissolved molecular oxygen",
  dfe    = "Iron",
  ph     = "pH"
)

# The end-year of the "baseline" dataset id differs by variable family
# (thetao/so/sws/swd use 2019, nutrients/o2/dfe/ph use 2018).
end_year <- c(
  thetao = 2019, so = 2019, sws = 2019, swd = 2019,
  no3 = 2018, po4 = 2018, si = 2018, o2 = 2018, dfe = 2018, ph = 2018
)

out_dir <- "data/biooracle_2010_2019"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

constraints <- list(TIME, c(MIN_LAT, MAX_LAT), c(MIN_LON, MAX_LON))
names(constraints) <- c("time", "latitude", "longitude")

for (v in names(vars)) {
  message("Downloading ", v, " (", vars[v], ")...")
  dataset_id <- paste0(v, "_baseline_2000_", end_year[v], "_depthsurf")
  r <- tryCatch({
    download_layers(
      dataset_id = dataset_id,
      variables = paste0(v, "_mean"),
      constraints = constraints,
      fmt = "raster",
      directory = out_dir,
      filename = v,
      verbose = TRUE
    )
  }, error = function(e) {
    message("FAILED ", v, ": ", e$message)
    NULL
  })
  if (!is.null(r)) {
    names(r) <- v
    writeRaster(r, file.path(out_dir, paste0(v, ".tif")), overwrite = TRUE)
    message(v, " -> ", file.path(out_dir, paste0(v, ".tif")), " | dims: ",
            paste(dim(r)[1:2], collapse = "x"), " | res: ", paste(round(res(r), 5), collapse = ", "))
  }
}

message("DONE")
