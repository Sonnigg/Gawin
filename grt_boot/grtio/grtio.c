//#include <stdarg.h>
#include "grtio.h"
#include "grthelpio.h"
#include "../grtdef/grtnil.h"
#include "../grtdef/grtheap.h"

/*
  THIS IS THE BASIC GRTIO IMPLEMENTATION THAT GIVES CONSOLE IO FOR PRINTING TO STDOUT
  AND GETTING INPUT FROM STDIN

  WHILE THERE IS STDERR SUPPORT THE UNDERLYING eprint AND eprintln FUNCTIONS HAVE
  NOT YET BEEN MADE

  WHEN CONTRIBUTING ACKNOWLEDGE THAT THE CRT (C Runtime) IS FORBIDDEN IN ANY AND
  ALL USAGES

  GRTIO IS SELF-CONTAINED, MEANING THAT WHILE GRTMEM AND GRTSTR EXIST THEY ARE
  NOT SUPPOSED TO BE INCLUDED IN GRTIO

  THE GRTDEF HEADERS (taken by directory name; ..\grtdef\*.h) ARE MEANT TO BE
  INCLUDED IF THOSE DEFINITIONS ARE NEEDED

  NAMING ANYTHING THE WAY IT ALREADY IS IN ANY OF THE GRTDEF HEADERS IS
  DISALLOWED, MEANING THAT IF YOU DECLARE (example taken from no real world
  context) typedef unsigned long USIZE; YOU WOULD BE BREAKING THIS RULE
  AS ..\grtdef\grtdef.h PROVIDES USIZE AS typedef unsigned long long USIZE;

  GRTIO IS LIMITED TO ..\grtdef\ AND ..\grtio\ (directory of this instance)
  THE LIMIT FACTOR ALSO COUNTS ..\win32\ AS ALLOWED TO BE USED FOR Windows
  SUPPORT

  GAWIN RUNTIME PROJECT (GRT)
  GAWIN STANDARD LIBRARY PROJECT (GSTD)
*/

/*
 * GRTHELPIO moved into GRTIO
 */

static void grt_local_memcpy(void *dest, const void *src, int n) {
  unsigned char *d = (unsigned char *)dest;
  const unsigned char *s = (const unsigned char *)src;

  for (int i = 0; i < n; ++i) {
    d[i] = s[i];
  }
}

static void grt_local_memmove(void *dest, const void *src, int n) {
  unsigned char *d = (unsigned char *)dest;
  const unsigned char *s = (const unsigned char *)src;

  if (d < s) {
    for (int i = 0; i < n; ++i) {
      d[i] = s[i];
    }
  } else {
    for (int i = n; i > 0; --i) {
      d[i - 1] = s[i - 1];
    }
  }
}

#if defined(__STDC_NO_ATOMICS__)
  #if defined(__clang__) || defined(__GNUC__)
    #define GRT_USE_GNU_ATOMICS 1
  #elif defined(_MSC_VER)
    #define GRT_USE_MSVC_ATOMICS 1
  #endif
#else
  #include <stdatomic.h>
  #define GRT_USE_STDATOMIC 1
#endif

#if defined(_WIN32)
  #include <windows.h>
#endif

static char grt_bufs[GRT_BUF_COUNT][GRT_BUF_SIZE];
#if defined(GRT_USE_STDATOMIC)
static atomic_uint grt_buf_index = 0;
static atomic_int grt_output_lock = 0;
#elif defined(GRT_USE_GNU_ATOMICS)
static unsigned int grt_buf_index = 0;
static int grt_output_lock = 0;
#elif defined(GRT_USE_MSVC_ATOMICS)
static volatile unsigned long grt_buf_index = 0;
static volatile LONG grt_output_lock = 0;
#else
static volatile unsigned int grt_buf_index = 0;
static volatile int grt_output_lock = 0;
#endif

static char grt_output_buffer[GRT_OUTPUT_BUFFER_SIZE];
static int grt_output_count = 0;

int __GRTCALL grt_chptr_len(const char *str) {
  int len = 0;
  while (str && str[len]) ++len;
  return len;
}

