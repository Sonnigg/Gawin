// gsge.cpp
#include "./gsge.hpp"
#include <iostream>
#include <algorithm>

namespace gsge {

bool is_capital(char c) { return (c >= 'A' && c <= 'Z'); }
bool is_letter(char c)  { return ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')); }
bool is_alnum(char c)   { return (is_letter(c) || (c >= '0' && c <= '9')); }

bool is_pascal_case(const std::string& s) {
    if (s.empty()) return false;
    if (!is_capital(s[0])) return false; // Must start with capital letter 
    for (char r : s) {
        if (r == '_' || (!is_alnum(r) && r != '_')) return false; // No underscores allowed [cite: 268, 269]
    }
    return true;
}

bool is_snake_case(const std::string& s) {
    if (s.empty()) return false;
    if (!is_letter(s[0])) return false; // Must start with letter [cite: 269]
    for (char r : s) {
        if (is_capital(r) || (!is_alnum(r) && r != '_')) return false; // No capital letters [cite: 269, 270]
    }
    return true;
}

bool is_screaming_snake_case(const std::string& s) {
    if (s.empty()) return false;
    for (char r : s) {
        if ((is_letter(r) && !is_capital(r)) || (!is_alnum(r) && r != '_')) return false; // Capital/Digit/Underscore only [cite: 270, 271]
    }
    return true;
}

bool is_camel_case(const std::string& s) {
    if (s.empty()) return false;
    if (!is_letter(s[0])) return false; // Must start with letter [cite: 271]
    for (char r : s) {
        if (r == '_' || !is_alnum(r)) return false; // Alphanumeric, no underscores [cite: 271, 272]
    }
    return true;
}

bool enforce_style(const glexer::LexerReturnType& l) {
    bool has_failed = false;
    std::vector<std::string> type_table;
    std::vector<std::string> const_table;
    std::vector<std::string> module_table;
    std::vector<std::string> variant_table;

    size_t idx = 0;
    for (const auto& tok : l.data) {
        glexer::Token next = (idx + 1 < l.data.size()) ? l.data[idx + 1] : tok; // Copy lookup character [cite: 272]
        if (!next.lit.empty() && next.lit[0] == '#' && next.lit.length() > 1) {
            next.lit = next.lit.substr(1); // Trim raw marker hashes [cite: 272]
        }

        switch (tok.kind) {
            case glexer::TokenType::key_struct:
            case glexer::TokenType::key_enum:
            case glexer::TokenType::key_type: {
                if (!is_pascal_case(next.lit)) {
                    std::cerr << next.lit << " should be PascalCase (" << next.ln << ":" << next.col << ").\n"; // Error output [cite: 272, 273]
                    has_failed = true;
                }
                type_table.push_back(next.lit);
                break;
            }
            case glexer::TokenType::key_variant: {
                if (!is_pascal_case(next.lit)) {
                    std::cerr << next.lit << " should be PascalCase (" << next.ln << ":" << next.col << ").\n";
                    has_failed = true;
                }
                type_table.push_back(next.lit);

                size_t local_idx = idx + 1;
                int depth = 1;
                if (local_idx < l.data.size()) {
                    glexer::TokenType c = l.data[local_idx].kind;
                    while (c != glexer::TokenType::lbrace && local_idx < l.data.size()) {
                        local_idx++;
                        if (local_idx < l.data.size()) c = l.data[local_idx].kind;
                    }
                    local_idx++;
                    while (depth > 0 && local_idx < l.data.size()) {
                        const auto& t = l.data[local_idx];
                        if (t.kind == glexer::TokenType::ident) {
                            bool in_type = std::find(type_table.begin(), type_table.end(), t.lit) != type_table.end();
                            bool in_const = std::find(const_table.begin(), const_table.end(), t.lit) != const_table.end();
                            bool in_mod = std::find(module_table.begin(), module_table.end(), t.lit) != module_table.end();
                            bool in_var = std::find(variant_table.begin(), variant_table.end(), t.lit) != variant_table.end();

                            if (!in_type && !in_const && !in_mod && !in_var) {
                                if (!is_pascal_case(t.lit)) {
                                    std::cerr << t.lit << " should be PascalCase (" << t.ln << ":" << t.col << ").\n";
                                    has_failed = true;
                                } else {
                                    variant_table.push_back(t.lit);
                                }
                            }
                            local_idx++;
                        } else if (t.kind == glexer::TokenType::lbrace) {
                            depth++; local_idx++;
                        } else if (t.kind == glexer::TokenType::rbrace) {
                            depth--; local_idx++;
                        } else {
                            local_idx++;
                        }
                    }
                }
                break;
            }
            case glexer::TokenType::key_const: {
                if (!is_screaming_snake_case(next.lit)) {
                    std::cerr << next.lit << " should be SCREAMING_SNAKE_CASE (" << next.ln << ":" << next.col << ").\n";
                    has_failed = true;
                }
                const_table.push_back(next.lit);
                break;
            }
            case glexer::TokenType::key_module: {
                if (!is_camel_case(next.lit)) {
                    std::cerr << next.lit << " should be camelCase (" << next.ln << ":" << next.col << ").\n";
                    has_failed = true;
                }
                module_table.push_back(next.lit);
                break;
            }
            case glexer::TokenType::ident: {
                std::string tok_lit = (!tok.lit.empty() && tok.lit[0] == '#' && tok.lit.length() > 1) ? tok.lit.substr(1) : tok.lit;

                bool in_type = std::find(type_table.begin(), type_table.end(), tok_lit) != type_table.end();
                bool in_const = std::find(const_table.begin(), const_table.end(), tok_lit) != const_table.end();
                bool in_mod = std::find(module_table.begin(), module_table.end(), tok_lit) != module_table.end();
                bool in_var = std::find(variant_table.begin(), variant_table.end(), tok_lit) != variant_table.end();

                if (!is_snake_case(tok_lit) && !in_type && !in_const && !in_mod && !in_var) {
                    std::cerr << tok.lit << " should be snake_case (" << tok.ln << ":" << tok.col << ").\n";
                    has_failed = true;
                }
                break;
            }
            default: break;
        }
        idx++;
    }
    return has_failed;
}

} // namespace gsge