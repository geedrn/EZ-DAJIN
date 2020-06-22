#!/bin/bash

################################################################################
#! Initialize shell environment
################################################################################

# set -u
umask 0022
export LC_ALL=C
type command >/dev/null 2>&1 && type getconf >/dev/null 2>&1 &&
export UNIX_STD=2003  # to make HP-UX conform to POSIX


################################################################################
#! Define the functions for printing usage and error message
################################################################################
VERSION=1.0

usage(){
cat <<- USAGE
Usage     : DAJIN.sh -f [text file] (described at "Input")

Example   : DAJIN.sh -f DAJIN/example/example.txt

Input     : Input file should be formatted as below:
            # Example
            ------
            design=DAJIN/example/design.txt
            input_dir=DAJIN/example/demultiplex
            control=barcode01
            output_dir=Cables2
            genome=mm10
            grna=CCTGTCCAGAGTGGGAGATAGCC,CCACTGCTAGCTGTGGGTAACCC
            threads=10
            ------
            - desing: a multi-FASTA file contains sequences of each genotype. ">wt" and ">target" must be included. 
            - input_dir: a directory contains FASTA or FASTQ files of long-read sequencing
            - control: control barcode ID
            - output_dir: output directory name. optional. default is DAJIN_results
            - genome: reference genome. e.g. mm10, hg38
            - grna: gRNA sequence(s). multiple gRNA sequences must be deliminated by comma.
            - threads: optional. default is two-thirds of available CPU threads.
USAGE
}

usage_and_exit(){
    usage
    exit 1
}

error_exit() {
    echo "$@" 1>&2
    exit 1
}

################################################################################
#! Parse arguments
################################################################################
[ $# -eq 0 ] && usage_and_exit

while [ $# -gt 0 ]
do
    case "$1" in
        --help | --hel | --he | --h | '--?' | -help | -hel | -he | -h | '-?')
            usage_and_exit
            ;;
        --version | --versio | --versi | --vers | --ver | --ve | --v | \
        -version | -versio | -versi | -vers | -ver | -ve | -v )
            echo "DAJIN version: $VERSION" && exit 0
            ;;
        --file | -f )
            if ! [ -r "$2" ]; then
                error_exit "$2: No such file"
            fi
            design=$(cat "$2" | grep "design" | sed -e "s/ //g" -e "s/.*=//g")
            ont_dir=$(cat "$2" | grep "input_dir" | sed -e "s/ //g" -e "s/.*=//g")
            ont_cont=$(cat "$2" | grep "control" | sed -e "s/ //g" -e "s/.*=//g")
            genome=$(cat "$2" | grep "genome" | sed -e "s/ //g" -e "s/.*=//g")
            grna=$(cat "$2" | grep "grna" | sed -e "s/ //g" -e "s/.*=//g")
            output_dir=$(cat "$2" | grep "output_dir" | sed -e "s/ //g" -e "s/.*=//g")
            threads=$(cat "$2" | grep "threads" | sed -e "s/ //g" -e "s/.*=//g")
            ;;
        -* )
        error_exit "Unrecognized option : $1"
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [ -z "$design" ] || [ -z "$ont_dir" ] || [ -z "$ont_cont" ] || [ -z "$genome" ] || [ -z "$grna" ]
then
    error_exit "Required arguments are not specified"
fi

#===========================================================
#? Check fasta file
#===========================================================

if ! [ -e "$design" ]; then
    error_exit "$design: No such file"
fi

if [ "$(grep -c '>target' ${design})" -eq 0 ] || [ "$(grep -c '>wt' ${design})" -eq 0 ]; then
    error_exit "$design: design must include \">target\" and \">wt\". "
fi

#===========================================================
#? Check directory
#===========================================================

if ! [ -d "${ont_dir}" ]; then
    error_exit "$ont_dir: No such directory"
fi

if [ -z "$(ls $ont_dir)" ]; then
    error_exit "$ont_dir: Empty directory"
fi

#===========================================================
#? Check control
#===========================================================

[ -z "$(find ${ont_dir}/ -name ${ont_cont}.f*)" ] &&
error_exit "$ont_cont: No control file in ${ont_dir}"

#===========================================================
#? Check genome
#===========================================================