static int grt_try_lock(void) {
#if defined(GRT_USE_STDATOMIC)
  int expected = 0;
  return atomic_compare_exchange_strong_explicit(
    &grt_output_lock,
    &expected,
    1,
    memory_order_acquire,
    memory_order_relaxed
  );
#elif defined(GRT_USE_GNU_ATOMICS)
  int expected = 0;
  return __atomic_compare_exchange_n(
    &grt_output_lock,
    &expected,
    1,
    0,
    __ATOMIC_ACQUIRE,
    __ATOMIC_RELAXED
  );
#elif defined(GRT_USE_MSVC_ATOMICS)
  return InterlockedCompareExchange(&grt_output_lock, 1, 0) == 0;
#else
  if (grt_output_lock == 0) {
    grt_output_lock = 1;
    return 1;
  }
  return 0;
#endif
}

static void grt_release_lock(void) {
#if defined(GRT_USE_STDATOMIC)
  atomic_store_explicit(&grt_output_lock, 0, memory_order_release);
#elif defined(GRT_USE_GNU_ATOMICS)
  __atomic_store_n(&grt_output_lock, 0, __ATOMIC_RELEASE);
#elif defined(GRT_USE_MSVC_ATOMICS)
  InterlockedExchange(&grt_output_lock, 0);
#else
  grt_output_lock = 0;
#endif
}

static void grt_acquire_lock(void) {
  while (!grt_try_lock()) {
    ;
  }
}

static int grt_next_buf_index(void) {
#if defined(GRT_USE_STDATOMIC)
  return (int)(atomic_fetch_add_explicit(&grt_buf_index, 1, memory_order_relaxed) % GRT_BUF_COUNT);
#elif defined(GRT_USE_GNU_ATOMICS)
  return (int)(__atomic_fetch_add(&grt_buf_index, 1, __ATOMIC_RELAXED) % GRT_BUF_COUNT);
#elif defined(GRT_USE_MSVC_ATOMICS)
  return (int)((InterlockedIncrement(&grt_buf_index) - 1) % GRT_BUF_COUNT);
#else
  return (int)((grt_buf_index++) % GRT_BUF_COUNT);
#endif
}

static char *grt_next_buf(void) {
  return grt_bufs[grt_next_buf_index()];
}

static void write_stdout_bytes(const char *data, int len) {
  if (!data || len <= 0) return;

#ifdef _WIN32
  HANDLE hstdout = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hstdout == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(hstdout, data, (DWORD)len, &written, NULL);
#else
  int total = 0;
  while (total < len) {
    int written = write(1, data + total, len - total);
    if (written <= 0) break;
    total += written;
  }
#endif
}

static void grt_flush_bytes_locked(int bytes) {
  if (grt_output_count == 0) return;

  if (bytes <= 0 || bytes > grt_output_count) {
    bytes = grt_output_count;
  }

  write_stdout_bytes(grt_output_buffer, bytes);
  if (bytes < grt_output_count) {
    grt_local_memmove(grt_output_buffer, grt_output_buffer + bytes, grt_output_count - bytes);
  }

  grt_output_count -= bytes;
}

void __GRTCALL grt_flush_bytes(int bytes) {
  grt_acquire_lock();
  grt_flush_bytes_locked(bytes);
  grt_release_lock();
}

void __GRTCALL grt_append_output(const char *data, int len) {
  if (!data || len <= 0) return;

  grt_acquire_lock();
  while (len > 0) {
    int space = GRT_OUTPUT_BUFFER_SIZE - grt_output_count;
    if (space == 0) {
      grt_flush_bytes_locked(grt_output_count);
      space = GRT_OUTPUT_BUFFER_SIZE;
    }

    int copy_len = len < space ? len : space;
    grt_local_memcpy(grt_output_buffer + grt_output_count, data, copy_len);
    grt_output_count += copy_len;
    data += copy_len;
    len -= copy_len;

    if (grt_output_count == GRT_OUTPUT_BUFFER_SIZE) {
      grt_flush_bytes_locked(grt_output_count);
    }
  }
  grt_release_lock();
}

