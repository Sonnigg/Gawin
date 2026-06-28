# Gawin Source Code Information

## The 4 Big Sources

* The **Gawin Compiler Project**
* The **Gawin Runtime Project**
* The **Gawin Standard Library Project**
* The **Gawin Toolchain**

---

## Gawin Compiler Project

The **Gawin Compiler Project** includes all sources that were used to make the Gawin Compiler. Those include:

* The **Lexer**
* The **Parser**
* The **Analysis**
* The **Codegen**
* The **SRC-Analyser**
* The **Style Guide Enforcer**
* The **Visibility Checker**

---

## Gawin Runtime Project

The **Gawin Runtime Project** includes all sources that were used to make the Gawin Boot Runtime (The Gawin Runtime). Those include:

* The **grtdef boot:** [grtdef.h](./grt_boot/grtdef/grtdef.h), [grtheap.c](./grt_boot/grtdef/grtheap.c), [grtheap.h](./grt_boot/grtdef/grtheap.h), [grtmax.h](./grt_boot/grtdef/grtmax.h), [grtnil.h](./grt_boot/grtdef/grtnil.h)
* The **grtio boot:** [grthelpio.h](./grt_boot/grtio/grthelpio.h), [grtio.c](./grt_boot/grtio/grtio.c), [grtio.h](./grt_boot/grtio/grtio.h)
* The **grtmem boot:** [grthelpmem.h](./grt_boot/grtmem/grthelpmem.h), [grtmem.c](./grt_boot/grtmem/grtmem.c), [grtmem.h](./grt_boot/grtmem/grtmem.h)
* The **grtstr boot:** [grthelpstr.h](./grt_boot/grtstr/grthelpstr.h), [grtstr.c](./grt_boot/grtstr/grtstr.c), [grtstr.h](./grt_boot/grtstr/grtstr.h)
* The **win32 boot:** [utf16.c](./grt_boot/win32/utf16.c)
* The **grt start-up:** [grt.c](./grt_boot/grt.c), [grt.h](./grt_boot/grt.h)
* The **LOC Text File:** [LOC.count.txt](./grt_boot/LOC.count.txt)

---

## Gawin Standard Library Project

---

## Gawin Toolchain

The **Gawin Toolchain** includes all sources that were used to make the Gawin Toolchain. Those include:

* The [Gawin Compiler for Freestanding Executables](./bin/src_exec/gfree.cpp)
* The [Gawin Runtime with LLVM Linker](./bin/src_exec/glld.cpp)
* The [Gawin Runtime Compiler](./bin/src_exec/gstdo.cpp)
* The [Timer Utility](./bin/src_exec/timer.cpp)
* The [Vlang LLVM API](./ggc/v_llvmc/v_llvmc.v)