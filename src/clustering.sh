#!/bin/sh

################################################################################
# Initialize shell environment
################################################################################

set -eu
umask 0022
export LC_ALL=C

################################################################################
# I/O naming
################################################################################

#===========================================================
# Auguments
#===========================================================

barcode="${1}"
alleletype="${2}"
threads="${3}"

#===========================================================
# Input
#===========================================================

suffix="${barcode}"_"${alleletype}"
mapping_alleletype="${alleletype}"
[ "$alleletype" = "normal" ] && mapping_alleletype="wt"
[ "$alleletype" = "abnormal" ] && mapping_alleletype="wt"

control_RDS=".DAJIN_temp/clustering/temp/df_control_freq_${mapping_alleletype}.RDS"

#===========================================================
# Output
#===========================================================

mkdir -p ".DAJIN_temp/clustering/temp/"
# hdbscan_id=".DAJIN_temp/clustering/temp/hdbscan_${suffix}"

#===========================================================
# Temporal
#===========================================================

MIDS_que=".DAJIN_temp/clustering/temp/MIDS_${suffix}".csv
query_score=".DAJIN_temp/clustering/temp/query_score_${suffix}".csv
query_seq=".DAJIN_temp/clustering/temp/query_seq_${suffix}".csv
query_label=".DAJIN_temp/clustering/temp/query_labels_${suffix}".csv

################################################################################
# MIDS conversion
################################################################################

./DAJIN/src/mids_clustering.sh "${barcode}" "${alleletype}" >"${MIDS_que}"

################################################################################
# Filter abnormal reads
################################################################################

if [ _"$alleletype" = "_abnormal" ]; then
    cat "${MIDS_que}" |
        awk '$2 ~ /[a-z]/ || $2 ~ "DDDDDDDDDD" || $2 ~ "SSSSSSSSSS"' |
        cat >.DAJIN_temp/clustering/temp/_MIDS_"${suffix}"
    mv .DAJIN_temp/clustering/temp/_MIDS_"${suffix}" "${MIDS_que}"
fi

################################################################################
# Query seq (compressed MIDS) and Query score (comma-sep MIDS)
################################################################################

#===========================================================
# Output query seq for `clustering_allele_percentage.sh`
#===========================================================

cat "${MIDS_que}" |
    grep "${barcode}" |
    sort -k 1,1 |
    join - .DAJIN_temp/data/DAJIN_MIDS_prediction_result.txt |
    awk -v atype="${alleletype}" '$NF==atype' |
    cut -d " " -f 1,2 |
    cat >"${query_seq}"

#===========================================================
# Output query score
#===========================================================

cat "${query_seq}" |
    cut -d " " -f 2 |
    awk '{n=split($0,array,""); for(i=1;i<=n;i++) printf array[i]","; print ""}' |
    sed "s/,$//" |
    sed "s/[0-9]/I/g" |
    sed "s/[a-z]/I/g" |
    cat >"${query_score}"

################################################################################
# Query label (seqID,barcodeID)
################################################################################

cat "${MIDS_que}" |
    grep "${barcode}" |
    sort -k 1,1 |
    join - .DAJIN_temp/data/DAJIN_MIDS_prediction_result.txt |
    awk -v atype="${alleletype}" '$NF==atype' |
    cut -d " " -f 1,3,4 |
    sed "s/ /,/g" |
    cat >"${query_label}"

################################################################################
# Clustering
################################################################################

echo "Clustering ${barcode} ${alleletype}..." >&2
if [ "$(cat ${query_label} | wc -l)" -gt 50 ]; then
    echo "$barcode" "$alleletype" --------------------- >>.DAJIN_temp/log.txt
    Rscript DAJIN/src/clustering.R "${query_score}" "${query_label}" "${control_RDS}" "${threads}" 2>>.DAJIN_temp/log.txt
    Rscript DAJIN/src/clustering_merge.R "${query_score}" "${query_label}" "${control_RDS}" "${threads}" 2>>.DAJIN_temp/log.txt
    ps -au | grep -e "clustering.R" -e "joblib" | awk '{print $2}' | xargs kill 2>/dev/null || :
fi
