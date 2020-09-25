#!/bin/bash

################################################################################
#! Initialize shell environment
################################################################################

set -u
umask 0022
export LC_ALL=C
export UNIX_STD=2003  # to make HP-UX conform to POSIX


################################################################################
#! Define the functions for printing usage and error message
################################################################################
VERSION=0.2

usage(){
cat <<- USAGE
Usage     : ./DAJIN/DAJIN.sh -i [text file] (described at "Input")

Example   : ./DAJIN/DAJIN.sh -i DAJIN/example/design.txt

Input     : Input file should be formatted as below:
            # Example
            ------
            design=DAJIN/example/design.txt
            input_dir=DAJIN/example/fastq
            control=barcode01
            genome=mm10
            grna=CCTGTCCAGAGTGGGAGATAGCC,CCACTGCTAGCTGTGGGTAACCC
            output_dir=DAJIN_cables2
            threads=10
            filter=on
            ------
            - design: a multi-FASTA file contains sequences of each genotype. ">wt" and ">target" must be included.
            - input_dir: a directory contains FASTA or FASTQ files of long-read sequencing
            - control: control barcode ID
            - genome: reference genome. e.g. mm10, hg38
            - grna: gRNA sequence(s) including PAM. multiple gRNA sequences must be deliminated by comma.
            - output_dir (optional): output directory name. optional. Default is "DAJIN_results"
            - threads (optional; integer): Default is two-thirds of available CPU threads.
            - filter (optional; "on" or "off"): set filter to remove very minor allele (less than 5%). Default is "on"
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
        --input | --in | --i | -i )
            if ! [ -r "$2" ]; then
                error_exit "$2: No such file"
            fi
            design=$(cat "$2" | grep "^design" | sed -e "s/ //g" -e "s/.*=//g")
            input_dir=$(cat "$2" | grep "^input_dir" | sed -e "s/ //g" -e "s/.*=//g")
            control=$(cat "$2" | grep "^control" | sed -e "s/ //g" -e "s/.*=//g")
            genome=$(cat "$2" | grep "^genome" | sed -e "s/ //g" -e "s/.*=//g")
            grna=$(cat "$2" | grep "^grna" | sed -e "s/ //g" -e "s/.*=//g")
            output_dir=$(cat "$2" | grep "^output_dir" | sed -e "s/ //g" -e "s/.*=//g")
            threads=$(cat "$2" | grep "^threads" | sed -e "s/ //g" -e "s/.*=//g")
            filter=$(cat "$2" | grep "^filter" | sed -e "s/ //g" -e "s/.*=//g")
            TEST=$(cat "$2" | grep "^TEST" | sed -e "s/ //g" -e "s/.*=//g")
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

#===========================================================
#? Check required arguments
#===========================================================

[ -z "$design" ] && error_exit "design argument is not specified"
[ -z "$input_dir" ] && error_exit "input_dir argument is not specified"
[ -z "$control" ] && error_exit "control argument is not specified"
[ -z "$genome" ] && error_exit "genome argument is not specified"
[ -z "$grna" ] && error_exit "grna argument is not specified"

#===========================================================
#? Check fasta file
#===========================================================

[ -e "$design" ] || error_exit "$design: No such file"

[ "$(grep -c -e '>wt' -e '>target' ${design})" -ne 2 ] &&
    error_exit "$design: design must include '>target' and '>wt'. "

#===========================================================
#? Check directory
#===========================================================

[ -d "${input_dir}" ] ||
    error_exit "$input_dir: No such directory"

[ -z "$(ls $input_dir)" ] &&
    error_exit "$input_dir: Empty directory"

#===========================================================
#? Check control
#===========================================================

if find ${input_dir}/ -type f | grep -q "${control}"; then
    :
else
    error_exit "$control: No control file in ${input_dir}"
fi

#===========================================================
#? Check genome
#===========================================================

genome_check=$(
    wget -q -O - "http://hgdownload.soe.ucsc.edu/downloads.html" |
    grep hgTracks |
    grep -c "${genome:-XXX}"
)

[ "$genome_check" -eq 0 ] &&
    error_exit "$genome: No such reference genome"

#===========================================================
#? Check grna
#===========================================================

