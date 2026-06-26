#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <stdexcept>
#include <sstream>
#include <iomanip>
#include <functional>
#include <algorithm>
#include <optional>

namespace llvm_cpp {

// ================= TYPES =================

enum class GTypes {
    boolean, str, void_t,
    integer_8, integer_16, integer_32, integer_64,
    unsigned_8, unsigned_16, unsigned_32, unsigned_64,
    float_32, float_64, float_128
};

enum class LLVMBaseType {
    void_t, i1, i8, i16, i32, i64,
    float_t, double_t, fp128,
    struct_t, union_t, variadic
};

enum class LLVMIntCond {
    eq, ne, sgt, sge, slt, sle
};

struct LLVMType {
    LLVMBaseType base = LLVMBaseType::void_t;
    int ptr_depth = 0; // 0 = value, 1 = ptr, 2 = ptr (opaque in modern LLVM)
    int array_len = 0;
    std::string name = "";
    std::vector<LLVMType> fields = {};

    bool operator==(const LLVMType& other) const {
        return base == other.base && ptr_depth == other.ptr_depth && 
               array_len == other.array_len && name == other.name;
    }
    bool operator!=(const LLVMType& other) const { return !(*this == other); }

    std::string to_string() const {
        // Modern LLVM 15+ uses opaque pointers
        if (ptr_depth > 0) {
            return "ptr";
        }

        if (array_len > 0) {
            LLVMType element = *this;
            element.array_len = 0;
            return "[" + std::to_string(array_len) + " x " + element.to_string() + "]";
        } 
        
        if (base == LLVMBaseType::struct_t || base == LLVMBaseType::union_t) {
            if (!name.empty()) {
                return "%" + name;
            } else {
                std::string res = "{ ";
                for (size_t i = 0; i < fields.size(); ++i) {
                    res += fields[i].to_string();
                    if (i < fields.size() - 1) res += ", ";
                }
                res += " }";
                return res;
            }
        }

        switch (base) {
            case LLVMBaseType::void_t: return "void";
            case LLVMBaseType::i1: return "i1";
            case LLVMBaseType::i8: return "i8";
            case LLVMBaseType::i16: return "i16";
            case LLVMBaseType::i32: return "i32";
            case LLVMBaseType::i64: return "i64";
            case LLVMBaseType::float_t: return "float";
            case LLVMBaseType::double_t: return "double";
            case LLVMBaseType::fp128: return "fp128";
            case LLVMBaseType::variadic: return "...";
            default: return "opaque";
        }
    }
};

inline std::string to_string(LLVMIntCond c) {
    switch (c) {
        case LLVMIntCond::eq: return "eq";
        case LLVMIntCond::ne: return "ne";
        case LLVMIntCond::sgt: return "sgt";
        case LLVMIntCond::sge: return "sge";
        case LLVMIntCond::slt: return "slt";
        case LLVMIntCond::sle: return "sle";
        default: return "";
    }
}

// ================= HELPERS & MANGLING =================

inline LLVMType array_type(const LLVMType& elem, int len) {
    LLVMType t = elem;
    t.array_len = len;
    return t;
}

inline LLVMType ptr_of(LLVMBaseType base) {
    return LLVMType{base, 1};
}

inline LLVMType ptr_of_type(const LLVMType& base) {
    LLVMType t = base;
    t.ptr_depth++;
    return t;
}

inline LLVMType var() {
    return LLVMType{LLVMBaseType::variadic};
}

inline LLVMType named_struct(const std::string& name, const std::vector<LLVMType>& fields) {
    return LLVMType{LLVMBaseType::struct_t, 0, 0, name, fields};
}

inline LLVMType named_union(const std::string& name, const std::vector<LLVMType>& fields) {
    return LLVMType{LLVMBaseType::union_t, 0, 0, name, fields};
}

// Basic Itanium-style C++ Name Mangling helper for functions
inline std::string mangle_function_name(const std::string& base_name, const std::vector<LLVMType>& args) {
    std::stringstream ss;
    ss << "_Z" << base_name.length() << base_name;
    if (args.empty()) {
        ss << "v"; // void
        return ss.str();
    }
    for (const auto& arg : args) {
        if (arg.ptr_depth > 0) ss << "P";
        switch (arg.base) {
            case LLVMBaseType::i1: ss << "b"; break; // bool
            case LLVMBaseType::i8: ss << "c"; break; // char
            case LLVMBaseType::i16: ss << "s"; break; // short
            case LLVMBaseType::i32: ss << "i"; break; // int
            case LLVMBaseType::i64: ss << "x"; break; // long long
            case LLVMBaseType::float_t: ss << "f"; break;
            case LLVMBaseType::double_t: ss << "d"; break;
            case LLVMBaseType::struct_t: ss << arg.name.length() << arg.name; break;
            default: ss << "v"; break;
        }
    }
    return ss.str();
}

inline std::string escape_string_constant(const std::string& value) {
    std::stringstream escaped;
    for (unsigned char ch : value) {
        if (ch == '\\') escaped << "\\5C";
        else if (ch == '"') escaped << "\\22";
        else if (ch == '\n') escaped << "\\0A";
        else if (ch == '\r') escaped << "\\0D";
        else if (ch == '\t') escaped << "\\09";
        else if (ch == '\0') escaped << "\\00";
        else if (ch < 32 || ch > 126) {
            escaped << "\\" << std::hex << std::uppercase << std::setw(2) << std::setfill('0') << (int)ch;
        } else {
            escaped << ch;
        }
    }
    return escaped.str();
}

// ================= VALUE =================

struct LLVMValue {
    std::string name;
    LLVMType typ;
    bool is_const = false;

