module v_llvmc

// ================= TYPES =================

pub enum GTypes {
	boolean
	str
	void
	integer_8
	integer_16
	integer_32
	integer_64
	unsigned_8
	unsigned_16
	unsigned_32
	unsigned_64
	float_32
	float_64
	float_128
}

pub enum LLVMBaseType {
	void
	i1
	i8
	i16
	i32
	i64
	float
	double
	fp128
	struct
	union
	variadic
}

pub enum LLVMIntCond {
	eq ne sgt sge slt sle
}

pub struct LLVMType {
pub:
	base      LLVMBaseType
	ptr       int // pointer depth (0 = value, 1 = *, 2 = **, etc.)
	array_len int
	name      string
	fields    []LLVMType
}

pub fn (t LLVMType) str() string {
	mut type_str := ''

	if t.array_len > 0 {
		element := LLVMType{base: t.base}
		type_str = '[${t.array_len} x ${element.str()}]'
	} else if t.base == .struct || t.base == .union {
		if t.name.len > 0 {
			type_str = '%${t.name}'
		} else {
			fields := t.fields.map(it.str()).join(', ')
			type_str = '{ ${fields} }'
		}
	} else {
		type_str = match t.base {
			.void { 'void' }
			.i1 { 'i1' }
			.i8 { 'i8' }
			.i16 { 'i16' }
			.i32 { 'i32' }
			.i64 { 'i64' }
			.float { 'float' }
			.double { 'double' }
			.fp128 { 'fp128' }
			.variadic { '...' }
			else { 'opaque' }
		}
	}

	if t.ptr > 0 {
		type_str += '*' .repeat(t.ptr)
	}

	return type_str
}

pub fn (c LLVMIntCond) str() string {
	return match c {
		.eq { 'eq' }
		.ne { 'ne' }
		.sgt { 'sgt' }
		.sge { 'sge' }
		.slt { 'slt' }
		.sle { 'sle' }
	}
}

pub fn array_type(elem LLVMType, len int) LLVMType {
	return LLVMType{base: elem.base, ptr: elem.ptr, array_len: len, name: elem.name, fields: elem.fields}
}

pub fn ptr_of(base LLVMBaseType) LLVMType {
	return LLVMType{base: base, ptr: 1}
}

pub fn ptr_of_type(base LLVMType) LLVMType {
	return LLVMType{base: base.base, ptr: base.ptr + 1, array_len: base.array_len, name: base.name, fields: base.fields}
}

pub fn var() LLVMType {
	return LLVMType{base: .variadic}
}

pub fn named_struct(name string, fields []LLVMType) LLVMType {
	return LLVMType{base: .struct, name: name, fields: fields}
}

pub fn named_union(name string, fields []LLVMType) LLVMType {
	return LLVMType{base: .union, name: name, fields: fields}
}

pub fn escape_string_constant(value string) string {
	mut escaped := ''
	for ch in value.bytes() {
		match ch {
			`\\` { escaped += '\\5C' }
			`"` { escaped += '\\22' }
			`\n` { escaped += '\\0A' }
			`\r` { escaped += '\\0D' }
			`\t` { escaped += '\\09' }
			0 { escaped += '\\00' }
			else {
				if ch < 32 || ch > 126 {
					escaped += '\\' + ch.hex().to_upper()
				} else {
					escaped += ch.ascii_str()
				}
			}
		}
	}
	return escaped
}

pub struct LLVMMatchCase {
	pub:
		compare LLVMValue
		builder fn (mut LLVMFunction) LLVMValue = unsafe { nil }
}

// ================= EXTERN =================

pub struct LLVMExternFunction {
pub:
	name string
	ret  LLVMType
	args []LLVMType
}

pub fn (e LLVMExternFunction) str() string {
	args := e.args.map(it.str()).join(', ')
	return 'declare ${e.ret.str()} @${e.name}(${args})'
}

// ================= PHI =================

pub struct LLVMPhiIncoming {
	val   LLVMValue
	label string
}

// ================= VALUE =================

pub struct LLVMValue {
pub:
	name string
	typ  LLVMType
	is_const bool
}

