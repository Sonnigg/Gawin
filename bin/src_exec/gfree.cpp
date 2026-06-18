#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>

static std::string quote(const std::filesystem::path &path) {
    std::string s = path.string();
    if (s.find(' ') != std::string::npos || s.find('\t') != std::string::npos) {
        return '"' + s + '"';
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

int main(int argc, char **argv) {
    if (argc < 2) {
        std::cout << "Usage: gfree <input.ll> [output";
#ifdef _WIN32
        std::cout << ".exe]";
#else
        std::cout << "]";
#endif
        std::cout << "\n";
        return 1;
    }

    std::filesystem::path input_ll = argv[1];
    if (!std::filesystem::exists(input_ll)) {
        std::cerr << "Input LLVM file not found: " << input_ll << std::endl;
        return 1;
    }

    std::filesystem::path output_exe;
    if (argc >= 3) {
        output_exe = argv[2];
    } else {
#ifdef _WIN32
        output_exe = input_ll.parent_path() / (input_ll.stem().string() + ".exe");
#else
        output_exe = input_ll.parent_path() / input_ll.stem();
#endif
    }

    std::string link_flags = "-ffreestanding -nostdlib -ffunction-sections -fdata-sections";
#ifdef _WIN32
    link_flags += " -Wl,/NODEFAULTLIB,/ENTRY:_start,/SUBSYSTEM:CONSOLE,/OPT:REF";
#else
    link_flags += " -Wl,-e,_start -Wl,--gc-sections -static";
#endif

    std::string link_cmd = "clang " + link_flags + " " + quote(input_ll);
#ifdef _WIN32
    link_cmd += " -lkernel32";
#endif
    link_cmd += " -o " + quote(output_exe);

    int final_rc = run_command(link_cmd);
    if (final_rc != 0) {
        std::cerr << "Linking failed." << std::endl;
        return final_rc;
    }

    std::cout << "Created executable: " << output_exe << std::endl;
    return 0;
}