    std::string operand() const {
        return is_const ? name : "%" + name;
    }

    std::string to_string() const {
        return typ.to_string() + " " + operand();
    }
};

// ================= PHI & LOOP VARS =================

struct LLVMPhiIncoming {
    LLVMValue val;
    std::string label;
};

struct LLVMLoopVar {
    std::string name;
    LLVMType typ;
    LLVMValue init;
};

struct LoopContext {
    std::string cond_label;
    std::string body_label;
    std::string end_label;
    std::string entry_label;
    std::vector<std::string> names;
    std::unordered_map<std::string, LLVMValue> phi_vars;
};

class LLVMFunction;

struct LLVMMatchCase {
    LLVMValue compare;
    std::function<LLVMValue(LLVMFunction&)> builder;
};

// ================= EXTERN =================

struct LLVMExternFunction {
    std::string name;
    LLVMType ret;
    std::vector<LLVMType> args;

    std::string to_string() const {
        std::string arg_str;
        for (size_t i = 0; i < args.size(); ++i) {
            arg_str += args[i].to_string();
            if (i < args.size() - 1) arg_str += ", ";
        }
        return "declare " + ret.to_string() + " @" + name + "(" + arg_str + ")";
    }
};

// ================= BASIC BLOCK =================

struct LLVMBasicBlock {
    std::string name;
    std::vector<std::string> instructions;
    bool terminated = false;

    std::string to_string() const {
        std::string out = name + ":\n";
        for (const auto& inst : instructions) {
            out += "  " + inst + "\n";
        }
        return out;
    }
};

// ================= FUNCTION (IR BUILDER) =================

class LLVMFunction {
public:
    std::string name;
    LLVMType return_type;
    std::vector<LLVMValue> args;

    std::vector<LLVMBasicBlock> blocks;
    int reg_counter = 0;
    std::unordered_map<std::string, LLVMValue> symbol_table;
    std::vector<LoopContext> loop_stack;

    LLVMFunction(std::string name, LLVMType ret_type, std::vector<LLVMValue> arguments) 
        : name(std::move(name)), return_type(std::move(ret_type)), args(std::move(arguments)) {}

    // ---- SSA & Blocks ----
    LLVMValue new_reg(LLVMType typ) {
        std::string reg_name = "reg_" + std::to_string(reg_counter++);
        return LLVMValue{reg_name, typ, false};
    }

    void new_block(const std::string& block_name) {
        blocks.push_back(LLVMBasicBlock{block_name, {}, false});
    }

    LLVMBasicBlock& current_block() {
        if (blocks.empty()) throw std::runtime_error("no active block");
        return blocks.back();
    }

    // ---- Symbols ----
    void init_symbols() {
        for (const auto& arg : args) {
            symbol_table[arg.name] = arg;
        }
    }

    void declare_var(const std::string& var_name, LLVMType typ, LLVMValue init) {
        symbol_table[var_name] = init;
    }

    LLVMValue get_var(const std::string& var_name) {
        auto it = symbol_table.find(var_name);
        if (it == symbol_table.end()) throw std::runtime_error("undefined variable " + var_name);
        return it->second;
    }

    void assign_var(const std::string& var_name, LLVMValue val) {
        symbol_table[var_name] = val;
    }

    // ---- Instructions ----
    LLVMValue icmp(LLVMIntCond cond, LLVMValue lhs, LLVMValue rhs) {
        if (lhs.typ != rhs.typ) throw std::runtime_error("icmp type mismatch");
        LLVMValue res = new_reg(LLVMType{LLVMBaseType::i1});
        current_block().instructions.push_back(
            "%" + res.name + " = icmp " + llvm_cpp::to_string(cond) + " " + lhs.typ.to_string() + " " + lhs.operand() + ", " + rhs.operand()
        );
        return res;
    }

