#pragma once

#include <string>
#include <vector>
#include <unordered_map>

namespace ppp_v {

struct Config {
    std::string project_name;
    std::string version;
    std::vector<std::string> dependencies;
    std::vector<std::string> flags;
    bool debug = false;
    bool verbose = false;
    std::vector<std::string> disable;
    std::vector<std::string> enable;
    std::unordered_map<std::string, std::string> args;
};

const std::string assign_op     = "=>";
const std::string block_prefix  = "my $";
const std::string block_assign  = "=";
const std::string comment_char  = "#";
const std::string array_open    = "[";
const std::string array_close   = "]";

Config parse_config(const std::string& content, bool& success);
void apply_known_keys(Config& cfg, const std::string& key, const std::string& raw_value);
std::vector<std::string> parse_array(const std::string& value);

} // namespace ppp_v