# Añade el atributo de profundidad (max_depth) y tipo de poligono (polygon_type)
# a los poligonos de Atlantis GOC, ya que el shapefile original no los trae.
#
# Entradas:
#   - data/goc_polygon_final_09142026.zip  (shapefile: ar_sq_k, box_no, mdpnt_lt, mdpnt_ln)
#   - data/tabla_poligonos_Atlantis_GOC.xlsx (Sheet1: area_sq_km, box_no, midpoint_lat,
#     midpoint_lon, polygon_type, max_depth, + columnas sueltas de notas que se descartan)
#
# Salida:
#   - data/goc_polygons_with_depth.gpkg

library(sf)
library(readxl)
library(dplyr)

zip_path <- "data/goc_polygon_final_09142026.zip"
xlsx_path <- "data/tabla_poligonos_Atlantis_GOC.xlsx"
out_path <- "data/goc_polygons_with_depth.gpkg"

extract_dir <- tempfile("goc_polygon_")
dir.create(extract_dir)
unzip(zip_path, exdir = extract_dir)

shp_file <- list.files(extract_dir, pattern = "\\.shp$", full.names = TRUE)
stopifnot(length(shp_file) == 1)

polygons <- st_read(shp_file, quiet = TRUE)

if ("max_depth" %in% names(polygons)) {
  message("El shapefile ya tiene el atributo de profundidad; no se requiere union.")
} else {
  message("El shapefile no tiene atributo de profundidad; uniendo con la tabla de Excel por box_no.")

  depth_table <- read_excel(xlsx_path, sheet = "Sheet1") |>
    select(box_no, polygon_type, max_depth)

  n_before <- nrow(polygons)
  polygons <- polygons |>
    left_join(depth_table, by = "box_no")

  n_missing <- sum(is.na(polygons$max_depth))
  if (n_missing > 0) {
    warning(n_missing, " de ", n_before, " poligonos quedaron sin profundidad tras la union (box_no sin match).")
  } else {
    message("Union exitosa: ", n_before, " poligonos, todos con profundidad asignada.")
  }
}

st_write(polygons, out_path, delete_dsn = TRUE, quiet = TRUE)
message("Escrito: ", out_path)