    LLVMValue add(LLVMValue lhs, LLVMValue rhs) {
        if (lhs.typ != rhs.typ) throw std::runtime_error("add type mismatch");
        LLVMValue res = new_reg(lhs.typ);
        current_block().instructions.push_back(
            "%" + res.name + " = add " + lhs.typ.to_string() + " " + lhs.operand() + ", " + rhs.operand()
        );
        return res;
    }

    LLVMValue alloca_inst(LLVMType typ) {
        LLVMType ptr_type = typ;
        ptr_type.ptr_depth++;
        LLVMValue res = new_reg(ptr_type);
        current_block().instructions.push_back(
            "%" + res.name + " = alloca " + typ.to_string()
        );
        return res;
    }

    void store(LLVMValue val, LLVMValue ptr) {
        if (ptr.typ.ptr_depth == 0) throw std::runtime_error("store destination must be pointer");
        if (val.typ.base != ptr.typ.base) throw std::runtime_error("store type mismatch");
        
        current_block().instructions.push_back(
            "store " + val.typ.to_string() + " " + val.operand() + ", " + ptr.typ.to_string() + " %" + ptr.name
        );
    }

    LLVMValue load(LLVMValue ptr) {
        if (ptr.typ.ptr_depth == 0) throw std::runtime_error("load requires pointer");

        LLVMType val_type = ptr.typ;
        val_type.ptr_depth--;
        
        LLVMValue res = new_reg(val_type);
        current_block().instructions.push_back(
            "%" + res.name + " = load " + val_type.to_string() + ", " + ptr.typ.to_string() + " %" + ptr.name
        );
        return res;
    }

    LLVMValue call(const std::string& fn_name, LLVMType ret, const std::vector<LLVMValue>& call_args) {
        std::string arg_str;
        for (size_t i = 0; i < call_args.size(); ++i) {
            arg_str += call_args[i].to_string();
            if (i < call_args.size() - 1) arg_str += ", ";
        }

        if (ret.base == LLVMBaseType::void_t && ret.ptr_depth == 0) {
            current_block().instructions.push_back("call void @" + fn_name + "(" + arg_str + ")");
            return LLVMValue{"", ret, false};
        }

        LLVMValue res = new_reg(ret);
        current_block().instructions.push_back("%" + res.name + " = call " + ret.to_string() + " @" + fn_name + "(" + arg_str + ")");
        return res;
    }

    LLVMValue getelementptr(LLVMValue ptr, const std::vector<LLVMValue>& indices) {
        if (ptr.typ.ptr_depth == 0) throw std::runtime_error("getelementptr requires pointer");

        LLVMType result_typ = ptr.typ;
        if (ptr.typ.array_len > 0 && indices.size() >= 2) {
            result_typ.array_len = 0;
        } else if ((ptr.typ.base == LLVMBaseType::struct_t || ptr.typ.base == LLVMBaseType::union_t) 
                   && !ptr.typ.fields.empty() && indices.size() >= 2) {
            if (indices[1].is_const && indices[1].typ.base == LLVMBaseType::i32) {
                int idx = std::stoi(indices[1].name);
                if (idx >= 0 && idx < (int)ptr.typ.fields.size()) {
                    result_typ = ptr.typ.fields[idx];
                    result_typ.ptr_depth = ptr.typ.ptr_depth;
                }
            }
        }

        LLVMType base_ptr_typ = ptr.typ;
        base_ptr_typ.ptr_depth--;

        LLVMValue res = new_reg(result_typ);
        std::string idx_str;
        for (size_t i = 0; i < indices.size(); ++i) {
            idx_str += indices[i].to_string();
            if (i < indices.size() - 1) idx_str += ", ";
        }

        current_block().instructions.push_back(
            "%" + res.name + " = getelementptr " + base_ptr_typ.to_string() + ", " + ptr.typ.to_string() + " " + ptr.operand() + ", " + idx_str
        );
        return res;
    }

    // ---- Control Flow ----
    void br(const std::string& label) {
        auto& b = current_block();
        if (b.terminated) throw std::runtime_error("block already terminated");
        b.instructions.push_back("br label %" + label);
        b.terminated = true;
    }

    void cond_br(LLVMValue cond, const std::string& t_label, const std::string& f_label) {
        if (cond.typ.base != LLVMBaseType::i1) throw std::runtime_error("condition must be i1");
        auto& b = current_block();
        b.instructions.push_back("br i1 %" + cond.name + ", label %" + t_label + ", label %" + f_label);
        b.terminated = true;
    }

    LLVMValue phi(LLVMType typ, const std::vector<LLVMPhiIncoming>& incomings) {
        LLVMValue res = new_reg(typ);
        std::string parts;
        for (size_t i = 0; i < incomings.size(); ++i) {
            parts += "[ " + incomings[i].val.operand() + ", %" + incomings[i].label + " ]";
            if (i < incomings.size() - 1) parts += ", ";
        }
        current_block().instructions.push_back("%" + res.name + " = phi " + typ.to_string() + " " + parts);
        return res;
    }

