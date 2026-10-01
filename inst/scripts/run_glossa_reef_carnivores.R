# Corre glossa_analysis() para el grupo funcional "Reef Carnivores"
# (peces), usando ocurrencias 2015-2025 y las covariables ambientales
# CHL (produccion primaria, Copernicus), SST (Copernicus), so
# (salinidad), o2 (oxigeno disuelto), ph y bathymetry -- todas de
# Bio-ORACLE salvo CHL/SST. bathymetry (bathymetry_mean, m) es
# estatica (misma capa repetida en todos los timestamps). Mismo set de
# covariables que run_glossa_group.R.
#
# El paquete glossa no esta instalado como libreria; se cargan las
# funciones directamente desde R/*.R.

r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
invisible(lapply(r_files, source))

suppressMessages({
  library(readxl)
  library(readr)
  library(dplyr)
  library(sf)
  library(terra)
})

set.seed(123)

# 1. Build presence data for the functional group ----
occ <- read_csv("data/occurrence_data_revised_taxonomy.csv", show_col_types = FALSE)
tax <- read_excel("data/grupos_funcionales_Atlantis_GOC.xlsx", sheet = "taxonomy_master")

target_years <- 2015:2025
sp_name <- "Reef Carnivores"

fg_occ <- occ %>%
  left_join(tax %>% select(old_species, new_species, atlantis_fg), by = c("species" = "old_species")) %>%
  filter(!is.na(new_species), new_species != "NA", atlantis_fg == sp_name,
         year >= min(target_years), year <= max(target_years))

message("Occurrence rows for ", sp_name, ": ", nrow(fg_occ))

pa_df <- data.frame(
  decimalLongitude = fg_occ$lon,
  decimalLatitude = fg_occ$lat,
  timestamp_original = fg_occ$year,
  timestamp = match(fg_occ$year, target_years),
  pa = 1
)

pa_data <- list(pa_df)
names(pa_data) <- sp_name

# 2. Study area polygon ----
study_area_poly <- read_extent_polygon("data/zona_estudio.gpkg")

# 3. Predictor variables ----
predictor_variables <- list(c("CHL", "SST", "so", "o2", "ph", "bathymetry"))
names(predictor_variables) <- sp_name

# 4. Run GLOSSA ----
start <- Sys.time()
result <- glossa_analysis(
  pa_data = pa_data,
  fit_layers = "data/fit_layers_2015_2025.zip",
  proj_files = NULL,
  study_area_poly = study_area_poly,
  predictor_variables = predictor_variables,
  thinning_method = "none",
  thinning_value = NULL,
  scale_layers = TRUE,
  buffer = NULL,
  native_range = "fit_layers",
  suitable_habitat = "fit_layers",
  other_analysis = c("variable_importance"),
  model_args = list(),
  pseudoabsence_method = "random",
  pa_ratio = 1,
  seed = 123
)
end <- Sys.time()
message("Total run time: ", round(difftime(end, start, units = "mins"), 2), " mins")

dir.create("outputs", showWarnings = FALSE)

# Quick diagnostics summary
for (scenario in c("native_range", "suitable_habitat")) {
  diag <- result$other_results$model_diagnostic[[scenario]][[sp_name]]
  if (!is.null(diag)) {
    message("== ", scenario, " diagnostics ==")
    print(diag$metrics)
  }
}

# 5. Variable importance summary ----
for (scenario in c("native_range", "suitable_habitat")) {
  vi <- result$other_results$variable_importance[[scenario]][[sp_name]]
  if (!is.null(vi)) {
    summary_vi <- data.frame(
      variable = names(vi),
      mean_importance = colMeans(vi)
    )
    summary_vi <- summary_vi[order(-summary_vi$mean_importance), ]
    message("== ", scenario, " variable importance (mean over permutations) ==")
    print(summary_vi, row.names = FALSE)
    write.csv(
      summary_vi,
      file.path("outputs", paste0("variable_importance_", scenario, "_reef_carnivores.csv")),
      row.names = FALSE
    )
  }
}

# 6. Habitat suitability map (suitable_habitat scenario, mean prediction) ----
suit_raster <- result$projections_results$fit_layers$suitable_habitat[[sp_name]]
cutoff <- result$pa_cutoff$suitable_habitat[[sp_name]]
mean_suit <- suit_raster[["mean"]]

# GeoPackage (raster)
gpkg_path <- "outputs/habitat_suitability_reef_carnivores.gpkg"
if (file.exists(gpkg_path)) file.remove(gpkg_path)
terra::writeRaster(mean_suit, gpkg_path, filetype = "GPKG", overwrite = TRUE,
                    names = "suitability_mean")

# PNG map
png_path <- "outputs/habitat_suitability_reef_carnivores.png"
png(png_path, width = 1600, height = 1400, res = 200)
terra::plot(
  mean_suit,
  main = paste0(sp_name, " - Suitable habitat probability (2015-2025 mean env.)"),
  col = hcl.colors(100, "YlOrRd", rev = TRUE),
  range = c(0, 1)
)
plot(study_area_poly, add = TRUE, border = "black", col = NA)
points(pa_df$decimalLongitude, pa_df$decimalLatitude, pch = 16, cex = 0.15, col = adjustcolor("black", 0.25))
dev.off()

message("Cutoff (suitable_habitat): ", round(cutoff, 4))
message("Wrote: ", gpkg_path)
message("Wrote: ", png_path)

# Save model result (raster components wrapped so they survive saveRDS/readRDS)
result$projections_results$fit_layers$native_range[[sp_name]] <-
  terra::wrap(result$projections_results$fit_layers$native_range[[sp_name]])
result$projections_results$fit_layers$suitable_habitat[[sp_name]] <-
  terra::wrap(result$projections_results$fit_layers$suitable_habitat[[sp_name]])
result$covariate_list$fit_layers <- terra::wrap(result$covariate_list$fit_layers)
saveRDS(result, "data/glossa_result_reef_carnivores_2015_2025.rds")
message("Saved: data/glossa_result_reef_carnivores_2015_2025.rds (raster components wrapped; use terra::unwrap() after readRDS)")
