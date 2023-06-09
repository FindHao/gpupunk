#include <cuda_runtime.h>

#include <iostream>

#include "gpu-patch.h"
#include "utils.h"
#include <cub/cub.cuh>

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
      fprintf(stderr, "error in %s\n", #fn);         \
      fprintf(stderr, "error code %s\n",             \
              cudaGetErrorString(status));           \
      exit(EXIT_FAILURE);                            \
    }                                                \
  }

/**
 * Each gpu_patch_buffer_t has a pointer to its records, and each records has 32 addresses. This function will unfold this structure into gpu_patch_buffer_t has new records while each record only has one address and its count. Besides the unfolding, this function will also do intra-warp counting.
 * @param buffer: the original buffer with a bunch of records
 * @param unfolded_buffer: the buffer with unfolded and intra-warp-processed records.
 */
static __device__ void unfold_records(gpu_patch_buffer_t *patch_buffer, gpu_patch_buffer_t *unfolded_buffer)
{
  auto warp_id = blockDim.x / GPU_PATCH_WARP_SIZE * blockIdx.x + threadIdx.x / GPU_PATCH_WARP_SIZE;
  // by default it is 4
  auto num_warps = blockDim.x / GPU_PATCH_WARP_SIZE;
  auto laneid = get_laneid();
  const int idx = threadIdx.x + blockDim.x * blockIdx.x;

  gpu_patch_record_address_t *records = (gpu_patch_record_address_t *)patch_buffer->records;
  gpu_patch_addr_hist_t *addr_hist = (gpu_patch_addr_hist_t *)unfolded_buffer->records;
  PRINT("gpu analysis->full: %u, analysis: %u, head_index: %u, tail_index: %u, size: %u, num_threads: %u",
        patch_buffer->full, patch_buffer->analysis, patch_buffer->head_index, patch_buffer->tail_index,
        patch_buffer->size, patch_buffer->num_threads)
  int addr_hist_index = 0;
  auto iter = warp_id;
  int round_head_index = (patch_buffer->head_index + num_warps - 1) / num_warps * num_warps;
  // every record has 32 addresses with mask. but the number of record may not be `num_warps` aligned.
  // e.g., there are 3 records. we need to let the last warp be inactive.
  // each warp will take care with one record (32 addresses) in each iteration
  for (; iter < round_head_index; iter += num_warps)
  {
    if (iter >= patch_buffer->head_index)
    {
      continue;
    }
    gpu_patch_record_address_t *record = records + iter;
    uint64_t address = record->address[laneid];
    // if the thread is not active, set the address to 0
    if (((0x1u << laneid) & record->active) == 0)
    {
      address = 0;
    }
    // sort addresses of a record inside a warp
    address = warp_sort(address, laneid);

    uint64_t value = address;
    uint64_t prev_value = __shfl_up_sync(0xffffffff, value, 1);
    bool is_unique = (laneid == 0) || (value != prev_value);

    unsigned int predicate = __ballot_sync(0xffffffff, !is_unique);
    uint32_t mask = 0xFFFFFFFF << laneid;
    uint32_t predicate2 = predicate & mask;
    uint32_t predicate2_reverse = __brev(predicate2);
    int leading_zeros_origin = __clz(predicate2_reverse);
    // Find the position of the most significant bit (MSB) set to 1
    int msb_position = 31 - __clz(predicate2_reverse);
    // Create a mask with all bits set to 1 up to and including the MSB
    mask = (0xFFFFFFFF >> (31 - msb_position));
    // Invert the input number (flip all the bits)
    unsigned int inverted_x = ~predicate2_reverse;
    // Count the number of leading zeros in the inverted number masked with the mask
    int leading_zeros = __clz(inverted_x & mask);
    int leading_ones = (predicate & (1 << (laneid + 1))) ? leading_zeros - leading_zeros_origin : 0;
    int count = leading_ones + 1;
    // how many unique addresses in this warp
    int unique_mark = __ballot_sync(0xffffffff, is_unique);
    __shared__ int unique_count_shared[GPU_PATH_ANALYSIS_NUM_WARPS];
    __shared__ int unique_count_shared_accumulate[GPU_PATH_ANALYSIS_NUM_WARPS];
    if (laneid == 0)
    {
      unique_count_shared[warp_id] = __popc(unique_mark);
      // unique_count_shared_accumulate[warp_id] = __popc(unique_mark);
      if (warp_id == 0)
      {
        int next_start = 0;
        for (int i = 0; i < GPU_PATH_ANALYSIS_NUM_WARPS; i++)
        {
          unique_count_shared_accumulate[i] = next_start;
          next_start += unique_count_shared[i];
        }
      }
    }
    __shared__ uint64_t addr_hist_addr[GPU_PATCH_WARP_SIZE * GPU_PATH_ANALYSIS_NUM_WARPS];
    __shared__ int addr_hist_count[GPU_PATCH_WARP_SIZE * GPU_PATH_ANALYSIS_NUM_WARPS];
    __syncthreads();
    if (is_unique)
    {
      int output_idx = __popc(unique_mark & ((1 << laneid) - 1)) + unique_count_shared_accumulate[warp_id];
      addr_hist_addr[output_idx] = value;
      addr_hist_count[output_idx] = count;
    }
    __syncthreads();
    if (idx == 0)
    {
      int all_unique_count = unique_count_shared_accumulate[GPU_PATH_ANALYSIS_NUM_WARPS - 1] + unique_count_shared[GPU_PATH_ANALYSIS_NUM_WARPS - 1];
      for (int i = 0; i < all_unique_count; i++)
      {
        addr_hist[addr_hist_index + i].address = addr_hist_addr[i];
        addr_hist[addr_hist_index + i].count = addr_hist_count[i];
      }
      addr_hist_index += all_unique_count;
    }
  }
  // unfolded_buffer->head_index = patch_buffer->head_index * GPU_PATCH_WARP_SIZE;
  unfolded_buffer->head_index = addr_hist_index;
}