    // ---- High-Level Builders ----
    LLVMValue build_if(LLVMValue cond, 
                       std::function<LLVMValue(LLVMFunction&)> then_builder, 
                       std::function<LLVMValue(LLVMFunction&)> else_builder) {
        
        std::string id = std::to_string(reg_counter);
        std::string then_label = "then_" + id;
        std::string else_label = "else_" + id;
        std::string end_label = "endif_" + id;

        cond_br(cond, then_label, else_label);

        new_block(then_label);
        LLVMValue then_val = then_builder(*this);
        br(end_label);

        new_block(else_label);
        LLVMValue else_val = else_builder(*this);
        br(end_label);

        new_block(end_label);

        return phi(then_val.typ, {
            {then_val, then_label},
            {else_val, else_label}
        });
    }

    void ret(LLVMValue val) {
        if (val.typ != return_type) throw std::runtime_error("return type mismatch");
        auto& b = current_block();
        b.instructions.push_back("ret " + val.typ.to_string() + " " + val.operand());
        b.terminated = true;
    }

    void ret_void() {
        if (return_type.base != LLVMBaseType::void_t) throw std::runtime_error("function must return void");
        auto& b = current_block();
        b.instructions.push_back("ret void");
        b.terminated = true;
    }

    // ---- Output ----
    std::string header() const {
        std::string arg_str;
        for (size_t i = 0; i < args.size(); ++i) {
            arg_str += args[i].typ.to_string() + " %" + args[i].name;
            if (i < args.size() - 1) arg_str += ", ";
        }
        return "define " + return_type.to_string() + " @" + name + "(" + arg_str + ")";
    }

    std::string to_string() const {
        std::string out = header() + " {\n";
        for (const auto& b : blocks) {
            out += b.to_string();
        }
        out += "}\n";
        return out;
    }
};

// ================= CONSTANTS =================

inline LLVMValue const_int(int val, LLVMType typ) {
    return LLVMValue{std::to_string(val), typ, true};
}

// ================= GLOBAL =================

struct LLVMGlobal {
    std::string name;
    LLVMType typ;
    LLVMValue value;
    bool is_const;

    std::string to_string() const {
        std::string c_g = is_const ? "constant" : "global";
        return "@" + name + " = " + c_g + " " + typ.to_string() + " " + value.operand();
    }
};

// ================= MODULE =================

struct LLVMNamedType {
    std::string name;
    bool is_union;
    std::vector<LLVMType> fields;
};

class LLVMModule {
public:
    std::vector<LLVMFunction> functions;
    std::vector<LLVMExternFunction> externs;
    std::vector<LLVMGlobal> globals;
    std::vector<LLVMNamedType> named_types;

    void add_function(const LLVMFunction& f) {
        functions.push_back(f);
    }

    void add_extern(const LLVMExternFunction& e) {
        externs.push_back(e);
    }

    LLVMValue add_global_var(const std::string& name, LLVMType typ, LLVMValue init, bool is_const) {
        globals.push_back(LLVMGlobal{name, typ, init, is_const});
        LLVMType ptr_type = typ;
        ptr_type.ptr_depth++;
        return LLVMValue{"@" + name, ptr_type, true};
    }

    LLVMType add_named_type(const std::string& name, const std::vector<LLVMType>& fields, bool is_union) {
        named_types.push_back(LLVMNamedType{name, is_union, fields});
        return LLVMType{is_union ? LLVMBaseType::union_t : LLVMBaseType::struct_t, 0, 0, name, fields};
    }

    LLVMValue add_string_constant(const std::string& name, const std::string& text) {
        std::string contents = text + '\x00';
        std::string escaped = escape_string_constant(contents);
        LLVMType array_type = LLVMType{LLVMBaseType::i8, 0, (int)contents.length()};
        
        LLVMValue str_val{"c\"" + escaped + "\"", array_type, true};
        globals.push_back(LLVMGlobal{name, array_type, str_val, true});

        LLVMType ptr_type = LLVMType{LLVMBaseType::i8, 1, array_type.array_len};
        return LLVMValue{"@" + name, ptr_type, true};
    }

    std::string to_string() const {
        std::string out;
        for (const auto& t : named_types) {
            std::string kind = t.is_union ? " ; union" : "";
            std::string fields_str;
            for (size_t i = 0; i < t.fields.size(); ++i) {
                fields_str += t.fields[i].to_string();
                if (i < t.fields.size() - 1) fields_str += ", ";
            }
            out += "%" + t.name + " = type { " + fields_str + " }" + kind + "\n";
        }
        for (const auto& g : globals) out += g.to_string() + "\n";
        for (const auto& e : externs) out += e.to_string() + "\n";
        for (const auto& f : functions) out += "\n" + f.to_string();
        return out;
    }
};

} // namespace llvm_cpp