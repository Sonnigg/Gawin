#pragma once

#include "../grtdef/grtdef.h"

#ifdef __cplusplus
extern "C" {
#endif

USIZE __GRTCALL grt_round_up_capacity(USIZE required);
int __GRTCALL grt_ptrs_overlap(const void *a, const void *b, USIZE len);
void __GRTCALL grt_copy_bytes(void *dest, const void *src, USIZE len);

#ifdef __cplusplus
}
#endif
