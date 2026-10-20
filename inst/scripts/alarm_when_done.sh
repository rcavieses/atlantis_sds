#!/usr/bin/env bash
# Espera "ALL DONE" en el resumen del lote y suena la campana (BEL) en la terminal pts/0.
cd "$(dirname "$0")/../.." || exit 1
until grep -q "ALL DONE" outputs/logs/_summary_all_groups.tsv 2>/dev/null; do sleep 20; done
for i in 1 2 3 4 5 6; do printf '\a' > /dev/pts/0; sleep 1; done
printf '\n*** GLOSSA terminó (%s) -- ver outputs/logs/_summary_all_groups.tsv ***\n\a' "$(date '+%F %T')" > /dev/pts/0
