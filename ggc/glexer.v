module glexer

pub struct Source {
pub mut:
	data 	string
	pos		u64
	ln		u64
	col		u64
}
fn (s Source) peek() u8 {
	if s.pos < s.data.len {
		return s.data[s.pos]
	}
	return `\000`
}

fn (s Source) peek_ahead() u8 {
	if s.pos + 1 < s.data.len {
		return s.data[s.pos+1]
	}
	return `\000`
}

fn (mut s Source) advance() {
  if s.pos >= s.data.len { return }
    
  // Get the current character before incrementing
  c := s.data[s.pos]
    
  if c == `\n` {
    s.ln++
    s.col = 1
  } else {
    s.col++
  }
  s.pos++
}

pub enum TokenType {
	plus
	dash
	star
	slash
	lparen
	rparen
	lbrack
	rbrack
	lbrace
	rbrace

	comma
	dot
	colon
	double_colon
	question_mark
	exclamation_mark
	percent
	wave

	ampersand
	pipe
	caret

	assign
	reassign

	plus_assign
	minus_assign
	star_assign
	slash_assign
	percent_assign
	caret_assign
	pipe_assign
	ampersand_assign
	wave_assign

	return_arrow
	error_exclamation_mark

	ident
	numeric_lit
	string_lit
	raw_string_lit

	line_comment
	block_comment_start
	block_comment_end

	key_func
	key_module
	key_const
	key_then
	key_match
	key_if
	double_key_else_if
	key_else
	key_type
	key_struct
	key_enum
	key_variant
	key_none
	key_pub
	key_exposed
	key_as
	key_unsafe
	key_atomic

	key_type_weak_ref 	// && instead of &

	key_type_ref		// & instead of &&
	key_ptr
	key_derefptr
	key_addr

	type_void
	type_str
	type_rstr
	type_bool
	type_half_byte			// i8
	type_short				// i16
	type_int				// i32
	type_long				// i64
	type_byte 				// u8
	type_unsigned_short 	// u16
	type_unsigned_int 		// u32
	type_unsigned_long 		// u64
	type_float				// f32
	type_double				// f64
	type_long_double		// f128

	no_ref_type
	unknown_at_point
}

pub struct ReferenceHandle {
pub mut:
	reference 		bool
	weak_reference 	bool
	ref_type		TokenType
}

pub struct VisibilityHandle {
pub mut:
	builtin		bool // for builtin primitives
	public		bool // to every import
	exposed		bool // to the module
	internal	bool // to the file
}

pub struct Token {
pub mut:
	kind 			TokenType
	lit 			string
	ln				u64
	col				u64
	extra_ref	ReferenceHandle
	extra_vis	VisibilityHandle
}

const ops_single = { // frick you V for not making it SCREAMING_SNAKE_CASE
	'+': TokenType.plus
	'-': TokenType.dash
	'*': TokenType.star
	'/': TokenType.slash
	'%': TokenType.percent
	'(': TokenType.lparen
	')': TokenType.rparen
	'[': TokenType.lbrack
	']': TokenType.rbrack
	'{': TokenType.lbrace
	'}': TokenType.rbrace

	'.': TokenType.dot
	',': TokenType.comma
	':': TokenType.colon
	'?': TokenType.question_mark
	'!': TokenType.exclamation_mark

	'=': TokenType.reassign

	'&': TokenType.ampersand
	'|': TokenType.pipe
	'^': TokenType.caret
	'~': TokenType.wave
}

const ops_double = {
	':=': TokenType.assign
	'->': TokenType.return_arrow
	'::': TokenType.double_colon
	'+=': TokenType.plus_assign
	'-=': TokenType.minus_assign
	'*=': TokenType.star_assign
	'/=': TokenType.slash_assign
	'%=': TokenType.percent_assign
	'^=': TokenType.caret_assign
	'|=': TokenType.pipe_assign
	'&=': TokenType.ampersand_assign
	'~=': TokenType.wave_assign
	'!!': TokenType.error_exclamation_mark
}

