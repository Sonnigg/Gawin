#include "grtstr.h"
#include "grthelpstr.h"
//#include "../grtmem/grtmem.h"
// grtmem.h is deprecated in use here
#define GRT_HEAP_CONFIG
#include "../grtdef/grtheap.h"
#include "../grtdef/grtdef.h"
#include "../grtdef/grtnil.h"

/*
 * GRTHELPSTR moved into GRTSTR
 */

USIZE __GRTCALL grt_string_next_capacity(USIZE required) {
    if (required <= 16) {
        return 16;
    }

    USIZE capacity = 16;
    while (capacity < required) {
        capacity <<= 1;
    }
    return capacity;
}

void __GRTCALL grt_string_ensure_capacity(char **data, USIZE *capacity, USIZE required) {
    if (!data || !capacity) {
        return;
    }

    if (*capacity >= required) {
        return;
    }

    USIZE next_capacity = grt_string_next_capacity(required);
    char *new_data = (char *)hdwr_realloc(*data, *capacity, next_capacity);
    if (!new_data) {
        return;
    }

    *data = new_data;
    *capacity = next_capacity;
}

void __GRTCALL grt_string_move_tail(char *data, USIZE start, USIZE count, ptrdiff_t shift) {
    if (!data || shift == 0 || count == 0) {
        return;
    }

    hdwr_memmove(data + start + shift, data + start, count);
}

static void grt_wstring_move_tail(WCHAR *data, USIZE start, USIZE count, ptrdiff_t shift) {
    if (!data || shift == 0 || count == 0) {
        return;
    }

    hdwr_memmove(data + start + shift, data + start, count * sizeof(WCHAR));
}

/*
 * GRTSTR begins here, GRTHELPSTR ends here
 */

static USIZE grt_strlen(const char *text) {
    if (!text) {
        return 0;
    }

    USIZE length = 0;
    while (text[length]) {
        ++length;
    }
    return length;
}

static USIZE grt_wstrlen(const WCHAR *text) {
    if (!text) {
        return 0;
    }

    USIZE length = 0;
    while (text[length]) {
        ++length;
    }
    return length;
}

static int grt_strcmp(const char *a, const char *b) {
    if (a == b) {
        return 0;
    }

    if (!a) {
        return b ? -1 : 0;
    }
    if (!b) {
        return 1;
    }

    while (*a && *b) {
        if (*a != *b) {
            return (unsigned char)*a < (unsigned char)*b ? -1 : 1;
        }
        ++a;
        ++b;
    }
    if (*a == *b) {
        return 0;
    }
    return *a ? 1 : -1;
}

static int grt_wstrcmp(const WCHAR *a, const WCHAR *b) {
    if (a == b) {
        return 0;
    }

    if (!a) {
        return b ? -1 : 0;
    }
    if (!b) {
        return 1;
    }

    while (*a && *b) {
        if (*a != *b) {
            return *a < *b ? -1 : 1;
        }
        ++a;
        ++b;
    }
    if (*a == *b) {
        return 0;
    }
    return *a ? 1 : -1;
}

static void grt_string_null_terminate(grt_String *str) {
    if (!str || !str->data) {
        return;
    }
    str->data[str->length] = '\0';
}

static void grt_wstring_null_terminate(grt_WString *str) {
    if (!str || !str->wdata) {
        return;
    }
    str->wdata[str->wlength] = (WCHAR)0;
}

static void grt_string_allocate(grt_String *str, USIZE capacity) {
    if (!str) {
        return;
    }

    if (capacity == 0) {
        capacity = 1;
    }

    str->data = (char *)hdwr_malloc(capacity);
    if (str->data) {
        str->capacity = capacity;
        str->length = 0;
        str->data[0] = '\0';
    }
}

