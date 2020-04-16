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
  echo "Usage: bash ${me} -l __SRC_LANG__ -g __GPU__"
  echo "For example: bash ${me} -l de -g 0"
  exit 1
}

while getopts "l:g:" flag
do
  case $flag in
    l) SRC_LANG=${OPTARG} ;;
    g) GPU=${OPTARG} ;;
    *) print_usage
  esac
done

if [[ -z $SRC_LANG || -z $GPU ]]; then
  print_usage
fi

#========================================================================================================
#------------------------------------------------- PARAMS -----------------------------------------------
#========================================================================================================
WD_GIT="$(dirname $0)"
CFG_PATH=${WD_GIT}/configs/${SRC_LANG}en.yml
WD=/mnt/work/onmt-tf/mdt
DATA_PATH=/mnt/tmpfs/${SRC_LANG}en-mdt
LOGFILE=${WD}/${SRC_LANG}en.log

#========================================================================================================
#------------------------------------------------- SCRIPT -----------------------------------------------
#========================================================================================================
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
echo "--------------------- START OF TRAINING ---------------------" >> $LOGFILE
onmt-main train_and_eval \
	--model_type Transformer \
	--config $CFG_PATH --auto_config \
	--data_dir $DATA_PATH \
	--run_dir $WD \
	--num_gpus 8 2>> $LOGFILE
echo "--------------------- END OF A NEW TRAINING ---------------------" >> $LOGFILE
