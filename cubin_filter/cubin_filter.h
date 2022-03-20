#ifndef CUBIN_FILTER_LIBRARY_H
#define CUBIN_FILTER_LIBRARY_H
#include <stdint.h>
typedef struct {
    uint32_t cubin_id;
    uint32_t unknown_field[1];
    uint32_t mod_id;
} hpctoolkit_cumod_st_t;

#endif //CUBIN_FILTER_LIBRARY_H