pub fn (v LLVMValue) operand() string {
	if v.is_const {
		return v.name
	}
	return '%${v.name}'
}

pub fn (v LLVMValue) str() string {
	return '${v.typ.str()} ${v.operand()}'
}

// ================= LOOP VAR =================

pub struct LLVMLoopVar {
pub:
	name string
	typ  LLVMType
	init LLVMValue
}

pub struct LoopContext {
pub:
	cond_label string
	body_label string
	end_label string
	entry_label string
	names []string
	phi_vars map[string]LLVMValue
}

// ================= BASIC BLOCK =================

pub struct LLVMBasicBlock {
pub:
	name string
mut:
	instructions []string
	terminated   bool
}

pub fn (b LLVMBasicBlock) str() string {
	mut out := '${b.name}:\n'
	for inst in b.instructions {
		out += '  ${inst}\n'
	}
	return out
}

// ================= FUNCTION =================

pub struct LLVMFunction {
pub:
	name        string
	return_type LLVMType
	args        []LLVMValue
mut:
	blocks      []LLVMBasicBlock
	reg_counter int
	symbol_table map[string]LLVMValue
	loop_stack []LoopContext
}

// ---- SSA ----
pub fn (mut f LLVMFunction) new_reg(typ LLVMType) LLVMValue {
	name := 'reg_${f.reg_counter}'
	f.reg_counter++
	return LLVMValue{name, typ, false}
}

// ---- blocks ----
pub fn (mut f LLVMFunction) new_block(name string) {
	f.blocks << LLVMBasicBlock{name: name}
}

pub fn (mut f LLVMFunction) current_block() !&LLVMBasicBlock {
	if f.blocks.len == 0 {
		return error('no active block')
	}
	return &f.blocks[f.blocks.len - 1]
}

pub fn (mut f LLVMFunction) init_symbols() {
	for arg in f.args {
		f.symbol_table[arg.name] = arg
	}
}

// ---- symbols ----
pub fn (mut f LLVMFunction) declare_var(name string, typ LLVMType, init LLVMValue) {
	f.symbol_table[name] = init
}

pub fn (f LLVMFunction) get_var(name string) LLVMValue {
	return f.symbol_table[name] or { panic('undefined variable ${name}') }
}

pub fn (mut f LLVMFunction) assign_var(name string, val LLVMValue) {
	f.symbol_table[name] = val
}

// ================= INSTRUCTIONS =================

// ---- comparisons ----
pub fn (mut f LLVMFunction) icmp(cond LLVMIntCond, lhs LLVMValue, rhs LLVMValue) !LLVMValue {
	if lhs.typ != rhs.typ {
		return error('icmp type mismatch')
	}

	mut b := f.current_block()!
	res := f.new_reg(LLVMType{base: .i1})

	b.instructions << '%${res.name} = icmp ${cond.str()} ${lhs.typ.str()} ${lhs.operand()}, ${rhs.operand()}'
	return res
}

// ---- constants ----
pub fn const_int(val int, typ LLVMType) LLVMValue {
	return LLVMValue{
		name: val.str()
		typ: typ
		is_const: true
	}
}

// to be implemented differently
/*
 * Works, yes, but very badly.
 */
pub fn const_str(val string, typ LLVMType) LLVMValue {
	return LLVMValue{
		name: val
		typ: typ
		is_const: true
	}
}

// ---- arithmetic ----
pub fn (mut f LLVMFunction) add(lhs LLVMValue, rhs LLVMValue) !LLVMValue {
	if lhs.typ != rhs.typ {
		return error('add type mismatch')
	}
	mut b := f.current_block()!
	res := f.new_reg(lhs.typ)
	b.instructions << '%${res.name} = add ${lhs.typ.str()} ${lhs.operand()}, ${rhs.operand()}'
	return res
}

// ---- memory ----
pub fn (mut f LLVMFunction) alloca(typ LLVMType) LLVMValue {
	mut b := f.current_block() or { panic(err) }
	ptr_type := LLVMType{base: typ.base, ptr: typ.ptr + 1}
	res := f.new_reg(ptr_type)
	b.instructions << '%${res.name} = alloca ${typ.str()}'
	return res
}

