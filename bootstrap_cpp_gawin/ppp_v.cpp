#include "ppp_v.hpp"
#include <algorithm>
#include <cctype>

namespace ppp_v {

// Local string utils matching V semantics
std::vector<std::string> split_into_lines(const std::string& s) {
    std::vector<std::string> lines;
    std::string line;
    for (char c : s) {
        if (c == '\n') { lines.push_back(line); line.clear(); }
        else if (c != '\r') { line += c; }
    }
    if (!line.empty() || (!s.empty() && s.back() == '\n')) lines.push_back(line);
    return lines;
}

std::string trim_space(const std::string& s) {
    size_t first = s.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return "";
    size_t last = s.find_last_not_of(" \t\r\n");
    return s.substr(first, (last - first + 1));
}

std::string trim(const std::string& s, const std::string& chars) {
    size_t first = s.find_first_not_of(chars);
    if (first == std::string::npos) return "";
    size_t last = s.find_last_not_of(chars);
    return s.substr(first, (last - first + 1));
}

bool starts_with(const std::string& s, const std::string& prefix) {
    return s.rfind(prefix, 0) == 0;
}

bool ends_with(const std::string& s, const std::string& suffix) {
    if (s.length() < suffix.length()) return false;
    return s.compare(s.length() - suffix.length(), suffix.length(), suffix) == 0;
}

bool contains(const std::string& s, const std::string& sub) {
    return s.find(sub) != std::string::npos;
}

std::string all_before(const std::string& s, const std::string& sub) {
    size_t pos = s.find(sub);
    if (pos == std::string::npos) return s;
    return s.substr(0, pos);
}

std::string all_after(const std::string& s, const std::string& sub) {
    size_t pos = s.find(sub);
    if (pos == std::string::npos) return "";
    return s.substr(pos + sub.length());
}

std::string replace_str(std::string s, const std::string& from, const std::string& to) {
    size_t start_pos = 0;
    while((start_pos = s.find(from, start_pos)) != std::string::npos) {
        s.replace(start_pos, from.length(), to);
        start_pos += to.length();
    }
    return s;
}

std::string to_lower(std::string s) {
    for (char &c : s) c = std::tolower(static_cast<unsigned char>(c));
    return s;
}

Config parse_config(const std::string& content, bool& success) {
    Config cfg;
    success = true;
    bool in_block = false;

    for (const auto& raw_line : split_into_lines(content)) {
        std::string line = trim_space(raw_line);
        if (line.empty() || starts_with(line, comment_char)) continue;

        if (contains(line, comment_char)) {
            line = trim_space(all_before(line, comment_char));
        }

        if (!in_block) {
            if (starts_with(line, block_prefix) && contains(line, block_assign)) {
                cfg.project_name = trim_space(replace_str(all_before(line, block_assign), block_prefix, ""));
                in_block = true;
            }
            continue;
        }

        if (starts_with(line, "}")) break;
        if (!contains(line, assign_op)) continue;

        std::string key = to_lower(trim(trim_space(all_before(line, assign_op)), "\"'"));
        std::string value = trim_space(all_after(line, assign_op));

        if (ends_with(value, ",")) {
            value = trim_space(value.substr(0, value.length() - 1));
        }

        cfg.args[key] = trim(value, "\"'");
        apply_known_keys(cfg, key, value);
    }

    if (cfg.project_name.empty()) {
        success = false;
    }
    return cfg;
}

void apply_known_keys(Config& cfg, const std::string& key, const std::string& raw_value) {
    std::string value = trim_space(trim(raw_value, "\"'"));

    if (key == "version") {
        cfg.version = value;
    } else if (key == "dependencies") {
        cfg.dependencies = parse_array(value);
    } else if (key == "flags") {
        cfg.flags = parse_array(value);
    } else if (key == "enable") {
        cfg.enable = parse_array(value);
    } else if (key == "disable") {
        cfg.disable = parse_array(value);
    } else if (key == "debug" || key == "verbose") {
        std::string low = to_lower(value);
        bool enabled = (low == "1" || low == "true" || low == "yes" || low == "on");
        if (key == "debug") cfg.debug = enabled;
        else cfg.verbose = enabled;
    }
}

std::vector<std::string> parse_array(const std::string& value) {
    std::string s = trim_space(value);
    if (!starts_with(s, array_open) || !ends_with(s, array_close)) return {};

    s = trim_space(s.substr(1, s.length() - 2));
    if (s.empty()) return {};

    std::vector<std::string> result;
    size_t start = 0;
    size_t end = s.find(',');
    while (end != std::string::npos) {
        result.push_back(trim(trim_space(s.substr(start, end - start)), "\"'"));
        start = end + 1;
        end = s.find(',', start);
    }
    result.push_back(trim(trim_space(s.substr(start)), "\"'"));
    return result;
}

} // namespace ppp_v