static void grt_wstring_allocate(grt_WString *str, USIZE capacity) {
    if (!str) {
        return;
    }

    if (capacity == 0) {
        capacity = 1;
    }

    str->wdata = (WCHAR *)hdwr_malloc(capacity * sizeof(WCHAR));
    if (str->wdata) {
        str->wcapacity = capacity;
        str->wlength = 0;
        str->wdata[0] = (WCHAR)0;
    }
}

static void grt_string_resize_internal(grt_String *str, USIZE required_length) {
    if (!str) {
        return;
    }

    USIZE required_capacity = required_length + 1;
    if (required_capacity > str->capacity) {
        USIZE next_capacity = grt_string_next_capacity(required_capacity);
        char *new_data = (char *)hdwr_realloc(str->data, str->capacity, next_capacity);
        if (!new_data) {
            return;
        }
        str->data = new_data;
        str->capacity = next_capacity;
    }
    str->length = required_length;
    grt_string_null_terminate(str);
}

static void grt_wstring_resize_internal(grt_WString *str, USIZE required_length) {
    if (!str) {
        return;
    }

    USIZE required_capacity = required_length + 1;
    if (required_capacity > str->wcapacity) {
        USIZE next_capacity = grt_string_next_capacity(required_capacity);
        WCHAR *new_data = (WCHAR *)hdwr_realloc(str->wdata, str->wcapacity * sizeof(WCHAR), next_capacity * sizeof(WCHAR));
        if (!new_data) {
            return;
        }
        str->wdata = new_data;
        str->wcapacity = next_capacity;
    }
    str->wlength = required_length;
    grt_wstring_null_terminate(str);
}

grt_String __GRTCALL grt_string_new(void) {
    grt_String result;
    result.data = NULL;
    result.length = 0;
    result.capacity = 0;
    grt_string_allocate(&result, 1);
    return result;
}

grt_String __GRTCALL grt_string_from_cstr(const char *text) {
    grt_String result;
    result.data = NULL;
    result.length = 0;
    result.capacity = 0;
    if (!text) {
        grt_string_allocate(&result, 1);
        return result;
    }

    USIZE length = grt_strlen(text);
    USIZE capacity = length + 1;
    result.data = (char *)hdwr_malloc(capacity);
    if (!result.data) {
        return grt_string_new();
    }

    hdwr_memcpy(result.data, text, length);
    result.data[length] = '\0';
    result.length = length;
    result.capacity = capacity;
    return result;
}

USIZE __GRTCALL grt_string_length(const grt_String *str) {
    return str && str->data ? str->length : 0;
}

USIZE __GRTCALL grt_string_capacity(const grt_String *str) {
    return str ? str->capacity : 0;
}

const char *__GRTCALL grt_string_data(const grt_String *str) {
    return str ? str->data : NULL;
}

void __GRTCALL grt_string_free(grt_String *str) {
    if (!str) {
        return;
    }
    if (str->data) {
        hdwr_free(str->data, sizeof(str->data)*str->length);
    }
    str->data = NULL;
    str->length = 0;
    str->capacity = 0;
}

void __GRTCALL grt_string_clear(grt_String *str) {
    if (!str || !str->data) {
        return;
    }
    str->length = 0;
    grt_string_null_terminate(str);
}

void __GRTCALL grt_string_resize(grt_String *str, USIZE new_length) {
    if (!str) {
        return;
    }
    grt_string_resize_internal(str, new_length);
}

void __GRTCALL grt_string_append_bytes(grt_String *str, const char *data, USIZE len) {
    if (!str || !data || len == 0) {
        return;
    }

    USIZE old_length = str->length;
    USIZE new_length = old_length + len;
    grt_string_resize_internal(str, new_length);
    if (!str->data) {
        return;
    }

    hdwr_memcpy(str->data + old_length, data, len);
    grt_string_null_terminate(str);
}

void __GRTCALL grt_string_append_cstr(grt_String *str, const char *suffix) {
    if (!suffix) {
        return;
    }
    USIZE suffix_length = grt_strlen(suffix);
    grt_string_append_bytes(str, suffix, suffix_length);
}

