module gsge

import glexer

// is_pascal_case: Checks for PascalCase (e.g., MyType, HTTPClient)
// Starts with Upper, no underscores, contains only alphanumeric
fn is_pascal_case(s string) bool {
	if s == '' { return false }
	mut runes := []u8{}

	for c in s {
		runes << c
	}
	
	// First char must be uppercase letter
	if !runes[0].is_capital() { return false }

	for r in runes {
		if r == `_` || (!r.is_alnum() && r != `_`) {
			return false
		}
	}
	return true
}

// is_snake_case: Checks for snake_case (e.g., my_var, field_one)
// Starts with lower, lowercase only or underscores/numbers
fn is_snake_case(s string) bool {
	if s == '' { return false }
	mut runes := []u8{}

	for c in s {
		runes << c
	}

	// Must start with lowercase letter
	if !runes[0].is_letter() { return false }

	for r in runes {
		if r.is_capital() || (!r.is_alnum() && r != `_`) {
			return false
		}
	}
	return true
}

// is_screaming_snake_case: Checks for SCREAMING_SNAKE_CASE (e.g., GLOBAL_VAR)
fn is_screaming_snake_case(s string) bool {
	if s == '' { return false }
	mut runes := []u8{}

	for c in s {
		runes << c
	}

	for r in runes {
		// Must not contain lowercase, must be Upper, digit, or underscore
		if (r.is_letter() && !r.is_capital()) || (!r.is_alnum() && r != `_`) {
			return false
		}
	}
	return true
}

// is_camel_case: Checks for camelCase (e.g., myModule)
fn is_camel_case(s string) bool {
	if s == '' { return false }
	mut runes := []u8{}

	for c in s {
		runes << c
	}

	// Must start with lowercase
	if !runes[0].is_letter() { return false }

	for r in runes {
		if r == `_` || !r.is_alnum() {
			return false
		}
	}
	return true
}

pub fn enforce_style(l glexer.LexerReturnType) bool {
	mut has_failed := false
	mut type_table := []string{}
	mut const_table := []string{}
	mut module_table := []string{}
	mut variant_table := []string{}
	mut idx := 0
	for tok in l.data {
		mut next := if idx + 1 < l.data.len { l.data[idx + 1] } else { tok }
		if next.lit[0] == `#` && next.lit.len > 1 {
			next.lit = next.lit[1..]
		}
		match tok.kind {
			.key_struct {
				if !is_pascal_case(next.lit) {
					eprintln('${next.lit} should be PascalCase (${next.ln}:${next.col}).')
					has_failed = true
				}
				type_table << next.lit
			}
			.key_enum {
				if !is_pascal_case(next.lit) {
					eprintln('${next.lit} should be PascalCase (${next.ln}:${next.col}).')
					has_failed = true
				}
				type_table << next.lit
			}
			.key_variant {
				if !is_pascal_case(next.lit) {
					eprintln('${next.lit} should be PascalCase (${next.ln}:${next.col}).')
					has_failed = true
				}
				type_table << next.lit
				mut local_idx := idx + 1
				mut depth := 1
				mut c := l.data[local_idx].kind
				for c != .lbrace && local_idx < l.data.len {
					local_idx++
					c = l.data[local_idx].kind
				}
				local_idx++
				for depth > 0 && local_idx < l.data.len {
					t := l.data[local_idx]
					match t.kind {
						.ident {
							if !(t.lit in type_table) && !(t.lit in const_table) && !(t.lit in module_table) && !(t.lit in variant_table) {
								if !is_pascal_case(t.lit) {
									eprintln('${t.lit} should be PascalCase (${t.ln}:${t.col}).')
									has_failed = true
								} else {
									variant_table << t.lit
								}
							}
							local_idx++
						}
						.lbrace {
							depth++
							local_idx++
						}
						.rbrace {
							depth--
							local_idx++
						}
						else {
							local_idx++
						}
					}
				}
			}
			.key_const {
				if !is_screaming_snake_case(next.lit) {
					eprintln('${next.lit} should be SCREAMING_SNAKE_CASE (${next.ln}:${next.col}).')
					has_failed = true
				}
				const_table << next.lit
			}
			.key_module {
				if !is_camel_case(next.lit) {
					eprintln('${next.lit} should be camelCase (${next.ln}:${next.col}).')
					has_failed = true
				}
				module_table << next.lit
			}
			.key_type {
				if !is_pascal_case(next.lit) {
					eprintln('${next.lit} should be PascalCase (${next.ln}:${next.col}).')
					has_failed = true
				}
				type_table << next.lit
			}
			.ident {
				tok_lit := if tok.lit[0] == `#` && tok.lit.len > 1 {
					tok.lit[1..]
				} else {
					tok.lit
				}
				if !is_snake_case(tok_lit) && !(tok_lit in type_table) && !(tok_lit in const_table) && !(tok_lit in module_table) && !(tok_lit in variant_table) {
					eprintln('${tok.lit} should be snake_case (${tok.ln}:${tok.col}).')
					has_failed = true
				}
			}
			else {}
		}
		idx++
	}
	return has_failed
}