genome_check=$(
    wget -qO - "https://gggenome.dbcls.jp/ja/help.html#db_list" |
    grep "href" |
    grep -c "/${genome:-XXX}/")

[ "$genome_check" -eq 0 ] &&
error_exit "$genome: No such reference genome"

#===========================================================
#? Check grna
#===========================================================
[ $(cat "${design}" | grep -c "${grna}") -eq 0 ] &&
error_exit "No gRNA sites"

#===========================================================
#? Check output directory name
#===========================================================
if [ $(echo "$output_dir" | grep  -c -e '\\' -e ':' -e '*' -e '?' -e '"' -e '<' -e '>' -e '|') -eq 1 ]; then
    error_exit "$output_dir: invalid directory name"
fi
mkdir -p "${output_dir:=DAJIN_results}"/BAM "${output_dir}"/Consensus

#===========================================================
#? Define threads
#===========================================================

expr "$threads" + 1 >/dev/null 2>&1
if [ $? -lt 2 ]; then
    :
else
    unset threads
    # Linux and similar...
    threads=$(getconf _NPROCESSORS_ONLN 2>/dev/null | awk '{print int($0/1.5+0.5)}')
    # FreeBSD and similar...
    [ -z "$threads" ] && threads=$(getconf NPROCESSORS_ONLN | awk '{print int($0/1.5)+0.5}')
    # Solaris and similar...
    [ -z "$threads" ] && threads=$(ksh93 -c 'getconf NPROCESSORS_ONLN' | awk '{print int($0/1.5+0.5)}')
    # Give up...
    [ -z "$threads" ] && threads=1
fi

################################################################################
#! Setting Conda environment
################################################################################

#===========================================================
#? DAJIN_nanosim
#===========================================================

CONDA_BASE=$(conda info --base)
source "${CONDA_BASE}/etc/profile.d/conda.sh"

if [ "$(conda info -e | grep -c DAJIN_nanosim)" -eq 0 ]; then
    conda config --add channels defaults
    conda config --add channels bioconda
    conda config --add channels conda-forge
    conda create -y -n DAJIN_nanosim python=3.6
    conda install -y -n DAJIN_nanosim --file ./DAJIN/utils/NanoSim/requirements.txt
    conda install -y -n DAJIN_nanosim minimap2
fi
#===========================================================
#? DAJIN
#===========================================================

if [ "$(conda info -e | cut -d " " -f 1 | grep -c DAJIN$)" -eq 0 ]; then
    conda config --add channels defaults
    conda config --add channels bioconda
    conda config --add channels conda-forge
    conda create -y -n DAJIN python=3.6 \
        anaconda nodejs wget gawk \
        tensorflow tensorflow-gpu swifter \
        samtools minimap2 \
        r-essentials r-base
fi

#===========================================================
#? Required software
#===========================================================

# type gzip > /dev/null 2>&1 || error_exit 'Command "gzip" not found'
# type wget > /dev/null 2>&1 || error_exit 'Command "wget" not found'
# type python > /dev/null 2>&1 || error_exit 'Command "python" not found'
# type samtools > /dev/null 2>&1 || error_exit 'Command "samtools" not found'
# type minimap2 > /dev/null 2>&1 || error_exit 'Command "minimap2" not found'

# python -c "import tensorflow as tf" > /dev/null 2>&1 ||
# error_exit '"Tensorflow" not found'

#===========================================================
#? For WSL (Windows Subsystem for Linux)
#===========================================================

uname -a | 
grep Microsoft 1>/dev/null 2>/dev/null &&
alias python="python.exe"

################################################################################
#! Formatting environments
################################################################################

#===========================================================
#? Make temporal directory
#===========================================================
rm -rf ".DAJIN_temp" 2>/dev/null || true
dirs="fasta fasta_conv fasta_ont NanoSim bam igvjs data clustering/temp seqlogo/temp"

echo "${dirs}" |
    sed "s:^:.DAJIN_temp/:g" |
    sed "s: : .DAJIN_temp/:g" |
xargs mkdir -p

#===========================================================
#? Format FASTA file
#===========================================================

cat "${design}" |
    tr -d "\r" |
    awk '{if($1~"^>"){print "\n"$0}
    else {printf $0}}
    END {print ""}' |
    grep -v "^$" |
