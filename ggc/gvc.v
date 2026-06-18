module gvc

import glexer

pub fn check_visibility(mut corrected []glexer.Token) []glexer.Token {

	mut public_table := []string{}
	mut exposed_table := []string{}
	mut internal_table := []string{}

	for idx in 0 .. corrected.len {
		kind := corrected[idx].kind
		lit := corrected[idx].lit

		next1_exists := idx + 1 < corrected.len
		next2_exists := idx + 2 < corrected.len

		// =========================
		// Handle `pub`
		// =========================
		if kind == .key_pub && next1_exists {
			next_kind := corrected[idx + 1].kind

			match next_kind {
				.key_const,
				.key_enum,
				.key_struct,
				.key_func,
				.key_variant {
					if next2_exists && corrected[idx + 2].kind == .ident {
						name := corrected[idx + 2].lit

						if !(name in exposed_table || name in internal_table) {
							public_table << name
						}
					}
				}

				.ident {
					name := corrected[idx + 1].lit

					if !(name in exposed_table || name in internal_table) {
						public_table << name
					}
				}

				else {}
			}

			continue
		}

		// =========================
		// Handle identifiers
		// =========================
		if kind == .ident {
			if lit in public_table {
				corrected[idx].extra_vis = glexer.VisibilityHandle{
					builtin: false
					public: true
					exposed: false
					internal: false
				}
			} else if lit in exposed_table || !(lit in public_table || lit in internal_table) {
				corrected[idx].extra_vis = glexer.VisibilityHandle{
					builtin: false
					public: false
					exposed: true
					internal: false
				}
			} else if lit in internal_table {
				corrected[idx].extra_vis = glexer.VisibilityHandle{
					builtin: false
					public: false
					exposed: false
					internal: true
				}
			} else {
				eprintln(
					'Identifier `${lit}` could not be mapped to a visibility level.'
				)
			}
		}
	}

	return corrected
}