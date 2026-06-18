#include "grtmem.h"
#include "../grtdef/grtdef.h"
#include "../grtdef/grtmax.h"
#include "../grtdef/grtnil.h"
#include "../grtdef/grtheap.h"

#include "grthelpmem.h"

/*
 * GRTHELPMEM moved into GRTMEM
 */

USIZE __GRTCALL grt_round_up_capacity(USIZE required) {
    if (required <= 16) {
        return 16;
    }

    USIZE capacity = 16;
    while (capacity < required) {
        capacity <<= 1;
    }
    return capacity;
}

int __GRTCALL grt_ptrs_overlap(const void *a, const void *b, USIZE len) {
    const unsigned char *a_bytes = (const unsigned char *)a;
    const unsigned char *b_bytes = (const unsigned char *)b;

    return (a_bytes < b_bytes)
        ? (a_bytes + len > b_bytes)
        : (b_bytes + len > a_bytes);
}

void __GRTCALL grt_copy_bytes(void *dest, const void *src, USIZE len) {
    if (grt_ptrs_overlap(dest, src, len)) {
        grt_memmove(dest, src, len);
    } else {
        grt_memcpy(dest, src, len);
    }
}

/*
 * GRTMEM begins here, GRTHELPMEM ends here
 */

static unsigned grt_size_to_bin(USIZE size) {
    USIZE normalized = size < GRT_MIN_BLOCK_SIZE ? GRT_MIN_BLOCK_SIZE : size;
    unsigned bin = 0;
    USIZE bucket = 1;
    while (bucket < normalized && bin + 1 < GRT_NUM_FREE_LISTS) {
        bucket <<= 1;
        ++bin;
    }
    return bin;
}

static void grt_update_free_mask(unsigned bin) {
    if (grt_free_lists[bin]) {
        grt_free_mask |= (1ULL << bin);
    } else {
        grt_free_mask &= ~(1ULL << bin);
    }
}

static unsigned grt_find_non_empty_bin(unsigned bin) {
    for (unsigned i = bin; i < GRT_NUM_FREE_LISTS; ++i) {
        if (grt_free_lists[i]) {
            return i;
        }
    }
    return GRT_NUM_FREE_LISTS;
}

static void grt_register_segment(grt_block_header *seg) {
    seg->next_seg = grt_seg_list;
    grt_seg_list = seg;
}

static void grt_remove_free_block(grt_block_header *block) {
    if (!block) return;

    unsigned bin = grt_size_to_bin(block->size);
    if (block->prev_free) {
        block->prev_free->next_free = block->next_free;
    } else {
        grt_free_lists[bin] = block->next_free;
    }
    if (block->next_free) {
        block->next_free->prev_free = block->prev_free;
    }

    block->next_free = NULL;
    block->prev_free = NULL;
    grt_update_free_mask(bin);
}

static void grt_insert_free_block(grt_block_header *block) {
    if (!block) return;

    unsigned bin = grt_size_to_bin(block->size);
    block->free = 1;
    block->prev_free = NULL;
    block->next_free = grt_free_lists[bin];
    if (grt_free_lists[bin]) {
        grt_free_lists[bin]->prev_free = block;
    }
    grt_free_lists[bin] = block;
    grt_update_free_mask(bin);
}

static void grt_append_segment_block(grt_block_header *new_block) {
    new_block->prev_phys = grt_heap_end;
    new_block->next_phys = NULL;
    if (grt_heap_end) {
        grt_heap_end->next_phys = new_block;
    }
    grt_heap_end = new_block;
}

static grt_block_header *grt_make_segment(USIZE segment_size) {
    unsigned char *seg = (unsigned char *)hdwr_malloc(segment_size);

    if (!seg) {
        return NULL;
    }

    if (!grt_heap_start) {
        grt_reset_allocator_state();
    }

    grt_block_header *root = (grt_block_header *)seg;

    root->size = segment_size - sizeof(grt_block_header);
    root->segment_size = segment_size;
    root->free = 1;

    root->next_phys = NULL;
    root->prev_phys = NULL;

    root->next_free = NULL;
    root->prev_free = NULL;

    root->next_seg = NULL;

    if (!grt_heap_start) {
        grt_heap_start = root;
        grt_heap_end = root;
    } else {
        grt_append_segment_block(root);
    }

    grt_register_segment(root);
    grt_insert_free_block(root);

    return root;
}

