#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>
#include <unordered_map>

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

// ------------------------------------------------------------
// resolve libfoo -> libfoo.a
// ------------------------------------------------------------
static std::filesystem::path resolve_library(
    const std::string &name,
    const std::vector<std::filesystem::path> &search_dirs
) {
    std::string filename = name + ".o";

    for (const auto &dir : search_dirs) {
        std::filesystem::path candidate = dir / filename;

        if (std::filesystem::exists(candidate)) {
            return candidate;
        }
    }

    return {};
}

int main(int argc, char **argv) {

    if (argc < 2) {
        std::cout << "Usage: glld <input.ll> [output.exe] [-lfoo ...] [-Ldir ...]\n";
        return 1;
    }

    std::filesystem::path input_ll = argv[1];

    if (!std::filesystem::exists(input_ll)) {
        std::cerr << "Input file not found: " << input_ll << std::endl;
        return 1;
    }

    std::filesystem::path output_exe;
    std::vector<std::string> lib_flags;
    std::vector<std::filesystem::path> search_dirs;

    bool output_set = false;

    // ------------------------------------------------------------
    // Parse args
    // ------------------------------------------------------------
    for (int i = 2; i < argc; ++i) {
        std::string arg = argv[i];

        if (arg.rfind("-l", 0) == 0) {
            lib_flags.push_back(arg.substr(2));
        }
        else if (arg.rfind("-L", 0) == 0) {
            search_dirs.push_back(arg.substr(2));
        }
        else if (!output_set) {
            output_exe = arg;
            output_set = true;
        }
        else {
            std::cerr << "Unknown argument: " << arg << std::endl;
            return 1;
        }
    }

    if (output_exe.empty()) {
        output_exe = input_ll.parent_path() /
            (input_ll.stem().string() + ".out");
    }

    // ------------------------------------------------------------
    // runtime discovery
    // ------------------------------------------------------------
    std::filesystem::path exe_path = argv[0];
    std::filesystem::path tool_dir = exe_path.parent_path();

    if (tool_dir.empty()) {
        tool_dir = std::filesystem::current_path();
    }

    std::filesystem::path runtime_dir = find_runtime_dir(tool_dir);

    if (runtime_dir.empty()) {
        std::cerr << "Could not find grt_boot directory\n";
        return 1;
    }

    std::filesystem::path build_dir = runtime_dir / "gstdobj";

    if (!std::filesystem::exists(build_dir)) {
        std::filesystem::create_directories(build_dir);
    }

    // ------------------------------------------------------------
    // default search path = runtime lib dir
    // ------------------------------------------------------------
    std::vector<std::filesystem::path> all_search_dirs = {
        build_dir
    };

    for (auto &d : search_dirs) {
        all_search_dirs.push_back(d);
    }

    // ------------------------------------------------------------
    // linker flags
    // ------------------------------------------------------------
    std::string link_flags =
        "-ffreestanding -nostdlib "
        "-ffunction-sections -fdata-sections "
        "-Wl,/NODEFAULTLIB,/ENTRY:_start,"
        "/SUBSYSTEM:CONSOLE,/OPT:REF";

    // ------------------------------------------------------------
    // mandatory core runtime objects
    // ------------------------------------------------------------
    std::vector<std::filesystem::path> object_files = {
        build_dir / "grt.o",
        build_dir / "utf16.o",
        build_dir / "grtheap.o"
    };

    for (const auto &obj : object_files) {
        if (!std::filesystem::exists(obj)) {
            std::cerr << "Missing mandatory runtime object file: " << obj << std::endl;
            std::cerr << "Run gstdo first to compile the standard library." << std::endl;
            return 1;
        }
    }

    std::vector<std::filesystem::path> libs_to_link;

    // ------------------------------------------------------------
    // resolve -l flags
    // ------------------------------------------------------------
    for (const auto &lib : lib_flags) {

        std::filesystem::path resolved =
            resolve_library(lib, all_search_dirs);

        if (resolved.empty()) {
            std::cerr << "Library not found: -l" << lib << std::endl;
            return 1;
        }

        libs_to_link.push_back(resolved);
    }

    // ------------------------------------------------------------
    // build final command
    // ------------------------------------------------------------
    std::string cmd = "clang " + link_flags + " " + quote(input_ll) + " -w";

    for (const auto &obj : object_files) {
        cmd += " " + quote(obj);
    }
    for (const auto &lib : libs_to_link) {
        cmd += " " + quote(lib);
    }

    cmd += " -lkernel32";
    cmd += " -o " + quote(output_exe);

    int rc = run_command(cmd);

    if (rc != 0) {
        std::cerr << "Linking failed.\n";
        return rc;
    }

    std::cout << "Created executable: " << output_exe << std::endl;
    return 0;
}