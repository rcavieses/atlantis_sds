# Scripts del proyecto Atlantis GOC

Pipeline para obtener, por grupo funcional de Atlantis del Golfo de California, (1) mapas de
idoneidad de hábitat con GLOSSA (BART) y (2) el BGM de cajas y las proporciones de
distribución por caja que pide Atlantis. Todo se corre desde la raíz del proyecto. `data/` y
`outputs/` están en `.gitignore`: son artefactos generados, el código está aquí.

```
ocurrencias + covariables ──► GLOSSA por grupo ──► habitat_suitability_<grupo>.gpkg ─┐
                                                                                     ├─► proporciones por caja
polígonos con profundidad ──► limpieza + BGMeriser ──► goc_boxes_depth.{shp,bgm} ────┘
```

## 1. Ocurrencias y covariables

| Script | Qué hace |
|---|---|
| `assign_functional_groups.R` | Une las ocurrencias con la hoja `taxonomy_master` de `data/grupos_funcionales_Atlantis_GOC.xlsx` y asigna `new_species`/grupo funcional; descarta registros sin nombre nuevo. |
| `fix_occurrence_taxonomy.R` | Corrige etiquetas de grupo funcional en `data/occurrence_data_final_taxonomy.csv` (capitalización, registros `#N/A` sin grupo, códigos `#REF!`, *Anadara* spp. → Bivalves). |
| `download_bathymetry_layer.R`, `download_biooracle_layers.R` | Descargan batimetría y covariables Bio-ORACLE (climatología 2010-2019, `mean`, superficie) a `data/biooracle_2010_2019/`. |
| `aggregate_sst_annual.R`, `aggregate_primary_production_annual.R` | Agregan SST y producción primaria de mensual a anual y las empaquetan en el ZIP que exige `read_layers_zip()`. |
| `build_fit_layers_biooracle.R` | Empaqueta las capas estáticas Bio-ORACLE (se replican por timestamp). |
| `build_fit_layers_2015_2025.R` | Combina PP, SST y Bio-ORACLE en `data/fit_layers_2015_2025.zip` (11 años, misma malla que SST). |
| `download_biooracle_future_layers.R`, `build_proj_layers_2050.R` | Capas futuras 2050 (SSP1-2.6 y SSP5-8.5) y ZIP de proyección. |
| `compute_mess_2050.R` | Análisis MESS: zonas de extrapolación de las proyecciones 2050. |

## 2. Modelos GLOSSA por grupo funcional

`run_glossa_group.R "<grupo>"` ajusta BART para un grupo con ocurrencias 2015-2025 de
`data/occurrence_data_final_taxonomy.csv` (filtra `atlantis_fg == <grupo>`, mínimo 30 registros),
covariables `CHL, SST, so, o2, ph, bathymetry` de `data/fit_layers_2015_2025.zip`, zona de
estudio `data/zona_estudio.gpkg`, pseudo-ausencias aleatorias (`pa_ratio = 1`), `scale_layers =
TRUE`, semilla 123, variantes *native range* y *suitable habitat* e importancia de variables.
Escribe `outputs/habitat_suitability_<slug>.{gpkg,png}` (predicción media del modelo *suitable
habitat*, 0-1, 0.05°), `outputs/variable_importance_*_<slug>.csv` y
`data/glossa_result_<slug>_2015_2025.rds`.

```bash
Rscript inst/scripts/run_glossa_group.R "Reef Carnivores"        # un grupo
bash inst/scripts/run_all_groups.sh                              # lote: grupos de outputs/logs/groups_to_run.txt, 2 en paralelo
bash inst/scripts/run_remaining_groups.sh "Grupo A" "Grupo B"    # reanuda grupos concretos, en paralelo
```

Los logs van a `outputs/logs/` (`_summary_all_groups.tsv` resume OK/FAILED por grupo).
`alarm_when_done.sh` avisa en la terminal cuando termina el lote. `run_glossa.R` es la entrada
por línea de comandos genérica de GLOSSA; `run_glossa_reef_carnivores.R` y
`rerun_all_functional_groups.sh` son versiones anteriores del lote.

**Los mapas de idoneidad no dependen de los polígonos de cajas**: solo de las ocurrencias, las
capas ambientales y `zona_estudio.gpkg`. Cambiar el shapefile de cajas no obliga a re-correr
GLOSSA, solo los pasos de la sección 3.

## 3. Cajas, BGM y proporciones por caja (versión 10172026)

Entrada: `goc_polygons_bgm_depth_atlantis_10172026.zip` → se extrae a
`data/goc_polygons_depth_atlantis_10172026/` (113 cajas, `box_no` 0-112: 96 dinámicas, 14 isla,
3 frontera; campos `box_no`, `plygn_t`, `region`, `mn_dpth`, `dep_lyr`, ...).

### 3.1 (opcional) Diagnóstico de topología — `list_topology_defects.R`

```bash
Rscript inst/scripts/list_topology_defects.R [shapefile]
```