void __GRTCALL grt_string_append_char(grt_String *str, char ch) {
    if (!str) {
        return;
    }

    USIZE old_length = str->length;
    USIZE new_length = old_length + 1;
    grt_string_resize_internal(str, new_length);
    if (!str->data) {
        return;
    }

    str->data[old_length] = ch;
    grt_string_null_terminate(str);
}

void __GRTCALL grt_string_insert_cstr(grt_String *str, USIZE index, const char *text) {
    if (!str || !str->data || !text) {
        return;
    }

    if (index > str->length) {
        index = str->length;
    }

    USIZE insert_length = grt_strlen(text);
    USIZE old_length = str->length;
    USIZE new_length = old_length + insert_length;
    grt_string_resize_internal(str, new_length);
    if (!str->data) {
        return;
    }

    grt_string_move_tail(str->data, index, old_length - index, (ptrdiff_t)insert_length);
    hdwr_memcpy(str->data + index, text, insert_length);
    grt_string_null_terminate(str);
}

void __GRTCALL grt_string_replace_range(grt_String *str, USIZE index, USIZE count, const char *text) {
    if (!str || !str->data || !text) {
        return;
    }

    if (index > str->length) {
        index = str->length;
    }

    if (index + count > str->length) {
        count = str->length - index;
    }

    USIZE replacement_length = grt_strlen(text);
    USIZE tail_length = str->length - index - count;
    USIZE new_length = str->length - count + replacement_length;

    grt_string_resize_internal(str, new_length);
    if (!str->data) {
        return;
    }

    if (replacement_length != count) {
        ptrdiff_t shift = (ptrdiff_t)replacement_length - (ptrdiff_t)count;
        grt_string_move_tail(str->data, index + count, tail_length, shift);
    }

    hdwr_memcpy(str->data + index, text, replacement_length);
    grt_string_null_terminate(str);
}

int __GRTCALL grt_string_compare(const grt_String *a, const grt_String *b) {
    if (!a || !a->data) {
        return b && b->data ? -1 : 0;
    }

    if (!b || !b->data) {
        return 1;
    }

    return grt_strcmp(a->data, b->data);
}

grt_String __GRTCALL grt_string_substring(const grt_String *str, USIZE index, USIZE count) {
    grt_String result = grt_string_new();
    if (!str || !str->data) {
        return result;
    }

    if (index > str->length) {
        return result;
    }

    if (index + count > str->length) {
        count = str->length - index;
    }

    USIZE capacity = count + 1;
    result.data = (char *)hdwr_malloc(capacity);
    if (!result.data) {
        return result;
    }

    hdwr_memcpy(result.data, str->data + index, count);
    result.data[count] = '\0';
    result.length = count;
    result.capacity = capacity;
    return result;
}

void __GRTCALL grt_string_init(grt_String *str) {
    if (!str) {
        return;
    }
    *str = grt_string_new();
}

void __GRTCALL grt_string_release(grt_String *str) {
    grt_string_free(str);
}

void __GRTCALL grt_string_append(grt_String *str, const char *suffix) {
    grt_string_append_cstr(str, suffix);
}

const char *__GRTCALL grt_string_data_ptr(const grt_String *str) {
    return grt_string_data(str);
}

char *__GRTCALL grt_string_build(const char *left, const char *right) {
    grt_String str = grt_string_new();
    grt_string_append_cstr(&str, left ? left : "");
    grt_string_append_cstr(&str, right ? right : "");

    USIZE length = str.length;
    char *result = (char *)hdwr_malloc(length + 1);
    if (!result) {
        grt_string_free(&str);
        return NULL;
    }

    hdwr_memcpy(result, str.data, length);
    result[length] = '\0';
    grt_string_free(&str);
    return result;
}

/*
 * WIDE STRING (WCHAR) IMPLEMENTATIONS
 */

