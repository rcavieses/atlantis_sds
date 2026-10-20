# BGM de Atlantis GOC a partir de las cajas con profundidad (113 cajas en la
# versión 10172026: data/goc_polygons_depth_atlantis_10172026/goc_polygons_bgm_depth_atlantis.shp).
#
# La numeración box_no (0-113) del shapefile se conserva como box_id del BGM,
# y botz es la profundidad MEDIA de la caja (campo mn_dpth; islas = 0).
#
# BGMeriser exige cajas de una sola parte, sin traslapes ni huecos y con
# vértices compartidos entre vecinas, así que antes se limpia la topología:
#  1. Se nodan todos los bordes y se reconstruye una cobertura (st_polygonize).
#  2. En zonas cubiertas por varias cajas (traslapes) gana la caja más pequeña.
#  3. Astillas y huecos se asignan a la caja vecina con la que comparten más borde.
#  4. Si una caja queda en varias partes, las partes menores se asignan a la
#     vecina con más borde en común (la parte mayor conserva el box_id).
# El número y la numeración de las cajas no cambian.
#
# Salidas (data/goc_polygons_depth_bgm/): goc_boxes_depth.shp (WGS84, cajas
# limpias), goc_boxes_depth_laea.shp (metros, entrada de BGMeriser),
# goc_boxes_depth.bgm, goc_boxes_depth.gpkg y goc_boxes_depth_cambios.csv.

library(sf)
sf_use_s2(FALSE)

CRS_M <- 6372 # Mexico ITRF2008 / LCC, en metros
PROJ_BGM <- "+proj=laea +lat_0=26 +lon_0=-110 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs"
in_shp <- "data/goc_polygons_depth_atlantis_10172026/goc_polygons_bgm_depth_atlantis.shp"
out_dir <- "data/goc_polygons_depth_bgm"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

p0 <- st_read(in_shp, quiet = TRUE)
p0 <- p0[order(p0$box_no), ]
stopifnot(identical(as.integer(p0$box_no), seq_len(nrow(p0)) - 1L))
p <- st_transform(p0, CRS_M)

# ---- utilidades (mismas que build_boxes_v2.R) ----
line_len <- function(x) {
  x <- x[!st_is_empty(x)]
  if (!length(x)) return(0)
  if (any(st_geometry_type(x) == "GEOMETRYCOLLECTION")) x <- suppressWarnings(st_collection_extract(x, "LINESTRING"))
  x <- x[st_geometry_type(x) %in% c("LINESTRING", "MULTILINESTRING")]
  if (!length(x)) return(0)
  sum(as.numeric(st_length(x)))
}
shared <- function(a, b) line_len(st_intersection(st_boundary(a), st_boundary(b)))

build_faces <- function(geoms) {
  noded <- st_union(st_geometry(st_cast(st_boundary(geoms), "MULTILINESTRING")))
  st_cast(st_collection_extract(st_polygonize(noded), "POLYGON"), "POLYGON")
}
edge_nb <- function(g) st_relate(g, g, pattern = "F***1****")

assign_owner <- function(faces, geoms) {
  hit <- st_intersects(st_point_on_surface(faces), geoms)
  ga <- as.numeric(st_area(geoms))
  vapply(hit, function(h) if (length(h)) h[which.min(ga[h])] else NA_integer_, integer(1))
}

fill_owner <- function(faces, own, nb) {
  repeat {
    na <- which(is.na(own))
    if (!length(na)) return(own)
    changed <- FALSE
    for (i in na) {
      cand <- nb[[i]][!is.na(own[nb[[i]]])]
      if (!length(cand)) next
      len <- vapply(cand, function(j) shared(faces[i], faces[j]), numeric(1))
      tot <- tapply(len, own[cand], sum)
      own[i] <- as.integer(names(tot)[which.max(tot)])
      changed <- TRUE
    }
    if (!changed) stop("Hay caras sin asignar sin vecinos asignados")
  }
}

components <- function(idx, nb) {
  left <- idx
  out <- list()
  while (length(left)) {
    seen <- q <- left[1]
    while (length(q)) {
      nx <- setdiff(intersect(nb[[q[1]]], left), seen)
      seen <- c(seen, nx)
      q <- c(q[-1], nx)
    }
    out[[length(out) + 1]] <- seen
    left <- setdiff(left, seen)
  }
  out
}

fix_disconnected <- function(faces, own, nb) {
  area <- as.numeric(st_area(faces))
  repeat {
    moved <- FALSE
    for (k in unique(own)) {
      comp <- components(which(own == k), nb)
      if (length(comp) < 2) next
      ca <- vapply(comp, function(cc) sum(area[cc]), numeric(1))
      for (cc in comp[-which.max(ca)]) {
        message(sprintf("Caja %d: parte de %.2f km2 pasa a una vecina", p$box_no[k], sum(area[cc]) / 1e6))
        own[cc] <- NA
      }
      moved <- TRUE
    }
    if (!moved) return(own)
    own <- fill_owner(faces, own, nb)
  }
}

# ---- 1-4. cobertura limpia ----
faces <- build_faces(st_geometry(p))
nb <- edge_nb(faces)
own0 <- assign_owner(faces, st_geometry(p))
message("Caras: ", length(faces), " | huecos/astillas: ", sum(is.na(own0)),
        " | caras traslapadas: ", sum(vapply(st_intersects(st_point_on_surface(faces), st_geometry(p)), length, 1L) > 1))
