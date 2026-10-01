# Calcula un analisis MESS (Multivariate Environmental Similarity
# Surface, Elith et al. 2010) para las 6 covariables usadas por los
# modelos de genero (CHL, SST, so, o2, ph, bathymetry), comparando el
# rango con el que se ajustaron los modelos (fit_layers_2015_2025.zip,
# 11 anios, valores crudos sin escalar) contra las capas de
# proyeccion 2050 (proj_layers_ssp126_2050.zip / ssp585_2050.zip).
#
# MESS < 0 en un pixel/escenario significa que al menos una covariable
# cae fuera del rango [min, max] observado durante el ajuste: son
# zonas de EXTRAPOLACION, donde BART (como cualquier modelo de
# arboles) no aprendio la respuesta de la especie a esos valores y la
# prediccion de habitat suitability no es confiable.
#
# El analisis es el mismo para los tres generos (Cynoscion,
# Callinectes, Octopus) porque los tres usan exactamente el mismo set
# de 6 covariables como predictor_variables.
#
# Uso: Rscript inst/scripts/compute_mess_2050.R

library(terra)
suppressMessages(library(raster))
suppressMessages(library(dismo))
library(sf)

r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
invisible(lapply(r_files, source))

vars <- c("CHL", "SST", "so", "o2", "ph", "bathymetry")
scenarios <- c(rcp26 = "ssp126", rcp85 = "ssp585")

out_dir <- "outputs/cobi/outputs"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

study_area_poly <- read_extent_polygon("data/zona_estudio.gpkg")

# 1. Reference (training) distribution: pool all 11 fit-layer years ----
fit_tmp <- tempfile("fit_layers_src")
dir.create(fit_tmp)
utils::unzip("data/fit_layers_2015_2025.zip", exdir = fit_tmp)

ref_values <- lapply(vars, function(v) {
  files <- sort(list.files(file.path(fit_tmp, v), pattern = "\\.tif$", full.names = TRUE))
  r <- rast(files)
  r <- layer_mask(layers = r, study_area = study_area_poly)
  as.vector(terra::values(r))
})
names(ref_values) <- vars
# Pool across years: recycle to a common length via a data.frame with NAs allowed per column
max_len <- max(sapply(ref_values, length))
v_df <- as.data.frame(lapply(ref_values, function(x) {
  length(x) <- max_len
  x
}))
message("Reference (training) sample size per variable: ", nrow(v_df))
print(sapply(v_df, function(x) summary(x[!is.na(x)])))

# 2. Future covariate stacks per scenario, MESS, and summary ----
summary_rows <- list()

for (scen_label in names(scenarios)) {
  bo_scenario <- scenarios[[scen_label]]
  message("=== MESS for ", scen_label, " (", bo_scenario, ", 2050) ===")

  proj_tmp <- tempfile("proj_layers_src")
  dir.create(proj_tmp)
  utils::unzip(file.path("data", paste0("proj_layers_", bo_scenario, "_2050.zip")), exdir = proj_tmp)

  future_stack <- rast(lapply(vars, function(v) {
    r <- rast(file.path(proj_tmp, v, paste0(v, "_01.tif")))
    names(r) <- v
    r
  }))
  future_stack <- layer_mask(layers = future_stack, study_area = study_area_poly)

  rs <- raster::stack(future_stack)
  names(rs) <- vars
  mess_full <- dismo::mess(rs, v_df, full = TRUE)
  mess_full <- rast(mess_full)
  # dismo::mess() does not reliably preserve layer names through its
  # disk-backed processing path, so index positionally instead: the
  # first length(vars) layers are per-variable MESS (in input var
  # order), and the last layer is the overall MESS (min across vars).
  stopifnot(nlyr(mess_full) == length(vars) + 1)
  var_layers <- mess_full[[seq_along(vars)]]
  mess_layer <- mess_full[[nlyr(mess_full)]]
  names(mess_layer) <- "mess"

  gpkg_path <- file.path(out_dir, paste0("mess_2050_", scen_label, ".gpkg"))
  if (file.exists(gpkg_path)) file.remove(gpkg_path)
  terra::writeRaster(mess_layer, gpkg_path, filetype = "GPKG", overwrite = TRUE, names = "mess")

  # Replace +-Inf (can occur in .messi3 when a variable is constant,
  # e.g. bathymetry at the coastline) with NA before computing ranges.
  mess_layer <- terra::ifel(is.infinite(mess_layer), NA, mess_layer)

  png_path <- file.path(out_dir, paste0("mess_2050_", scen_label, ".png"))
  png(png_path, width = 1600, height = 1400, res = 200)
  vmin <- min(terra::values(mess_layer), na.rm = TRUE)
  vmax <- max(terra::values(mess_layer), na.rm = TRUE)
  terra::plot(
    mess_layer,
    main = paste0("MESS 2050 - ", toupper(scen_label), " (", bo_scenario, ")\nrojo = extrapolacion (MESS < 0)"),
    col = c("firebrick", hcl.colors(99, "Blues", rev = TRUE)),
    breaks = c(vmin, seq(0, vmax, length.out = 99))
  )
  plot(study_area_poly, add = TRUE, border = "black", col = NA)
  dev.off()

  vals <- terra::values(mess_layer)
  pct_extrapolated <- 100 * mean(vals < 0, na.rm = TRUE)

  # Which variable is most often the limiting (most negative) one where MESS < 0
  # (`which()` on a comparison against NA cells silently drops them, so row
  # indices stay aligned between vals and var_vals, which share the same grid)
  var_vals <- terra::values(var_layers)
  novel_rows <- which(vals < 0)
  limiting_var <- vars[apply(var_vals[novel_rows, , drop = FALSE], 1, which.min)]
  limiting_tbl <- sort(table(limiting_var), decreasing = TRUE)

  message("% area in extrapolation (MESS < 0): ", round(pct_extrapolated, 1), "%")
  message("Most limiting variable(s) in extrapolated pixels: ")
  print(limiting_tbl)

  summary_rows[[scen_label]] <- data.frame(
    scenario = paste0(toupper(scen_label), " (", bo_scenario, ") 2050"),
    pct_area_extrapolated = round(pct_extrapolated, 1),
    top_limiting_variable = names(limiting_tbl)[1]
  )

  unlink(proj_tmp, recursive = TRUE)
}

summary_df <- do.call(rbind, summary_rows)
rownames(summary_df) <- NULL
message("== MESS 2050 summary (applies to all 3 genus models: same predictor set) ==")
print(summary_df, row.names = FALSE)
write.csv(summary_df, file.path(out_dir, "mess_2050_summary.csv"), row.names = FALSE)

unlink(fit_tmp, recursive = TRUE)
message("DONE")
