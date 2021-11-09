#!/bin/bash


if [ $# -lt 1 ];then
    echo "usage: script/build.sh target_install_path"
    exit -1
fi

source_path=$(pwd)

# CUDA_PATH=/usr/local/cuda
install_path=$1 


if [ ! -d $install_path ]
then
    echo "target install path does not exist. "
    exit -1
fi


echo $source_path
echo $install_path

cd ${source_path}/gpu-patch
make clean
make PREFIX=${install_path}/gpu-patch CUDA_PATH=$CUDA_PATH install

cd  ${source_path}/redshow
make clean
make PREFIX=${install_path}/redshow BOOST_DIR=/scratch/spack/opt/spack/linux-ubuntu20.04-cascadelake/gcc-9.3.0/boost-1.76.0-bx6o75jbt5g5ngshnrpzlvodqpjnvjxh GPU_PATCH_DIR=${install_path}/gpu-patch DEBUG=1 install -j 12

cd ${source_path}/libmonitor
make clean
./configure --prefix=${install_path}/libmonitor/
make -j 12
make install

cd ${source_path}/gputrigger
rm -rf build
mkdir build && cd build
cmake .. -Dredshow_path=${install_path}/redshow  -DCMAKE_INSTALL_PREFIX=${install_path}/gputrigger -Dgpu_patch_path=${install_path}/gpu-patch
make -j 16
make install -j 4

# export GPUPUNK_PATCH=/home/yhao24/opt/gpupunk/gpu-patch/lib/gpu-patch.fatbin