# Versión con los polígonos con profundidad (113 cajas, box_no 0-112, ya con
# numeración Atlantis; goc_polygons_bgm_depth_atlantis_10172026.zip), tras la limpieza
# topológica de build_bgm_depth.R (correr ese script primero), de modo que las
# proporciones corresponden exactamente a las cajas del BGM. Salidas en
# outputs/atlantis_box_proportions_depth/.
#
# Probabilidad de ocurrencia y proporción de distribución por caja (polígono)
# de Atlantis GOC, para cada grupo funcional, a partir de los mapas de
# idoneidad de GLOSSA (outputs/habitat_suitability_<grupo>.gpkg).
#
# Por caja y grupo:
#   pr_<COD> = media de idoneidad (0-1) ponderada por área de agua de cada
#              celda dentro de la caja (fracción de cobertura x área de celda).
#   pp_<COD> = idoneidad integrada en la caja (sum(idoneidad x área)) dividida
#              entre el total de las cajas dinámicas; suma 1 por grupo. Es el
#              vector de proporciones que pide Atlantis en FXXX_S1..S4 /
#              XXX_recruit_hdistrib (User Guide Part I, cap. 11.1 y 11.3).
# Las cajas boundary e island llevan pp = 0 y pr = NA (Atlantis no aloja
# biomasa en ellas). Supone abundancia proporcional a la idoneidad.
#
#   pa_<COD> = fracción (0-1) del área de agua de la caja con idoneidad >=
#              min_suit (área ocupada / área con datos de la caja).
#
# Criterio de exclusión: las celdas con idoneidad < min_suit se cuentan como 0
# antes de agregar por caja (afecta tanto a pr_ como a pp_).

library(sf)
library(terra)
library(readxl)

polys_file <- "data/goc_polygons_depth_bgm/goc_boxes_depth.shp" # cajas limpias de build_bgm_depth.R
groups_file <- "data/grupos_funcionales_Atlantis_GOC.xlsx"
out_shp <- "outputs/atlantis_box_proportions_depth/goc_box_proportions.shp"
out_csv <- "outputs/atlantis_box_proportions_depth/goc_box_proportions_long.csv"
min_suit <- 0.3

polys <- st_read(polys_file, quiet = TRUE)
polys$box_no <- polys$box_id
polys <- polys[order(polys$box_no), ]
dynamic <- polys$plygn_t == "dynamic"

files <- list.files("outputs", "^habitat_suitability_.*\\.gpkg$", full.names = TRUE)
slugs <- sub("^habitat_suitability_(.*)\\.gpkg$", "\\1", basename(files))

fg <- unique(read_excel(groups_file, sheet = "final_groups")[, c("atlantis_fg1", "atlantis_code1")])
fg$slug <- gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(fg$atlantis_fg1)))
codes <- vapply(slugs, function(s) {
  cod <- unique(fg$atlantis_code1[fg$slug == s])
  if (length(cod) != 1) stop("Grupo sin código Atlantis único: ", s)
  cod
}, character(1))

suit <- rast(files)
names(suit) <- codes
cell_area <- cellSize(suit[[1]], unit = "km")
names(cell_area) <- "cell_km2"

# exact = TRUE da la fracción de cada celda cubierta por el polígono
ext <- terra::extract(c(suit, cell_area), vect(polys), exact = TRUE)
ext$w <- ext$fraction * ext$cell_km2
for (cod in codes) {
  below <- !is.na(ext[[cod]]) & ext[[cod]] < min_suit
  ext[[cod]][below] <- 0
}

prob <- matrix(NA_real_, nrow(polys), length(codes), dimnames = list(NULL, codes))
mass <- matrix(0, nrow(polys), length(codes), dimnames = list(NULL, codes))
area_frac <- matrix(NA_real_, nrow(polys), length(codes), dimnames = list(NULL, codes))
for (cod in codes) {
  ok <- !is.na(ext[[cod]])
  w_sum <- tapply(ext$w[ok], ext$ID[ok], sum)
  s_sum <- tapply(ext[[cod]][ok] * ext$w[ok], ext$ID[ok], sum)
  idx <- as.integer(names(s_sum))
  prob[idx, cod] <- s_sum / w_sum
  mass[idx, cod] <- s_sum
  occ <- tapply(ext$w[ok] * (ext[[cod]][ok] >= min_suit), ext$ID[ok], sum)
  area_frac[idx, cod] <- occ / w_sum
}
prob[!dynamic, ] <- NA
area_frac[!dynamic, ] <- NA
mass[!dynamic, ] <- 0
prop <- sweep(mass, 2, colSums(mass), "/")

no_data <- polys$box_no[dynamic & is.na(prob[, 1])]
if (length(no_data) > 0) {
  message("Cajas dinámicas sin celdas con idoneidad (pp = 0): ", paste(no_data, collapse = ", "))
}

out <- polys
out[paste0("pr_", codes)] <- round(prob, 6)
out[paste0("pp_", codes)] <- round(prop, 8)
out[paste0("pa_", codes)] <- round(area_frac, 6)
dir.create(dirname(out_shp), showWarnings = FALSE, recursive = TRUE)
st_write(out, out_shp, delete_dsn = TRUE, quiet = TRUE)

long <- data.frame(
  box_no = rep(polys$box_no, length(codes)),
  region = rep(polys$region, length(codes)),
  box_type = rep(polys$plygn_t, length(codes)),
  atlantis_code = rep(codes, each = nrow(polys)),
  group = rep(fg$atlantis_fg1[match(slugs, fg$slug)], each = nrow(polys)),
  prob_occurrence = as.vector(prob),
  proportion = as.vector(prop),
  area_fraction = as.vector(area_frac)
)
write.csv(long, out_csv, row.names = FALSE)

message("Shapefile: ", out_shp, " (", nrow(out), " cajas, ", length(codes), " grupos)")
message("Suma de proporciones por grupo: ", paste(range(round(colSums(prop), 10)), collapse = " - "))
