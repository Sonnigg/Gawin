/*
 * Gawin Runtime (GRT) - Core Runtime Implementation
 * This file provides the main initialization and cleanup logic
 * for the Gawin runtime system in a fully C independent manner.
 */

#include "grt.h"
#include "../grtdef/grtheap.h"

#ifdef _WIN32
#include <windows.h>
#endif

/* Define _fltused for freestanding MSVC-style floating-point support */
int _fltused = 0;

void __GRTCALL grt_mem_cleanup(void) {
    grt_block_header *current = grt_seg_list;

    while (current) {
        grt_block_header *next = current->next_seg;

        hdwr_free(current, current->segment_size);

        current = next;
    }

    grt_heap_start = NULL;
    grt_heap_end = NULL;
    grt_seg_list = NULL;

    grt_next_segment_size = GRT_BASE_SEGMENT_SIZE;
}

/*
 * grt_init_runtime - Initialize all runtime subsystems
 * This function initializes the memory manager, I/O subsystem,
 * and string utilities required by the G runtime.
 */
int __GRTCALL grt_init_runtime(void)
{
	return 0;
}

/*
 * grt_cleanup_runtime - Clean up runtime resources
 * This function performs cleanup of all runtime subsystems
 * in reverse order of initialization.
 */
void __GRTCALL grt_cleanup_runtime(void)
{
	/* Cleanup memory management */
	grt_mem_cleanup();
}

/*
 * _start - runtime entry point (for freestanding mode)
 * This is called by the OS/bootloader. We initialize the G runtime
 * and then call the user's grt_main function.
 */
#ifdef _WIN32
	/* Windows uses _start as the entry point when linking freestanding */
	void __stdcall _start(void)
	{
		UINT code;

		if (grt_init_runtime() != 0)
			ExitProcess(1);

		code = (UINT)grt_main();

		grt_cleanup_runtime();

		ExitProcess(code);
	}
#else
	/* Unix-like systems use _start as entry point */
	void _start(void)
	{
		int exit_code;

		/* Initialize the G runtime */
		if (grt_init_runtime() != 0) {
			exit(1);
		}

		/* Call the user's main function */
		exit_code = grt_main();

		/* Cleanup the G runtime */
		grt_cleanup_runtime();

		exit(exit_code);
	}
#endif