cat > .DAJIN_temp/fasta/fasta.fa

design_LF=".DAJIN_temp/fasta/fasta.fa"

# Separate multiple-FASTA into FASTA files
cat ${design_LF} |
    sed "s/^/@/g" |
    tr -d "\n" |
    sed -e "s/@>/\n>/g" \
        -e "s/@/ /g" \
        -e "s/$/\n/g" |
    grep -v "^$" |
    awk '{id=$1
        gsub(">","",id)
        output=".DAJIN_temp/fasta/"id".fa"
        print $1"\n"toupper($2) > output
    }'

#===========================================================
#? Reverse complement if the mutation sites are closer
#? to right flanking than left flanking 
#===========================================================

wt_seqlen=$(awk '!/[>|@]/ {print length($0)}' .DAJIN_temp/fasta/wt.fa)

convert_revcomp=$(
    minimap2 -ax splice \
    .DAJIN_temp/fasta/wt.fa \
    .DAJIN_temp/fasta/target.fa --cs 2>/dev/null |
    awk '{for(i=1; i<=NF;i++) if($i ~ /cs:Z/) print $i}' |
    sed -e "s/cs:Z:://g" -e "s/:/\t/g" -e "s/~/\t/g" |
    tr -d "\~\*\-\+atgc" |
    awk '{$NF=0; for(i=1;i<=NF;i++) sum+=$i} END{print $1,sum}' |
    awk -v wt_seqlen="$wt_seqlen" \
    '{if(wt_seqlen-$2>$1) print 0; else print 1}'
    )

if [ "$convert_revcomp" -eq 1 ] ; then
    cat "${design_LF}" |
        ./DAJIN/src/revcomp.sh - |
    cat > .DAJIN_temp/fasta/fasta_revcomp.fa
    design_LF=".DAJIN_temp/fasta/fasta_revcomp.fa"
fi

#---------------------------------------
#* Separate multiple-FASTA into FASTA files
#---------------------------------------
cat ${design_LF} |
    sed "s/^/@/g" |
    tr -d "\n" |
    sed -e "s/@>/\n>/g" \
        -e "s/@/ /g" \
        -e "s/$/\n/g" |
    grep -v "^$" |
    awk '{id=$1
        gsub(">","",id)
        output=".DAJIN_temp/fasta_conv/"id".fa"
        print $1"\n"toupper($2) > output
    }'

#---------------------------------------
#* Define mutation type
#---------------------------------------
mutation_type=$(
    minimap2 -ax map-ont \
        .DAJIN_temp/fasta/wt.fa \
        .DAJIN_temp/fasta/target.fa \
        --cs 2>/dev/null |
    grep -v "^@" |
    awk '{
        cstag=$(NF-1)
        if(cstag ~ "-") print "D"
        else if(cstag ~ "\+") print "I"
        else if(cstag ~ "\*") print "P"
        }' 2>/dev/null
)

#---------------------------------------
#* Targetが一塩基変異の場合: 
#* Cas9の切断部に対してgRNA部自体の欠損およびgRNA長分の塩基挿入したものを異常アレルとして作成する
#---------------------------------------

if [ "_${mutation_type}" = "_P" ]; then
    grna_len=$(awk -v grna="$grna" 'BEGIN{print length(grna)}')
    grna_firsthalf=$(awk -v grna="$grna" 'BEGIN{print substr(grna, 1, int(length(grna)/2))}')
    grna_secondhalf=$(awk -v grna="$grna" 'BEGIN{print substr(grna, int(length(grna)/2)+1, length(grna))}')
    # ランダム配列の作成
    ins_seq=$(
        seq_length="$grna_len" &&
        od -A n  -t u4 -N $(($seq_length*100)) /dev/urandom |
        tr -d "\n" |
        sed 's/[^0-9]//g' |
        sed "s/[4-9]//g" |
        sed -e "s/0/A/g" -e "s/1/G/g" -e "s/2/C/g" -e "s/3/T/g" |
        awk -v seq_length=$seq_length '{print substr($0, 1, seq_length)}'
    )
    # insertion
    cat .DAJIN_temp/fasta_conv/wt.fa |
        sed "s/$grna/$grna_firsthalf,$grna_secondhalf/g" |
        sed "s/,/$ins_seq/g" |
        sed "s/>wt/>wt_ins/g" |
    cat > .DAJIN_temp/fasta_conv/wt_ins.fa
    # deletion
    cat .DAJIN_temp/fasta_conv/wt.fa |
        sed "s/$grna//g" |
        sed "s/>wt/>wt_del/g" |
    cat > .DAJIN_temp/fasta_conv/wt_del.fa
