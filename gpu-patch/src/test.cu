#include <cuda_runtime.h>

#include <iostream>

#include "gpu-patch.h"
#include "utils.h"

#define GPU_ANALYSIS_DEBUG 1

#if GPU_ANALYSIS_DEBUG
#define PRINT(...)                         \
  if (threadIdx.x == 0 && blockIdx.x == 0) \
  {                                        \
    printf(__VA_ARGS__);                   \
  }
#define PRINT_ALL(...) \
  printf(__VA_ARGS__)
#define PRINT_RECORDS(buffer)                                                                                               \
  __syncthreads();                                                                                                          \
  if (threadIdx.x == 0)                                                                                                     \
  {                                                                                                                         \
    gpu_patch_analysis_address_t *records = (gpu_patch_analysis_address_t *)buffer->records;                                \
    for (uint32_t i = 0; i < buffer->head_index; ++i)                                                                       \
    {                                                                                                                       \
      printf("gpu analysis-> merged <%p, %p> (%p)\n", records[i].start, records[i].end, records[i].end - records[i].start); \
    }                                                                                                                       \
  }                                                                                                                         \
  __syncthreads();
#else
#define PRINT(...)
#define PRINT_ALL(...)
#define PRINT_RECORDS(buffer)
#endif

#define MAX_U64 (0xFFFFFFFFFFFFFFFF)
#define MAX_U32 (0xFFFFFFFF)

#define SANITIZER_FN_NAME(f) f

#define CHECK_CALL(fn, args)                         \
  {                                                  \
    cudaError_t status = SANITIZER_FN_NAME(fn) args; \
    if (status != cudaSuccess)                       \
    {                                                \
      fprintf(stderr, "error code %s\n",             \
              cudaGetErrorString(status));           \
      exit(EXIT_FAILURE);                            \
    }                                                \
  }

/**
 * Each gpu_patch_buffer_t has a pointer to its records, and each records has 32 addresses. This function will unfold this structure into gpu_patch_buffer_t has new records while each record only has one address and its count.
 * @param buffer: the original buffer with a bunch of records
 * @param tmp_buffer: the buffer with unfolded records
 */
static __device__ void unfold_records(gpu_patch_buffer_t *patch_buffer, gpu_patch_buffer_t *tmp_buffer)
{
  auto warp_index = blockDim.x / GPU_PATCH_WARP_SIZE * blockIdx.x + threadIdx.x / GPU_PATCH_WARP_SIZE;
  // by default it is 4
  auto num_warps = blockDim.x / GPU_PATCH_WARP_SIZE;
  auto laneid = get_laneid();
  gpu_patch_record_address_t *records = (gpu_patch_record_address_t *)patch_buffer->records;
  gpu_patch_addr_sort_t *addr_hist = (gpu_patch_addr_sort_t *)tmp_buffer->records;
  PRINT("gpu analysis->full: %u, analysis: %u, head_index: %u, tail_index: %u, size: %u, num_threads: %u",
        patch_buffer->full, patch_buffer->analysis, patch_buffer->head_index, patch_buffer->tail_index,
        patch_buffer->size, patch_buffer->num_threads)
  // each warp will take care with one record (32 addresses) in each iteration
  for (auto iter = warp_index; iter < patch_buffer->head_index; iter += num_warps)
  {
    gpu_patch_record_address_t *record = records + iter;
    uint64_t address = record->address[laneid];
    // if the thread is not active, set the address to 0
    if (((0x1u << laneid) & record->active) == 0)
    {
      address = 0;
    }

    addr_hist[iter * GPU_PATCH_WARP_SIZE + laneid] = address;
  }
  tmp_buffer->head_index = patch_buffer->head_index * GPU_PATCH_WARP_SIZE;
}
template <int THREADS>
static __device__ void block_radix_sort(gpu_patch_buffer_t *tmp_buffer, gpu_patch_buffer_t *hist_buffer) {
  int num_of_records = tmp_buffer->head_index;
  // DEFAULT_GPU_PATCH_RECORD_NUM is 1280*1024 by default. each record includes 32 addresses with uint64_t type. so the total size is 1280*1024*32*8 = 335544320 bytes. Since we have 1024 threads for our analysis kernel, each thread need 335544320/1024/1024 = 320KB memory. The max local memory per thread is 512KB, so we are good for default configuration.
  int items_per_thread = num_of_records / THREADS;
  // Specialize BlockRadixSort type for our thread block
  typedef cub::BlockRadixSort<uint64_t, THREADS, items_per_thread, uint64_t> BlockRadixSortT;
  // __shared__ typename BlockRadixSort::TempStorage temp_storage;
  uint64_t *keys_in = (uint64_t *)tmp_buffer->records;
}

