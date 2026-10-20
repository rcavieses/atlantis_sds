# Corrige inconsistencias de grupo funcional en
# data/occurrence_data_final_taxonomy.csv:
#   1. "Benthic grazers" -> "Benthic Grazers" (misma etiqueta, distinta capitalizacion).
#   2. Registros con atlantis_fg/code "#N/A" (manglar, plantas terrestres,
#      parasitos, hongos, "Laridae sp."): sin grupo funcional, se eliminan.
#   3. "Other Shrimps" con codigo "#N/A" -> OSH (codigo en group_list).
#   4. Codigo "#REF!" (Microlepidotus inornatus, pez) -> Other Demersal Fish / ODF,
#      segun taxonomy_master.
#   5. Anadara spp. etiquetadas como Benthic Grazers/BG (subgeneros antiguos) ->
#      Bivalves / BIV, segun taxonomy_master.

library(readr)
library(dplyr)

f <- "data/occurrence_data_final_taxonomy.csv"
d <- read_csv(f, show_col_types = FALSE, na = "")

n0 <- nrow(d)
d <- d %>%
  mutate(
    atlantis_fg = ifelse(atlantis_fg == "Benthic grazers", "Benthic Grazers", atlantis_fg),
    is_anadara = atlantis_code == "BG" & grepl("^Anadara ", species)
  )
d$atlantis_fg[d$is_anadara] <- "Bivalves"; d$atlantis_code[d$is_anadara] <- "BIV"
d$atlantis_code[d$atlantis_fg == "Other Shrimps"] <- "OSH"
i <- d$atlantis_code == "#REF!" & d$species == "Microlepidotus inornatus"
d$atlantis_fg[i] <- "Other Demersal Fish"; d$atlantis_code[i] <- "ODF"
d <- d %>% select(-is_anadara) %>% filter(atlantis_fg != "#N/A", atlantis_code != "#N/A", atlantis_code != "#REF!")

stopifnot(!anyNA(d$atlantis_fg), !anyNA(d$atlantis_code))
chk <- d %>% distinct(atlantis_fg, atlantis_code)
stopifnot(!anyDuplicated(chk$atlantis_fg), !anyDuplicated(chk$atlantis_code))
message("Registros: ", n0, " -> ", nrow(d), "; grupos funcionales: ", nrow(chk))
write_csv(d, f, na = "")
