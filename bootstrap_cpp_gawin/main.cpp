#include "glexer.hpp"
#include "ppp_v.hpp"
#include "gsge.hpp"
#include "gvc.hpp"
#include <iostream>
#include <fstream>
#include <sstream>

const int too_many_files_provided = -2;
const int no_file_provided = -1;
const int invalid_file_provided = 1;
const int lexer_failure = 100;
const int style_failure = 200;
const int success = 0;

// Cross-platform utility definitions
std::string get_dir(const std::string& path) {
    size_t found = path.find_last_of("/\\");
    if (found == std::string::npos) return ".";
    return path.substr(0, found);
}

std::string join_path(const std::string& dir, const std::string& file) {
    if (dir.empty()) return file;
    char last = dir.back();
    if (last == '/' || last == '\\') return dir + file;
    return dir + "/" + file;
}

bool ends_with(const std::string& s, const std::string& suffix) {
    if (s.length() < suffix.length()) return false;
    return s.compare(s.length() - suffix.length(), suffix.length(), suffix) == 0;
}

std::string read_file(const std::string& path, bool& success) {
    std::ifstream file(path);
    if (!file.is_open()) { success = false; return ""; }
    std::stringstream buffer;
    buffer << file.rdbuf();
    success = true;
    return buffer.str();
}

std::string get_version(const std::string& argv0) {
    std::string bin_dir = get_dir(argv0);
    std::string parent_dir = get_dir(bin_dir);
    std::string config_path = join_path(parent_dir, "config.pl");

    bool ok;
    std::string content = read_file(config_path, ok);
    if (!ok) return "unknown";

    ppp_v::Config cfg = ppp_v::parse_config(content, ok);
    if (!ok) return "unknown";

    return cfg.version.empty() ? "unknown" : cfg.version;
}

struct CompilerOptions {
    bool style_guide_enabled = true;
    bool emit_ir = false;
    bool warnings_as_errors = false;
    bool no_warnings = false;
    int optimization_level = 0;
};

bool helper_for_matching_flags_with_f(const std::string& flag, CompilerOptions& opts) {
    if (flag == "no-style" || flag == "no-s" || flag == "ns") {
        opts.style_guide_enabled = false;
    } else if (flag == "emit-ir" || flag == "emi" || flag == "ei") {
        opts.emit_ir = true;
    } else {
        std::cerr << "Invalid flag '" << flag << "'\n";
        return false;
    }
    return true;
}

bool helper_for_matching_flags_with_double_slash(const std::string& flag, CompilerOptions& opts) {
    return true;
}

bool helper_for_matching_flags_with_w(const std::string& flag, CompilerOptions& opts) {
    if (flag == "error" || flag == "e") {
        opts.warnings_as_errors = true;
    } else if (flag == "silent" || flag == "s" || flag == "ignore") {
        opts.no_warnings = true;
    } else {
        std::cerr << "Invalid flag '" << flag << "'\n";
        return false;
    }
    return true;
}

