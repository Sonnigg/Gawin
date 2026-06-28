"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WorkspaceIndex = void 0;
exports.buildSymbols = buildSymbols;
class WorkspaceIndex {
    constructor() {
        this.definitions = new Map();
        this.references = new Map();
    }
    addDefinition(name, loc) {
        if (!name)
            return;
        const arr = this.definitions.get(name) || [];
        arr.push(loc);
        this.definitions.set(name, arr);
    }
    addReference(name, loc) {
        if (!name)
            return;
        const arr = this.references.get(name) || [];
        arr.push(loc);
        this.references.set(name, arr);
    }
    setForUri(uri, nodes) {
        // purge definitions and references for this uri
        for (const [k, arr] of this.definitions.entries())
            this.definitions.set(k, arr.filter(s => s.uri !== uri));
        for (const [k, arr] of this.references.entries())
            this.references.set(k, arr.filter(s => s.uri !== uri));
        // collect definitions by node type
        const walk = (n) => {
            if (!n)
                return;
            if (n.name && (n.type === 'Function' || n.type === 'Type' || n.type === 'Module' || n.type === 'Import')) {
                const loc = { uri, range: n.range, kind: n.type };
                this.addDefinition(n.name, loc);
            }
            if (n.children)
                for (const c of n.children)
                    walk(c);
            if (n.params)
                for (const p of n.params)
                    walk(p);
        };
        for (const n of nodes)
            walk(n);
    }
    findDefinitions(name) { return this.definitions.get(name) || []; }
    findReferences(name) { return this.references.get(name) || []; }
    findAllSymbols() {
        const res = [];
        for (const arr of this.definitions.values())
            res.push(...arr);
        return res;
    }
    allOccurrences(name) {
        const defs = this.findDefinitions(name).map(d => ({ ...d, isDefinition: true }));
        const refs = this.findReferences(name);
        return defs.concat(refs || []);
    }
}
exports.WorkspaceIndex = WorkspaceIndex;
function buildSymbols(uri, nodes) {
    const res = [];
    for (const n of nodes) {
        if (!n.name)
            continue;
        res.push({ uri, range: n.range, kind: n.type });
    }
    return res;
}
