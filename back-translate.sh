set -e


source ~/tf1.14/bin/activate


# Path to each GP model (to be used for back-translations).
declare -A MODELS=( \
  ["de"]="ende_gp_8_gpu/model/ende_gp_8_gpu" \
  ["ar"]="enar_gp_8_gpu/model/enar_gp_8_gpu" \
  ["ru"]="enru_gp_8_gpu/model/enru_gp_8_gpu" \
  )

# Print usage example and exit when getting bad input.
print_usage() {
  me=`basename "$0"`
  echo "Usage: bash ${me} -l __LANG__"
  echo "For example: bash ${me} -l de"
  exit 1
}

while getopts "l:" flag
do
  case $flag in
    l)
      LANG=${OPTARG}
      MODEL_EXPORT="/mnt/work/onmt-tf/${MODELS[${LANG}]}/export/manual/best"
      TAG=${TAGS[${LANG}]}
      DATA_DIR="/mnt/tmpfs/bt"
      ;;
    *) print_usage
  esac
done

if [[ -z $MODEL_EXPORT ]]; then
  print_usage
fi

# Currently hardcoded python script path (endpoint not working).
_translate() {
  if [[ -z $TAG ]]; then
    cat $1 | translate -m ${MODEL_EXPORT} -c 0
  else
    cat $1 | translate -m ${MODEL_EXPORT} -c 0 -t $TAG
  fi
}

monolingual_bt () {
  # For each row monolingual dataset, we first decode from b64 and split sentences, then convert
  # to 'encoded_json' and then translate. Finally we convert the translated file to get rid of JSON.
  if [ ! -f ${1} ]; then
    echo "File ${1} not found, exiting!"
    exit 2
  fi

  echo "Back-translating $1 using model ${MODEL_EXPORT}." >> $LOGFILE
  # Extract text only
  # Remove super long sentences
  # Remove duplicates
  # Translate (optionally using language tag)
  cat $1 \
    | cut -f 4 \
    | sed '/^.\{2048\}./d' \
    | awk -F "\t" '!_[$1]++' \
    | _translate \
    > $2
}

LOGFILE=${DATA_DIR}/bt.log
monolingual_bt ${DATA_DIR}/messaging.en.${PART} ${DATA_DIR}/messaging.en${LANG}.${PART} >> $LOGFILE 2>&1 $LOGFILE
