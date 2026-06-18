#pragma once

//#include <stdarg.h>
#include "grthelpio.h"
#include "../grtdef/grtdef.h"

#ifdef __cplusplus
extern "C" {
#endif // #ifdef __cplusplus

/* Runtime initialization and cleanup */
int __GRTCALL grt_io_init(void);
void __GRTCALL grt_io_cleanup(void);

void __GRTCALL print_int(int value);
void __GRTCALL print_uint(USIZE value);
void __GRTCALL print_float(float value);
void __GRTCALL print_double(double value);
void __GRTCALL print_str(const char *str);
void __GRTCALL print_char(char value);

void __GRTCALL println_int(int value);
void __GRTCALL println_uint(USIZE value);
void __GRTCALL println_float(float value);
void __GRTCALL println_double(double value);
void __GRTCALL println_str(const char *str);
void __GRTCALL println_char(char value);

void __GRTCALL grt_flush_bytes(int bytes);

#ifdef _WIN32
void __GRTCALL __WCHAR print_wstr(const WCHAR *wstr);
void __GRTCALL __WCHAR print_wchar(const WCHAR wc);
void __GRTCALL __WCHAR print_wint(int value);
void __GRTCALL __WCHAR print_wuint(USIZE value);
void __GRTCALL __WCHAR print_wfloat(float value);
void __GRTCALL __WCHAR print_wdouble(double value);

void __GRTCALL __WCHAR println_wstr(const WCHAR *wstr);
void __GRTCALL __WCHAR println_wchar(const WCHAR wc);
void __GRTCALL __WCHAR println_wint(int value);
void __GRTCALL __WCHAR println_wuint(USIZE value);
void __GRTCALL __WCHAR println_wfloat(float value);
void __GRTCALL __WCHAR println_wdouble(double value);
#endif // #ifdef _WIN32

#ifdef __cplusplus
}
#endif // #ifdef __cplusplus

/*
  FOR HANDWRITTEN C/C++ THAT INCLUDE THIS HEADER DIRECTLY OR USAGE ACROSS THE LIBRARY OF GRTIO
*/

#define GRT_PRINT(x) _Generic((x), \
  int:    print_int,        \
  USIZE:  print_uint,       \
  char:   print_char,       \
  char*:  print_str,        \
  float:  print_float,      \
  double: print_double,     \
  default: print_int        \
)(x)

#define GRT_PRINTLN(x) _Generic((x), \
  int:    println_int,      \
  USIZE:  println_uint,     \
  char:   println_char,     \
  char*:  println_str,      \
  float:  println_float,    \
  double: println_double,   \
  default: println_int      \
)(x)

#ifdef _WIN32
#define GRT_WPRINT(x) _Generic((x), \
  int:    print_wint,       \
  USIZE:  print_wuint,      \
  WCHAR:  print_wchar,      \
  WCHAR*: print_wstr,       \
  float:  print_wfloat,     \
  double: print_wdouble,    \
  default: print_wint       \
)(x)

#define GRT_WPRINTLN(x) _Generic((x), \
  int:    println_wint,     \
  USIZE:  println_wuint,    \
  WCHAR:  println_wchar,    \
  WCHAR*: println_wstr,     \
  float:  println_wfloat,   \
  double: println_wdouble,  \
  default: println_wint     \
)(x)
#endif // #ifdef _WIN32