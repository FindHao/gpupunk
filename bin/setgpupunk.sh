# set cuda enviroment
# source ~/setenvs/setcuda11.2.sh
# change to your install path
export GPUPUNK_PATH=/home/yhao24/opt/gpupunk

export ENABLE_GPUTRIGGER=1
export GPUPATCH_PATH=${GPUPUNK_PATH}/gpu-patch/
export REDSHOW_PATH=${GPUPUNK_PATH}/redshow
export GPUTRIGGER_PATH=${GPUPUNK_PATH}/gputrigger
export DRCCTPROF_PATH=${GPUPUNK_PATH}/drcctprof

SPACK_PATH=${SPACK_PATH:-$GPUPUNK_PATH/spack}
source ${SPACK_PATH}/share/spack/setup-env.sh
spack load boost mbedtls elfutils
# @FindHao NOTE: this is a hack to get the path of the latest version of mbedtls
B=$(spack find --path mbedtls | tail -n 1 | cut -d ' ' -f 3)
S=${B%/*}
echo "GPUPUNK-> mbedtls install path is " $B

export LD_LIBRARY_PATH=$B/lib:${GPUTRIGGER_PATH}:${REDSHOW_PATH}/lib:$LD_LIBRARY_PATH
export PATH=${GPUPUNK_PATH}/bin/:${DRCCTPROF_PATH}/bin:$PATH