fi

#---------------------------------------
#* Format ONT reads into FASTA file
#---------------------------------------

for input in ${ont_dir}/* ; do
    output=$(
        echo "${input}" |
        sed -e "s#.*/#.DAJIN_temp/fasta_ont/#g" \
            -e "s#\.f.*#.fa#g")
    # Check wheather the files are binary:
    if [ "$(file ${input} | grep -c compressed)" -eq 1 ]
    then
        gzip -dc "${input}"
    else
        cat "${input}"
    fi |
    awk '{if((4+NR)%4==1 || (4+NR)%4==2) print $0}' |
    sed "s/^@/>/g" |
    cat > "${output}"
done

################################################################################
#! NanoSim (v2.5.0)
################################################################################

conda activate DAJIN_nanosim

cat << EOF
++++++++++++++++++++++++++++++++++++++++++
NanoSim read simulation
++++++++++++++++++++++++++++++++++++++++++
EOF

#===========================================================
#? NanoSim
#===========================================================

printf "Read analysis...\n"
./DAJIN/utils/NanoSim/src/read_analysis.py genome \
    -i ".DAJIN_temp/fasta_ont/${ont_cont}.fa" \
    -rg .DAJIN_temp/fasta_conv/wt.fa \
    -t ${threads:-1} \
    -o .DAJIN_temp/NanoSim/training

wt_seqlen=$(awk '!/[>|@]/ {print length($0)}' .DAJIN_temp/fasta/wt.fa)

