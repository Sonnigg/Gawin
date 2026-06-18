#pragma once

#include "../grtdef/grtdef.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GRT_BUF_COUNT 4
#define GRT_BUF_SIZE  32
#define GRT_OUTPUT_BUFFER_SIZE 4096

int __GRTCALL grt_chptr_len(const char *str);
const char *__GRTCALL grt_int_to_chptr(int value);
const char *__GRTCALL grt_uint_to_chptr(USIZE value);
const char *__GRTCALL grt_char_to_chptr(char value);
const char *__GRTCALL grt_float_to_chptr(float value);
const char *__GRTCALL grt_double_to_chptr(double value);
void __GRTCALL grt_append_output(const char *data, int len);
void __GRTCALL grt_flush_bytes(int bytes);

#define grt_to_chptr(x) _Generic((x), \
  int:    grt_int_to_chptr, \
  USIZE:  grt_uint_to_chptr, \
  char:   grt_char_to_chptr, \
  float:  grt_float_to_chptr, \
  double: grt_double_to_chptr, \
  default: grt_int_to_chptr \
)(x)

#ifdef __cplusplus
}
#endif
