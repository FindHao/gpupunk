# set cuda enviroment
source ~/setenvs/setcuda11.2.sh
# change to your install path
export GPUPUNK_PATH=/home/yhao24/opt/gpupunk

export ENABLE_GPUTRIGGER=1
export GPUPATCH_PATH=${GPUPUNK_PATH}/gpu-patch/
export REDSHOW_PATH=${GPUPUNK_PATH}/redshow
export GPUTRIGGER_PATH=${GPUPUNK_PATH}/gputrigger
export DRCCTPROF_PATH=${GPUPUNK_PATH}/drcctprof-debug

export LD_LIBRARY_PATH=${GPUTRIGGER_PATH}:${REDSHOW_PATH}/lib:$LD_LIBRARY_PATH
export PATH=${GPUPUNK_PATH}/bin/:${DRCCTPROF_PATH}/bin:$PATH