pub fn (mut f LLVMFunction) store(val LLVMValue, ptr LLVMValue) ! {
	if ptr.typ.ptr == 0 {
		return error('store destination must be pointer')
	}
	if val.typ.base != ptr.typ.base {
		return error('store type mismatch')
	}

	mut b := f.current_block()!
	b.instructions << 'store ${val.typ.str()} ${val.operand()}, ${ptr.typ.str()} %${ptr.name}'
}

pub fn (mut f LLVMFunction) load(ptr LLVMValue) !LLVMValue {
	if ptr.typ.ptr == 0 {
		return error('load requires pointer')
	}

	val_type := LLVMType{base: ptr.typ.base, ptr: ptr.typ.ptr - 1}
	mut b := f.current_block()!
	res := f.new_reg(val_type)
	b.instructions << '%${res.name} = load ${val_type.str()}, ${ptr.typ.str()} %${ptr.name}'
	return res
}

// ---- calls ----
pub fn (mut f LLVMFunction) call(name string, ret LLVMType, args []LLVMValue) !LLVMValue {
	mut b := f.current_block()!
	arg_str := args.map('${it.typ.str()} ${it.operand()}').join(', ')

	if ret.base == .void && ret.ptr == 0 {
		b.instructions << 'call void @${name}(${arg_str})'
		return LLVMValue{'', ret, false}
	}

	res := f.new_reg(ret)
	b.instructions << '%${res.name} = call ${ret.str()} @${name}(${arg_str})'
	return res
}

// ---- getelementptr ----
pub fn (mut f LLVMFunction) getelementptr(ptr LLVMValue, indices []LLVMValue) !LLVMValue {
	if ptr.typ.ptr == 0 {
		return error('getelementptr requires pointer to aggregate')
	}

	mut result_typ := LLVMType{base: ptr.typ.base, ptr: ptr.typ.ptr, array_len: ptr.typ.array_len, name: ptr.typ.name, fields: ptr.typ.fields}
	if ptr.typ.array_len > 0 && indices.len >= 2 {
		result_typ = LLVMType{base: ptr.typ.base, ptr: ptr.typ.ptr, array_len: 0}
	} else if (ptr.typ.base == .struct || ptr.typ.base == .union) && ptr.typ.fields.len > 0 && indices.len >= 2 {
		if indices[1].is_const && indices[1].typ.base == .i32 {
			idx := indices[1].name.int()
			if idx >= 0 && idx < ptr.typ.fields.len {
				result_typ = LLVMType{base: ptr.typ.fields[idx].base, ptr: ptr.typ.ptr, array_len: ptr.typ.fields[idx].array_len, name: ptr.typ.fields[idx].name, fields: ptr.typ.fields[idx].fields}
			}
		}
	}

	mut base_ptr_typ := LLVMType{base: ptr.typ.base, ptr: ptr.typ.ptr - 1, array_len: ptr.typ.array_len, name: ptr.typ.name, fields: ptr.typ.fields}
	res := f.new_reg(result_typ)
	idx_str := indices.map('${it.typ.str()} ${it.operand()}').join(', ')

	mut b := f.current_block()!
	b.instructions << '%${res.name} = getelementptr ${base_ptr_typ.str()}, ${ptr.typ.str()} ${ptr.operand()}, ${idx_str}'
	return res
}

// ---- control flow ----
pub fn (mut f LLVMFunction) br(label string) ! {
	mut b := f.current_block()!
	if b.terminated {
		return error('block already terminated')
	}
	b.instructions << 'br label %${label}'
	b.terminated = true
}

pub fn (mut f LLVMFunction) cond_br(cond LLVMValue, t string, f_label string) ! {
	if cond.typ.base != .i1 {
		return error('condition must be i1')
	}
	mut b := f.current_block()!
	b.instructions << 'br i1 %${cond.name}, label %${t}, label %${f_label}'
	b.terminated = true
}