extern "C" __launch_bounds__(GPU_PATCH_ANALYSIS_THREADS, 1)
    __global__
    void gpu_analysis_hist(
        gpu_patch_buffer_t *buffer,
        gpu_patch_buffer_t *tmp_buffer
        // gpu_patch_buffer_t *hist_buffer
    )
{
  // // Continue processing until CPU notifies analysis is done
  // while (true) {
  //   // Wait until GPU notifies buffer is full. i.e., analysis can begin process.
  //   // Block sampling is not allowed
  //   while (buffer->analysis == 0 && atomic_load(&buffer->num_threads) != 0)
  //     ;
  //   if (atomic_load(&buffer->num_threads) == 0) {
  //     // buffer->analysis must be 0
  //     break;
  //   }

  // }
  unfold_records(buffer, tmp_buffer);
}

int main(int argc, char **argv)
{
  std::cout << "Hello, world!" << std::endl;
  int num_records = 2000;

  // tmp_buffer is used to store the unfolded records
  gpu_patch_buffer_t *tmp_buffer;
  CHECK_CALL(cudaMalloc, ((void **)&tmp_buffer, sizeof(gpu_patch_buffer_t)));
  void *tmp_buffer_records_g = NULL;
  CHECK_CALL(cudaMalloc, ((void **)&tmp_buffer_records_g,
                          sizeof(gpu_patch_addr_sort_t) * num_records * GPU_PATCH_WARP_SIZE));
  // we need to update the records pointer in tmp_buffer by this way. because we can't directly update the records pointer in tmp_buffer on CPU side.
  gpu_patch_buffer_t *tmp_buffer_h;
  tmp_buffer_h = (gpu_patch_buffer_t *)malloc(sizeof(gpu_patch_buffer_t));
  tmp_buffer_h->records = tmp_buffer_records_g;

  CHECK_CALL(cudaMemcpy, (tmp_buffer, tmp_buffer_h, sizeof(gpu_patch_buffer_t), cudaMemcpyHostToDevice));

  // gpu_buffer stores the original trace
  gpu_patch_buffer_t *gpu_buffer;
  CHECK_CALL(cudaMalloc, ((void **)&gpu_buffer, sizeof(gpu_patch_buffer_t)));
  void *gpu_buffer_records;
  CHECK_CALL(cudaMalloc, ((void **)&gpu_buffer_records,
                          sizeof(gpu_patch_record_address_t) * num_records));

  gpu_patch_buffer_t *gpu_buffer_h;
  gpu_buffer_h = (gpu_patch_buffer_t *)malloc(sizeof(gpu_patch_buffer_t));
  gpu_patch_record_address_t *gpu_buffer_records_h;
  gpu_buffer_records_h = (gpu_patch_record_address_t *)malloc(sizeof(gpu_patch_record_address_t) * num_records);
  gpu_buffer_h->records = gpu_buffer_records;
  gpu_buffer_h->head_index = num_records;
  for (int i = 0; i < num_records; i++)
  {
    for (int j = 0; j < GPU_PATCH_WARP_SIZE; j++)
    {
      gpu_buffer_records_h[i].address[j] = i % 100;
      gpu_buffer_records_h[i].size = 1;
    }
    gpu_buffer_records_h[i].active = 0xffffffff;
  }
  CHECK_CALL(cudaMemcpy, (gpu_buffer, gpu_buffer_h, sizeof(gpu_patch_buffer_t), cudaMemcpyHostToDevice));
  CHECK_CALL(cudaMemcpy, (gpu_buffer_records, gpu_buffer_records_h, sizeof(gpu_patch_record_address_t) * num_records, cudaMemcpyHostToDevice));
  gpu_analysis_hist<<<1, GPU_PATCH_ANALYSIS_THREADS>>>(gpu_buffer, tmp_buffer);
  gpu_patch_addr_sort_t *tmp_buffer_records_h = (gpu_patch_addr_sort_t *)malloc(sizeof(gpu_patch_addr_sort_t) * num_records * GPU_PATCH_WARP_SIZE);
  CHECK_CALL(cudaMemcpy, (tmp_buffer_records_h, tmp_buffer_records_g, sizeof(gpu_patch_addr_sort_t) * num_records * GPU_PATCH_WARP_SIZE, cudaMemcpyDeviceToHost));
  CHECK_CALL(cudaDeviceSynchronize, ());
  for (int i = 0; i < num_records; i++)
  {
    for (int j = 0; j < GPU_PATCH_WARP_SIZE; j++)
    {
      std::cout << tmp_buffer_records_h[i * GPU_PATCH_WARP_SIZE + j] << " ";
    }
    std::cout << std::endl;
  }

  CHECK_CALL(cudaFree, (gpu_buffer));
  CHECK_CALL(cudaFree, (gpu_buffer_records));
  CHECK_CALL(cudaFree, (tmp_buffer));
  CHECK_CALL(cudaFree, (tmp_buffer_records_g));
  free(tmp_buffer_h);
  free(gpu_buffer_h);
  free(gpu_buffer_records_h);

  return 0;
}