set $(echo "${grna}" | sed "s/,/ /g")
x=1
while [ "${x}" -le $# ]
do
    [ "$(grep -c ${1} ${design})" -eq 0 ] && error_exit "No gRNA sites"
    x=$(( "${x}" + 1 ))
done

#===========================================================
#? Check output directory name
#===========================================================
[ $(echo "$output_dir" | sed "s/[_a-zA-Z0-9]*//g" | wc | awk '{print $2}') -ne 0 ] &&
    error_exit "$output_dir: invalid directory name"

#===========================================================
#? Check "filter"
#===========================================================
if [ -z "${filter}" ];then
    filter=on
elif [ _"${filter}" = _"off" ];then
    :
else
    error_exit "${filter}: invalid filter name (on/off)"
fi

#===========================================================
#? Define threads
#===========================================================

max_cpu=$(python -c "import multiprocessing; print(multiprocessing.cpu_count())")
tmp_threads=$(expr "${threads}" + 1 2>/dev/null)

if [ $? -eq 0 ] && [ "${tmp_threads}" -gt 1 ] && [ "${threads}" -lt "${max_cpu}" ]; then
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

. DAJIN/src/conda_setting.sh

################################################################################
#! Formatting environments
################################################################################

#===========================================================
#? Make temporal directory
#===========================================================

rm -rf ".DAJIN_temp" 2>/dev/null || true
dirs="fasta fasta_conv fasta_ont NanoSim data"

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

#===========================================================
#? Define mutation type
#? Insertion = I; Deletion = D; Substitution = S
#===========================================================

mutation_type=$(
    minimap2 -ax splice \
        .DAJIN_temp/fasta/wt.fa \
        .DAJIN_temp/fasta/target.fa \
        --cs 2>/dev/null |
    grep -v "^@" |
    awk '{
        cstag=$(NF-1)
        if(cstag ~ "~") print "D"
        else if(cstag ~ "\+") print "I"
        else if(cstag ~ "\*") print "S"
        }' 2>/dev/null
)

#---------------------------------------
#* In the case of Point mutation:
#* Generate randome insertion and deletion at gRNA sites as abnormal alleles
#---------------------------------------