static void grt_coalesce(grt_block_header *block) {
    if (!block) {
        return;
    }

    grt_block_header *next = block->next_phys;
    if (next && next->free && next->segment_size == block->segment_size) {
        grt_remove_free_block(next);
        block->size += sizeof(grt_block_header) + next->size;
        block->next_phys = next->next_phys;
        if (block->next_phys) {
            block->next_phys->prev_phys = block;
        } else {
            grt_heap_end = block;
        }
    }

    grt_block_header *prev = block->prev_phys;
    if (prev && prev->free && prev->segment_size == block->segment_size) {
        grt_remove_free_block(prev);
        prev->size += sizeof(grt_block_header) + block->size;
        prev->next_phys = block->next_phys;
        if (block->next_phys) {
            block->next_phys->prev_phys = prev;
        } else {
            grt_heap_end = prev;
        }
        block = prev;
    }

    grt_insert_free_block(block);
}

static void grt_split_block(grt_block_header *block, USIZE required_size) {
    if (!block) {
        return;
    }

    USIZE remaining = block->size - required_size;
    if (remaining <= sizeof(grt_block_header) + GRT_MIN_BLOCK_SIZE) {
        return;
    }

    unsigned char *split_position = (unsigned char *)block + sizeof(grt_block_header) + required_size;
    grt_block_header *next_block = (grt_block_header *)split_position;
    next_block->size = remaining - sizeof(grt_block_header);
    next_block->segment_size = block->segment_size;
    next_block->free = 1;
    next_block->prev_phys = block;
    next_block->next_phys = block->next_phys;
    next_block->next_free = NULL;
    next_block->prev_free = NULL;
    next_block->next_seg = block->next_seg;

    if (block->next_phys) {
        block->next_phys->prev_phys = next_block;
    } else {
        grt_heap_end = next_block;
    }

    block->size = required_size;
    block->next_phys = next_block;

    grt_insert_free_block(next_block);
}

static grt_block_header *grt_data_to_header(void *data) {
    return data ? (grt_block_header *)((unsigned char *)data - sizeof(grt_block_header)) : NULL;
}

static void *grt_header_to_data(grt_block_header *block) {
    return block ? (void *)((unsigned char *)block + sizeof(grt_block_header)) : NULL;
}

static grt_block_header *grt_find_free_block(USIZE size) {
    if (!grt_heap_start) {
        if (!grt_make_segment(grt_next_segment_size)) {
            return NULL;
        }
    }

    unsigned bin = grt_size_to_bin(size);
    unsigned available = grt_find_non_empty_bin(bin);

    if (available == GRT_NUM_FREE_LISTS) {
        USIZE alloc_size = grt_next_segment_size;

        if (alloc_size < size + sizeof(grt_block_header)) {
            alloc_size = size + sizeof(grt_block_header);
        }

        grt_block_header *segment = grt_make_segment(alloc_size);

        if (!segment) {
            return NULL;
        }

        if (grt_next_segment_size <= USIZE_MAX / 2) {
            grt_next_segment_size *= 2;
        }

        available = grt_find_non_empty_bin(bin);

        if (available == GRT_NUM_FREE_LISTS) {
            return NULL;
        }
    }

    grt_block_header *block = grt_free_lists[available];

    grt_remove_free_block(block);

    return block;
}

static USIZE grt_align_up_internal(USIZE value, USIZE alignment) {
    if (alignment == 0) {
        return value;
    }
    USIZE mask = alignment - 1;
    return (value + mask) & ~mask;
}

static void grt_reset_allocator_state(void) {
    for (unsigned i = 0; i < GRT_NUM_FREE_LISTS; ++i) {
        grt_free_lists[i] = NULL;
    }

    grt_free_mask = 0;
}

void __GRTCALL grt_wipe_segment(void *ptr) {
    if (!ptr || !grt_seg_list) {
        return;
    }

    grt_block_header *seg = grt_seg_list;
    while (seg) {
        if ((unsigned char *)ptr >= (unsigned char *)seg &&
            (unsigned char *)ptr < (unsigned char *)seg + seg->segment_size) {

            grt_block_header *current = seg;
            unsigned char *segment_end = (unsigned char *)seg + seg->segment_size;
            while (current && (unsigned char *)current < segment_end) {
                grt_block_header *next = current->next_phys;
                if (current->free) {
                    grt_remove_free_block(current);
                }
                current = next;
            }

            grt_block_header *next_segment_root = seg->next_phys;
            while (next_segment_root && (unsigned char *)next_segment_root < segment_end) {
                next_segment_root = next_segment_root->next_phys;
            }

            seg->size = seg->segment_size - sizeof(grt_block_header);
            seg->free = 1;
            seg->next_phys = next_segment_root;
            if (next_segment_root) {
                next_segment_root->prev_phys = seg;
            } else {
                grt_heap_end = seg;
            }
            grt_insert_free_block(seg);
            return;
        }
        seg = seg->next_seg;
    }
}

