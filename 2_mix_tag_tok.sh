#################################################################################################
### We assume that all monolingual usecases to be back-translated can be found at `$DATA_DIR` ###
### in the `encoded` format. Parallel data will be read directly from `PARALLEL_DATA`.         ###
#################################################################################################
set -e

# Weird stuff that only happen on my machine. Please ignore it if you review this script
# trust me it is not as trivial as it seems to solve the real issue.
export LC_ALL=

print_usage() {
  me=`basename "$0"`
  echo "Usage: bash ${me} -s __SOURCE_LANGUAGE__ -t __TARGET_LANGUAGE_"
  echo "Exactly one of the passed languages has to be 'en'."
  echo "For example: bash ${me} -s de -t en"
  exit 1
}

while getopts "s:t:" flag
do
  case $flag in
    s) SRC_LANGUAGE=${OPTARG} ;;
    t) TGT_LANGUAGE=${OPTARG} ;;
    *) print_usage
  esac
done

if [[ (! ($SRC_LANGUAGE == "en" || $TGT_LANGUAGE == "en")) ]]; then
  print_usage
  exit
fi

# I need to know what the "other" language is to grab it's data from `raw_data/en-$lang`.
if [[ $SRC_LANGUAGE == "en" ]]; then
  LANGUAGE=$TGT_LANGUAGE
else
  LANGUAGE=$SRC_LANGUAGE
fi

DATA_DIR="/mnt/tmpfs/${SRC_LANGUAGE}${TGT_LANGUAGE}-mdt"
PARALLEL_DATA="/mnt/work/data/raw_data/en-${LANGUAGE}"
USECASES='description review messaging'
LOGFILE="${DATA_DIR}/preparation.log"
BT_LINES_PER_USECASE=1000000

if [ -f ${DATA_DIR}/shared.bpe ]; then
  echo "Shared BPE detected."
  SRC_BPE=${DATA_DIR}/shared.bpe
  TGT_BPE=${DATA_DIR}/shared.bpe
elif [[ -f ${DATA_DIR}/${SRC_LANGUAGE}.bpe && -f ${DATA_DIR}/${TGT_LANGUAGE}.bpe ]]; then
  echo "Language specific BPEs detected."
  SRC_BPE=${DATA_DIR}/${SRC_LANGUAGE}.bpe
  TGT_BPE=${DATA_DIR}/${TGT_LANGUAGE}.bpe
else
  echo "Could not find neither shared, nor language specific BPE files at ${DATA_DIR}"
  exit 2
fi

# Unzip and gather parallel data. Redirect errors to effectively ignore non-existent files.
for USECASE in ${USECASES}; do
  echo "Reading ${USECASE} into ${DATA_DIR}/parallel.${USECASE}.tsv. This file will be deleted later." >> $LOGFILE
  if ls ${PARALLEL_DATA}/${USECASE}*.${TGT_LANGUAGE}-${SRC_LANGUAGE}* 1> /dev/null 2>&1; then
    zcat ${PARALLEL_DATA}/${USECASE}*.${TGT_LANGUAGE}-${SRC_LANGUAGE}* > ${DATA_DIR}/all.parallel.${USECASE}
  fi
  if ls ${PARALLEL_DATA}/${USECASE}*.${SRC_LANGUAGE}-${TGT_LANGUAGE}* 1> /dev/null 2>&1; then
    zcat ${PARALLEL_DATA}/${USECASE}*.${SRC_LANGUAGE}-${TGT_LANGUAGE}* \
      | awk -F $'\t' ' { t = $1; $1 = $2; $2 = t; print; } ' OFS=$'\t' \
      >> ${DATA_DIR}/all.parallel.${USECASE}
  fi
  head -n  1500 ${DATA_DIR}/all.parallel.${USECASE} > ${DATA_DIR}/valid.parallel.${USECASE}
  tail -n +1501 ${DATA_DIR}/all.parallel.${USECASE} > ${DATA_DIR}/train.parallel.${USECASE}
done
rm ${DATA_DIR}/all.parallel.*

# Get Back-translations.
BT_DATA="/mnt/work/data/bt/"
cp ${BT_DATA}/messaging/${TGT_LANGUAGE}${SRC_LANGUAGE}.tagged.encoded ${DATA_DIR}
cp ${BT_DATA}/description/${TGT_LANGUAGE}${SRC_LANGUAGE}.tagged.encoded ${DATA_DIR}
cp ${BT_DATA}/review/${TGT_LANGUAGE}${SRC_LANGUAGE}.tagged.encoded ${DATA_DIR}