grt_WString __GRTCALL __WCHAR grt_wstring_new(void) {
    grt_WString result;
    result.wdata = NULL;
    result.wlength = 0;
    result.wcapacity = 0;
    grt_wstring_allocate(&result, 1);
    return result;
}

grt_WString __GRTCALL __WCHAR grt_wstring_from_wcstr(const WCHAR *text) {
    grt_WString result;
    result.wdata = NULL;
    result.wlength = 0;
    result.wcapacity = 0;
    if (!text) {
        grt_wstring_allocate(&result, 1);
        return result;
    }

    USIZE length = grt_wstrlen(text);
    USIZE capacity = length + 1;
    result.wdata = (WCHAR *)hdwr_malloc(capacity * sizeof(WCHAR));
    if (!result.wdata) {
        return grt_wstring_new();
    }

    hdwr_memcpy(result.wdata, text, length * sizeof(WCHAR));
    result.wdata[length] = (WCHAR)0;
    result.wlength = length;
    result.wcapacity = capacity;
    return result;
}

USIZE __GRTCALL __WCHAR grt_wstring_length(const grt_WString *str) {
    return str && str->wdata ? str->wlength : 0;
}

USIZE __GRTCALL __WCHAR grt_wstring_capacity(const grt_WString *str) {
    return str ? str->wcapacity : 0;
}

const WCHAR *__GRTCALL __WCHAR grt_wstring_data(const grt_WString *str) {
    return str ? str->wdata : NULL;
}

void __GRTCALL __WCHAR grt_wstring_free(grt_WString *str) {
    if (!str) {
        return;
    }
    if (str->wdata) {
        hdwr_free(str->wdata, sizeof(str->wdata) * str->wlength);
    }
    str->wdata = NULL;
    str->wlength = 0;
    str->wcapacity = 0;
}

void __GRTCALL __WCHAR grt_wstring_clear(grt_WString *str) {
    if (!str || !str->wdata) {
        return;
    }
    str->wlength = 0;
    grt_wstring_null_terminate(str);
}

void __GRTCALL __WCHAR grt_wstring_resize(grt_WString *str, USIZE new_length) {
    if (!str) {
        return;
    }
    grt_wstring_resize_internal(str, new_length);
}

void __GRTCALL __WCHAR grt_wstring_append_wbytes(grt_WString *str, const WCHAR *data, USIZE len) {
    if (!str || !data || len == 0) {
        return;
    }

    USIZE old_length = str->wlength;
    USIZE new_length = old_length + len;
    grt_wstring_resize_internal(str, new_length);
    if (!str->wdata) {
        return;
    }

    hdwr_memcpy(str->wdata + old_length, data, len * sizeof(WCHAR));
    grt_wstring_null_terminate(str);
}

void __GRTCALL __WCHAR grt_wstring_append_wcstr(grt_WString *str, const WCHAR *suffix) {
    if (!suffix) {
        return;
    }
    USIZE suffix_length = grt_wstrlen(suffix);
    grt_wstring_append_wbytes(str, suffix, suffix_length);
}

void __GRTCALL __WCHAR grt_wstring_append_wchar(grt_WString *str, WCHAR ch) {
    if (!str) {
        return;
    }

    USIZE old_length = str->wlength;
    USIZE new_length = old_length + 1;
    grt_wstring_resize_internal(str, new_length);
    if (!str->wdata) {
        return;
    }

    str->wdata[old_length] = ch;
    grt_wstring_null_terminate(str);
}

void __GRTCALL __WCHAR grt_wstring_insert_wcstr(grt_WString *str, USIZE index, const WCHAR *text) {
    if (!str || !str->wdata || !text) {
        return;
    }

    if (index > str->wlength) {
        index = str->wlength;
    }

    USIZE insert_length = grt_wstrlen(text);
    USIZE old_length = str->wlength;
    USIZE new_length = old_length + insert_length;
    grt_wstring_resize_internal(str, new_length);
    if (!str->wdata) {
        return;
    }

    grt_wstring_move_tail(str->wdata, index, old_length - index, (ptrdiff_t)insert_length);
    hdwr_memcpy(str->wdata + index, text, insert_length * sizeof(WCHAR));
    grt_wstring_null_terminate(str);
}

