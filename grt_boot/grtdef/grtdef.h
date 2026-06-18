#pragma once

// grtdef.h

typedef unsigned short WCHAR;
typedef unsigned long long USIZE;
typedef long long GRT_SIZE;
typedef GRT_SIZE ptrdiff_t;

#ifndef __GRTCALL
    #if _WIN32
        #define __GRTCALL __stdcall
    #else
        #define __GRTCALL __cdecl
    #endif // #if _WIN32
#endif // #ifndef __GRTCALL

#ifndef __WCHAR
    #define __WCHAR
#endif // #ifndef __WCHAR