int main(int argc, char* argv[]) {
    CompilerOptions opts;
    std::string version_message = "Gawin Version " + get_version(argv[0]);
    std::string help_message = 
        "\nUsage: " + std::string(argv[0]) + " <file.gw> [files.gw] [flags]\n\n"
        "VERSION:\n    " + version_message + "\n\n"
        "FLAGS:\n"
        "    -h, --help    Show this help message\n"
        "    -v, --ver     Shows the current installed version\n"
        "-f...:\n"
        "    no-style, no-s, ns    Disable the Gawin Style Guide\n"
        "    emit-ir, emi, ei      Don't delete the temporary LLVM IR file\n\n"
        "-W...:\n"
        "    error, e              Treats warnings as errors\n"
        "    silent, s, ignore     Ignores warnings altogether\n";

    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <file.gw> [files.gw] [flags]\n"
                  << "\tExpected at least one file, got 0 files instead.\n"
                  << "\tArguments received: ";
        for (int i = 0; i < argc; ++i) std::cerr << argv[i] << " ";
        std::cerr << "\n";
        return no_file_provided;
    }

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            std::cout << help_message << "\n";
            return 0;
        }
        if (arg == "-v" || arg == "--ver") {
            std::cout << version_message << "\n";
            return 0;
        }
    }

    std::vector<std::string> file_paths;
    bool flag_marked = false;

    for (int i = 1; i < argc; ++i) {
        if (flag_marked) {
            flag_marked = false;
            continue;
        }

        std::string a = argv[i];
        if (ends_with(a, ".gw") || ends_with(a, ".g")) {
            file_paths.push_back(a);
        }

        if (a.length() >= 2 && a[0] == '-') {
            switch (a[1]) {
                case 'f':
                    if (a.length() <= 2) {
                        if (i + 1 < argc) {
                            helper_for_matching_flags_with_f(argv[i + 1], opts);
                            flag_marked = true;
                        }
                    } else {
                        helper_for_matching_flags_with_f(a.substr(2), opts);
                    }
                    break;
                case 'W':
                    if (a.length() <= 2) {
                        if (i + 1 < argc) {
                            helper_for_matching_flags_with_w(argv[i + 1], opts);
                            flag_marked = true;
                        }
                    } else {
                        helper_for_matching_flags_with_w(a.substr(2), opts);
                    }
                    break;
                case '-':
                    helper_for_matching_flags_with_double_slash(a.substr(2), opts);
                    break;
                default:
                    std::cerr << "Invalid flag '" << a[1] << "'\n";
                    break;
            }
        }
    }

    if (file_paths.empty()) {
        std::cerr << "Usage: ggc <file.gw> [files.gw] [flags]\n";
        return no_file_provided;
    }

    for (const auto& file_path : file_paths) {
        bool read_ok;
        std::string input = read_file(file_path, read_ok);
        if (!read_ok) {
            std::cerr << "Failed to read file: " << file_path << "\n";
            return invalid_file_provided;
        }

        glexer::Source src { input, 0, 1, 1 };
        glexer::LexerReturnType lex_result = src.lex();

        if (lex_result.failed) {
            std::cerr << "Lexing failed due to weird code.\n";
            return lexer_failure;
        }

        bool style_not_ok = opts.style_guide_enabled ? gsge::enforce_style(lex_result) : false;
        if (style_not_ok) {
            std::cerr << "Style guide violation.\n";
            return style_failure;
        }

        auto vis_corrected = gvc::check_visibility(lex_result.data);

        size_t idx2 = 0;
        std::cout << std::boolalpha;
        for (const auto& tok : vis_corrected) {
            std::cout << "Token(\"" << tok.lit << "\") {\n"
                      << "\tkind\t: " << glexer::to_string(tok.kind) << ",\n"
                      << "\tlit\t: " << tok.lit << ",\n"
                      << "\tln\t: " << tok.ln << ",\n"
                      << "\tcol\t: " << tok.col << ",\n"
                      << "\textra_ref\t: ReferenceHandle {\n"
                      << "\t\treference\t: " << tok.extra_ref.reference << ",\n"
                      << "\t\tweak_reference\t: " << tok.extra_ref.weak_reference << ",\n"
                      << "\t\tref_type\t: " << glexer::to_string(tok.extra_ref.ref_type) << "\n"
                      << "\t},\n"
                      << "\textra_vis\t: VisibilityHandle {\n"
                      << "\t\tbuiltin\t: " << tok.extra_vis.builtin << ",\n"
                      << "\t\tpublic\t: " << tok.extra_vis.public_vis << ",\n"
                      << "\t\texposed\t: " << tok.extra_vis.exposed << ",\n"
                      << "\t\tinternal: " << tok.extra_vis.internal << "\n"
                      << "\t}\n"
                      << "}" << (idx2 < vis_corrected.size() - 1 ? ",\n" : "\n");
            idx2++;
        }
    }

    return success;
}