Nodifica todos los bordes, reconstruye caras y lista huecos, astillas (< 200 m de ancho medio)
y traslapes, más las aristas de caja que los limitan. Escribe en `data/goc_polygons_depth_bgm/`:
`goc_topologia_defectos.csv`, `goc_topologia_aristas.csv` y `goc_topologia_defectos.gpkg`.
**Escribe siempre en esa carpeta, también si se le pasa otro shapefile.** Para 10172026
encuentra 4 defectos (1 traslape de área 0 y 3 astillas, 0.32 km² en total; cajas 97/99/101/102
y 1/2/6/13) y ningún hueco.

### 3.2 Limpieza + BGM — `build_bgm_depth.R`

```bash
Rscript inst/scripts/build_bgm_depth.R        # requiere java y tools/bgmeriser.jar
```

1. Proyecta a México ITRF2008 / LCC (EPSG:6372), nodifica los bordes y reconstruye la cobertura
   con `st_polygonize`.
2. En traslapes gana la caja más pequeña; astillas y huecos pasan a la vecina con la que
   comparten más borde.
3. Si una caja queda en varias partes, las menores pasan a la vecina con más borde común
   (la mayor conserva el `box_id`). Se verifica: una sola parte, sin agujeros, válida.
4. Atributos: `box_id` = `box_no`, `boundary` (1 si frontera), `botz` = profundidad media
   (`mn_dpth`, islas = 0), `plygn_t`, `region`, `area_km2` (en LAEA), `dep_max`, punto medio.
5. Reproyecta a metros (`+proj=laea +lat_0=26 +lon_0=-110 +datum=WGS84`) y corre
   `java -jar tools/bgmeriser.jar -as "<proj>" goc_boxes_depth_laea.shp goc_boxes_depth.bgm`.
   Si BGMeriser deja vacío o fuera de la caja el `box#.inside`, se reemplaza por un punto
   dentro de la caja.

Salidas en `data/goc_polygons_depth_bgm/`: `goc_boxes_depth.shp` (WGS84, cajas limpias),
`goc_boxes_depth_laea.shp` (metros), `goc_boxes_depth.bgm`, `goc_boxes_depth.gpkg` (capas
`cajas_<n>`, `cajas_originales`, `cambios_area`) y `goc_boxes_depth_cambios.csv`. Con 10172026:
113 cajas, 679 caras, ninguna caja cambia de área ≥ 1 km²; los `inside` de las cajas 17, 25 y
104 se corrigen.

Para generar un BGM **sin** limpieza (no recomendado: caras duplicadas o sin vértices
compartidos, `inside` fuera de caja en 17, 25, 37 y 104):

```bash
P='+proj=laea +lat_0=26 +lon_0=-110 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs'
ogr2ogr -t_srs "$P" -dialect sqlite -sql "SELECT geometry, CAST(box_no AS integer) AS box_id,
  CASE WHEN plygn_t='boundary' THEN 1 ELSE 0 END AS boundary,
  CASE WHEN plygn_t='island' THEN 0 ELSE ROUND(mn_dpth,1) END AS botz
  FROM goc_polygons_bgm_depth_atlantis ORDER BY box_no" raw_laea.shp \
  data/goc_polygons_depth_atlantis_10172026/goc_polygons_bgm_depth_atlantis.shp
java -jar tools/bgmeriser.jar -as "$P" raw_laea.shp raw.bgm
```

### 3.3 Proporciones por caja — `compute_box_proportions_depth.R`

```bash
Rscript inst/scripts/compute_box_proportions_depth.R   # requiere 3.2 y los habitat_suitability_*.gpkg
```

Lee `data/goc_polygons_depth_bgm/goc_boxes_depth.shp`, todos los
`outputs/habitat_suitability_*.gpkg` y los códigos Atlantis de la hoja `final_groups` de
`data/grupos_funcionales_Atlantis_GOC.xlsx`. Con `terra::extract(exact = TRUE)` pondera cada
celda por su fracción dentro de la caja × área de celda. Las celdas con idoneidad < `min_suit`
(0.3) cuentan como 0. Por caja y grupo `<COD>`:

- `pr_<COD>`: idoneidad media ponderada por área (0-1).
- `pp_<COD>`: idoneidad integrada de la caja / total de las cajas dinámicas; suma 1 por grupo.
  Es el vector de `FXXX_S1..S4` y `XXX_recruit_hdistrib` de Atlantis (supone abundancia
  proporcional a la idoneidad).
- `pa_<COD>`: fracción del área de la caja con idoneidad ≥ 0.3.

Cajas frontera e isla: `pp = 0`, `pr`/`pa` = NA. Las dinámicas sin celdas de idoneidad
(caja 40 en 10172026) quedan con `pp = 0` y `pr` NA. Salidas en
`outputs/atlantis_box_proportions_depth/`: `goc_box_proportions.shp` (60 grupos × 3 columnas) y
`goc_box_proportions_long.csv` (`box_no, region, box_type, atlantis_code, group,
prob_occurrence, proportion, area_fraction`).

### 3.4 Entrega

El zip `data/goc_polygons_bgm_depth_clean_10172026.zip` se armó a mano con `zip` (no hay
script): `goc_boxes_depth.bgm`, `.gpkg`, `_cambios.csv`, los shapefiles WGS84 y LAEA, la
carpeta `proporciones/` y un `LEEME.txt`.
