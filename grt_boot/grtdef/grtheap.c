#include "grtdef.h"
#include "grtnil.h"

// grtheap.c

#ifdef _WIN32
#include <windows.h>
#elif defined(__linux__)
#include <sys/mman.h>
#include <unistd.h>
#endif

/* Hardware-level memory allocation */
void *hdwr_malloc(USIZE size) {
#ifdef _WIN32
    return VirtualAlloc(NULL, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
#elif defined(__linux__)
    void *ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return (ptr == MAP_FAILED) ? NULL : ptr;
#else
    return NULL;
#endif
}

/* Hardware-level memory release */
void hdwr_free(void *ptr, USIZE size) {
    if (!ptr) return;
#ifdef _WIN32
    VirtualFree(ptr, 0, MEM_RELEASE);
#elif defined(__linux__)
    munmap(ptr, size);
#endif
}

/*
 * Hardware-level realloc
 *
 * Behaves similarly to standard realloc():
 *
 * - realloc(NULL, size)     -> malloc
 * - realloc(ptr, 0)         -> free + NULL
 * - preserves old contents
 * - old_size must be known
 */
void *hdwr_realloc(
    void *ptr,
    USIZE old_size,
    USIZE new_size
) {
    /* realloc(NULL, size) */
    if (!ptr)
        return hdwr_malloc(new_size);

    /* realloc(ptr, 0) */
    if (new_size == 0) {
        hdwr_free(ptr, old_size);
        return NULL;
    }

#ifdef _WIN32

    /*
     * Try to expand/shrink in place first.
     *
     * MEM_COMMIT alone can extend already
     * reserved pages if contiguous space exists.
     */
    void *expanded = VirtualAlloc(
        (BYTE *)ptr + old_size,
        new_size > old_size
            ? new_size - old_size
            : 0,
        MEM_COMMIT,
        PAGE_READWRITE
    );

    /*
     * If shrinking OR expansion succeeded,
     * we can keep the same pointer.
     */
    if (new_size <= old_size || expanded)
        return ptr;

#elif defined(__linux__)

    /*
     * Linux has mremap() which is basically
     * kernel-level realloc().
     */
#ifdef MREMAP_MAYMOVE

    void *new_ptr = mremap(
        ptr,
        old_size,
        new_size,
        MREMAP_MAYMOVE
    );

    if (new_ptr != MAP_FAILED)
        return new_ptr;

#endif // ^^^^ MREMAP_MAYMOVE ^^^^

#endif

    /*
     * Fallback:
     * allocate new block,
     * copy old data,
     * free old block.
     */

    void *new_ptr = hdwr_malloc(new_size);

    if (!new_ptr)
        return NULL;

    /*
     * Copy minimum size.
     */
    USIZE copy_size =
        (old_size < new_size)
            ? old_size
            : new_size;

    /*
     * Manual memcpy to avoid CRT dependency.
     */
    unsigned char *dst =
        (unsigned char *)new_ptr;

    unsigned char *src =
        (unsigned char *)ptr;

    for (USIZE i = 0; i < copy_size; i++)
        dst[i] = src[i];

    hdwr_free(ptr, old_size);

    return new_ptr;
}

/*
 * Hardware-level memcpy
 *
 * Copies exactly `size` bytes from src to dst.
 *
 * Undefined behavior if regions overlap.
 */
void *hdwr_memcpy(
    void *dst,
    const void *src,
    USIZE size
) {
    unsigned char *d =
        (unsigned char *)dst;

    const unsigned char *s =
        (const unsigned char *)src;

    /*
     * Copy forward.
     */
    for (USIZE i = 0; i < size; i++)
        d[i] = s[i];

    return dst;
}

/*
 * Hardware-level memmove
 *
 * Safe for overlapping regions.
 */
void *hdwr_memmove(
    void *dst,
    const void *src,
    USIZE size
) {
    unsigned char *d =
        (unsigned char *)dst;

    const unsigned char *s =
        (const unsigned char *)src;

    /*
     * Same pointer or zero size.
     */
    if (d == s || size == 0)
        return dst;

    /*
     * If destination is before source,
     * forward copy is safe.
     */
    if (d < s) {

        for (USIZE i = 0; i < size; i++)
            d[i] = s[i];

    } else {

        /*
         * Overlap case:
         * copy backwards.
         */
        for (USIZE i = size; i != 0; i--)
            d[i - 1] = s[i - 1];
    }

    return dst;
}