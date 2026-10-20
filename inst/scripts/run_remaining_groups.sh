#!/usr/bin/env bash
# Reanuda el lote: corre los grupos pasados como argumentos, todos en paralelo.
cd "$(dirname "$0")/../.." || exit 1
for g in "$@"; do
  (
    slug=$(echo "$g" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g')
    s=$(date '+%F %T')
    if Rscript inst/scripts/run_glossa_group.R "$g" > "outputs/logs/run_glossa_group_${slug}.log" 2>&1; then st=OK; else st=FAILED; fi
    printf '%s\t%s\t%s\t%s\n' "$g" "$st" "$s" "$(date '+%F %T')" >> outputs/logs/_summary_all_groups.tsv
  ) &
done
wait
echo "ALL DONE $(date '+%F %T')" >> outputs/logs/_summary_all_groups.tsv