// ---- while builder ----
pub fn (mut f LLVMFunction) build_while_with_vars(
	vars []LLVMLoopVar,
	cond fn (mut LLVMFunction, []LLVMValue) !LLVMValue,
	body fn (mut LLVMFunction, []LLVMValue) ![]LLVMValue,
) ![]LLVMValue {

	base_id := f.reg_counter

	cond_label := 'while_cond_${base_id}'
	body_label := 'while_body_${base_id}'
	end_label  := 'while_end_${base_id}'

	entry_label := f.current_block()!.name

	// jump from current block to condition
	f.br(cond_label)!

	// ================= COND BLOCK =================
	f.new_block(cond_label)

	mut phi_vars := []LLVMValue{}
	mut phi_indices := []int{}

	for v in vars {
		phi := f.new_reg(v.typ)

		idx := f.current_block()!.instructions.len

		f.current_block()!.instructions << 
			'%${phi.name} = phi ${v.typ.str()} [ ${v.init.operand()}, %${entry_label} ]'

		phi_vars << phi
		phi_indices << idx
	}

	// condition
	c := cond(mut f, phi_vars)!
	f.cond_br(c, body_label, end_label)!

	// ================= BODY BLOCK =================
	f.new_block(body_label)

	new_vals := body(mut f, phi_vars)!

	if new_vals.len != phi_vars.len {
		return error('loop body must return same number of vars')
	}

	// jump back
	f.br(cond_label)!

	// ================= PATCH PHI =================
	mut cond_block := &f.blocks[f.blocks.len - 2]

	for i in 0 .. phi_vars.len {
		incoming := '[ ${new_vals[i].name}, %${body_label} ]'
		idx := phi_indices[i]

		cond_block.instructions[idx] += ', ' + incoming
	}

	// ================= END BLOCK =================
	f.new_block(end_label)

	return phi_vars
}

// ---- while with symbols ----
pub fn (mut f LLVMFunction) start_while(cond_fn fn(mut LLVMFunction) LLVMValue) ! {
	base_id := f.reg_counter

	cond_label := 'while_cond_${base_id}'
	body_label := 'while_body_${base_id}'
	end_label := 'while_end_${base_id}'

	entry_label := f.current_block()!.name

	f.br(cond_label)!

	f.new_block(cond_label)

	mut names := []string{}
	mut phi_vars := map[string]LLVMValue{}

	for name, init_val in f.symbol_table {
		names << name
		phi := f.new_reg(init_val.typ)
		f.current_block()!.instructions << '%${phi.name} = phi ${init_val.typ.str()} [ ${init_val.operand()}, %${entry_label} ]'
		phi_vars[name] = phi
	}

	// update symbol_table
	for name, phi in phi_vars {
		f.symbol_table[name] = phi
	}

	// cond
	c := cond_fn(mut f)
	f.cond_br(c, body_label, end_label)!

	f.new_block(body_label)

	f.loop_stack << LoopContext{
		cond_label: cond_label
		body_label: body_label
		end_label: end_label
		entry_label: entry_label
		names: names
		phi_vars: phi_vars
	}
}

pub fn (mut f LLVMFunction) end_while() ! {
	if f.loop_stack.len == 0 {
		return error('no active loop')
	}
	ctx := f.loop_stack.pop()
	// jump back
	f.br(ctx.cond_label)!

	// patch phi
	mut cond_block := &f.blocks[f.blocks.len - 2]
	for i, name in ctx.names {
		current_val := f.symbol_table[name]
		incoming := ', [ ${current_val.name}, %${ctx.body_label} ]'
		cond_block.instructions[i] += incoming
	}
	f.new_block(ctx.end_label)
}

pub fn (mut f LLVMFunction) break_loop() ! {
	if f.loop_stack.len == 0 {
		return error('no active loop')
	}
	ctx := f.loop_stack[f.loop_stack.len - 1]
	f.br(ctx.end_label)!
}

pub fn (mut f LLVMFunction) continue_loop() ! {
	if f.loop_stack.len == 0 {
		return error('no active loop')
	}
	ctx := f.loop_stack[f.loop_stack.len - 1]
	f.br(ctx.cond_label)!
}