static char *grt_uint_to_chptr(USIZE value) {
  char *buf = grt_next_buf();
  char *p = buf + GRT_BUF_SIZE - 1;
  *p = '\0';

  do {
    *--p = '0' + (int)(value % 10ull);
    value /= 10ull;
  } while (value);

  return p;
}

const char *__GRTCALL grt_int_to_chptr(int value) {
  unsigned int u = (unsigned int)value;
  int negative = value < 0;
  if (negative) {
    u = (unsigned int)(-(value + 1)) + 1;
  }

  char *p = grt_uint_to_chptr(u);
  if (negative) {
    *--p = '-';
  }

  return p;
}

const char *__GRTCALL grt_char_to_chptr(char value) {
  char *buf = grt_next_buf();
  buf[0] = value;
  buf[1] = '\0';
  return buf;
}

const char *__GRTCALL grt_float_to_chptr(float value) {
  char *buf = grt_next_buf();
  char *p = buf;

  if (value < 0.0f) {
    *p++ = '-';
    value = -value;
  }

  int int_part = (int)value;
  float frac = value - (float)int_part;

  const char *int_str = grt_int_to_chptr(int_part);
  while (*int_str) *p++ = *int_str++;

  *p++ = '.';
  for (int i = 0; i < 6; ++i) {
    frac *= 10.0f;
    int digit = (int)frac;
    *p++ = '0' + digit;
    frac -= digit;
  }

  *p = '\0';
  return buf;
}

const char *__GRTCALL grt_double_to_chptr(double value) {
  char *buf = grt_next_buf();
  char *p = buf;

  if (value < 0.0) {
    *p++ = '-';
    value = -value;
  }

  USIZE int_part = (USIZE)value;
  double frac = value - (double)int_part;

  const char *int_str = grt_uint_to_chptr(int_part);
  while (*int_str) *p++ = *int_str++;

  *p++ = '.';
  for (int i = 0; i < 6; ++i) {
    frac *= 10.0;
    int digit = (int)frac;
    *p++ = '0' + digit;
    frac -= digit;
  }

  *p = '\0';
  return buf;
}

/*
 * GRTIO begins here, GRTHELPIO ends here
 */

#ifdef _WIN32
  #include <windows.h>
  #define STDIN   STD_INPUT_HANDLE
  #define STDOUT  STD_OUTPUT_HANDLE
  #define STDERR  STD_ERROR_HANDLE
#else
  #include <unistd.h>
  #define STDIN   0
  #define STDOUT  1
  #define STDERR  2
#endif

#ifndef GRTIO_BUFFER_SIZE
#define GRTIO_BUFFER_SIZE 1024
#endif


/*
 * Reads from STDIN and returns a heap allocated string.
 * The caller MUST free() the returned string.
 */
char *__GRTCALL get_stdin(void) {
  USIZE capacity = GRTIO_BUFFER_SIZE;
  USIZE length = 0;

  char *buffer = (char *)hdwr_malloc(capacity);

  if (!buffer)
    return NULL;

#ifdef _WIN32

  HANDLE hstdin = GetStdHandle(STDIN);

  while (1) {
    DWORD bytes_read = 0;
    char chunk[256];

    BOOL ok = ReadFile(
      hstdin,
      chunk,
      sizeof(chunk),
      &bytes_read,
      NULL
    );

    if (!ok || bytes_read == 0)
      break;

    for (DWORD i = 0; i < bytes_read; i++) {
      char c = chunk[i];

      /* stop on newline */
      if (c == '\n') {
        buffer[length] = '\0';
        return buffer;
      }

      /* ignore carriage return */
      if (c == '\r')
        continue;

      /*
       * Need room for:
       * - character
       * - null terminator
       */
      if (length + 1 >= capacity) {

        USIZE old_capacity = capacity;
        capacity *= 2;

        char *new_buffer =
          (char *)hdwr_realloc(
            buffer,
            old_capacity,
            capacity
          );

        if (!new_buffer) {
          hdwr_free(buffer, old_capacity);
          return NULL;
        }

        buffer = new_buffer;
      }

      buffer[length++] = c;
    }
  }

#else

  while (1) {
    char c;

    int bytes_read =
      read(STDIN, &c, 1);

    if (bytes_read <= 0)
      break;

    /* stop on newline */
    if (c == '\n')
      break;

    /* ignore carriage return */
    if (c == '\r')
      continue;

    if (length + 1 >= capacity) {

      USIZE old_capacity = capacity;
      capacity *= 2;

      char *new_buffer =
        (char *)hdwr_realloc(
          buffer,
          old_capacity,
          capacity
        );

      if (!new_buffer) {
        hdwr_free(buffer, old_capacity);
        return NULL;
      }

      buffer = new_buffer;
    }

    buffer[length++] = c;
  }

#endif

  buffer[length] = '\0';
  return buffer;
}

