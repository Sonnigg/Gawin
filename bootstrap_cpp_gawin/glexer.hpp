#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <cstdint>

namespace glexer {

enum class TokenType {
    plus, dash, star, slash, lparen, rparen, lbrack, rbrack, lbrace, rbrace,
    comma, dot, colon, double_colon, question_mark, exclamation_mark, percent, wave,
    ampersand, pipe, caret,
    assign, reassign,
    plus_assign, minus_assign, star_assign, slash_assign, percent_assign, caret_assign, pipe_assign, ampersand_assign, wave_assign,
    return_arrow, error_exclamation_mark,
    ident, numeric_lit, string_lit, raw_string_lit,
    line_comment, block_comment_start, block_comment_end,
    key_func, key_module, key_const, key_then, key_match, key_if, double_key_else_if, key_else, key_type, key_struct, key_enum, key_variant, key_none, key_pub, key_exposed, key_as, key_unsafe, key_atomic,
    key_type_weak_ref, key_type_ref, key_ptr, key_derefptr, key_addr,
    type_void, type_str, type_rstr, type_bool, type_bool_short, type_bool_int, type_half_byte, type_short, type_int, type_long, type_byte, type_unsigned_short, type_unsigned_int, type_unsigned_long, type_float, type_double, type_long_double,
    no_ref_type, unknown_at_point
};

std::string to_string(TokenType kind);

struct ReferenceHandle {
    bool reference = false;
    bool weak_reference = false;
    TokenType ref_type = TokenType::no_ref_type;
};

struct VisibilityHandle {
    bool builtin = false;
    bool public_vis = false; // 'public' is a C++ keyword
    bool exposed = false;
    bool internal = false;
};

struct Token {
    TokenType kind;
    std::string lit;
    uint64_t ln;
    uint64_t col;
    ReferenceHandle extra_ref;
    VisibilityHandle extra_vis;
};

struct LexerReturnType {
    std::vector<Token> data;
    bool failed;
};

struct Source {
    std::string data;
    uint64_t pos = 0;
    uint64_t ln = 1;
    uint64_t col = 1;

    char peek() const;
    char peek_ahead() const;
    void advance();
    LexerReturnType lex();
};

extern const std::unordered_map<std::string, TokenType> ops_single;
extern const std::unordered_map<std::string, TokenType> ops_double;
extern const std::unordered_map<std::string, TokenType> ops_comment;
extern const std::unordered_map<std::string, TokenType> keywords;
extern const std::unordered_map<std::string, TokenType> types;

} // namespace glexer