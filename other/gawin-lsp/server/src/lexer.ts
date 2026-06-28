// Lightweight lexer reusing token regexes from g.tmLanguage.json

export const KEYWORDS = [
  "if","else","for","in","match","return","break","continue","as","unsafe","default","goto","spawn","then",
  "func","pub","public","exposed","enum","struct","variant","module","import","type","mut","const","panic","atomic","static",
  "sizeof","typeof"
];

export const TYPES = [
  "str","i8","i16","i32","i64","u8","u16","u32","u64","f32","f64","f128","bool","void","usize","size"
];

export function tokenize(text: string) {
  const lines = text.split(/\r?\n/);
  return lines.map((line, index) => ({ line: index, text: line }));
}