// STDOUT == (DWORD)-11 OR STDOUT == 1
void __GRTCALL write_stdout(const char *string) {
  if (!string) return;

  int len = grt_chptr_len(string);
  if (len <= 0) return;

#ifdef _WIN32
  HANDLE hstdout = GetStdHandle(STDOUT);

  DWORD total = 0;
  while (total < (DWORD)len) {
    DWORD written = 0;

    BOOL ok = WriteFile(
      hstdout,
      string + total,
      (DWORD)len - total,
      &written,
      NULL
    );

    if (!ok || written == 0)
      break;

    total += written;
  }
#else
  int total = 0;
  while (total < len) {
    int written = write(STDOUT, string + total, len - total);

    if (written <= 0)
      break;

    total += written;
  }
#endif
}

// STDERR == (DWORD)-12 OR STDERR == 2
void __GRTCALL write_stderr(const char *string) {
  if (!string) return;

  int len = grt_chptr_len(string);
  if (len <= 0) return;

#ifdef _WIN32
  HANDLE hstderr = GetStdHandle(STDERR);

  DWORD total = 0;
  while (total < (DWORD)len) {
    DWORD written = 0;

    BOOL ok = WriteFile(
      hstderr,
      string + total,
      (DWORD)len - total,
      &written,
      NULL
    );

    if (!ok || written == 0)
      break;

    total += written;
  }
#else
  int total = 0;
  while (total < len) {
    int written = write(STDERR, string + total, len - total);

    if (written <= 0)
      break;

    total += written;
  }
#endif
}

/*
 * Prints a prompt to STDOUT
 * and returns the user input.
 *
 * The caller MUST free() the returned string.
 */
char *__GRTCALL preadln(const char *prompt) {
  if (prompt)
    write_stdout(prompt);

  return get_stdin();
}

#ifdef _WIN32

static void write_string(const char *string, DWORD channel)
{
  if (!string)
    return;

  int len = grt_chptr_len(string);

  if (len <= 0) {
    return;
  }

  switch (channel) {
    case STDIN:
      break;
    case STDOUT:
      write_stdout(string);
      break;

    case STDERR:
      write_stderr(string);
      break;

    default:
      write_stderr(
        "[GRTIO]: Unexpected channel does not match STDOUT or STDERR"
      );
      break;
  }
}

#else
static void write_string(const char *string, int channel)
{
  if (!string)
    return;

  int len = grt_chptr_len(string);

  if (len <= 0) {
    write_stderr("[GRTIO]: Unexpected negative or zero length");
    return;
  }

  switch (channel) {
    case STDOUT:
      write_stdout(string);
      break;

    case STDERR:
      write_stderr(string);
      break;

    default:
      write_stderr(
        "[GRTIO]: Unexpected channel does not match STDIN, STDOUT or STDERR"
      );
      break;
  }
}
#endif

void __GRTCALL print_int(int value) {
  write_stdout(grt_int_to_chptr(value));
}

void __GRTCALL print_uint(USIZE value) {
  write_stdout(grt_uint_to_chptr(value));
}

void __GRTCALL print_str(const char *str) {
  write_stdout(str);
}

void __GRTCALL print_float(float value) {
  write_stdout(grt_float_to_chptr(value));
}

void __GRTCALL print_double(double value) {
  write_stdout(grt_double_to_chptr(value));
}

