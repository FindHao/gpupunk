#!/bin/bash

# usage: install_path=/path/to/install CUDA_PATH=/scratch/opt/cuda-11.8 ./install.sh

current_path=$(dirname $(readlink -f $0))
# if current_path ends with gpupunk/bin, then source_path is gpupunk
if [[ $current_path =~ .*gpupunk/bin$ ]];then
    tmp_path=${current_path%/*}
fi
source_path=${source_path:-$tmp_path}
install_path=${install_path:-~/opt/gpupunk}
if [ ! -d $install_path ]
then
    echo "target install path not exist, will create it"
    mkdir -p $install_path
fi
CUDA_PATH=${CUDA_PATH:-/usr/local/cuda}
if [ ! -d $CUDA_PATH ]
then
    echo "CUDA_PATH not exist"
fi

echo "Your source code path is " $source_path
echo "Your install path is " $install_path
echo "Your cuda path is " $CUDA_PATH


# check if the previous command is successful
function check_status {
    if [ $? -ne 0 ];then
        echo "GPUPUNK-> $1 failed"
        exit -1
    fi
}


echo "GPUPUNK-> install dependencies"
cd $install_path
# if spack doesn't exist, then clone it
if [ ! -d spack ];then
    git clone --depth 1 https://github.com/spack/spack.git
fi
export SPACK_ROOT=$(pwd)/spack
source ${SPACK_ROOT}/share/spack/setup-env.sh
# Fix the versions of dependencies
spack install boost@1.81.0 mbedtls@3.3.0 libs=shared elfutils@0.189
check_status "spack install"
spack load boost mbedtls elfutils

# Find spack and boost dir
B=$(spack find --path boost | tail -n 1 | cut -d ' ' -f 3)
S=${B%/*}
echo "GPUPUNK-> boost install path is " $B

cd ${source_path}/gpu-patch
make clean
make PREFIX=${install_path}/gpu-patch CUDA_PATH=$CUDA_PATH install -j 4
check_status "gpu-patch install"

cd  ${source_path}/redshow
make clean
make PREFIX=${install_path}/redshow BOOST_DIR=$B GPU_PATCH_DIR=${install_path}/gpu-patch DEBUG=1  STATIC_CPP=1 install -j 12 -f Makefile.static
check_status "redshow install"

cd ${source_path}/libmonitor
make clean
./configure --prefix=${install_path}/libmonitor/
make -j 12
check_status "libmonitor install"
make install

cd ${source_path}/gputrigger
rm -rf ${source_path}/gputrigger/build
mkdir build && cd build
cmake ..  -DCMAKE_INSTALL_PREFIX=${install_path}/gputrigger -Dgpu_patch_path=${install_path}/gpu-patch -Dredshow_path=${install_path}/redshow 
make -j 16
check_status "gputrigger install"
make install -j 4

export ENABLE_GPUTRIGGER=1
export REDSHOW_PATH=${install_path}/redshow
export GPUPATCH_PATH=${install_path}/gpu-patch
cd ${source_path}/drcctprof_clients
./build_clean.sh ; ./build.sh
cp -r ./DrCCTProf/build ${install_path}/drcctprof
check_status "drcctprof install"

cd ${source_path}/cubin_filter
rm -rf ${source_path}/cubin_filter/build
mkdir build && cd build
cmake ..  -DCMAKE_INSTALL_PREFIX=${install_path}/cubin_filter 
make -j 16
make install -j 4
check_status "cubin_filter install"

cd ${source_path}
# cp -rf ./bin ${install_path}/
mkdir ${install_path}/bin
# @FindHao TODO: change to copy before final release
if [ -f ${install_path}/bin/gpupunk ];then
    rm ${install_path}/bin/gpupunk
fi
ln -s ${source_path}/bin/gpupunk ${install_path}/bin/gpupunk

