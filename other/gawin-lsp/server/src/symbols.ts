import { Node } from "./parser";

export interface SymbolLocation {
  uri: string;
  name?: string;
  range: { start: { line: number; character: number }; end: { line: number; character: number } };
  kind: string;
}

export interface ReferenceLocation extends SymbolLocation {
  isDefinition?: boolean;
}

export class WorkspaceIndex {
  private definitions = new Map<string, SymbolLocation[]>();
  private references = new Map<string, ReferenceLocation[]>();

  addDefinition(name: string, loc: SymbolLocation) {
    if (!name) return;
    const arr = this.definitions.get(name) || [];
    arr.push(loc);
    this.definitions.set(name, arr);
  }

  addReference(name: string, loc: ReferenceLocation) {
    if (!name) return;
    const arr = this.references.get(name) || [];
    arr.push(loc);
    this.references.set(name, arr);
  }

  setForUri(uri: string, nodes: Node[]) {
    // purge definitions and references for this uri
    for (const [k, arr] of this.definitions.entries()) this.definitions.set(k, arr.filter(s => s.uri !== uri));
    for (const [k, arr] of this.references.entries()) this.references.set(k, arr.filter(s => s.uri !== uri));

    // collect definitions by node type
    const walk = (n: Node | undefined) => {
      if (!n) return;
      if (n.name && (n.type === 'Function' || n.type === 'Type' || n.type === 'Module' || n.type === 'Import')) {
        const loc: SymbolLocation = { uri, range: n.range as any, kind: n.type };
        this.addDefinition(n.name, loc);
      }
      if (n.children) for (const c of n.children) walk(c);
      if (n.params) for (const p of n.params) walk(p);
    };
    for (const n of nodes) walk(n as Node);
  }

  findDefinitions(name: string) { return this.definitions.get(name) || [] }
  findReferences(name: string) { return this.references.get(name) || [] }

  findAllSymbols() {
    const res: SymbolLocation[] = [];
    for (const arr of this.definitions.values()) res.push(...arr);
    return res;
  }

  allOccurrences(name: string) {
    const defs = this.findDefinitions(name).map(d => ({ ...d, isDefinition: true } as ReferenceLocation));
    const refs = this.findReferences(name);
    return defs.concat(refs || []);
  }
}

export function buildSymbols(uri: string, nodes: Node[]) {
  const res: SymbolLocation[] = [];
  for (const n of nodes) {
    if (!n.name) continue;
    res.push({ uri, range: n.range as any, kind: n.type });
  }
  return res;
}
