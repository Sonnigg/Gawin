#include "glexer.hpp"
#include <iostream>
#include <cctype>

namespace glexer {

std::string to_string(TokenType kind) {
    switch(kind) {
        case TokenType::plus: return "plus"; case TokenType::dash: return "dash"; case TokenType::star: return "star"; case TokenType::slash: return "slash";
        case TokenType::lparen: return "lparen"; case TokenType::rparen: return "rparen"; case TokenType::lbrack: return "lbrack"; case TokenType::rbrack: return "rbrack";
        case TokenType::lbrace: return "lbrace"; case TokenType::rbrace: return "rbrace"; case TokenType::comma: return "comma"; case TokenType::dot: return "dot";
        case TokenType::colon: return "colon"; case TokenType::double_colon: return "double_colon"; case TokenType::question_mark: return "question_mark"; case TokenType::exclamation_mark: return "exclamation_mark";
        case TokenType::percent: return "percent"; case TokenType::wave: return "wave"; case TokenType::ampersand: return "ampersand"; case TokenType::pipe: return "pipe";
        case TokenType::caret: return "caret"; case TokenType::assign: return "assign"; case TokenType::reassign: return "reassign"; case TokenType::plus_assign: return "plus_assign";
        case TokenType::minus_assign: return "minus_assign"; case TokenType::star_assign: return "star_assign"; case TokenType::slash_assign: return "slash_assign"; case TokenType::percent_assign: return "percent_assign";
        case TokenType::caret_assign: return "caret_assign"; case TokenType::pipe_assign: return "pipe_assign"; case TokenType::ampersand_assign: return "ampersand_assign"; case TokenType::wave_assign: return "wave_assign";
        case TokenType::return_arrow: return "return_arrow"; case TokenType::error_exclamation_mark: return "error_exclamation_mark"; case TokenType::ident: return "ident"; case TokenType::numeric_lit: return "numeric_lit";
        case TokenType::string_lit: return "string_lit"; case TokenType::raw_string_lit: return "raw_string_lit"; case TokenType::line_comment: return "line_comment"; case TokenType::block_comment_start: return "block_comment_start";
        case TokenType::block_comment_end: return "block_comment_end"; case TokenType::key_func: return "key_func"; case TokenType::key_module: return "key_module"; case TokenType::key_const: return "key_const";
        case TokenType::key_then: return "key_then"; case TokenType::key_match: return "key_match"; case TokenType::key_if: return "key_if"; case TokenType::double_key_else_if: return "double_key_else_if";
        case TokenType::key_else: return "key_else"; case TokenType::key_type: return "key_type"; case TokenType::key_struct: return "key_struct"; case TokenType::key_enum: return "key_enum";
        case TokenType::key_variant: return "key_variant"; case TokenType::key_none: return "key_none"; case TokenType::key_pub: return "key_pub"; case TokenType::key_exposed: return "key_exposed";
        case TokenType::key_as: return "key_as"; case TokenType::key_unsafe: return "key_unsafe"; case TokenType::key_atomic: return "key_atomic"; case TokenType::key_type_weak_ref: return "key_type_weak_ref";
        case TokenType::key_type_ref: return "key_type_ref"; case TokenType::key_ptr: return "key_ptr"; case TokenType::key_derefptr: return "key_derefptr"; case TokenType::key_addr: return "key_addr";
        case TokenType::type_void: return "type_void"; case TokenType::type_str: return "type_str"; case TokenType::type_rstr: return "type_rstr"; case TokenType::type_bool: return "type_bool";
        case TokenType::type_bool_short: return "type_bool_short"; case TokenType::type_bool_int: return "type_bool_int"; case TokenType::type_half_byte: return "type_half_byte"; case TokenType::type_short: return "type_short";
        case TokenType::type_int: return "type_int"; case TokenType::type_long: return "type_long"; case TokenType::type_byte: return "type_byte"; case TokenType::type_unsigned_short: return "type_unsigned_short";
        case TokenType::type_unsigned_int: return "type_unsigned_int"; case TokenType::type_unsigned_long: return "type_unsigned_long"; case TokenType::type_float: return "type_float"; case TokenType::type_double: return "type_double";
        case TokenType::type_long_double: return "type_long_double"; case TokenType::no_ref_type: return "no_ref_type"; case TokenType::unknown_at_point: return "unknown_at_point";
    }
    return "unknown";
}

const std::unordered_map<std::string, TokenType> ops_single = {
    {"+", TokenType::plus}, {"-", TokenType::dash}, {"*", TokenType::star}, {"/", TokenType::slash}, {"%", TokenType::percent},
    {"(", TokenType::lparen}, {")", TokenType::rparen}, {"[", TokenType::lbrack}, {"]", TokenType::rbrack}, {"{", TokenType::lbrace}, {"}", TokenType::rbrace},
    {".", TokenType::dot}, {",", TokenType::comma}, {":", TokenType::colon}, {"?", TokenType::question_mark}, {"!", TokenType::exclamation_mark},
    {"=", TokenType::reassign}, {"&", TokenType::ampersand}, {"|", TokenType::pipe}, {"^", TokenType::caret}, {"~", TokenType::wave}
};

const std::unordered_map<std::string, TokenType> ops_double = {
    {":=", TokenType::assign}, {"->", TokenType::return_arrow}, {"::", TokenType::double_colon}, {"+=", TokenType::plus_assign},
    {"-=", TokenType::minus_assign}, {"*=", TokenType::star_assign}, {"/=", TokenType::slash_assign}, {"%=", TokenType::percent_assign},
    {"^=", TokenType::caret_assign}, {"|=", TokenType::pipe_assign}, {"&=", TokenType::ampersand_assign}, {"~=", TokenType::wave_assign},
    {"!!", TokenType::error_exclamation_mark}
};

const std::unordered_map<std::string, TokenType> ops_comment = {
    {"//", TokenType::line_comment}, {"/*", TokenType::block_comment_start}, {"*/", TokenType::block_comment_end}
};

const std::unordered_map<std::string, TokenType> keywords = {
    {"func", TokenType::key_func}, {"module", TokenType::key_module}, {"const", TokenType::key_const}, {"then", TokenType::key_then},
    {"match", TokenType::key_match}, {"if", TokenType::key_if}, {"else", TokenType::key_else}, {"type", TokenType::key_type},
    {"struct", TokenType::key_struct}, {"enum", TokenType::key_enum}, {"variant", TokenType::key_variant}, {"none", TokenType::key_none},
    {"pub", TokenType::key_pub}, {"exposed", TokenType::key_exposed}, {"as", TokenType::key_as}, {"unsafe", TokenType::key_unsafe},
    {"ptr", TokenType::key_ptr}, {"derefptr", TokenType::key_derefptr}, {"addr", TokenType::key_addr}, {"atomic", TokenType::key_atomic}
};

const std::unordered_map<std::string, TokenType> types = {
    {"void", TokenType::type_void}, {"str", TokenType::type_str}, {"rstr", TokenType::type_rstr}, {"bool", TokenType::type_bool},
    {"bool8", TokenType::type_bool}, {"bool16", TokenType::type_bool_short}, {"bool32", TokenType::type_bool_int}, {"b8", TokenType::type_bool},
    {"b16", TokenType::type_bool_short}, {"b32", TokenType::type_bool_int}, {"i8", TokenType::type_half_byte}, {"i16", TokenType::type_short},
    {"i32", TokenType::type_int}, {"i64", TokenType::type_long}, {"u8", TokenType::type_byte}, {"u16", TokenType::type_unsigned_short},
    {"u32", TokenType::type_unsigned_int}, {"u64", TokenType::type_unsigned_long}, {"f32", TokenType::type_float}, {"f64", TokenType::type_double}, {"f128", TokenType::type_long_double}
};

char Source::peek() const {
    if (pos < data.length()) return data[pos];
    return '\0';
}

char Source::peek_ahead() const {
    if (pos + 1 < data.length()) return data[pos + 1];
    return '\0';
}

void Source::advance() {
    if (pos >= data.length()) return;
    char c = data[pos];
    if (c == '\n') {
        ln++;
        col = 1;
    } else {
        col++;
    }
    pos++;
}

bool is_alpha(char c) {
    return ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c == '_'));
}