// ---- phi ----
pub fn (mut f LLVMFunction) phi(typ LLVMType, incomings []LLVMPhiIncoming) LLVMValue {
	mut b := f.current_block() or { panic(err) }

	res := f.new_reg(typ)

	parts := incomings.map('[ ${it.val.operand()}, %${it.label} ]').join(', ')
	b.instructions << '%${res.name} = phi ${typ.str()} ${parts}'

	return res
}

// ---- if builder ----
pub fn (mut f LLVMFunction) build_if(
	cond LLVMValue,
	then_builder fn (mut LLVMFunction) LLVMValue,
	else_builder fn (mut LLVMFunction) LLVMValue,
) !LLVMValue {

	then_label := 'then_${f.reg_counter}'
	else_label := 'else_${f.reg_counter}'
	end_label  := 'endif_${f.reg_counter}'

	f.cond_br(cond, then_label, else_label)!

	// THEN
	f.new_block(then_label)
	then_val := then_builder(mut f)
	f.br(end_label)!

	// ELSE
	f.new_block(else_label)
	else_val := else_builder(mut f)
	f.br(end_label)!

	// END
	f.new_block(end_label)

	return f.phi(then_val.typ, [
		LLVMPhiIncoming{then_val, then_label},
		LLVMPhiIncoming{else_val, else_label},
	])
}

pub fn (mut f LLVMFunction) build_match(value LLVMValue, cases []LLVMMatchCase, default_builder fn (mut LLVMFunction) LLVMValue) !LLVMValue {
	if cases.len == 0 {
		return error('match requires at least one case')
	}

	id := f.reg_counter
	end_label := 'match_end_${id}'
	default_label := 'match_default_${id}'
	mut next_label := 'match_cond_${id}_0'

	f.br(next_label)!

	mut incomings := []LLVMPhiIncoming{}

	for i, c in cases {
		cond_label := 'match_cond_${id}_${i}'
		case_label := 'match_case_${id}_${i}'
		
		f.new_block(cond_label)
		cmp := f.icmp(.eq, value, c.compare)!
		branch_label := if i == cases.len - 1 { default_label } else { 'match_cond_${id}_${i + 1}' }
		f.cond_br(cmp, case_label, branch_label)!

		f.new_block(case_label)
		case_val := c.builder(mut f)
		f.br(end_label)!
		incomings << LLVMPhiIncoming{case_val, case_label}
	}

	f.new_block(default_label)
	default_val := default_builder(mut f)
	f.br(end_label)!
	incomings << LLVMPhiIncoming{default_val, default_label}

	f.new_block(end_label)
	return f.phi(default_val.typ, incomings)
}

// ---- while builder ----
pub fn (mut f LLVMFunction) build_while(
	cond_builder fn (mut LLVMFunction) LLVMValue,
	body fn (mut LLVMFunction),
) ! {

	cond_label := 'while_cond_${f.reg_counter}'
	body_label := 'while_body_${f.reg_counter}'
	end_label  := 'while_end_${f.reg_counter}'

	f.br(cond_label)!

	// condition block
	f.new_block(cond_label)
	cond := cond_builder(mut f)
	f.cond_br(cond, body_label, end_label)!

	// body block
	f.new_block(body_label)
	body(mut f)
	f.br(cond_label)!

	// end
	f.new_block(end_label)
}

// ---- return ----
pub fn (mut f LLVMFunction) ret(val LLVMValue) ! {
	if val.typ != f.return_type {
		return error('return type mismatch')
	}
	mut b := f.current_block()!
	b.instructions << 'ret ${val.typ.str()} ${val.operand()}'
	b.terminated = true
}

pub fn (mut f LLVMFunction) ret_void() ! {
	if f.return_type.base != .void {
		return error('function must return void')
	}
	mut b := f.current_block()!
	b.instructions << 'ret void'
	b.terminated = true
}

// ================= OUTPUT =================

