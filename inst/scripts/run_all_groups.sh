#!/usr/bin/env bash
# Corre run_glossa_group.R para cada grupo de outputs/logs/groups_to_run.txt
# (grupos con >= 30 registros 2015-2025), 2 grupos en paralelo.
cd "$(dirname "$0")/../.." || exit 1
run_one() {
  g="$1"; slug=$(echo "$g" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g')
  log="outputs/logs/run_glossa_group_${slug}.log"
  s=$(date '+%F %T')
  if Rscript inst/scripts/run_glossa_group.R "$g" > "$log" 2>&1; then st=OK; else st=FAILED; fi
  printf '%s\t%s\t%s\t%s\n' "$g" "$st" "$s" "$(date '+%F %T')" >> outputs/logs/_summary_all_groups.tsv
}
export -f run_one
: > outputs/logs/_summary_all_groups.tsv
tr '\n' '\0' < outputs/logs/groups_to_run.txt | xargs -0 -P 2 -I{} bash -c 'run_one "$1"' _ {}
echo "ALL DONE $(date '+%F %T')" >> outputs/logs/_summary_all_groups.tsv
