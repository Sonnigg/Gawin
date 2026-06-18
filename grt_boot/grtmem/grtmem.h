#pragma once

#include "../grtdef/grtdef.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Runtime initialization and cleanup */
void __GRTCALL grt_mem_cleanup(void);
void __GRTCALL grt_reset_allocator_state(void);
void __GRTCALL grt_wipe_segment(void *ptr);

/* Memory management functions */
void *__GRTCALL grt_malloc(USIZE size);
void *__GRTCALL grt_calloc(USIZE count, USIZE size);
void *__GRTCALL grt_realloc(void *ptr, USIZE size);
void __GRTCALL grt_free(void *ptr);

void *__GRTCALL grt_memcpy(void *dest, const void *src, USIZE n);
void *__GRTCALL grt_memmove(void *dest, const void *src, USIZE n);
void *__GRTCALL grt_memset(void *dest, int value, USIZE n);
int __GRTCALL grt_memcmp(const void *s1, const void *s2, USIZE n);
void *__GRTCALL grt_memchr(const void *s, int c, USIZE n);

USIZE __GRTCALL grt_align_up(USIZE value, USIZE alignment);

#ifdef __cplusplus
}
#endif
