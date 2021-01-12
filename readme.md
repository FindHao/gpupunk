gputrigger: Callback functions which is used to catch the triggers of CUDA APIs. It will be monitered by gpupunk client of drcctprof.

gpupunk_sanitizer_patch: The instrumentation functions to collect all memory accesses.

drcctprof: drcctprof/src/clients/drcctlib_gpupunk is the main client to hold and analysis memory accesses passed from gputrigger.

## 1. Install

### gputrigger

```
cd gputrigger
mkdir build && cd build
cmake ..
make -j8
```

It will generate  `lib_gputrigger.so` and `gputrigger_patch.fatbin`.

### drcctprof



## 2. Usage

### test gputrigger only

Copy `gputrigger_patch.fatbin` to the test program folder. Run vectorAdd as an example.

```
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/compute-sanitizer
LD_PRELOAD=libgputrigger.so ./vectorAdd
```