split_and_tag () {
  # Split each file into source and target files, then tag the source part.
  # Only use a subset of lines to make sure all use-cases are balanced.
  fix_size $1
  echo "Splitting and tagging ${1} with tag ${2}" >> $LOGFILE
  cut -f 1 ${1} | subtokenizer tokenize -s ${TGT_BPE} > ${1}.${TGT_LANGUAGE}.tok
  cut -f 2 ${1} | subtokenizer tokenize -s ${SRC_BPE} | sed -e "s/^/${2} @bt· /" > ${1}.${SRC_LANGUAGE}.tok
}

min_number() {
    printf "%s\n" "$@" | sort -g | head -n1
}

fix_size() {
  N_LINES=$(cat $1 | wc -l)
  if (( N_LINES > BT_LINES_PER_USECASE )); then
    echo "$1 is too big, using the first $BT_LINES_PER_USECASE only."
    head -n $BT_LINES_PER_USECASE $1 > "$1.upsampled"
    mv "$1.upsampled" $1
  else
    echo "$1 is too small, upsampling to $BT_LINES_PER_USECASE"
    UPSAMPLING=$((BT_LINES_PER_USECASE / N_LINES + 1))
    for i in `seq ${UPSAMPLING}`; do
      cat $1 >> "$1.upsampled"
    done
    head -n $BT_LINES_PER_USECASE "$1.upsampled" > $1
    rm "$1.upsampled"
  fi
}

split_and_tag ${DATA_DIR}/description.tagged.encoded "@description·"
split_and_tag ${DATA_DIR}/messaging.tagged.encoded "@messaging·"
split_and_tag ${DATA_DIR}/review.tagged.encoded "@review·"

cat ${DATA_DIR}/*.tagged.encoded.${TGT_LANGUAGE}.tok > ${DATA_DIR}/tmp.${TGT_LANGUAGE}.tok
cat ${DATA_DIR}/*.tagged.encoded.${SRC_LANGUAGE}.tok > ${DATA_DIR}/tmp.${SRC_LANGUAGE}.tok
rm ${DATA_DIR}/*.tagged.encoded.${TGT_LANGUAGE}.tok
rm ${DATA_DIR}/*.tagged.encoded.${SRC_LANGUAGE}.tok

# Tokenize, tag and upsample the parallel dataset.
REAL_LINES=$(cat ${DATA_DIR}/train.parallel.* | wc -l)
SYNTHETIC_LINES=$(wc -l < "$DATA_DIR/tmp.${SRC_LANGUAGE}.tok")
UPSAMPLING=$((SYNTHETIC_LINES / REAL_LINES + 1))
echo "Found ${REAL_LINES} real lines and ${SYNTHETIC_LINES} back-translated lines, upsampling the real dataset ${UPSAMPLING} times" >> $LOGFILE

# Tokenize parallel
for USECASE in ${USECASES}; do
  cut -f 1 ${DATA_DIR}/train.parallel.${USECASE} \
    | subtokenizer tokenize -s ${TGT_BPE} \
    >> ${DATA_DIR}/tmp.parallel.${TGT_LANGUAGE}.tok
  cut -f 2 ${DATA_DIR}/train.parallel.${USECASE} \
    | subtokenizer tokenize -s ${SRC_BPE} \
    | sed -e "s/^/@${USECASE}· @real· /" \
    >> ${DATA_DIR}/tmp.parallel.${SRC_LANGUAGE}.tok
done

# Upsample parallel
for i in `seq ${UPSAMPLING}`; do
  cat ${DATA_DIR}/tmp.parallel.${TGT_LANGUAGE}.tok >> ${DATA_DIR}/tmp.${TGT_LANGUAGE}.tok;
  cat ${DATA_DIR}/tmp.parallel.${SRC_LANGUAGE}.tok >> ${DATA_DIR}/tmp.${SRC_LANGUAGE}.tok;
done

# Tokenise split and tag the validation set.
for USECASE in ${USECASES}; do
  cut -f 1 ${DATA_DIR}/valid.parallel.${USECASE} | subtokenizer tokenize -s ${TGT_BPE} >> ${DATA_DIR}/valid.${TGT_LANGUAGE}.tok
  cut -f 2 ${DATA_DIR}/valid.parallel.${USECASE} \
    | subtokenizer tokenize -s ${SRC_BPE} \
    | sed -e "s/^/@${USECASE}· @real· /" \
    >> ${DATA_DIR}/valid.${SRC_LANGUAGE}.tok
done

# Shuffle and cleanup.
paste ${DATA_DIR}/tmp.${TGT_LANGUAGE}.tok ${DATA_DIR}/tmp.${SRC_LANGUAGE}.tok | shuf > ${DATA_DIR}/tmp
cut -f 1 ${DATA_DIR}/tmp > ${DATA_DIR}/train.${TGT_LANGUAGE}.tok
cut -f 2 ${DATA_DIR}/tmp > ${DATA_DIR}/train.${SRC_LANGUAGE}.tok
rm ${DATA_DIR}/*.parallel.*
rm ${DATA_DIR}/tmp*