for input in .DAJIN_temp/fasta_conv/*; do
    printf "${input} is now simulating...\n"
    output=$(
        echo "$input" |
        sed -e "s#fasta_conv/#fasta_ont/#g" \
            -e "s/.fasta$//g" -e "s/.fa$//g"
        )
    ## For deletion allele
    input_seqlength=$(
        cat "${input}" |
        awk '!/[>|@]/ {print length($0)-100}'
        )
    if [ "$input_seqlength" -lt "$wt_seqlen" ]; then
        len=${input_seqlength}
    else
        len=${wt_seqlen}
    fi
    ##
    ./DAJIN/utils/NanoSim/src/simulator.py genome \
        -dna_type linear \
        -c .DAJIN_temp/NanoSim/training \
        -rg "${input}" \
        -n 10000 \
        -t "${threads:-1}" \
        -min "${len}" \
        -o "${output}_simulated"
    ##
    rm .DAJIN_temp/fasta_ont/*_error_* .DAJIN_temp/fasta_ont/*_unaligned_* 2>/dev/null || true
done

rm -rf DAJIN/utils/NanoSim/src/__pycache__

printf 'Success!!\nSimulation is finished\n'

################################################################################
#! Mapping by minimap2 for IGV visualization
################################################################################

conda activate DAJIN

cat << EOF
++++++++++++++++++++++++++++++++++++++++++
Generate BAM files
++++++++++++++++++++++++++++++++++++++++++"
EOF

if [ "$mutation_type" = "P" ]; then
    mv .DAJIN_temp/fasta_ont/wt_ins* .DAJIN_temp/
    mv .DAJIN_temp/fasta_ont/wt_del* .DAJIN_temp/
fi

./DAJIN/src/igvjs.sh "${genome:-mm10}" "${threads:-1}"

mkdir -p "${output_dir:-DAJIN_results}"/BAM
cp -r .DAJIN_temp/bam/* "${output_dir:-DAJIN_results}"/BAM

if [ "$mutation_type" = "P" ]; then
    mv .DAJIN_temp/wt_ins* .DAJIN_temp/fasta_ont/
    mv .DAJIN_temp/wt_del* .DAJIN_temp/fasta_ont/
fi

printf "BAM files are saved at bam\n"
printf "Next converting BAM to MIDS format...\n"

################################################################################
#! MIDS conversion
################################################################################
cat << EOF
++++++++++++++++++++++++++++++++++++++++++
Converting ACGT into MIDS format
++++++++++++++++++++++++++++++++++++++++++"
EOF

reference=".DAJIN_temp/fasta_conv/wt.fa"
query=".DAJIN_temp/fasta_conv/target.fa"

# Get mutation loci...
cat "${reference}" |
    minimap2 -ax splice - "${query}" --cs 2>/dev/null |
    awk '{for(i=1; i<=NF;i++) if($i ~ /cs:Z/) print $i}' |
    sed -e "s/cs:Z:://g" -e "s/:/\t/g" -e "s/~/\t/g" |
    tr -d "\~\*\-\+atgc" |
    awk '{$NF=0; for(i=1;i<=NF;i++) sum+=$i} END{print $1,sum}' |
cat > .DAJIN_temp/data/mutation_points

# MIDS conversion...
find .DAJIN_temp/fasta_ont -type f | sort |
    awk '{print "./DAJIN/src/mids_classification.sh", $0, "wt", "&"}' |
    awk -v th=${threads:-1} '{
        if (NR%th==0) gsub("&","&\nwait",$0)
        print}
        END{print "wait"}' |
sh - 2>/dev/null

[ "_${mutation_type}" = "_P" ] && rm .DAJIN_temp/data/MIDS_target*

cat .DAJIN_temp/data/MIDS_* |
    sed -e "s/_aligned_reads//g" |
    sort -k 1,1 |
cat > ".DAJIN_temp/data/DAJIN_MIDS.txt"

rm .DAJIN_temp/data/MIDS_*

printf "MIDS conversion was finished...\n"

cat ".DAJIN_temp/data/DAJIN_MIDS.txt" |
    grep "_sim" |
cat > ".DAJIN_temp/data/DAJIN_MIDS_sim.txt"

cat ".DAJIN_temp/data/DAJIN_MIDS.txt" |
    grep -v "_sim" |
cat > ".DAJIN_temp/data/DAJIN_MIDS_real.txt"

python ./DAJIN/src/ml_simulated.py \
    ".DAJIN_temp/data/DAJIN_MIDS_sim.txt" \
    "${mutation_type}" "${threads}"


mkdir -p .DAJIN_temp/data/split
split -l 10000 ".DAJIN_temp/data/DAJIN_MIDS_real.txt" .DAJIN_temp/data/split/DAJIN_MIDS_

rm ".DAJIN_temp/data/DAJIN_MIDS_prediction_result.txt" 2>/dev/null

num=$(find .DAJIN_temp/data/split/DAJIN_MIDS_* | wc -l)
i=1
find .DAJIN_temp/data/split/DAJIN_MIDS_* |
while read -r input; do
    echo "${i}"/"${num}"
    python ./DAJIN/src/ml_real.py \
        "${input}" \
        "${mutation_type}" "${threads}"
    i=$((i+1))
done

################################################################################
#! Prediction
################################################################################

cat << EOF
++++++++++++++++++++++++++++++++++++++++++
Allele prediction
++++++++++++++++++++++++++++++++++++++++++"
EOF

python DAJIN/src/ml_l2softmax.py \
    ".DAJIN_temp"/data/DAJIN_MIDS.txt \
    "${mutation_type}" "${threads}"

printf "Prediction was finished...\n"

#===========================================================
#? Filter low-persentage allele
#===========================================================

#---------------------------------------
#* 各サンプルに含まれるアレルの割合を出す
#---------------------------------------

cat .DAJIN_temp/data/DAJIN_MIDS_prediction_result.txt |
    cut -f 2,3 |
    sort |
    uniq -c |
    awk '{barcode[$2]+=$1
        read_info[$2]=$1"____"$3" "read_info[$2]}
    END{for(key in barcode) print key,barcode[key], read_info[key]}' |
    awk '{for(i=3;i<=NF; i++) print $1,$2,$i}' |
    sed "s/____/ /g" |
    awk '{print $1, $3/$2*100, $4}' |
cat > ".DAJIN_temp/tmp_prediction_proportion"

#---------------------------------------
#* コントロールの異常アレルの割合を出す
#---------------------------------------

percentage_of_abnormal_in_cont=$(
    cat ".DAJIN_temp"/tmp_prediction_proportion | 
    grep "${ont_cont:=barcode32}" | #! define "control" by automate manner
    grep abnormal |
    cut -d " " -f 2)

#---------------------------------------
#* Filter low-percent alleles
#---------------------------------------

cat .DAJIN_temp/tmp_prediction_proportion |
    awk -v refab="${percentage_of_abnormal_in_cont}" \
        '!($2<refab+3 && $3 == "abnormal")' |
    # --------------------------------
    # Retain more than 5% of the "non-target" sample and more than 1% of the "target"
    # 「ターゲット以外」のサンプルは5%以上、「ターゲット」は1%以上を残す
    # --------------------------------
    awk '($2 > 5 && $3 != "target") || ($2 > 1 && $3 == "target")' |
    awk '{barcode[$1]+=$2
        read_info[$1]=$2"____"$3" "read_info[$1]}
    END{for(key in barcode) print key,barcode[key], read_info[key]}' |
    awk '{for(i=3;i<=NF; i++) print $1,$2,$i}' |
    sed "s/____/ /g" |
    # --------------------------------
    # Interpolate the removed alleles to bring the total to 100%
    # 除去されたアレル分を補間し、合計を100%にする
    # --------------------------------
    awk '{print $1, int($3*100/$2+0.5),$4}' |
    sort |
cat > .DAJIN_temp/data/DAJIN_MIDS_prediction_filterd.txt

rm .DAJIN_temp/tmp_*

################################################################################
#! Clustering
################################################################################
cat << EOF
++++++++++++++++++++++++++++++++++++++++++
Allele clustering
++++++++++++++++++++++++++++++++++++++++++"
EOF

#===========================================================
#? Prepare control score
#===========================================================
# rm -rf .DAJIN_temp/clustering
./DAJIN/src/clustering_prerequisit_re.sh "${ont_cont}" "wt"
# wc -l .DAJIN_temp/clustering/temp/control_score_*

cat .DAJIN_temp/data/DAJIN_MIDS_prediction_filterd.txt |
    #!--------------------------------------------------------
    # grep barcode18 | grep target |
    #!--------------------------------------------------------
    awk '{print "./DAJIN/src/clustering_re.sh",$1, $3, "&"}' |
    awk -v th=${threads:-1} '{
        if (NR%th==0) gsub("&","&\nwait",$0)}1
        END{print "wait"}' |
sh -

#===========================================================
#? Clustering by HDBSCAN
#===========================================================

cat .DAJIN_temp/data/DAJIN_MIDS_prediction_filterd.txt |
    #!--------------------------------------------------------
    # grep -e barcode18 | grep target |
    #!--------------------------------------------------------
    awk '{print "./DAJIN/src/clustering_hdbscan.sh",$1, $3}' |
sh -

# ls -lh .DAJIN_temp/clustering/temp/hdbscan_*
# rm .DAJIN_temp/tmp_*

#===========================================================
#? Allele percentage
#===========================================================

cat .DAJIN_temp/data/DAJIN_MIDS_prediction_filterd.txt |
    awk '{print "./DAJIN/src/clustering_allele_percentage.sh",$1, $3, $2}' |
    #!--------------------------------------------------------
    # grep barcode18 | grep target |
    #!--------------------------------------------------------
    awk -v th=${threads:-1} '{
        if (NR%th==0) gsub("&","&\nwait",$0)}1
        END{print "wait"}' |
sh -

ls -l .DAJIN_temp/clustering/result_allele_percentage_*

################################################################################
#! Get consensus sequence in each cluster
################################################################################
cat << EOF
++++++++++++++++++++++++++++++++++++++++++
"Report consensus sequence
++++++++++++++++++++++++++++++++++++++++++"
EOF

cat .DAJIN_temp/clustering/result_allele_percentage* |
    sed "s/_/ /" |
    awk '{nr[$1]++; print $0, nr[$1]}' |
    #!--------------------------------------------------------
    # grep barcode18 | grep target |
    #!--------------------------------------------------------
    awk '{print "./DAJIN/src/consensus.sh", $0, "&"}' |
    awk -v th=${threads:-1} '{
        if (NR%th==0) gsub("&","&\nwait",$0)}1
        END{print "wait"}' |
sh -

mkdir -p "${output_dir:-DAJIN_results}"/Consensus/
cp -r .DAJIN_temp/consensus/* "${output_dir:-DAJIN_results}"/Consensus/

################################################################################
#! Summarize to Details.csv
################################################################################

find .DAJIN_temp/consensus/* -type f |
    grep html |
    sed "s:.*/::g" |
    sed "s/.html//g" |
    sed "s/_/ /g" |
    awk '{print $1"_"$2,$3,$4}' |
    sort |