pub fn (f LLVMFunction) header() string {
	args := f.args.map('${it.typ.str()} %${it.name}').join(', ')
	return 'define ${f.return_type.str()} @${f.name}(${args})'
}

pub fn (f LLVMFunction) str() string {
	mut out := f.header() + ' {\n'
	for b in f.blocks {
		out += b.str()
	}
	out += '}\n'
	return out
}

// ================= GLOBAL =================

pub struct LLVMGlobal {
pub:
	name     string
	typ      LLVMType
	value    LLVMValue
	is_const bool
}

pub fn (g LLVMGlobal) str() string {
	const_or_global := if g.is_const { 'constant' } else { 'global' }
	return '@${g.name} = ${const_or_global} ${g.typ.str()} ${g.value.operand()}'
}

// ================= MODULE =================

pub struct LLVMNamedType {
pub:
	name     string
	is_union bool
	fields   []LLVMType
}

pub struct LLVMModule {
mut:
	functions   []LLVMFunction
	externs     []LLVMExternFunction
	globals     []LLVMGlobal
	named_types []LLVMNamedType
}

pub fn (mut m LLVMModule) add_function(f LLVMFunction) {
	m.functions << f
}

pub fn (mut m LLVMModule) add_extern(e LLVMExternFunction) {
	m.externs << e
}

pub fn (mut m LLVMModule) add_global(g LLVMGlobal) {
	m.globals << g
}

pub fn (mut m LLVMModule) add_global_var(name string, typ LLVMType, init LLVMValue, is_const bool) LLVMValue {
	m.globals << LLVMGlobal{name: name, typ: typ, value: init, is_const: is_const}
	return LLVMValue{name: '@${name}', typ: LLVMType{base: typ.base, ptr: typ.ptr + 1, array_len: typ.array_len, name: typ.name, fields: typ.fields}, is_const: true}
}

pub fn (mut m LLVMModule) add_named_type(name string, fields []LLVMType, is_union bool) LLVMType {
	m.named_types << LLVMNamedType{name: name, is_union: is_union, fields: fields}
	return LLVMType{base: if is_union { .union } else { .struct }, name: name, fields: fields}
}

pub fn (mut m LLVMModule) add_struct(name string, fields []LLVMType) LLVMType {
	return m.add_named_type(name, fields, false)
}

pub fn (mut m LLVMModule) add_union(name string, fields []LLVMType) LLVMType {
	return m.add_named_type(name, fields, true)
}

pub fn (mut m LLVMModule) add_string_constant(name string, text string) LLVMValue {
	contents := text + '\x00'
	escaped := escape_string_constant(contents)
	array_type := LLVMType{base: .i8, array_len: contents.len}
	m.globals << LLVMGlobal{name: name, typ: array_type, value: LLVMValue{name: 'c"${escaped}"', typ: array_type, is_const: true}, is_const: true}
	return LLVMValue{name: '@${name}', typ: LLVMType{base: .i8, ptr: 1, array_len: array_type.array_len}, is_const: true}
}

pub fn (m LLVMModule) str() string {
	mut out := ''

	for t in m.named_types {
		kind := if t.is_union { ' ; union' } else { '' }
		fields := t.fields.map(it.str()).join(', ')
		out += '%${t.name} = type { ${fields} }${kind}\n'
	}

	for g in m.globals {
		out += g.str() + '\n'
	}

	for e in m.externs {
		out += e.str() + '\n'
	}

	for f in m.functions {
		out += '\n' + f.str()
	}

	return out
}

// ================= TYPE CONVERSION =================

pub fn convert_type(g GTypes) !LLVMType {
	base := match g {
		.boolean { LLVMBaseType.i1 }
		.void { LLVMBaseType.void }
		.integer_8, .unsigned_8 { .i8 }
		.integer_16, .unsigned_16 { .i16 }
		.integer_32, .unsigned_32 { .i32 }
		.integer_64, .unsigned_64 { .i64 }
		.float_32 { .float }
		.float_64 { .double }
		.float_128 { .fp128 }
		else { return error('unsupported type') }
	}
	return LLVMType{base: base, ptr: 0}
}