own <- fix_disconnected(faces, fill_owner(faces, own0, nb), nb)
stopifnot(setequal(unique(own), seq_len(nrow(p))))

G <- do.call(c, lapply(seq_len(nrow(p)), function(k) st_union(faces[own == k])))
st_crs(G) <- st_crs(p)
n_parts <- vapply(G, function(x) if (inherits(x, "MULTIPOLYGON")) length(x) else 1L, integer(1))
n_holes <- vapply(G, function(x) {
  if (inherits(x, "POLYGON")) return(length(x) - 1L)
  sum(vapply(x, function(pp) length(pp) - 1L, integer(1)))
}, integer(1))
stopifnot(all(n_parts == 1), all(n_holes == 0), all(st_is_valid(G)))

area_new <- as.numeric(st_area(G)) / 1e6
area_old <- as.numeric(st_area(p)) / 1e6
chg <- data.frame(box_no = p$box_no, area_orig_km2 = round(area_old, 2), area_nueva_km2 = round(area_new, 2),
                  dif_km2 = round(area_new - area_old, 2), dif_pct = round(100 * (area_new / area_old - 1), 2))
write.csv(chg, file.path(out_dir, "goc_boxes_depth_cambios.csv"), row.names = FALSE)
big <- chg[abs(chg$dif_km2) >= 1, ]
message("Cajas con cambio de área >= 1 km2:\n", paste(capture.output(print(big, row.names = FALSE)), collapse = "\n"))

# ---- atributos ----
v <- st_transform(st_sf(
  box_id = as.integer(p$box_no),
  boundary = as.integer(p$plygn_t == "boundary"),
  botz = round(p$mn_dpth, 1),
  plygn_t = p$plygn_t,
  region = p$region,
  area_km2 = NA_real_,
  dep_max = p$dep_lyr,
  geometry = G
), 4326)
# área en la proyección equivalente del BGM (la cónica LCC de arriba solo se usó para la topología)
v$area_km2 <- round(as.numeric(st_area(st_transform(v, PROJ_BGM))) / 1e6, 2)
v$botz[v$plygn_t == "island"] <- 0
v$dep_max[v$plygn_t == "island"] <- 0
stopifnot(!anyNA(v$botz))
mid <- st_coordinates(suppressWarnings(st_point_on_surface(v)))
v$mdpnt_ln <- round(mid[, 1], 5)
v$mdpnt_lt <- round(mid[, 2], 5)

st_write(v, file.path(out_dir, "goc_boxes_depth.shp"), delete_dsn = TRUE, quiet = TRUE)

# ---- BGM ----
# Atlantis toma áreas y volúmenes de las coordenadas del BGM, así que va en metros.
bgm_shp <- file.path(out_dir, "goc_boxes_depth_laea.shp")
bgm_file <- file.path(out_dir, "goc_boxes_depth.bgm")
v_m <- st_transform(v, PROJ_BGM)
st_write(v_m, bgm_shp, delete_dsn = TRUE, quiet = TRUE)
unlink(bgm_file)
log <- system2("java", c("-jar", "tools/bgmeriser.jar", "-as", shQuote(PROJ_BGM), bgm_shp, bgm_file),
               stdout = TRUE, stderr = TRUE)
if (!file.exists(bgm_file)) stop("BGMeriser falló:\n", paste(log, collapse = "\n"))
message(paste(grep("error|warn|abort|island|inside", log, ignore.case = TRUE, value = TRUE), collapse = "\n"))

# BGMeriser deja vacío box#.inside cuando su punto cae fuera de una caja cóncava
bgm <- readLines(bgm_file)
inside_pt <- st_coordinates(suppressWarnings(st_point_on_surface(st_geometry(v_m))))
empty <- grep("^box[0-9]+\\.inside\\s*$", bgm)
for (i in empty) {
  b <- as.integer(sub("^box([0-9]+)\\..*", "\\1", bgm[i]))
  bgm[i] <- sprintf("box%d.inside\t%.3f %.3f", b, inside_pt[b + 1, 1], inside_pt[b + 1, 2])
}

# BGMeriser escribe box#.vertmix y box#.horizmix como NaN; Atlantis necesita valores
# numericos. Se usan los estandar: vertmix 1.0E-6 y horizmix 1.0 para todas las cajas.
VERTMIX <- "1.0E-6"
HORIZMIX <- "1.0"
bgm <- sub("^(box[0-9]+\\.vertmix)\\s+NaN\\s*$", paste0("\\1\t", VERTMIX), bgm)
bgm <- sub("^(box[0-9]+\\.horizmix)\\s+NaN\\s*$", paste0("\\1\t", HORIZMIX), bgm)
stopifnot(!any(grepl("NaN", bgm)))
writeLines(bgm, bgm_file)
message("BGM: ", bgm_file, " | ", grep("^nbox", bgm, value = TRUE), " | ", grep("^nface", bgm, value = TRUE),
        " | inside corregidos: ", length(empty), " | vertmix ", VERTMIX, ", horizmix ", HORIZMIX)

# ---- GeoPackage para compartir ----
gpkg <- file.path(out_dir, "goc_boxes_depth.gpkg")
unlink(gpkg)
st_write(v, gpkg, layer = paste0("cajas_", nrow(v)), quiet = TRUE)
st_write(p0, gpkg, layer = "cajas_originales", quiet = TRUE)
st_write(chg, gpkg, layer = "cambios_area", quiet = TRUE)
message("GeoPackage: ", gpkg)
