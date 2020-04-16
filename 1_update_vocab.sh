set -e

#######################################################################################################
#######################################################################################################
### Update the vocabulary for all models before finetuning, in order to ensure                      ###
### that usecase tags (description, messaging, review) as well as source text tags (back-translated, real) ###
### get a dedicated embedding. The process handles both separate and shared BPEs.                   ###
### This script can be called as :                                                                  ###
###   $ bash update_vocab -l fr                                                                     ###
###   $ bash update_vocab -l ar                                                                     ###
###   $ bash update_vocab -l ru                                                                     ###
#######################################################################################################
#######################################################################################################


source /mnt/v_envs/tf1.14/bin/activate


# Path to each GP model (to be used for back-translations).
declare -A MODELS=( \
  ["de"]="deen_gp_8_gpu/model/deen_gp_8_gpu" \
  ["ar"]="aren_gp_8_gpu/model/aren_gp_8_gpu" \
  ["ru"]="ruen_gp_8_gpu/model/ruen_gp_8_gpu" \
  )

declare -A ENGLISH_BPES=( \
  ["de"]="onmt-tf/deen_gp_8_gpu/model/deen_gp_8_gpu/assets/shared.bpe" \
  ["ar"]="onmt-tf/aren_gp_8_gpu/model/aren_gp_8_gpu/assets/en.bpe" \
  ["ru"]="onmt-tf/ruen_gp_8_gpu/model/ruen_gp_8_gpu/assets/en.bpe" \
  )

declare -A OTHER_BPES=( \
  ["ar"]="onmt-tf/aren_gp_8_gpu/model/aren_gp_8_gpu/assets/ar.bpe" \
  ["ru"]="onmt-tf/ruen_gp_8_gpu/model/ruen_gp_8_gpu/assets/ru.bpe"
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
      MODEL_DIR="/mnt/work/onmt-tf/${MODELS[${LANG}]}/best_checkpoint"
      if [[ ! -f $MODEL_DIR/checkpoint ]]; then
        echo "Checkpoint not found at $MODEL_DIR, copying from parent directory."
        cp $MODEL_DIR/../checkpoint $MODEL_DIR
      fi
      DATA_DIR="/mnt/tmpfs/${LANG}en-mdt"
      ENGLISH_BPE="/mnt/work/${ENGLISH_BPES[${LANG}]}"
      OTHER_BPE="/mnt/work/${OTHER_BPES[${LANG}]}"

      # If the source BPE is not specified, this means it is shared.
      if [[ -z ${OTHER_BPES[${LANG}]} ]]; then
        OTHER_BPE=$ENGLISH_BPE
      fi
      echo "English bpe: ${ENGLISH_BPE}"
      echo "${LANG} BPE: ${OTHER_BPE}"
      mkdir -p ${DATA_DIR}
      ;;
    *) print_usage
  esac
done

if [[ -z $ENGLISH_BPE || -z $OTHER_BPE ]]; then
  print_usage
fi

# Make the new vocab files that include all possible tags.
TAGS='@real· @bt· @review· @description· @messaging·'
# Shared BPE.
if [ "$ENGLISH_BPE" == "$OTHER_BPE" ]; then
  echo "Updating vocab to include the tag in the shared BPE (updated BPE at: ${DATA_DIR}/shared.bpe)"
  echo "Old model was ${MODEL_DIR}, new model is /mnt/work/onmt-tf/mdt/model_${LANG}en."
  cp $ENGLISH_BPE ${DATA_DIR}/shared.bpe
  for TAG in $TAGS; do
    echo $TAG >> ${DATA_DIR}/shared.bpe
  done

  onmt-update-vocab \
  	--model_dir ${MODEL_DIR} \
  	--output_dir /mnt/work/onmt-tf/mdt/model_${LANG}en \
  	--src_vocab $OTHER_BPE \
  	--tgt_vocab $ENGLISH_BPE \
  	--new_src_vocab ${DATA_DIR}/shared.bpe \
  	--new_tgt_vocab ${DATA_DIR}/shared.bpe \
  	--mode replace
# Separate BPE.
else
  echo "Updating vocab to include the tag in the shared BPE."
  echo "Updated BPEs at: "
  echo -e "\tEN: ${DATA_DIR}/en.bpe"
  echo -e "\t${LANG}: ${DATA_DIR}/${LANG}.bpe"

  cp $ENGLISH_BPE ${DATA_DIR}/en.bpe
  cp $OTHER_BPE ${DATA_DIR}/${LANG}.bpe
  for TAG in $TAGS; do
    echo $TAG >> ${DATA_DIR}/${LANG}.bpe
  done
  onmt-update-vocab \
  	--model_dir ${MODEL_DIR} \
  	--output_dir /mnt/work/onmt-tf/mdt/model_${LANG}en \
  	--src_vocab $OTHER_BPE \
  	--tgt_vocab $ENGLISH_BPE \
  	--new_src_vocab ${DATA_DIR}/${LANG}.bpe \
  	--new_tgt_vocab ${DATA_DIR}/en.bpe \
  	--mode replace
fi

# Make sure we get the tensorboard files as well.
cp ${MODEL_DIR}/../events.out.tfevents* /mnt/work/onmt-tf/mdt/model_${LANG}en
