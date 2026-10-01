# Asigna grupo funcional (Atlantis GOC) a los registros de ocurrencia.
#
# Une data/final_taxonomy_occ.csv con la hoja "taxonomy_master" de
# data/grupos_funcionales_Atlantis_GOC.xlsx por species == old_species,
# asigna new_species, y elimina los registros sin nuevo nombre asignado
# (sin match en la tabla, o con new_species == "NA").

library(readxl)
library(readr)
library(dplyr)

occ <- read_csv("data/final_taxonomy_occ.csv", show_col_types = FALSE)
tax <- read_excel("data/grupos_funcionales_Atlantis_GOC.xlsx", sheet = "taxonomy_master")

joined <- occ %>%
  left_join(tax %>% select(old_species, new_species), by = c("species" = "old_species"))

n_no_match <- sum(is.na(joined$new_species))
n_explicit_na <- sum(joined$new_species == "NA", na.rm = TRUE)

result <- joined %>%
  filter(!is.na(new_species), new_species != "NA")

cat("Registros originales:", nrow(occ), "\n")
cat("Sin match en taxonomy_master:", n_no_match, "\n")
cat("Con nuevo nombre 'NA' (eliminados de la tabla):", n_explicit_na, "\n")
cat("Registros eliminados en total:", nrow(joined) - nrow(result), "\n")
cat("Registros finales:", nrow(result), "\n")

write_csv(result, "data/final_taxonomy_occ_functional_groups.csv")
