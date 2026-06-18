module main

import glexer
import gsge
import gvc
import gparser
import gsem
import garc
import ggen

import os
import regex

const too_many_files_provided = -2
const no_file_provided = -1
const invalid_file_provided = 1
const lexer_failure = 100
const style_failure = 200
const success = 0

fn get_version() string {
	content := os.read_file('../../glang_meta/VERSION.gwin') or {
		return 'unknown'
	}

	mut re := regex.regex_opt(r'version\s*:=\s*"([^"]+)"') or {
		return 'unknown'
	}

	mut matches := re.find_all_str(content)
	if matches.len > 0 {
		return matches[0].all_after('"').all_before_last('"')
	}

	return 'unknown'
}

const version_message = 'Gawin Version ${get_version()}'

const help_message = '
Usage: ${os.args[0]} <file.gw> [files.gw] [flags]

VERSION:
    ${version_message}

FLAGS:
    -h, --help    Show this help message
'

struct CompilerOptions {
mut:
	style_guide_enabled bool
	emit_ir             bool

	warnings_as_errors  bool
	no_warnings			bool

	optimization_level  int
}

fn helper_for_matching_flags_with_f(flag string, mut opts CompilerOptions) bool {
	match flag {
		'no-style', 'no-s', 'ns' {
			opts.style_guide_enabled = false
		}
		'emit-ir', 'emi', 'ei' {
			opts.emit_ir = true
		}
		else {
			eprintln('Invalid flag \'${flag}\'')
			return false
		}
	}

	return true
}

fn helper_for_matching_flags_with_double_slash(flag string, mut opts CompilerOptions) bool {
	return true
}

fn helper_for_matching_flags_with_w(flag string, mut opts CompilerOptions) bool {
	match flag {
		'error' {
			opts.warnings_as_errors = true
		}
		'silent', 's', 'ignore' {
			opts.no_warnings = true
		}
		else {
			eprintln('Invalid flag \'${flag}\'')
			return false
		}
	}

	return true
}

fn main() {

	mut opts := CompilerOptions{
		style_guide_enabled: true
	}

	if os.args.len < 2 {
		eprintln('Usage: ggc <file.gw> [files.gw] [flags]')
		eprintln('\tExpected at least one file, got 0 files instead.')
		eprintln('\tArguments received: $os.args')
		exit(no_file_provided)
	}
	mut file_paths := []string{}
	mut flag_marked := false
	mut idx := 0
	for a in os.args {
		if a == '-h' || a == '--help' {
			println(help_message)
			exit(0)
		}
		if a == '-v' || a == '--version' {
			println(version_message)
			exit(0)
		}
	}

	for a in os.args {
		if flag_marked {
			flag_marked = false // because flag_marked can now be safely disabled due to it being the flag argument we want
			idx++
			continue
		}

		if a.ends_with(".gw") || a.ends_with(".g") { file_paths << a }
		if a.len >= 2 && a[0] == `-`{
			match a[1] {
				`f` {
					if a.len <= 2 {
						helper_for_matching_flags_with_f(os.args[idx+1], mut opts)
						flag_marked = true
					} else {
						helper_for_matching_flags_with_f(a[2..], mut opts)
					}
				}

				`W`, `w` {
					if a.len <= 2 {
						helper_for_matching_flags_with_w(os.args[idx+1], mut opts)
						flag_marked = true
					} else {
						helper_for_matching_flags_with_w(a[2..], mut opts)
					}
				}

				`-` {
					helper_for_matching_flags_with_double_slash(a[2..], mut opts)
				}

				else {
					eprintln('Invalid flag \'${a[1]}\'')
				}
			}
		}
		idx++
	}

	if file_paths == [] {
		eprintln('Usage: ggc <file.gw> [files.gw] [flags]')
		exit(no_file_provided)
	}

	for file_path in file_paths {
		input := os.read_file(file_path) or {
			eprintln('Failed to read file: ${file_path}')
			exit(invalid_file_provided)
		}

		mut src := glexer.Source {
			data: input // some file operations here for the content later
			pos: 0 	// always set to 0
			ln: 1 	// always set to 1
			col: 1 	// always set to 1
		}

		mut lex_result := src.lex()

		if lex_result.failed {
			eprintln('Lexing failed due to weird code.')
			exit(lexer_failure)
		}

		style_not_ok := if opts.style_guide_enabled { gsge.enforce_style(lex_result) } else { false }
		if style_not_ok {
			eprintln('Style guide violation.')
			exit(style_failure)
		}

		vis_corrected := gvc.check_visibility(mut lex_result.data)

		mut idx2 := 0
		for tok in vis_corrected {
			println('Token("$tok.lit") {
	kind\t: $tok.kind,
	lit\t: $tok.lit,
	ln\t: $tok.ln,
	col\t: $tok.col,
	extra_ref\t: ReferenceHandle {
		reference\t: $tok.extra_ref.reference,
		weak_reference\t: $tok.extra_ref.weak_reference,
		ref_type\t: $tok.extra_ref.ref_type
	},
	extra_vis\t: VisibilityHandle {
		builtin\t: $tok.extra_vis.builtin,
		public\t: $tok.extra_vis.public,
		exposed\t: $tok.extra_vis.exposed,
		internal: $tok.extra_vis.internal
	}
}${if idx2 < vis_corrected.len - 1 {','} else {''}}')
			idx2++
		}

		// GVC works
		

		//ast := gparser.parse(vis_corrected)

		/*
		sem_ast := gsem.analyze(ast)

		arc_ast := garc.inject_arc(sem_ast)

		llvm_ir := ggen.generate(arc_ast)

		// Write to file or something
		println(llvm_ir)
		*/
	}

	exit(success)
}