void *__GRTCALL grt_malloc(USIZE size) {
    if (size == 0) {
        return NULL;
    }

    USIZE required_size = grt_align_up_internal(size, GRT_ALIGNMENT);
    grt_block_header *block = grt_find_free_block(required_size);
    if (!block) {
        return NULL;
    }

    block->free = 0;
    grt_split_block(block, required_size);
    return grt_header_to_data(block);
}

void *__GRTCALL grt_calloc(USIZE count, USIZE size) {
    if (count == 0 || size == 0) {
        return NULL;
    }
    if (count > USIZE_MAX / size) {
        return NULL;
    }

    USIZE total = count * size;
    void *ptr = grt_malloc(total);
    if (ptr) {
        grt_memset(ptr, 0, total);
    }
    return ptr;
}

void *__GRTCALL grt_realloc(void *ptr, USIZE size) {
    if (!ptr) {
        return grt_malloc(size);
    }
    if (size == 0) {
        grt_free(ptr);
        return NULL;
    }

    grt_block_header *block = grt_data_to_header(ptr);
    if (!block) {
        return NULL;
    }

    USIZE required_size = grt_align_up_internal(size, GRT_ALIGNMENT);
    if (block->size >= required_size) {
        grt_split_block(block, required_size);
        return ptr;
    }

    void *new_ptr = grt_malloc(size);
    if (!new_ptr) {
        return NULL;
    }

    grt_memcpy(new_ptr, ptr, block->size < size ? block->size : size);
    grt_free(ptr);
    return new_ptr;
}

void __GRTCALL grt_free(void *ptr) {
    if (!ptr) {
        return;
    }

    grt_block_header *block = grt_data_to_header(ptr);
    if (!block) {
        return;
    }

    if (!block->free) {
        grt_coalesce(block);
    }
}

void *__GRTCALL grt_memcpy(void *dest, const void *src, USIZE n) {
    if (!dest || !src || n == 0) {
        return dest;
    }
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    for (USIZE i = 0; i < n; ++i) {
        d[i] = s[i];
    }
    return dest;
}

void *__GRTCALL grt_memmove(void *dest, const void *src, USIZE n) {
    if (!dest || !src || n == 0 || dest == src) {
        return dest;
    }
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    if (d < s) {
        for (USIZE i = 0; i < n; ++i) {
            d[i] = s[i];
        }
    } else {
        for (USIZE i = n; i > 0; --i) {
            d[i - 1] = s[i - 1];
        }
    }
    return dest;
}

void *__GRTCALL grt_memset(void *dest, int value, USIZE n) {
    if (!dest || n == 0) {
        return dest;
    }
    unsigned char *d = (unsigned char *)dest;
    unsigned char byte = (unsigned char)value;
    for (USIZE i = 0; i < n; ++i) {
        d[i] = byte;
    }
    return dest;
}

int __GRTCALL grt_memcmp(const void *s1, const void *s2, USIZE n) {
    if (n == 0) {
        return 0;
    }
    const unsigned char *a = (const unsigned char *)s1;
    const unsigned char *b = (const unsigned char *)s2;
    for (USIZE i = 0; i < n; ++i) {
        if (a[i] != b[i]) {
            return a[i] < b[i] ? -1 : 1;
        }
    }
    return 0;
}

void *__GRTCALL grt_memchr(const void *s, int c, USIZE n) {
    if (!s || n == 0) {
        return NULL;
    }
    const unsigned char *p = (const unsigned char *)s;
    unsigned char target = (unsigned char)c;
    for (USIZE i = 0; i < n; ++i) {
        if (p[i] == target) {
            return (void *)(p + i);
        }
    }
    return NULL;
}

USIZE __GRTCALL grt_align_up(USIZE value, USIZE alignment) {
    return grt_align_up_internal(value, alignment);
}