

export GPUPUNK_PATH=/home/yhao24/opt/gpupunk
export GPUPATCH_PATH=${GPUPUNK_PATH}/gpu-patch/lib/gpu-patch.fatbin
export REDSHOW_PATH=${GPUPUNK_PATH}/redshow
export GPUTRIGGER_PATH=${GPUPUNK_PATH}/gputrigger

export LD_LIBRARY_PATH=${GPUTRIGGER_PATH}:${REDSHOW_PATH}/lib:$LD_LIBRARY_PATH
export PATH=${GPUPUNK_PATH}/bin/:$PATH