if [ "_${mutation_type}" = "_S" ]; then
    grna_len=$(awk -v grna="$grna" 'BEGIN{print length(grna)}')
    grna_firsthalf=$(awk -v grna="$grna" 'BEGIN{print substr(grna, 1, int(length(grna)/2))}')
    grna_secondhalf=$(awk -v grna="$grna" 'BEGIN{print substr(grna, int(length(grna)/2)+1, length(grna))}')
    # Randome sequence
    ins_seq=$(
        seq_length="$grna_len" &&
        od -A n  -t u4 -N $(($seq_length*100)) /dev/urandom |
        tr -d "\n" |
        sed 's/[^0-9]//g' |
        sed "s/[4-9]//g" |
        sed -e "s/0/A/g" -e "s/1/G/g" -e "s/2/C/g" -e "s/3/T/g" |
        awk -v seq_length="$seq_length" '{print substr($0, 1, seq_length)}'
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

#===========================================================
#? Format ONT reads into FASTA file
#===========================================================

for input in ${input_dir}/* ; do
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

cat << EOF >&2
--------------------------------------------------------------------------------
NanoSim read simulation
--------------------------------------------------------------------------------
EOF

#===========================================================
#? NanoSim
#===========================================================

set +u
conda activate DAJIN_nanosim
set -u

./DAJIN/src/nanosim.sh "${control}" "${threads}"

################################################################################
#! MIDS conversion
################################################################################
set +u
conda activate DAJIN
set -u

cat << EOF >&2
--------------------------------------------------------------------------------
MIDS conversion
--------------------------------------------------------------------------------
EOF

#===========================================================
#? Get mutation loci
#===========================================================

minimap2 -ax splice \
    ".DAJIN_temp/fasta_conv/wt.fa" ".DAJIN_temp/fasta_conv/target.fa" \
    --cs 2>/dev/null |
    awk '{for(i=1; i<=NF;i++) if($i ~ /cs:Z/) print $i}' |
    sed -e "s/cs:Z:://g" -e "s/:/\t/g" -e "s/~/\t/g" |
    tr -d "\~\*\-\+atgc" |
    awk '{$NF=0; for(i=1;i<=NF;i++) sum+=$i} END{print $1,sum}' |
cat > .DAJIN_temp/data/mutation_points

#===========================================================
#? MIDS conversion
#===========================================================

find .DAJIN_temp/fasta_ont -type f |
    sort |
    awk '{print "./DAJIN/src/mids_classification.sh", $0, "wt", "&"}' |
    awk -v th=${threads:-1} '{
        if (NR%th==0) gsub("&","&\nwait",$0)
        print}
        END{print "wait"}' |
sh - 2>/dev/null

################################################################################
#! Prediction
################################################################################

cat << EOF >&2
--------------------------------------------------------------------------------
Allele prediction
--------------------------------------------------------------------------------
EOF

./DAJIN/src/ml_prediction.sh "${control}" "${threads}" \
> .DAJIN_temp/data/DAJIN_MIDS_prediction_result.txt ||
exit 1


################################################################################
#! Clustering
################################################################################

cat << EOF >&2
--------------------------------------------------------------------------------
Allele clustering
--------------------------------------------------------------------------------
EOF

rm -rf .DAJIN_temp/clustering 2>/dev/null
mkdir -p .DAJIN_temp/clustering/temp

#===========================================================
#? Prepare control's score to define sequencing error
#===========================================================

./DAJIN/src/clustering_control_score.sh "${control}" "${threads}"

#===========================================================
#? Clustering
#===========================================================

cat .DAJIN_temp/data/DAJIN_MIDS_prediction_result.txt |
    cut -f 2,3 |
    sort -u |
    awk -v th=${threads:-1} '{print "./DAJIN/src/clustering.sh", $1, $2, th}' |
sh -

#===========================================================
#? Allele percentage
#===========================================================

cat .DAJIN_temp/data/DAJIN_MIDS_prediction_result.txt |
    cut -f 2 |
    sort -u |
    awk -v filter="${filter:-on}" \
    '{print "./DAJIN/src/clustering_allele_percentage.sh", $1, filter, "&"}' |
    awk -v th=${threads:-1} '{
        if (NR%th==0) gsub("&","&\nwait",$0)}1
        END{print "wait"}' |
sh -

################################################################################
#! Get consensus sequence in each cluster
################################################################################

cat << EOF >&2
--------------------------------------------------------------------------------
Report consensus sequence
--------------------------------------------------------------------------------
EOF

#===========================================================
#? Setting directory
#===========================================================

find .DAJIN_temp/consensus/* -type d 2>/dev/null |
    grep -v "sam$" |
xargs -I @ rm -rf @ 2>/dev/null
mkdir -p .DAJIN_temp/consensus/temp .DAJIN_temp/consensus/sam

#===========================================================
#? Generate temporal SAM files
#===========================================================

cat .DAJIN_temp/clustering/label* |
    cut -d " " -f 1,2 |
    sort -u |
    grep -v abnormal |  #TODO <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
while read -r input; do
    barcode="${input%% *}"
    mapping_alleletype="$(echo "${input##* }" | sed "s/ab*normal/wt/g")"

    if ! [ -f .DAJIN_temp/consensus/sam/"${barcode}"_"${mapping_alleletype}".sam ]; then

    cat .DAJIN_temp/clustering/readid_cl_mids_"${barcode}"_"${mapping_alleletype}" |
        awk '{print ">"$1}' |
        sort |
    cat > .DAJIN_temp/consensus/tmp_id

    cat .DAJIN_temp/fasta_ont/"${barcode}".fa |
        awk '{print $1}' |
        tr "\n" " " |
        sed "s/>/\n>/g" |
        sort |
        join - .DAJIN_temp/consensus/tmp_id |
        sed "s/ /\n/g" |
        grep -v "^$" |
        minimap2 -ax map-ont -t "${threads}" \
            ".DAJIN_temp/fasta/${mapping_alleletype}.fa" - \
            --cs=long 2>/dev/null |
        sort |
    cat > .DAJIN_temp/consensus/sam/"${barcode}"_"${mapping_alleletype}".sam
    rm .DAJIN_temp/consensus/tmp_id
    fi
done

#===========================================================
#? Execute consensus.sh
#===========================================================

cat .DAJIN_temp/clustering/label* |
    awk '{nr[$1]++; print $0, nr[$1]}' |
    grep -v abnormal |  #TODO <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    awk '{print "./DAJIN/src/consensus.sh", $0, "&"}' |
    awk -v th=${threads:-1} '{
        if (NR%th==0) gsub("&","&\nwait",$0)}1
        END{print "wait"}' |
sh -

################################################################################
#! Summarize to Details.csv and Details.pdf
################################################################################

./DAJIN/src/details.sh

################################################################################
#! Mapping by minimap2 for IGV visualization
################################################################################

cat << EOF >&2
--------------------------------------------------------------------------------
Generate BAM files
--------------------------------------------------------------------------------
EOF

./DAJIN/src/generate_bam.sh "${genome}" "${threads}"

################################################################################
#! Move output files
################################################################################

rm -rf "${output_dir:=DAJIN_results}" 2>/dev/null
mkdir -p "${output_dir:-DAJIN_results}"/BAM
mkdir -p "${output_dir:-DAJIN_results}"/Consensus

#===========================================================
#? BAM
#===========================================================

rm -rf .DAJIN_temp/bam/temp 2>/dev/null
cp -r .DAJIN_temp/bam/* "${output_dir:-DAJIN_results}"/BAM/ 2>/dev/null

#===========================================================
#? Consensus
#===========================================================

find .DAJIN_temp/consensus/* -type d |
grep -v -e "consensus/temp" -e "sam" |
xargs -I @ cp -f -r @ "${output_dir:-DAJIN_results}"/Consensus/ 2>/dev/null

#===========================================================
#? Details
#===========================================================

cp .DAJIN_temp/details/* "${output_dir:-DAJIN_results}"/

################################################################################
#! Finish call
################################################################################

[ -z "${TEST}" ] && rm -rf .DAJIN_temp/

set +u
conda deactivate

cat << EOF >&2
--------------------------------------------------------------------------------
Completed!
Check ${output_dir:-DAJIN_results} directory
--------------------------------------------------------------------------------
EOF

exit 0