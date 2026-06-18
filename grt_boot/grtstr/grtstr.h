#pragma once

#include "../grtdef/grtdef.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Runtime initialization and cleanup */
int __GRTCALL grt_str_init(void);
void __GRTCALL grt_str_cleanup(void);

typedef struct {
    char *data;
    USIZE length;
    USIZE capacity;
} grt_String;

typedef struct {
    WCHAR *wdata;
    USIZE wlength;
    USIZE wcapacity;
} grt_WString;

grt_String __GRTCALL grt_string_new(void);
grt_String __GRTCALL grt_string_from_cstr(const char *text);

grt_WString __GRTCALL __WCHAR grt_wstring_new(void);
grt_WString __GRTCALL __WCHAR grt_wstring_from_wcstr(const WCHAR *text);

USIZE __GRTCALL grt_string_length(const grt_String *str);
USIZE __GRTCALL grt_string_capacity(const grt_String *str);
const char *__GRTCALL grt_string_data(const grt_String *str);

USIZE __GRTCALL __WCHAR grt_wstring_length(const grt_WString *str);
USIZE __GRTCALL __WCHAR grt_wstring_capacity(const grt_WString *str);
const WCHAR *__GRTCALL __WCHAR grt_wstring_data(const grt_WString *str);

void __GRTCALL grt_string_free(grt_String *str);
void __GRTCALL grt_string_clear(grt_String *str);
void __GRTCALL grt_string_resize(grt_String *str, USIZE new_length);

void __GRTCALL __WCHAR grt_wstring_free(grt_WString *str);
void __GRTCALL __WCHAR grt_wstring_clear(grt_WString *str);
void __GRTCALL __WCHAR grt_wstring_resize(grt_WString *str, USIZE new_length);

void __GRTCALL grt_string_append_cstr(grt_String *str, const char *suffix);
void __GRTCALL grt_string_append_char(grt_String *str, char ch);
void __GRTCALL grt_string_append_bytes(grt_String *str, const char *data, USIZE len);
void __GRTCALL grt_string_insert_cstr(grt_String *str, USIZE index, const char *text);
void __GRTCALL grt_string_replace_range(grt_String *str, USIZE index, USIZE count, const char *text);

void __GRTCALL __WCHAR grt_wstring_append_wcstr(grt_WString *str, const WCHAR *suffix);
void __GRTCALL __WCHAR grt_wstring_append_wchar(grt_WString *str, WCHAR ch);
void __GRTCALL __WCHAR grt_wstring_append_wbytes(grt_WString *str, const WCHAR *data, USIZE len);
void __GRTCALL __WCHAR grt_wstring_insert_wcstr(grt_WString *str, USIZE index, const WCHAR *text);
void __GRTCALL __WCHAR grt_wstring_replace_range(grt_WString *str, USIZE index, USIZE count, const WCHAR *text);

int __GRTCALL grt_string_compare(const grt_String *a, const grt_String *b);
grt_String __GRTCALL grt_string_substring(const grt_String *str, USIZE index, USIZE count);

int __GRTCALL __WCHAR grt_wstring_compare(const grt_WString *a, const grt_WString *b);
grt_WString __GRTCALL __WCHAR grt_wstring_substring(const grt_WString *str, USIZE index, USIZE count);

void __GRTCALL grt_string_init(grt_String *str);
void __GRTCALL grt_string_release(grt_String *str);
void __GRTCALL grt_string_append(grt_String *str, const char *suffix);
const char *__GRTCALL grt_string_data_ptr(const grt_String *str);
char *__GRTCALL grt_string_build(const char *left, const char *right);

void __GRTCALL grt_wstring_init(grt_WString *str);
void __GRTCALL grt_wstring_release(grt_WString *str);
void __GRTCALL grt_wstring_append(grt_WString *str, const WCHAR *suffix);
const WCHAR *__GRTCALL grt_wstring_data_ptr(const grt_WString *str);
WCHAR *__GRTCALL grt_wstring_build(const WCHAR *left, const WCHAR *right);

#ifdef __cplusplus
}
#endif