const ops_comment = {
	'//': TokenType.line_comment
	'/*': TokenType.block_comment_start
	'*/': TokenType.block_comment_end
}

const keywords = {
	'func'		: TokenType.key_func
	'module'	: TokenType.key_module
	'const'		: TokenType.key_const
	'then'		: TokenType.key_then
	'match'		: TokenType.key_match
	'if'		: TokenType.key_if
	'else'		: TokenType.key_else
	'type'		: TokenType.key_type
	'struct'	: TokenType.key_struct
	'enum'		: TokenType.key_enum
	'variant'	: TokenType.key_variant
	'none'		: TokenType.key_none
	'pub'		: TokenType.key_pub
	'exposed'	: TokenType.key_exposed
	'as'		: TokenType.key_as
	'unsafe'	: TokenType.key_unsafe
	'ptr'		: TokenType.key_ptr
	'derefptr'	: TokenType.key_derefptr
	'addr'		: TokenType.key_addr
	'atomic'	: TokenType.key_atomic
	//'weak'		: TokenType.key_type_weak // a key-type is a keyword that can modify a type completely ||||| REMOVED WEAK
}

const types = {
	'void'	: TokenType.type_void
	'str'	: TokenType.type_str // Normal String
	'rstr'	: TokenType.type_rstr // Raw String
	'bool'	: TokenType.type_bool
	'i8'	: TokenType.type_half_byte
	'i16'	: TokenType.type_short
	'i32'	: TokenType.type_int
	'i64'	: TokenType.type_long
	'u8'	: TokenType.type_byte
	'u16'	: TokenType.type_unsigned_short
	'u32'	: TokenType.type_unsigned_int
	'u64'	: TokenType.type_unsigned_long
	'f32'	: TokenType.type_float
	'f64'	: TokenType.type_double
	'f128'	: TokenType.type_long_double
}

pub struct LexerReturnType {
pub mut:
	data []Token
	failed bool
}

fn is_alpha(c u8) bool {
	return ((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c == `_`))
}

