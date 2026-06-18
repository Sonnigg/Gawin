#include "grtdef/grtdef.h"
#include "grtdef/grtnil.h"
#include "grtdef/grtheap.h"
#include <windows.h>

/*
    THIS IS A WINDOWS-ONLY HEADER C FILE AND IS MEANT TO BE USED FOR HANDWRITTEN LLVM IR
    WHEN COMPILING WITH glld input.ll output.exe [-l...] [-L...]

    build_wstr CONVERTS ANY UTF-8 STRING (basic C char*) INTO UTF-16 (Windows-native wchar_t* aka WCHAR*)
    THIS IS SO THAT IN HANDWRITTEN LLVM IR YOU DON'T HAVE TO WRITE AN i16 ARRAY 
    BY HAND

    TO USE UTF-16 STRINGS RELIABLY USE THE BUILTIN *_utf16 OR *_wstr FUNCTIONS
    THAT ARE PROVIDED BY THE GAWIN STANDARD LIBRARY
*/

WCHAR *__GRTCALL __WCHAR build_wstr(const char *str) {

    if (!str)
        return NULL;

    int needed = MultiByteToWideChar(
        CP_UTF8,
        0,
        str,
        -1,
        NULL,
        0
    );

    if (needed <= 0)
        return NULL;

    WCHAR *wstr =
        (WCHAR *)hdwr_malloc(
            needed * sizeof(WCHAR)
        );

    if (!wstr)
        return NULL;

    int result = MultiByteToWideChar(
        CP_UTF8,
        0,
        str,
        -1,
        wstr,
        needed
    );

    if (result == 0) {
        hdwr_free(
            wstr,
            needed * sizeof(WCHAR)
        );

        return NULL;
    }

    return wstr;
}