/**
 * @brief This function only sorts THREADS * ITEMS_PER_THREAD items in unfolded_buffer->records
 * @Yueming TODO: add the histogram part
 */
template <int THREADS, int ITEMS_PER_THREAD>
static __device__ void block_radix_sort_tile(
    uint64_t *d_in,
    uint64_t *d_out)
{
  typedef cub::BlockRadixSort<uint64_t, THREADS, ITEMS_PER_THREAD> BlockRadixSortT;
  __shared__ typename BlockRadixSortT::TempStorage temp_storage;
  uint64_t keys[ITEMS_PER_THREAD];
  for (int i = 0; i < ITEMS_PER_THREAD; ++i)
  {
    keys[i] = d_in[threadIdx.x * ITEMS_PER_THREAD + i];
  }
  BlockRadixSortT(temp_storage).Sort(keys);
  for (int i = 0; i < ITEMS_PER_THREAD; ++i)
  {
    d_out[threadIdx.x * ITEMS_PER_THREAD + i] = keys[i];
  }
  // maybe we can use the similar code in unfold_records to process all 4 warps in a block.
}

template <int THREADS, int ITEMS_PER_THREAD>
static __device__ void block_radix_sort(
    gpu_patch_buffer_t *unfolded_buffer,
    gpu_patch_buffer_t *hist_buffer)
{
}

extern "C" __launch_bounds__(GPU_PATCH_ANALYSIS_THREADS, 1)
    __global__
    void gpu_analysis_hist(
        gpu_patch_buffer_t *buffer,
        gpu_patch_buffer_t *unfolded_buffer,
        gpu_patch_addr_hist_t *unfolded_buffer_records_g_sorted
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
  unfold_records(buffer, unfolded_buffer);
  // @Yueming TODO: use a for loop to split the unfolded_buffer into multiple tiles, and use block_radix_sort_tile to process each tile. Add another outside for loop to process at least twice to compress more. Finally, the unfolded_buffer_records_g_sorted will have compressed histogram.
  // uint32_t tile_size = THREADS * GPU_PATCH_ANALYSIS_THREADS;
  // block_radix_sort<GPU_PATCH_ANALYSIS_THREADS, GPU_PATCH_ANALYSIS_ITEMS>(unfolded_buffer, hist_buffer);
}