pub fn (mut s Source) lex() LexerReturnType {
    mut tokens := []Token{}
	mut has_failed := false
    
    // Initialize start positions if not already set
    if s.ln == 0 { s.ln = 1 }
    if s.col == 0 { s.col = 1 }
	if s.pos != 0 { s.pos = 0 }

    for s.pos < s.data.len {
        c := s.peek()
        combined := c.ascii_str() + s.peek_ahead().ascii_str()

		if (is_alpha(c) || c == `#`) && (combined != 'r"' && combined != 'r\'') {
			mut ident := c.ascii_str()
			start_ln := s.ln
			start_col := s.col
			s.advance()
			for s.peek().is_alnum() || s.peek() == `_` {
				ident += s.peek().ascii_str()
				s.advance()
			}
			if ident in keywords {
				if tokens.len > 0 && tokens[tokens.len - 1].kind == .key_else && keywords[ident] == .key_if {

					tokens[tokens.len - 1] = Token {
						kind		: .double_key_else_if
						lit			: 'else if'
						ln			: tokens[tokens.len - 1].ln
						col			: tokens[tokens.len - 1].col
						extra_ref	: ReferenceHandle {
							reference		: false
							weak_reference	: false
							ref_type		: .no_ref_type
						}
						extra_vis	: VisibilityHandle {
							builtin	: true
							public	: false
							exposed : false
							internal: false
						}
					}
				}
				else {
					tokens << Token {
						kind		: keywords[ident]
						lit			: ident
						ln			: start_ln
						col			: start_col
						extra_ref	: ReferenceHandle {
							reference		: false
							weak_reference	: false
							ref_type		: .no_ref_type
						}
						extra_vis	: VisibilityHandle {
							builtin	: true
							public	: false
							exposed : false
							internal: false
						}
					}
				}
			}
			else if ident in types {
				if tokens.len > 1 && tokens[tokens.len - 1].kind == .ampersand && tokens[tokens.len - 2].kind == .ampersand {
					tokens[tokens.len - 1] = Token {
						kind		: .key_type_weak_ref
						lit			: '&&' + ident
						ln			: tokens[tokens.len - 2].ln
						col			: tokens[tokens.len - 2].col
						extra_ref	: ReferenceHandle {
							reference		: false
							weak_reference	: true
							ref_type		: .ident
						}
						extra_vis	: VisibilityHandle {
							builtin	: true
							public	: false
							exposed : false
							internal: false
						}
					}
				}
				else if tokens.len > 0 && tokens[tokens.len - 1].kind == .ampersand {
					tokens[tokens.len - 1] = Token {
						kind		: .key_type_ref
						lit			: '&' + ident
						ln			: tokens[tokens.len - 1].ln
						col			: tokens[tokens.len - 1].col
						extra_ref	: ReferenceHandle {
							reference		: true
							weak_reference	: false
							ref_type		: .ident
						}
						extra_vis	: VisibilityHandle {
							builtin	: true
							public	: false
							exposed : false
							internal: false
						}
					}
				}
				else {
					tokens << Token {
						kind		: types[ident]
						lit			: ident
						ln			: start_ln
						col			: start_col
						extra_ref	: ReferenceHandle {
							reference		: false
							weak_reference	: false
							ref_type		: .no_ref_type
						}
						extra_vis	: VisibilityHandle {
							builtin	: true
							public	: false
							exposed	: false
							internal: false
						}
					}
				}
			}
			else {
				if tokens.len > 1 && tokens[tokens.len - 1].kind == .ampersand && tokens[tokens.len - 2].kind == .ampersand {
					tokens[tokens.len - 1] = Token {
						kind		: .key_type_weak_ref
						lit			: '&&' + ident
						ln			: tokens[tokens.len - 2].ln
						col			: tokens[tokens.len - 2].col
						extra_ref	: ReferenceHandle {
							reference		: false
							weak_reference	: true
							ref_type		: .unknown_at_point
						}
						extra_vis	: VisibilityHandle {
							builtin	: false
							public	: if tokens.len > 0 && tokens[tokens.len - 1].kind == .key_pub && ident[0] != `#` { true } else { false }
							exposed : if ident[0] != `#` { true } else { false }
							internal: if ident[0] == `#` { true } else { false }
						}
					}
				}
				else if tokens.len > 0 && tokens[tokens.len - 1].kind == .ampersand {
					tokens[tokens.len - 1] = Token {
						kind		: .key_type_ref
						lit			: '&' + ident
						ln			: tokens[tokens.len - 1].ln
						col			: tokens[tokens.len - 1].col
						extra_ref	: ReferenceHandle {
							reference		: true
							weak_reference	: false
							ref_type		: .unknown_at_point
						}
						extra_vis	: VisibilityHandle {
							builtin	: false
							public	: if tokens.len > 0 && tokens[tokens.len - 1].kind == .key_pub && ident[0] != `#` { true } else { false }
							exposed : if ident[0] != `#` { true } else { false }
							internal: if ident[0] == `#` { true } else { false }
						}
					}
				}
				else {
					tokens << Token {
						kind		: .ident
						lit			: ident
						ln			: start_ln
						col			: start_col
						extra_ref	: ReferenceHandle {
							reference		: false
							weak_reference	: false
							ref_type		: .no_ref_type
						}
						extra_vis	: VisibilityHandle {
							builtin	: false
							public	: if tokens.len > 0 && tokens[tokens.len - 1].kind == .key_pub && ident[0] != `#` { true } else { false }
							exposed : if ident[0] != `#` { true } else { false }
							internal: if ident[0] == `#` { true } else { false }
						}
					}
				}
			}
			continue
		}

		if c.is_digit() {
			mut num := c.ascii_str()
			start_ln := s.ln
			start_col := s.col
			mut dot_count := 0

			s.advance()
			for s.peek().is_digit() || s.peek() == `.` {
				if s.peek() == `.` {
					if dot_count >= 1 {
						println('You can\'t be serious... trying to add multiple dots into a number?')
						has_failed = true
						break
					}
					dot_count++
				}
				num += s.peek().ascii_str()
				s.advance()
			}

			tokens << Token {
				kind		: .numeric_lit 
				lit			: num
				ln			: start_ln
				col			: start_col
				extra_ref	: ReferenceHandle {
					reference		: false
					weak_reference	: false
					ref_type		: .no_ref_type
				}
				extra_vis	: VisibilityHandle {
					builtin	: true
					public	: false
					exposed	: false
					internal: false
				}
			}
			continue
		}

		if c == `"` || c == `'` {
			mut str_lit := ''
			start_ln := s.ln
			start_col := s.col
			s.advance() // skip opening "
			for s.pos < s.data.len && s.peek() != c {
				str_lit += s.peek().ascii_str()
				s.advance()
			}
			if s.pos < s.data.len {
				s.advance() // skip closing " or '
			} else {
				eprintln('Unterminated string literal')
				has_failed = true
			}
			tokens << Token {
				kind		: .string_lit
				lit			: str_lit
				ln			: start_ln
				col			: start_col
				extra_ref	: ReferenceHandle {
					reference		: false
					weak_reference	: false
					ref_type		: .no_ref_type
				}
				extra_vis	: VisibilityHandle {
					builtin	: true
					public	: false
					exposed	: false
					internal: false
				}
			}
			continue
		}

		if combined == 'r"' || combined == 'r\'' {
			s.advance() // for r
			continue
		} // handle later

        // Comments
        if combined in ops_comment {
            match ops_comment[combined] {
                .line_comment {
                    // Skip the "//"
                    s.advance()
                    s.advance()
                    for s.pos < s.data.len && s.peek() != `\n` {
                        s.advance()
                    }
                }
                .block_comment_start {
                    mut depth := 1
                    s.advance() // /
                    s.advance() // *
                    
                    for s.pos < s.data.len && depth > 0 {
                        if s.peek() == `/` && s.peek_ahead() == `*` {
                            depth++
                            s.advance()
                            s.advance()
                        }
						else if s.peek() == `*` && s.peek_ahead() == `/` {
                            depth--
                            s.advance()
                            s.advance()
                        }
						else {
                            s.advance()
                        }
                    }
                }
                else { 
                    // Handle stray */ here if desired
                    s.advance()
					s.advance()
					println('Buddy... why use \'*/\' outside of a block-comment..?')
					has_failed = true
                }
            }
            continue
        }

        // Double Ops
        if combined in ops_double {
            tokens << Token {
				kind		: ops_double[combined]
				lit			: combined
				ln			: s.ln
				col			: s.col
				extra_ref	: ReferenceHandle {
					reference		: false
					weak_reference	: false
					ref_type		: .no_ref_type
				}
				extra_vis	: VisibilityHandle {
					builtin	: true
					public	: false
					exposed	: false
					internal: false
				}
			}
            s.advance()
            s.advance()
            continue
        }

        // Single Ops
        if c.ascii_str() in ops_single {
            tokens << Token {
				kind		: ops_single[c.ascii_str()]
				lit			: c.ascii_str()
				ln			: s.ln
				col			: s.col
				extra_ref	: ReferenceHandle {
					reference		: false
					weak_reference	: false
					ref_type		: .no_ref_type
				}
				extra_vis	: VisibilityHandle {
					builtin	: true
					public	: false
					exposed	: false
					internal: false
				}
			}
            s.advance()
            continue
        }

        // Skip Whitespace (including newlines)
        if c == ` ` || c == `\t` || c == `\n` || c == `\r` {
            s.advance()
            continue
        }

        // Default: advance to avoid infinite loop on unknown chars
        s.advance()
		has_failed = true
		println('The character \'' + c.ascii_str() + '\' is not supported.')
    }

    return LexerReturnType {
		data	: tokens
		failed	: has_failed
	}
}