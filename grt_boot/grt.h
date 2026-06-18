#pragma once

/*
 * Gawin Runtime (GRT) - Core Runtime Initialization Header
 * This header provides the main entry point and initialization
 * for the Gawin runtime system, making it fully C independent.
 */

#include "grtdef/grtdef.h"
#include "grtdef/grtmax.h"
#include "grtdef/grtnil.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * grt_init_runtime - Initialize all G runtime subsystems
 * This must be called before any G code executes.
 * Returns 0 on success, non-zero on failure.
 */
int __GRTCALL grt_init_runtime(void);

/*
 * grt_cleanup_runtime - Clean up and shutdown G runtime subsystems
 * This should be called before program termination.
 */
void __GRTCALL grt_cleanup_runtime(void);

/*
 * grt_main - Main entry point for G programs
 * Implemented by the generated G code, called by the OS.
 * Returns exit code.
 */
int __GRTCALL grt_main(void);

#ifdef __cplusplus
}
#endif
