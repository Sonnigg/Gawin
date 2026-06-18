module ggen

import gparser
import v_llvmc
/*
pub fn generate(ast gparser.AST) string {
	mut ir := '; Module\n'
	
	for func in ast.modules[0].functions {
		ir += 'define i32 @${func.name}() {\n'
		for stmt in func.body {
			if stmt.typ == .expr {
				if stmt.expr.typ == .call {
					call := stmt.expr.call
					if call.func.typ == .ident && call.func.ident == 'println' {
						ir += '  call void @println_str(i8* getelementptr inbounds ([4 x i8], [4 x i8]* @str, i32 0, i32 0))\n'
					}
				}
			}
		}
		ir += '  ret i32 0\n'
		ir += '}\n'
	}
	
	return ir
}
*/