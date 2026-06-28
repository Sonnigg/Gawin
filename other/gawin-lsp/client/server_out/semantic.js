"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.analyze = analyze;
function analyze(nodes, text, workspace) {
    const diagnostics = [];
    // build local scope: collect declarations per-file
    const declared = new Set();
    const declarationKinds = new Set(['Function', 'Type', 'Module', 'Import', 'Const', 'Variable', 'Parameter', 'Struct', 'Enum', 'Variant']);
    const markDeclared = (n) => {
        if (!n)
            return;
        if (n.name && (declarationKinds.has(n.type) || (n.type === 'Assignment' && n.isDeclaration))) {
            declared.add(n.name);
        }
        if (n.params)
            for (const p of n.params)
                markDeclared(p);
        if (n.children)
            for (const c of n.children)
                markDeclared(c);
    };
    for (const n of nodes)
        markDeclared(n);
    // duplicates in file
    const seen = new Map();
    for (const n of nodes) {
        if (!n.name)
            continue;
        if (!(declarationKinds.has(n.type) || (n.type === 'Assignment' && n.isDeclaration)))
            continue;
        const key = `${n.type}:${n.name}`;
        const line = n.range.start.line;
        if (seen.has(key))
            diagnostics.push({ line, message: `Duplicate ${n.type} declaration '${n.name}'` });
        else
            seen.set(key, line);
    }
    // undefined symbol detection by scanning identifier nodes in AST (simple traversal)
    function walk(n) {
        if (!n)
            return;
        if (n.type === 'Identifier' && n.name) {
            const name = n.name;
            if (declared.has(name))
                return;
            if (/^(if|else|for|in|match|return|break|continue|as|unsafe|default|goto|spawn|then|func|module|import|type|pub|const|struct|variant|enum|true|false|none|println)$/.test(name))
                return;
            // check workspace index (or none -> treat as not found)
            const defs = workspace ? workspace.findDefinitions(name) : [];
            if (!defs || defs.length === 0) {
                const line = n.range.start.line;
                diagnostics.push({ line, message: `Undefined symbol '${name}'` });
            }
        }
        if (n.children)
            for (const c of n.children)
                walk(c);
        if (n.params)
            for (const p of n.params)
                walk(p);
    }
    for (const n of nodes)
        walk(n);
    return diagnostics;
}
