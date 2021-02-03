#!/bin/bash
export GPUPUNK_PATCH=/path/to/gputrigger/build/gputrigger_patch.fatbin
LD_PRELOAD=/path/to/libgputrigger.so /path/to/DrCCTProf/build/bin64/drrun -t drcctlib_gpupunk --  ./vectorAdd