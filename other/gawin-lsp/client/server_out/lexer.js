"use strict";
// Lightweight lexer reusing token regexes from g.tmLanguage.json
Object.defineProperty(exports, "__esModule", { value: true });
exports.TYPES = exports.KEYWORDS = void 0;
exports.tokenize = tokenize;
exports.KEYWORDS = [
    "if", "else", "for", "in", "match", "return", "break", "continue", "as", "unsafe", "default", "goto", "spawn", "then",
    "func", "pub", "public", "exposed", "enum", "struct", "variant", "module", "import", "type", "mut", "const", "panic", "atomic", "static",
    "sizeof", "typeof"
];
exports.TYPES = [
    "str", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "f128", "bool", "void", "usize", "size"
];
function tokenize(text) {
    const lines = text.split(/\r?\n/);
    return lines.map((line, index) => ({ line: index, text: line }));
}
