#!/bin/bash

source /scratch/setenvs/setspack.sh
spack load cmake@3.19.2
source /scratch/setenvs/setcuda11.2.sh

cd drcctprof/
./rebuild.sh

cd ../gputrigger/
mkdir build
cd build
cmake ..
make -j8

cd ../../
cd gpupunk_samples/vectorAdd.f32.uvm
make -j8
