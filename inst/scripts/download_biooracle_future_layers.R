# Descarga las capas futuras de Bio-ORACLE v3 (derivadas de CMIP6)
# necesarias para proyectar los modelos de habitat suitability al
# horizonte 2050 bajo dos escenarios climaticos:
#   ssp126 (~RCP2.6, mitigacion fuerte) y ssp585 (~RCP8.5, altas
#   emisiones).
#
# Variables descargadas (estadistico "mean", depthsurf, corte decadal
# 2050-01-01): thetao (temperatura, sustituto de SST ya que Bio-ORACLE
# no publica proyecciones futuras de SST/Copernicus), chl (sustituto
# de CHL/produccion primaria), so (salinidad), o2 (oxigeno disuelto),
# ph. bathymetry no se descarga: es estatica y se reutiliza tal cual
# desde data/biooracle_2010_2019/bathymetry.tif.
#
# Uso: Rscript inst/scripts/download_biooracle_future_layers.R

library(biooracler)
library(terra)

MIN_LON <- -117; MAX_LON <- -102
MIN_LAT <- 18; MAX_LAT <- 36
TIME_2050 <- c("2050-01-01T00:00:00Z", "2050-01-01T00:00:00Z")

scenarios <- c("ssp126", "ssp585")
vars <- c("thetao", "chl", "so", "o2", "ph")

constraints <- list(TIME_2050, c(MIN_LAT, MAX_LAT), c(MIN_LON, MAX_LON))
names(constraints) <- c("time", "latitude", "longitude")

out_root <- "data/biooracle_future"
dir.create(out_root, showWarnings = FALSE, recursive = TRUE)

for (scenario in scenarios) {
  out_dir <- file.path(out_root, scenario)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  for (v in vars) {
    message("Downloading ", v, " (", scenario, ", 2050)...")
    dataset_id <- paste0(v, "_", scenario, "_2020_2100_depthsurf")
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
      message("FAILED ", v, " (", scenario, "): ", e$message)
      NULL
    })
    if (!is.null(r)) {
      names(r) <- v
      writeRaster(r, file.path(out_dir, paste0(v, ".tif")), overwrite = TRUE)
      message(v, " (", scenario, ") -> ", file.path(out_dir, paste0(v, ".tif")))
    }
  }
}

message("DONE")
