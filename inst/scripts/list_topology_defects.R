# Lista de defectos de topología de las cajas de Atlantis GOC (antes de la
# limpieza de build_bgm_depth.R):
#   hueco    = zona rodeada por cajas que no pertenece a ninguna, de ancho medio
#              >= SLIVER_W m
#   astilla  = igual, pero de ancho medio < SLIVER_W m (franja delgada)
#   traslape = zona cubierta por dos o más cajas (cajas_traslapadas = las cajas que la cubren)
#   arista   = tramo del borde de una caja que limita con un defecto (una fila
#              por defecto y caja vecina; n_vert = vértices del tramo)
# Ancho medio = 2 * área / perímetro de la zona.
#
# Uso: Rscript inst/scripts/list_topology_defects.R [shapefile]
# Salidas (data/goc_polygons_depth_bgm/): goc_topologia_defectos.csv,
# goc_topologia_aristas.csv y goc_topologia_defectos.gpkg (capas defectos y aristas).

library(sf)
sf_use_s2(FALSE)

args <- commandArgs(trailingOnly = TRUE)
in_shp <- if (length(args)) args[1] else "data/goc_polygons_depth_atlantis_10172026/goc_polygons_bgm_depth_atlantis.shp"
out_dir <- "data/goc_polygons_depth_bgm"
CRS_M <- 6372
PROJ_AREA <- "+proj=laea +lat_0=26 +lon_0=-110 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs"
SLIVER_W <- 200 # m
TOL <- 1 # m, para decidir qué borde de caja toca una zona

p <- st_read(in_shp, quiet = TRUE)
p <- st_transform(p[order(p$box_no), ], CRS_M)
g <- st_geometry(p)

noded <- st_union(st_cast(st_boundary(g), "MULTILINESTRING"))
faces <- st_cast(st_collection_extract(st_polygonize(noded), "POLYGON"), "POLYGON")
hit <- st_intersects(st_point_on_surface(faces), g)
n_own <- lengths(hit)
bad <- which(n_own != 1)
faces <- faces[bad]
hit <- hit[bad]
n_own <- n_own[bad]

area_m2 <- as.numeric(st_area(st_transform(faces, PROJ_AREA)))
perim_m <- as.numeric(st_length(st_cast(st_boundary(faces), "MULTILINESTRING")))
width_m <- 2 * area_m2 / perim_m
tipo <- ifelse(n_own > 1, "traslape", ifelse(width_m < SLIVER_W, "astilla", "hueco"))
ctr <- st_coordinates(st_transform(suppressWarnings(st_point_on_surface(faces)), 4326))

# aristas: borde de cada defecto compartido con el borde de cada caja
edges <- list()
for (i in seq_along(faces)) {
  bnd <- st_boundary(faces[i])
  near <- which(st_is_within_distance(g, bnd, TOL, sparse = FALSE)[, 1])
  for (b in near) {
    ln <- suppressWarnings(st_intersection(bnd, st_buffer(st_boundary(g[b]), TOL)))
    ln <- suppressWarnings(st_collection_extract(ln, "LINESTRING"))
    if (!length(ln) || all(st_is_empty(ln))) next
    ln <- st_union(ln)
    len <- as.numeric(st_length(ln))
    if (len < 0.01) next
    nv <- nrow(st_coordinates(ln))
    edges[[length(edges) + 1]] <- st_sf(
      defecto = i, tipo = tipo[i], box_no = p$box_no[b], largo_m = round(len, 1), n_vert = nv,
      geometry = st_sfc(ln, crs = CRS_M))
  }
}
edges <- do.call(rbind, edges)

# numeración por tipo, ordenada de mayor a menor área
ord <- order(factor(tipo, c("traslape", "hueco", "astilla")), -area_m2)
new_id <- integer(length(faces))
new_id[ord] <- seq_along(faces)
cajas <- vapply(seq_along(faces), function(i) paste(sort(unique(edges$box_no[edges$defecto == i])), collapse = "/"), "")
defects <- data.frame(
  id = new_id, tipo = tipo,
  cajas_traslapadas = vapply(hit, function(h) if (length(h) > 1) paste(p$box_no[h], collapse = "/") else "", ""),
  cajas_vecinas = cajas,
  area_m2 = round(area_m2), area_km2 = round(area_m2 / 1e6, 4), ancho_medio_m = round(width_m, 1),
  n_aristas = as.integer(table(factor(edges$defecto, seq_along(faces)))),
  lon = round(ctr[, 1], 5), lat = round(ctr[, 2], 5)
)
defects <- defects[order(defects$id), ]
edges$defecto <- new_id[edges$defecto]
edges <- edges[order(edges$defecto, edges$box_no), ]
fi <- st_transform(edges, 4326)
mid <- st_coordinates(suppressWarnings(st_point_on_surface(fi)))
edges_tab <- data.frame(defecto = edges$defecto, tipo = edges$tipo, box_no = edges$box_no,
                        largo_m = edges$largo_m, n_vert = edges$n_vert,
                        lon_medio = round(mid[, 1], 5), lat_medio = round(mid[, 2], 5))

write.csv(defects, file.path(out_dir, "goc_topologia_defectos.csv"), row.names = FALSE)
write.csv(edges_tab, file.path(out_dir, "goc_topologia_aristas.csv"), row.names = FALSE)

gpkg <- file.path(out_dir, "goc_topologia_defectos.gpkg")
unlink(gpkg)
fd <- st_transform(faces, 4326)
fd <- st_sf(defects, geometry = st_geometry(fd)[order(new_id)]) # defects ya está ordenado por id
st_write(fd, gpkg, layer = "defectos", quiet = TRUE)
st_write(cbind(edges_tab, geometry = st_geometry(fi)) |> st_as_sf(), gpkg, layer = "aristas", quiet = TRUE)

cat("Archivo:", in_shp, "\n")
print(table(defects$tipo))
cat(sprintf("Área total: huecos %.2f km2, astillas %.2f km2, traslapes %.2f km2\n",
            sum(defects$area_km2[defects$tipo == "hueco"]), sum(defects$area_km2[defects$tipo == "astilla"]),
            sum(defects$area_km2[defects$tipo == "traslape"])))
cat("Aristas:", nrow(edges_tab), "| largo total:", round(sum(edges_tab$largo_m) / 1000, 1), "km\n")
print(defects, row.names = FALSE)
