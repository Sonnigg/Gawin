#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

static std::string quote(const std::filesystem::path &path) {
    std::string s = path.string();
    if (s.find(' ') != std::string::npos || s.find('\t') != std::string::npos) {
        return "\"" + s + "\"";
    }
    return s;
}

static int run_command(const std::string &command) {
    std::cout << "Running: " << command << std::endl;

    int result = std::system(command.c_str());

    if (result != 0) {
        std::cerr << "Command failed with exit code: " << result << std::endl;
    }

    return result;
}

static std::filesystem::path find_runtime_dir(std::filesystem::path start) {
    start = std::filesystem::absolute(start);

    while (!start.empty()) {
        std::filesystem::path candidate = start / "grt_boot";

        if (std::filesystem::exists(candidate) &&
            std::filesystem::is_directory(candidate)) {
            return candidate;
        }

        std::filesystem::path parent = start.parent_path();
        if (parent == start) break;

        start = parent;
    }

    return {};
}

struct SourceFile {
    const char *source;
    const char *object;
};

int main(int argc, char **argv) {
    std::filesystem::path exe_path = argv[0];
    std::filesystem::path tool_dir = exe_path.parent_path();

    if (tool_dir.empty()) {
        tool_dir = std::filesystem::current_path();
    }

    std::filesystem::path runtime_dir = find_runtime_dir(tool_dir);

    if (runtime_dir.empty()) {
        std::cerr << "Could not find grt_boot in parent directories from: "
                  << tool_dir << std::endl;
        return 1;
    }

    std::filesystem::path build_dir = runtime_dir / "gstdobj";
    std::error_code ec;

    if (!std::filesystem::exists(build_dir) &&
        !std::filesystem::create_directories(build_dir, ec)) {
        std::cerr << "Could not create build directory: " << ec.message() << std::endl;
        return 1;
    }

    std::string compile_flags =
        "-ffreestanding -nostdlib -ffunction-sections -fdata-sections";

    std::string include_flags =
        "-I" + quote(runtime_dir) +
        " -I" + quote(runtime_dir / "grtio") +
        " -I" + quote(runtime_dir / "grtmem") +
        " -I" + quote(runtime_dir / "grtstr") +
        #ifdef _WIN32
        " -I" + quote(runtime_dir / "win32") +
        #endif
        " -I" + quote(runtime_dir / "grtdef");

    SourceFile sources[] = {
        { "grt.c", "grt.o" },
        #ifdef _WIN32
        { "win32/utf16.c", "utf16.o" },
        #endif
        { "grtdef/grtheap.c", "grtheap.o" },
        { "grtio/grtio.c", "grtio.o" },
        { "grtmem/grtmem.c", "grtmem.o" },
        { "grtstr/grtstr.c", "grtstr.o" },
    };

    for (const auto &source : sources) {
        std::filesystem::path src = runtime_dir / source.source;
        std::filesystem::path obj = build_dir / source.object;

        if (!std::filesystem::exists(src)) {
            std::cerr << "Missing source: " << src << std::endl;
            return 1;
        }

        std::string cmd =
            "clang " + compile_flags +
            " -c " + quote(src) +
            " -o " + quote(obj) +
            " " + include_flags;

        if (run_command(cmd) != 0) {
            return 1;
        }

        std::cout << "Compiled: " << obj << std::endl;
    }

    std::cout << "Build complete. Runtime objects in: " << build_dir << std::endl;
    return 0;
}