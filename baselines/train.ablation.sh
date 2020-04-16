#!/bin/bash
set -e

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:$LD_LIBRARY_PATH
source ~/tf1.14/bin/activate

#################################################################################################
### We assume that all monolingual usecases to be back-translated can be found at `$DATA_DIR` ###
### in the `encoded` format. Parallel data will be read directly from `PARALLEL_DATA`.         ###
#################################################################################################


print_usage() {
  me=`basename "$0"`
  echo "Usage: bash ${me} -g __GPU__ -l __LANG__"
  echo "For example: bash ${me} -g 0 -l de"
  exit 1
}

while getopts "g:l:" flag
do
  case $flag in
    g) GPU=${OPTARG} ;;
    l) LANG=${OPTARG} ;;
    *) print_usage
  esac
done

if [[  -z $GPU || -z $LANG ]]; then
  print_usage
fi

#========================================================================================================
#------------------------------------------------- PARAMS -----------------------------------------------
#========================================================================================================
WD_GIT="$(dirname $0)"
CFG_PATH=${WD_GIT}/configs/${LANG}en-ablation.yml
WD=/mnt/work/onmt-tf/mdt/baselines
DATA_PATH=/mnt/tmpfs/${LANG}en-ablation/
LOGFILE=${WD}/${LANG}en-ablation.log

#========================================================================================================
#------------------------------------------------- SCRIPT -----------------------------------------------
#========================================================================================================
export CUDA_VISIBLE_DEVICES=$GPU
echo "--------------------- START OF TRAINING ---------------------" >> $LOGFILE
onmt-main -v >> $LOGFILE 2>> $LOGFILE
onmt-main train_and_eval \
	--model_type Transformer \
	--config $CFG_PATH --auto_config \
	--data_dir $DATA_PATH \
	--run_dir $WD \
	--num_gpus 1 2>> $LOGFILE
echo "--------------------- END OF A NEW TRAINING ---------------------" >> $LOGFILE