cat > .DAJIN_temp/tmp_nameid

cat .DAJIN_temp/clustering/result_allele_percentage* |
    sed "s/_/ /" |
    awk '{nr[$1]++; print $0, nr[$1]}' |
    awk '{print $1"_allele"$5, $4, $2}' |
    sort |
    join -a 1 - .DAJIN_temp/tmp_nameid |
    sed "s/_/ /" |
    awk '$4=="abnormal" {$5="mutation"}1' |
    awk 'BEGIN{OFS=","}
        {gsub("allele","",$2)
        
        if($4 == "abnormal") $6 ="+"
        else $6 = "-"
        gsub("intact","-", $5)
        gsub("mutation","+", $5)
        }1' |
    sed -e "1i Sample, Allele ID, % of reads, Allele type, indel, large indel" |
cat > "${output_dir:-DAJIN_results}"/Details.csv

rm .DAJIN_temp/tmp_nameid


################################################################################
#! Generate BAM files on each cluster
################################################################################

cat .DAJIN_temp/clustering/result_allele_percentage* |
    sed "s/_/ /" |
    awk '{nr[$1]++; print $0, nr[$1]}' |
while read -r allele
do
    barcode=$(echo ${allele} | cut -d " " -f 1)
    alleletype=$(echo ${allele} | cut -d " " -f 2)
    cluster=$(echo ${allele} | cut -d " " -f 3)
    alleleid=$(echo ${allele} | cut -d " " -f 5)
    #
    input_bam="${barcode}_${alleletype}"
    output_bam="${barcode}_allele${alleleid}"
    #
    find .DAJIN_temp/clustering/result_allele_id* |
        grep "${input_bam}" |
        xargs cat |
        awk -v cl="${cluster}" '$2==cl' |
        cut -f 1 |
        sort |
    cat > ".DAJIN_temp/clustering/temp/tmp_id_$$"
    #
    samtools view -h "${output_dir:-DAJIN_results}"/BAM/"${barcode}".bam |
        awk '/^@/{print}
            NR==FNR{a[$1];next}
            $1 in a' \
            ".DAJIN_temp/clustering/temp/tmp_id_$$" - |
        head -n 22 |
        samtools sort -@ "${threads:-1}" 2>/dev/null |
    cat > "${output_dir:-DAJIN_results}"/BAM/"${output_bam}".bam
    samtools index "${output_dir:-DAJIN_results}"/BAM/"${output_bam}".bam
done

################################################################################
#! Alignment viewing
################################################################################

printf "Visualizing alignment reads...\n"
printf "Browser will be launched. Click 'igvjs.html'.\n"
{ npx live-server "${output_dir:-DAJIN_results}"/BAM/igvjs/ & } 1>/dev/null 2>/dev/null

# rm -rf .tmp_
# rm .DAJIN_temp/tmp_* .DAJIN_temp/clustering/tmp_* 2>/dev/null

printf "Completed! \nCheck 'results/figures/' directory.\n"

exit 0


# ----------------------------------------------------------------
# 2-cut deletionの場合は、大丈夫そうなabnormalを検出する
# ----------------------------------------------------------------

# if [ "$mutation_type" = "D" ]; then
#     ./DAJIN/src/anomaly_exondeletion.sh ${genome} ${threads}
# else
#     cp .DAJIN_temp/anomaly_classification.txt .DAJIN_temp/anomaly_classification_revised.txt
# fi
#
# cp .DAJIN_temp/anomaly_classification.txt .DAJIN_temp/anomaly_classification_revised.txt
#