LexerReturnType Source::lex() {
    std::vector<Token> tokens;
    bool has_failed = false;

    if (ln == 0) ln = 1;
    if (col == 0) col = 1;
    if (pos != 0) pos = 0;

    while (pos < data.length()) {
        char c = peek();
        std::string combined = "";
        combined += c;
        if (peek_ahead() != '\0') combined += peek_ahead();

        if ((is_alpha(c) || c == '#') && (combined != "r\"" && combined != "r'")) {
            std::string ident = "";
            ident += c;
            uint64_t start_ln = ln;
            uint64_t start_col = col;
            advance();
            while (std::isalnum(static_cast<unsigned char>(peek())) || peek() == '_') {
                ident += peek();
                advance();
            }

            if (keywords.find(ident) != keywords.end()) {
                if (!tokens.empty() && tokens.back().kind == TokenType::key_else && keywords.at(ident) == TokenType::key_if) {
                    tokens.back() = Token {
                        TokenType::double_key_else_if, "else if", tokens.back().ln, tokens.back().col,
                        ReferenceHandle{false, false, TokenType::no_ref_type},
                        VisibilityHandle{true, false, false, false}
                    };
                } else {
                    tokens.push_back(Token {
                        keywords.at(ident), ident, start_ln, start_col,
                        ReferenceHandle{false, false, TokenType::no_ref_type},
                        VisibilityHandle{true, false, false, false}
                    });
                }
            }
            else if (types.find(ident) != types.end()) {
                if (tokens.size() > 1 && tokens[tokens.size() - 1].kind == TokenType::ampersand && tokens[tokens.size() - 2].kind == TokenType::ampersand) {
                    tokens[tokens.size() - 1] = Token {
                        TokenType::key_type_weak_ref, "&&" + ident, tokens[tokens.size() - 2].ln, tokens[tokens.size() - 2].col,
                        ReferenceHandle{false, true, TokenType::ident},
                        VisibilityHandle{true, false, false, false}
                    };
                }
                else if (!tokens.empty() && tokens.back().kind == TokenType::ampersand) {
                    tokens.back() = Token {
                        TokenType::key_type_ref, "&" + ident, tokens.back().ln, tokens.back().col,
                        ReferenceHandle{true, false, TokenType::ident},
                        VisibilityHandle{true, false, false, false}
                    };
                }
                else {
                    tokens.push_back(Token {
                        types.at(ident), ident, start_ln, start_col,
                        ReferenceHandle{false, false, TokenType::no_ref_type},
                        VisibilityHandle{true, false, false, false}
                    });
                }
            }
            else {
                if (tokens.size() > 1 && tokens[tokens.size() - 1].kind == TokenType::ampersand && tokens[tokens.size() - 2].kind == TokenType::ampersand) {
                    tokens[tokens.size() - 1] = Token {
                        TokenType::key_type_weak_ref, "&&" + ident, tokens[tokens.size() - 2].ln, tokens[tokens.size() - 2].col,
                        ReferenceHandle{false, true, TokenType::unknown_at_point},
                        VisibilityHandle{false, (!tokens.empty() && tokens.back().kind == TokenType::key_pub && ident[0] != '#'), ident[0] != '#', ident[0] == '#'}
                    };
                }
                else if (!tokens.empty() && tokens.back().kind == TokenType::ampersand) {
                    tokens.back() = Token {
                        TokenType::key_type_ref, "&" + ident, tokens.back().ln, tokens.back().col,
                        ReferenceHandle{true, false, TokenType::unknown_at_point},
                        VisibilityHandle{false, (!tokens.empty() && tokens.back().kind == TokenType::key_pub && ident[0] != '#'), ident[0] != '#', ident[0] == '#'}
                    };
                }
                else {
                    tokens.push_back(Token {
                        TokenType::ident, ident, start_ln, start_col,
                        ReferenceHandle{false, false, TokenType::no_ref_type},
                        VisibilityHandle{false, (!tokens.empty() && tokens.back().kind == TokenType::key_pub && ident[0] != '#'), ident[0] != '#', ident[0] == '#'}
                    });
                }
            }
            continue;
        }

        if (std::isdigit(static_cast<unsigned char>(c))) {
            std::string num = "";
            num += c;
            uint64_t start_ln = ln;
            uint64_t start_col = col;
            int dot_count = 0;
            advance();
            while (std::isdigit(static_cast<unsigned char>(peek())) || peek() == '.') {
                if (peek() == '.') {
                    if (dot_count >= 1) {
                        std::cout << "You can't be serious... trying to add multiple dots into a number?\n";
                        has_failed = true;
                        break;
                    }
                    dot_count++;
                }
                num += peek();
                advance();
            }
            tokens.push_back(Token {
                TokenType::numeric_lit, num, start_ln, start_col,
                ReferenceHandle{false, false, TokenType::no_ref_type},
                VisibilityHandle{true, false, false, false}
            });
            continue;
        }

        if (c == '"' || c == '\'') {
            std::string str_lit = "";
            uint64_t start_ln = ln;
            uint64_t start_col = col;
            advance();
            while (pos < data.length() && peek() != c) {
                str_lit += peek();
                advance();
            }
            if (pos < data.length()) {
                advance();
            } else {
                std::cerr << "Unterminated string literal\n";
                has_failed = true;
            }
            tokens.push_back(Token {
                TokenType::string_lit, str_lit, start_ln, start_col,
                ReferenceHandle{false, false, TokenType::no_ref_type},
                VisibilityHandle{true, false, false, false}
            });
            continue;
        }

        if (combined == "r\"" || combined == "r'") {
            advance();
            continue;
        }

        if (ops_comment.find(combined) != ops_comment.end()) {
            TokenType comm_type = ops_comment.at(combined);
            if (comm_type == TokenType::line_comment) {
                advance(); advance();
                while (pos < data.length() && peek() != '\n') advance();
            }
            else if (comm_type == TokenType::block_comment_start) {
                int depth = 1;
                advance(); advance();
                while (pos < data.length() && depth > 0) {
                    if (peek() == '/' && peek_ahead() == '*') {
                        depth++; advance(); advance();
                    }
                    else if (peek() == '*' && peek_ahead() == '/') {
                        depth--; advance(); advance();
                    }
                    else {
                        advance();
                    }
                }
            } else {
                advance(); advance();
                std::cout << "Buddy... why use '*/' outside of a block-comment..?\n";
                has_failed = true;
            }
            continue;
        }

        if (ops_double.find(combined) != ops_double.end()) {
            tokens.push_back(Token {
                ops_double.at(combined), combined, ln, col,
                ReferenceHandle{false, false, TokenType::no_ref_type},
                VisibilityHandle{true, false, false, false}
            });
            advance(); advance();
            continue;
        }

        std::string c_str(1, c);
        if (ops_single.find(c_str) != ops_single.end()) {
            tokens.push_back(Token {
                ops_single.at(c_str), c_str, ln, col,
                ReferenceHandle{false, false, TokenType::no_ref_type},
                VisibilityHandle{true, false, false, false}
            });
            advance();
            continue;
        }

        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            advance();
            continue;
        }

        advance();
        has_failed = true;
        std::cout << "The character '" << c_str << "' is not supported.\n";
    }

    return LexerReturnType { tokens, has_failed };
}

} // namespace glexer