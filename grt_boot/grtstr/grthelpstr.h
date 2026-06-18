#pragma once

#include "../grtdef/grtdef.h"

#ifdef __cplusplus
extern "C" {
#endif

USIZE __GRTCALL grt_string_next_capacity(USIZE required);
void __GRTCALL grt_string_ensure_capacity(char **data, USIZE *capacity, USIZE required);
void __GRTCALL grt_string_move_tail(char *data, USIZE start, USIZE count, ptrdiff_t shift);

#ifdef __cplusplus
}
#endif