void __GRTCALL print_char(char value) {
  char ch[2] = {value, '\0'};
  write_stdout(ch);
}

void __GRTCALL println_int(int value) {
  print_int(value);
  write_stdout("\n");
}

void __GRTCALL println_uint(USIZE value) {
  print_uint(value);
  write_stdout("\n");
}

void __GRTCALL println_str(const char *str) {
  print_str(str);
  write_stdout("\n");
}

void __GRTCALL println_float(float value) {
  print_float(value);
  write_stdout("\n");
}

void __GRTCALL println_double(double value) {
  print_double(value);
  write_stdout("\n");
}

void __GRTCALL println_char(char value) {
  print_char(value);
  write_stdout("\n");
}

/* Runtime initialization and cleanup */
int __GRTCALL grt_io_init(void) {
  /* Initialize I/O subsystem if needed */
  return 0;
}

void __GRTCALL grt_io_cleanup(void) {
  /* Cleanup I/O subsystem if needed */
}


#ifdef _WIN32

/*
  THE UTF-16 C FILE (..\win32\utf16.c) IS INCLUDED DIRECTLY DUE TO IT
  BEING A VITAL PART OF THE COMPILATION PIPELINE ON WINDOWS

  WHILE GENERALLY NOT ENCOURAGED, IT IS NECESSARY HERE DUE TO THE
  WEIRDNESS (but also genius) OF MANY C COMPILERS, THOUGH HERE
  clang (20.1.8+) IS ENCOURAGED TO BE USED AND IS USED BY THE
  GAWIN CREATOR ACTIVELY

  THIS IS SO THAT THE BINARIES ARE MADE BY ONE COMPILER AND NOT
  TWO, THREE, OR MORE FROM MANY DIFFERENT CONTRIBUTORS
*/

#include "../win32/utf16.c"

/*
 * UTF-16 helpers
 */

int __GRTCALL __WCHAR grt_wchptr_len(const WCHAR *str) {
  int len = 0;

  while (str && str[len]) {
    ++len;
  }

  return len;
}

/*
 * UTF-16 STDOUT
 */

void __GRTCALL __WCHAR write_stdout_utf16(const WCHAR *string) {
  if (!string)
    return;

  int len = grt_wchptr_len(string);

  if (len <= 0)
    return;

  HANDLE hstdout = GetStdHandle(STD_OUTPUT_HANDLE);

  if (hstdout == INVALID_HANDLE_VALUE)
    return;

  DWORD total = 0;

  while (total < (DWORD)len) {

    DWORD written = 0;

    BOOL ok = WriteConsoleW(
      hstdout,
      string + total,
      (DWORD)len - total,
      &written,
      NULL
    );

    if (!ok || written == 0)
      break;

    total += written;
  }
}

/*
 * UTF-16 STDERR
 */

void __GRTCALL __WCHAR write_stderr_utf16(const WCHAR *string) {
  if (!string)
    return;

  int len = grt_wchptr_len(string);

  if (len <= 0)
    return;

  HANDLE hstderr = GetStdHandle(STD_ERROR_HANDLE);

  if (hstderr == INVALID_HANDLE_VALUE)
    return;

  DWORD total = 0;

  while (total < (DWORD)len) {

    DWORD written = 0;

    BOOL ok = WriteConsoleW(
      hstderr,
      string + total,
      (DWORD)len - total,
      &written,
      NULL
    );

    if (!ok || written == 0)
      break;

    total += written;
  }
}

/*
 * UTF-16 stdin reader
 *
 * Caller MUST free()
 */

