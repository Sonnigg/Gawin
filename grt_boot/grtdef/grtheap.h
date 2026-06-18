#pragma once

// grtheap.h

#include "grtdef.h"
#include "grtnil.h"

/* Hardware-level memory allocation */
void *hdwr_malloc(USIZE size);

/* Hardware-level memory release */
void hdwr_free(void *ptr, USIZE size);

/*
 * Hardware-level realloc
 *
 * Behaves similarly to standard realloc():
 *
 * - realloc(NULL, size)     -> malloc
 * - realloc(ptr, 0)         -> free + NULL
 * - preserves old contents
 * - old_size must be known
 */
void *hdwr_realloc(
    void *ptr,
    USIZE old_size,
    USIZE new_size
);

void *hdwr_memcpy(
    void *dst,
    const void *src,
    USIZE size
);

void *hdwr_memmove(
    void *dst,
    const void *src,
    USIZE size
);

typedef struct grt_block_header {
    USIZE size;
    USIZE segment_size;
    struct grt_block_header *next_phys;
    struct grt_block_header *prev_phys;
    struct grt_block_header *next_free;
    struct grt_block_header *prev_free;
    struct grt_block_header *next_seg;
    int free;
} grt_block_header;

#define GRT_BASE_SEGMENT_SIZE (1 * 1024 * 1024)                     // 1MB base segment size
#define GRT_ALIGNMENT 16
#define GRT_MIN_BLOCK_SIZE 32
#define GRT_NUM_FREE_LISTS 64

static grt_block_header *grt_heap_start = NULL;
static grt_block_header *grt_heap_end = NULL;
static grt_block_header *grt_seg_list = NULL;
static grt_block_header *grt_free_lists[GRT_NUM_FREE_LISTS] = { 0 };
static USIZE grt_free_mask = 0;
static USIZE grt_next_segment_size = GRT_BASE_SEGMENT_SIZE;