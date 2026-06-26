# The Gawin Language Project - Official README.md

## The W-questions

- **What is Gawin?**
- **Why choose Gawin?**
- **Who is Gawin for?**
- **When should you use Gawin?**
- **Where are the benchmarks?**

### What is Gawin?

**Gawin** (or **GLang**) is a highly performant systems language designed for fast prototyping and development—built so you don't have to fight the compiler for a week just to catch a logic bug. 

While Gawin is a new and growing language, it offers a robust ecosystem focused on developer convenience:

1. **Extensive Toolchain:** Driven by `gwin` (the orchestrator), the ecosystem includes `ggc` (Gawin Compiler), `glld` (LLVM IR + GRT Linker), `gfree` (freestanding compiler), `gstdo` (GSTD builder), and `timer` (benchmarking utility).
2. **Readability First:** Features "one way to write things," recognizing that code is read far more often than it is written.
3. **Transparent Codebase:** An easy-to-inspect source codebase for quick scanning of logic and definitions.
4. **First-Class Windows Support:** Excellent Windows compatibility, making modern systems development on Windows seamless.
5. **Zero Bloat:** Adheres to a strict *"Pay only for what you use"* philosophy to keep binaries as small as possible.

### Why choose Gawin?

Gawin eliminates the boilerplate and friction found in traditional systems languages:

1. **Blazing Fast Memory Performance:** Speeds that rival or outmatch C in heavily allocation-driven workloads (see benchmarks).
2. **Rapid Prototyping:** A clean syntax designed to get out of your way, letting you write code as fast as you can think.
3. **No-Friction Safety:** Enjoy memory safety via deterministic Static Reference Counting (SRC), no complex borrow checkers, and no runtime GC pauses.
4. **Instant Readability:** A syntax designed to be easily read and understood, even by developers new to systems programming.
5. **True Zero-Cost Abstractions:** High-level code that compiles down to highly optimized, minimal native binaries.

### Who is Gawin for?

**Gawin** is for anybody wanting a language that combines Go's readability, with the safety of an *SRC-managed language*, and the speed of C (give or take depending on workload). Gawin is definitely something for you if you are tired of the binary bloat of other languages or of the gruesome setup/installing procedure.

Gawin handles the setup/installing procedure for you automatically and keeps its binaries small due to its strict philosophy!

Gawin could also be something for you if you want to learn systems programming and are intimidated by C, C++, and Rust.

While Gawin technically isn't the best scripting language, you can definitely use it as one!
While you accept that it might take a bit longer than, say, Python or JS to run the program (due to compilation and then running the program), you will get a significant increase in speed, since Gawin compiles to native.

### When should you use Gawin?

When deciding where to use **Gawin**, it's best to just try it out and see how it feels! While obviously not the professional approach, this can help often, as you are much more willing to write a project in a language that you personally like or really like for the specific project's usage.

Of course Gawin also shines at a few specific things, such as its Windows-first approach. By making UTF-16 the standard when compiling to Windows, Gawin ensures that you have the best possible experience when targeting Windows.

Not only does Gawin shine with Windows, but it also shines immensely with its gigantic CLI and currently-growing terminal (custom terminal creation) support.

### Where are the benchmarks?

The benchmarks for **Gawin** vs **C** vs **Raw syscalls** are in a seperate [BENCHMARK.csv](./benchmarking/BENCHMARK.csv) file and listed from C to Gawin. All benchmarks were done on a simple program that, in pseudocode, looks like this:

```python
i = 0
WORKLOAD = 16 * 1024 * 1024 # 16MB
while i < 100_000:
    ptr = allocate(WORKLOAD)
    free(ptr)
    i += 1
```

To see the individual benchmarks, follow the links below:

* **C:** [OUTPUT_C.txt](./benchmarking/OUTPUT_C.txt)
* **HARDWARE:** [OUTPUT_HARDWARE.txt](./benchmarking/OUTPUT_HARDWARE.txt)
* **GAWIN:** [OUTPUT_GAWIN.txt](./benchmarking/OUTPUT_GAWIN.txt)

---

## Downloading & Installation

To install **Gawin**, run the correct setup script depending on your operating system.

* **Windows (PowerShell):** `.\setup.ps1`
* **Linux / macOS (Shell):** `chmod +x ./setup.sh && ./setup.sh`

### Verify Installation

After running the installer, restart your terminal and verify the toolchain using the following commands:

* `gwin version` - Displays the current GLang and installed LLVM toolchain versions.
* `gwin path` - Shows the executable path for `gwin` and the associated LLVM `clang` binary.

---

## Troubleshooting

If the `gwin` command is not recognized after installation, follow these recovery steps.

### Short-Form Checklist
1. **Linux/macOS:** Ensure the `bin` path is added to your `~/.bashrc` or `~/.zshrc`.
2. **Environment:** Restart your terminal (fully close and re-open all IDE/terminal applications).
3. **Reinstall:** Freshly download the toolchain from the GitHub repository.
4. **Integrity:** Ensure no local source files or configurations were manually altered.

### Long-Form Details
* **Terminal State:** Environmental variables (`PATH`) often do not update in active terminal sessions. Fully close your IDE (like VS Code) and reopen it to force a environment refresh.
* **Manual PATH Configuration (Linux):** If the installer failed to update your shell profile, you may need to manually append the Gawin binary directory to your target shell startup file (`~/.bashrc`, `~/.zshrc`, or `~/.profile`) and run `source ~/.bashrc`.
* **Code Modification:** If you have modified the underlying installer scripts or folder structures prior to installation, the binary links may break. Revert to the official distribution package.

---

## What to do after downloading?

After installing **Gawin**, you can dive into writing and running code instantly! Create a file named `main.gw`, copy-paste any of the examples below into it, and run it using the orchestrator:

```bash
gwin run main.gw
```

1. "Hello, World!" program
```gawin
func main() {
    println("Hello, World!")
}
```

2. Interactive program
```gawin
func main() {
    input := preadln("Input a number: ")
    println("Let me guess... you inputted $(input)!")
}
```

3. Basic math program
```gawin
func add(a: i64, b: i64) -> i64 {
    return a + b
}

func multiply(a: i64, b: i64) -> i64 {
    return a * b
}

func main() {
    result_1 := add(3, -4)
    println("Result 1 is: $(result_1)")
    result_2 := multiply(result_1, 5)
    println("Result 2 is: $(result_2)")
}
```