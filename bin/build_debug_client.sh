#!/bin/bash

export install_path=~/opt/gpupunk
export source_path=~/p/gpupunk
export ENABLE_GPUTRIGGER=1
export REDSHOW_PATH=${install_path}/redshow
export GPUPATCH_PATH=${install_path}/gpu-patch
cd ${source_path}/drcctprof_clients
./build_clean.sh ; ./build_debug.sh ; rm -rf ~/opt/gpupunk/drcctprof-debug
cp -r ./DrCCTProf/build_debug ${install_path}/drcctprof-debug

