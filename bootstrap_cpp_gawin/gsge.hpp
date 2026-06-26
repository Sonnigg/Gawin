// gsge.h

#include "./glexer.hpp"

namespace gsge {
    bool is_pascal_case(const std::string& s);
    bool is_snake_case(const std::string& s);
    bool is_screaming_snake_case(const std::string& s);
    bool is_camel_case(const std::string& s);
    bool enforce_style(const glexer::LexerReturnType& l);
}
