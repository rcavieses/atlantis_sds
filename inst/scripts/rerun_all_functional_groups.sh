#!/usr/bin/env bash
# Re-corre run_glossa_group.R para los 23 grupos funcionales que ya
# tenian resultados en data/glossa_result_*_2015_2025.rds, ahora que
# fit_layers_2015_2025.zip incluye la covariable "bathymetry".
set -uo pipefail

groups=(
  "Amberjacks"
  "Billfish"
  "Coastal Planktivores"
  "Drums and croakers"
  "Flatfish"
  "Groupers"
  "Guitarfish"
  "Hammerhead Sharks"
  "Lanternfish and Deep"
  "Large Pelagic fish"
  "Large sharks and rays"
  "Mullets"
  "Oceanic fish and elasmobranchs"
  "Other Demersal Fish"
  "Other pelagic fish"
  "Other Tunas"
  "Pelagic Sharks"
  "Reef Carnivores"
  "Reef Herbivores and planktivores"
  "Scorpionfish"
  "Small sharks and rays"
  "Snappers"
  "Yellowfin Tuna"
)

mkdir -p outputs/logs
overall_log="outputs/logs/rerun_all_functional_groups.log"
: > "$overall_log"

for g in "${groups[@]}"; do
  slug=$(echo "$g" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g')
  log="outputs/logs/run_glossa_group_${slug}.log"
  echo "=== $(date '+%F %T') START: $g ===" | tee -a "$overall_log"
  if Rscript inst/scripts/run_glossa_group.R "$g" > "$log" 2>&1; then
    echo "=== $(date '+%F %T') OK: $g ===" | tee -a "$overall_log"
  else
    echo "=== $(date '+%F %T') FAILED: $g (see $log) ===" | tee -a "$overall_log"
  fi
done

echo "=== $(date '+%F %T') ALL DONE ===" | tee -a "$overall_log"
