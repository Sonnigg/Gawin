#include "grtstr.h"
#include "grthelpstr.h"
//#include "../grtmem/grtmem.h"
// grtmem.h is deprecated in use here
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
    char *new_data = (char *)grt_realloc(*data, next_capacity);
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

static void grt_string_null_terminate(grt_String *str) {
    if (!str || !str->data) {
        return;
    }
    str->data[str->length] = '\0';
}

static void grt_string_allocate(grt_String *str, USIZE capacity) {
    if (!str) {
        return;
    }

    if (capacity == 0) {
        capacity = 1;
    }

    str->data = (char *)hdwr_alloc(capacity);
    if (str->data) {
        str->capacity = capacity;
        str->length = 0;
        str->data[0] = '\0';
    }
}

static void grt_string_resize_internal(grt_String *str, USIZE required_length) {
    if (!str) {
        return;
    }

    USIZE required_capacity = required_length + 1;
    if (required_capacity > str->capacity) {
        USIZE next_capacity = grt_string_next_capacity(required_capacity);
        char *new_data = (char *)grt_realloc(str->data, next_capacity);
        if (!new_data) {
            return;
        }
        str->data = new_data;
        str->capacity = next_capacity;
    }
    str->length = required_length;
    grt_string_null_terminate(str);
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
    result.data = (char *)hdwr_alloc(capacity);
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
        grt_free(str->data);
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
    result.data = (char *)hdwr_alloc(capacity);
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

/* Runtime initialization and cleanup */
int __GRTCALL grt_str_init(void) {
    /* Initialize string subsystem if needed */
    return 0;
}

void __GRTCALL grt_str_cleanup(void) {
    /* Cleanup string subsystem if needed */
}