void __GRTCALL __WCHAR grt_wstring_replace_range(grt_WString *str, USIZE index, USIZE count, const WCHAR *text) {
    if (!str || !str->wdata || !text) {
        return;
    }

    if (index > str->wlength) {
        index = str->wlength;
    }

    if (index + count > str->wlength) {
        count = str->wlength - index;
    }

    USIZE replacement_length = grt_wstrlen(text);
    USIZE tail_length = str->wlength - index - count;
    USIZE new_length = str->wlength - count + replacement_length;

    grt_wstring_resize_internal(str, new_length);
    if (!str->wdata) {
        return;
    }

    if (replacement_length != count) {
        ptrdiff_t shift = (ptrdiff_t)replacement_length - (ptrdiff_t)count;
        grt_wstring_move_tail(str->wdata, index + count, tail_length, shift);
    }

    hdwr_memcpy(str->wdata + index, text, replacement_length * sizeof(WCHAR));
    grt_wstring_null_terminate(str);
}

int __GRTCALL __WCHAR grt_wstring_compare(const grt_WString *a, const grt_WString *b) {
    if (!a || !a->wdata) {
        return b && b->wdata ? -1 : 0;
    }

    if (!b || !b->wdata) {
        return 1;
    }

    return grt_wstrcmp(a->wdata, b->wdata);
}

grt_WString __GRTCALL __WCHAR grt_wstring_substring(const grt_WString *str, USIZE index, USIZE count) {
    grt_WString result = grt_wstring_new();
    if (!str || !str->wdata) {
        return result;
    }

    if (index > str->wlength) {
        return result;
    }

    if (index + count > str->wlength) {
        count = str->wlength - index;
    }

    USIZE capacity = count + 1;
    result.wdata = (WCHAR *)hdwr_malloc(capacity * sizeof(WCHAR));
    if (!result.wdata) {
        return result;
    }

    hdwr_memcpy(result.wdata, str->wdata + index, count * sizeof(WCHAR));
    result.wdata[count] = (WCHAR)0;
    result.wlength = count;
    result.wcapacity = capacity;
    return result;
}

void __GRTCALL grt_wstring_init(grt_WString *str) {
    if (!str) {
        return;
    }
    *str = grt_wstring_new();
}

void __GRTCALL grt_wstring_release(grt_WString *str) {
    grt_wstring_free(str);
}

void __GRTCALL grt_wstring_append(grt_WString *str, const WCHAR *suffix) {
    grt_wstring_append_wcstr(str, suffix);
}

const WCHAR *__GRTCALL grt_wstring_data_ptr(const grt_WString *str) {
    return grt_wstring_data(str);
}

WCHAR *__GRTCALL grt_wstring_build(const WCHAR *left, const WCHAR *right) {
    grt_WString str = grt_wstring_new();
    grt_wstring_append_wcstr(&str, left ? left : L"");
    grt_wstring_append_wcstr(&str, right ? right : L"");

    USIZE length = str.wlength;
    WCHAR *result = (WCHAR *)hdwr_malloc((length + 1) * sizeof(WCHAR));
    if (!result) {
        grt_wstring_free(&str);
        return NULL;
    }

    hdwr_memcpy(result, str.wdata, length * sizeof(WCHAR));
    result[length] = (WCHAR)0;
    grt_wstring_free(&str);
    return result;
}

/* Runtime initialization and cleanup */
int __GRTCALL grt_str_init(void) {
    /* Initialize string subsystem if needed */
    return 0;
}

void __GRTCALL grt_str_cleanup(void) {
    /* Cleanup string subsystem if needed */
}