int main(int argc, char **argv)
{
  std::cout << "Hello, world!" << std::endl;
  int num_records = 3;

  // unfolded_buffer is used to store the unfolded records
  gpu_patch_buffer_t *unfolded_buffer;
  CHECK_CALL(cudaMalloc, ((void **)&unfolded_buffer, sizeof(gpu_patch_buffer_t)));
  // unfolded_buffer_records_g is used to store the unfolded records
  void *unfolded_buffer_records_g = NULL;
  CHECK_CALL(cudaMalloc, ((void **)&unfolded_buffer_records_g,
                          sizeof(gpu_patch_addr_hist_t) * num_records * GPU_PATCH_WARP_SIZE));
  // unfolded_buffer_records_g_sorted is used to store the sorted unfolded records
  void *unfolded_buffer_records_g_sorted = NULL;
  CHECK_CALL(cudaMalloc, ((void **)&unfolded_buffer_records_g_sorted,
                          sizeof(gpu_patch_addr_hist_t) * num_records * GPU_PATCH_WARP_SIZE));
  // we need to update the records pointer in unfolded_buffer by this way. because we can't directly update the records pointer in unfolded_buffer on CPU side.
  gpu_patch_buffer_t *unfolded_buffer_h;
  unfolded_buffer_h = (gpu_patch_buffer_t *)malloc(sizeof(gpu_patch_buffer_t));
  unfolded_buffer_h->records = unfolded_buffer_records_g;

  CHECK_CALL(cudaMemcpy, (unfolded_buffer, unfolded_buffer_h, sizeof(gpu_patch_buffer_t), cudaMemcpyHostToDevice));

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
      // gpu_buffer_records_h[i].address[j] = j % 10;
      gpu_buffer_records_h[i].address[j] = 1;
      gpu_buffer_records_h[i].size = 1;
    }
    gpu_buffer_records_h[i].active = 0xffffffff;
  }
  CHECK_CALL(cudaMemcpy, (gpu_buffer, gpu_buffer_h, sizeof(gpu_patch_buffer_t), cudaMemcpyHostToDevice));
  CHECK_CALL(cudaMemcpy, (gpu_buffer_records, gpu_buffer_records_h, sizeof(gpu_patch_record_address_t) * num_records, cudaMemcpyHostToDevice));
  gpu_analysis_hist<<<1, GPU_PATCH_ANALYSIS_THREADS>>>(gpu_buffer, unfolded_buffer, (gpu_patch_addr_hist_t *)unfolded_buffer_records_g_sorted);

  gpu_patch_addr_hist_t *unfolded_buffer_records_h = (gpu_patch_addr_hist_t *)malloc(sizeof(gpu_patch_addr_hist_t) * num_records * GPU_PATCH_WARP_SIZE);
  // copy the unfolded records from GPU to CPU
  CHECK_CALL(cudaMemcpy, (unfolded_buffer_records_h, unfolded_buffer_records_g, sizeof(gpu_patch_addr_hist_t) * num_records * GPU_PATCH_WARP_SIZE, cudaMemcpyDeviceToHost));
  // copy the head_index back to CPU
  CHECK_CALL(cudaMemcpy, (unfolded_buffer_h, unfolded_buffer, sizeof(gpu_patch_buffer_t), cudaMemcpyDeviceToHost));
  CHECK_CALL(cudaDeviceSynchronize, ());
  std::cout << std::endl
            << "unfolded records: "
            << "head_index:" << unfolded_buffer_h->head_index << std::endl;
  for (int i = 0; i < num_records; i++)
  {
    for (int j = 0; j < GPU_PATCH_WARP_SIZE; j++)
    {
      std::cout << unfolded_buffer_records_h[i * GPU_PATCH_WARP_SIZE + j].address << ":" << unfolded_buffer_records_h[i * GPU_PATCH_WARP_SIZE + j].count << "  ";
    }
    std::cout << std::endl;
  }

  CHECK_CALL(cudaFree, (gpu_buffer));
  CHECK_CALL(cudaFree, (gpu_buffer_records));
  CHECK_CALL(cudaFree, (unfolded_buffer));
  CHECK_CALL(cudaFree, (unfolded_buffer_records_g));
  free(unfolded_buffer_h);
  free(gpu_buffer_h);
  free(gpu_buffer_records_h);

  return 0;
}