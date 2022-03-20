#!/bin/bash

if [ $# -lt 1 ];then
    echo "usage: bin/build.sh target_install_path"
    exit -1
fi

source_path=$(pwd)
# CUDA_PATH=/usr/local/cuda
install_path=$1 

if [ ! -d $install_path ]
then
    echo "target install path not exist, will create it"
    mkdir -p $install_path
fi

echo "Your source code path is " $source_path
echo "Your install path is " $install_path

echo "GPUPUNK-> install dependencies"
cd $install_path
git clone --depth 1 https://github.com/spack/spack.git
export SPACK_ROOT=$(pwd)/spack
source ${SPACK_ROOT}/share/spack/setup-env.sh
spack install boost@1.76.0 mbedtls@3.1.0
spack load boost@1.76.0 mbedtls@3.1.0

# Find spack and boost dir
B=$(spack find --path boost | tail -n 1 | cut -d ' ' -f 3)
S=${B%/*}
echo "GPUPUNK-> boost install path is " $B


cd ${source_path}/gpu-patch
make clean
make PREFIX=${install_path}/gpu-patch CUDA_PATH=$CUDA_PATH install -j 4

cd  ${source_path}/redshow
make clean
make PREFIX=${install_path}/redshow BOOST_DIR=$B GPU_PATCH_DIR=${install_path}/gpu-patch DEBUG=1  STATIC_CPP=1 install -j 12 -f Makefile.static

cd ${source_path}/libmonitor
make clean
./configure --prefix=${install_path}/libmonitor/
make -j 12
make install

cd ${source_path}/gputrigger
rm -rf ${source_path}/gputrigger/build
mkdir build && cd build
cmake ..  -DCMAKE_INSTALL_PREFIX=${install_path}/gputrigger -Dgpu_patch_path=${install_path}/gpu-patch
make -j 16
make install -j 4


export ENABLE_GPUTRIGGER=1
export REDSHOW_PATH=${install_path}/redshow
export GPUPATCH_PATH=${install_path}/gpu-patch
cd ${source_path}/drcctprof_clients
./build_clean.sh ; ./build.sh
cp -r ./DrCCTProf/build ${install_path}/drcctprof

cd ${source_path}/cubin_filter
rm -rf ${source_path}/cubin_filter/build
mkdir build && cd build
cmake ..  -DCMAKE_INSTALL_PREFIX=${install_path}/cubin_filter 
make -j 16
make install -j 4

cd ${source_path}
# cp -rf ./bin ${install_path}/
mkdir ${install_path}/bin
# @FindHao TODO: change to copy before final release
ln -s ${source_path}/bin/gpupunk ${install_path}/bin/gpupunk