WCHAR *__GRTCALL __WCHAR get_stdin_utf16(void) {

  USIZE capacity = GRTIO_BUFFER_SIZE;
  USIZE length = 0;

  WCHAR *buffer =
    (WCHAR *)hdwr_malloc(
      capacity * sizeof(WCHAR)
    );

  if (!buffer)
    return NULL;

  HANDLE hstdin = GetStdHandle(STD_INPUT_HANDLE);

  while (1) {

    WCHAR ch;
    DWORD read = 0;

    BOOL ok = ReadConsoleW(
      hstdin,
      &ch,
      1,
      &read,
      NULL
    );

    if (!ok || read == 0)
      break;

    if (ch == L'\n')
      break;

    if (ch == L'\r')
      continue;

    if (length + 1 >= capacity) {

      USIZE old_capacity = capacity;

      capacity *= 2;

      WCHAR *new_buffer =
        (WCHAR *)hdwr_realloc(
          buffer,
          old_capacity * sizeof(WCHAR),
          capacity * sizeof(WCHAR)
        );

      if (!new_buffer) {

        hdwr_free(
          buffer,
          old_capacity * sizeof(WCHAR)
        );

        return NULL;
      }

      buffer = new_buffer;
    }

    buffer[length++] = ch;
  }

  buffer[length] = L'\0';

  return buffer;
}

/*
 * UTF-16 prompt + input
 */

WCHAR *__GRTCALL __WCHAR preadln_utf16(const WCHAR *prompt) {

  if (prompt)
    write_stdout_utf16(prompt);

  return get_stdin_utf16();
}

/*
 * UTF-16 generic writer
 */

static void __GRTCALL __WCHAR write_string_utf16(
  const WCHAR *string,
  DWORD channel
) {

  if (!string)
    return;

  switch (channel) {

    case STD_OUTPUT_HANDLE:
      write_stdout_utf16(string);
      break;

    case STD_ERROR_HANDLE:
      write_stderr_utf16(string);
      break;

    default:
      write_stderr(
        "[GRTIO]: Invalid UTF16 output channel\n"
      );
      break;
  }
}

/*
 * UTF-16 print helpers
 */

void __GRTCALL __WCHAR print_wstr(const WCHAR *str) {
  write_stdout_utf16(
    str
  );
}

void __GRTCALL __WCHAR print_wint(const int i) {
  WCHAR *wstr = build_wstr(grt_int_to_chptr(i));
  write_stdout_utf16(
    wstr
  );
  hdwr_free(wstr, sizeof(WCHAR) * (grt_wchptr_len(wstr) + 1));
}

void __GRTCALL __WCHAR print_wuint(const USIZE ull) {
  WCHAR *wstr = build_wstr(grt_uint_to_chptr(ull));
  write_stdout_utf16(
    wstr
  );
  hdwr_free(wstr, sizeof(WCHAR) * (grt_wchptr_len(wstr) + 1));
}

void __GRTCALL __WCHAR print_wfloat(const float f) {
  WCHAR *wstr = build_wstr(grt_float_to_chptr(f));
  write_stdout_utf16(
    wstr
  );
  hdwr_free(wstr, sizeof(WCHAR) * (grt_wchptr_len(wstr) + 1));
}

void __GRTCALL __WCHAR print_wdouble(const double d) {
  WCHAR *wstr = build_wstr(grt_double_to_chptr(d));
  write_stdout_utf16(
    wstr
  );
  hdwr_free(wstr, sizeof(WCHAR) * (grt_wchptr_len(wstr) + 1));
}

void __GRTCALL __WCHAR print_wchar(const WCHAR ch) {

  WCHAR buf[2];

  buf[0] = ch;
  buf[1] = L'\0';

  print_wstr(buf);
}

void __GRTCALL __WCHAR println_wstr(const WCHAR *str) {

  print_wstr(str);

  write_stdout_utf16(L"\n");
}

void __GRTCALL __WCHAR println_wchar(const WCHAR ch) {

  print_wchar(ch);

  write_stdout_utf16(L"\n");
}

void __GRTCALL __WCHAR println_wint(const int i) {

  print_wint(i);

  write_stdout_utf16(L"\n");
}

void __GRTCALL __WCHAR println_wuint(const USIZE ull) {
  
  print_wuint(ull);

  write_stdout_utf16(L"\n");
}

void __GRTCALL __WCHAR println_wfloat(const float f) {

  print_wfloat(f);

  write_stdout_utf16(L"\n");
}

void __GRTCALL __WCHAR println_wdouble(const double d) {
  
  print_wdouble(d);

  write_stdout_utf16(L"\n");
}

#endif