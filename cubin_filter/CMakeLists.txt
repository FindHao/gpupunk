cmake_minimum_required(VERSION 3.10)
project(cubin_filter)
include(CheckLanguage)
check_language(CUDA)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_FLAGS " -Wall -Wextra")

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "RelWithDebInfo" CACHE STRING
            "Default build type: RelWithDebInfo" FORCE)
endif ()

if (${CMAKE_VERSION} VERSION_LESS "3.17.0")
    find_package(CUDA REQUIRED)
    set(CUDAToolkit_NVCC_EXECUTABLE ${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc)
    set(CUDAToolkit_TARGET_DIR ${CUDA_TOOLKIT_ROOT_DIR})
    if (${CUDA_VERSION} LESS 11.2)
        message(FATAL_ERROR "CUDAToolkit mush be newer or equal to 11.2. Your version is " ${CUDA_VERSION})
    endif ()
else ()
    find_package(CUDAToolkit REQUIRED)
    if (NOT CMAKE_CUDA_COMPILER)
        if (NOT ${CUDAToolkit_NVCC_EXECUTABLE} AND UNIX AND EXISTS "/usr/local/cuda/bin/nvcc")
            set(CUDAToolkit_NVCC_EXECUTABLE "/usr/local/cuda/bin/nvcc")
            set(CMAKE_CUDA_COMPILER ${CUDAToolkit_NVCC_EXECUTABLE})
            message(WARNING "CMAKE_CUDA_COMPILER guessed: " ${CUDAToolkit_NVCC_EXECUTABLE} "\n"
                    "Please fix your cuda installation: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#mandatory-post")
        endif ()
    endif ()
    if (${CUDAToolkit_VERSION} LESS 11.2)
        message(FATAL_ERROR "CUDAToolkit mush be newer or equal to 11.2. Your version is " ${CUDAToolkit_VERSION})
    endif ()
endif ()
enable_language(CUDA)

include(FindLibElf.cmake)
include(FindMbedTLS.cmake)

message(INFO "==========")
message(STATUS ${LIBELF_INCLUDE_DIRS})
message(STATUS ${LIBELF_LIBRARIES_PATH})
message(STATUS ${MBEDTLS_INCLUDE_DIRS})
message(STATUS ${MBEDCRYPTO_LIBRARY_PATH})

set(SANITIZER_PATH ${CUDAToolkit_TARGET_DIR}/compute-sanitizer)
find_library(mbedcrypto_lib NAMES libmbedcrypto.so)
include_directories(${SANITIZER_PATH}/include/
        ${CUDAToolkit_TARGET_DIR}/include/
        ${CMAKE_CURRENT_LIST_DIR}/include/
        ${CMAKE_CURRENT_LIST_DIR}/src/
        ${LIBELF_INCLUDE_DIRS}
        ${MBEDTLS_INCLUDE_DIRS}
        )
message(INFO ${SANITIZER_PATH} ${CUDAToolkit_NVCC_EXECUTABLE})
add_link_options(-L${SANITIZER_PATH} -fPIC -shared)

aux_source_directory(${CMAKE_CURRENT_LIST_DIR}/ cubin_filter_src)
file(GLOB cubin_filter_head CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/*.h" )



add_link_options(-L${LIBELF_LIBRARIES_PATH} -L${MBEDTLS_LIBRARY_PATH} -L${MBEDCRYPTO_LIBRARY_PATH})

message(INFO ${mbedcrypto_lib})

add_library(cubin_filter SHARED ${cubin_filter_src} )

target_link_libraries(cubin_filter PUBLIC
        -lsanitizer-public
        -lmbedcrypto
)


install(TARGETS cubin_filter DESTINATION ${CMAKE_INSTALL_PREFIX})
install(FILES  ${cubin_filter_head} DESTINATION ${CMAKE_INSTALL_PREFIX}/include/)
