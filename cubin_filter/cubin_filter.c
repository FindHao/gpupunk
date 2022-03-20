#include "cubin_filter.h"
#include <stdio.h>
#include "crypto-hash.h"
#include <sanitizer_callbacks.h>
#include <sys/stat.h>
#include <stdbool.h>
#include <errno.h>     // errno
#include <fcntl.h>     // open
#include <unistd.h>    // close

#define PRINT(__VA_ARGS__...) fprintf(stderr, __VA_ARGS__)
#define PATH_MAX        4096    /* # chars in a path name including nul */

static bool
cuda_write_cubin(
        const char *file_name,
        const void *cubin,
        size_t cubin_size) {
    int fd;
    errno = 0;
    fd = open(file_name, O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (errno == EEXIST) {
        close(fd);
        return true;
    }
    if (fd >= 0) {
        // Success
        if (write(fd, cubin, cubin_size) != cubin_size) {
            close(fd);
            return false;
        } else {
            close(fd);
            return true;
        }
    } else {
        // Failure to open is a fatal error.
        fprintf(stderr, "hpctoolkit: unable to open file: '%s'", file_name);
        return false;
    }
}

static void ApiTrackerCallback(
        void *userdata,
        Sanitizer_CallbackDomain domain,
        Sanitizer_CallbackId cbid,
        const void *cbdata) {
    if (domain != SANITIZER_CB_DOMAIN_RESOURCE)
        return;

    Sanitizer_CallbackData *pCallbackData = (Sanitizer_CallbackData *) cbdata;
    if (cbid == SANITIZER_CBID_RESOURCE_MODULE_LOADED) {
        Sanitizer_ResourceModuleData *pModuleLoadedData = (Sanitizer_ResourceModuleData *) pCallbackData;
        PRINT("Module loaded: %s\n", pModuleLoadedData->pCubin);
        PRINT("cubin size: %zu\n", pModuleLoadedData->cubinSize);
        unsigned char hash[0];
        const void *cubin = pModuleLoadedData->pCubin;
        unsigned int hash_length = crypto_hash_length();
        crypto_hash_compute(cubin, pModuleLoadedData->cubinSize, hash, hash_length);
        uint32_t cubin_id = ((hpctoolkit_cumod_st_t *) pModuleLoadedData->module)->cubin_id;
        // Create file name
        char file_name[PATH_MAX];
        size_t i;
        size_t used = 0;
        //    @todo fix path
        used += sprintf(&file_name[used], "%s", "./");
        used += sprintf(&file_name[used], "%s", "/cubins/");
        mkdir(file_name, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
        for (i = 0; i < hash_length; ++i) {
            used += sprintf(&file_name[used], "%02x", hash[i]);
        }
        used += sprintf(&file_name[used], "%s", ".cubin");
        PRINT("Sanitizer-> cubin_id %d hash %s\n", cubin_id, file_name);
        cuda_write_cubin(file_name, cubin, pModuleLoadedData->cubinSize);

    } else if (cbid == SANITIZER_CBID_RESOURCE_MODULE_UNLOAD_STARTING) {
        Sanitizer_ResourceModuleData *pModuleUnloadedData = (Sanitizer_ResourceModuleData *) pCallbackData;
        PRINT("Module unloaded: %s\n", pModuleUnloadedData->pCubin);
    }
}

__attribute__((constructor))
int InitializeInjection() {
    Sanitizer_SubscriberHandle handle;
    sanitizerSubscribe(&handle, ApiTrackerCallback, NULL);
    sanitizerEnableDomain(1, handle, SANITIZER_CB_DOMAIN_RESOURCE);
    return 0;
}



