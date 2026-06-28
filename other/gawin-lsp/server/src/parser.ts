import { KEYWORDS, TYPES } from "./lexer";

export type NodeKind =
  | "Program"
  | "Module"
  | "Import"
  | "Namespace"
  | "Function"
  | "Type"
  | "Variant"
  | "Struct"
  | "Enum"
  | "Const"
  | "Variable"
  | "Parameter"
  | "Assignment"
  | "Block"
  | "If"
  | "Match"
  | "CallExpression"
  | "Identifier"
  | "Literal"
  | "Return"
  | "Unknown";

export interface Pos { line: number; character: number }
export interface Range { start: Pos; end: Pos }

export interface Node {
  type: NodeKind;
  name?: string;
  range: Range;
  children?: Node[];
  value?: any;
  params?: Node[];
  returnType?: string | null;
  namespace?: string;
  isPub?: boolean;
  isDeclaration?: boolean;
}

export interface Token { type: string; value: string; line: number; col: number }

function tokenize(text: string): Token[] {
  const tokens: Token[] = [];
  const lines = text.split(/\r?\n/);
  const id = /[A-Za-z_][A-Za-z0-9_]*/y;
  const num = /\b\d+(?:\.\d+)?\b/y;
  for (let li = 0; li < lines.length; li++) {
    const line = lines[li];
    let i = 0;
    while (i < line.length) {
      const ch = line[i];
      if (/\s/.test(ch)) { i++; continue }
      if (ch === '/' && line[i+1] === '/') break; // line comment
      if (ch === '/' && line[i+1] === '*') { // block comment skip to end of block across lines
        const rest = lines.slice(li).join('\n');
        const endIdx = rest.indexOf('*/');
        if (endIdx >= 0) {
          // advance indices accordingly
          const consumed = rest.slice(0, endIdx+2);
          const consumedLines = consumed.split(/\r?\n/);
          li += consumedLines.length - 1;
          i = consumedLines[consumedLines.length-1].length;
          continue;
        } else break;
      }
      if (ch === '"' || ch === "'") {
        const q = ch; let j = i+1; while (j < line.length && line[j] !== q) { if (line[j] === '\\') j+=2; else j++ }
        const val = line.slice(i, Math.min(j+1, line.length));
        tokens.push({ type: 'string', value: val, line: li, col: i }); i = j+1; continue;
      }
      if (/[{\}()\[\],.:;+\-*/%=&|<>!?]/.test(ch)) { tokens.push({ type: 'punct', value: ch, line: li, col: i }); i++; continue }
      id.lastIndex = i; const im = id.exec(line);
      if (im) { const v = im[0]; const t = KEYWORDS.includes(v) ? 'keyword' : (TYPES.includes(v) ? 'type' : 'identifier'); tokens.push({ type: t, value: v, line: li, col: i }); i = id.lastIndex; continue }
      num.lastIndex = i; const nm = num.exec(line);
      if (nm) { tokens.push({ type: 'number', value: nm[0], line: li, col: i }); i = num.lastIndex; continue }
      tokens.push({ type: 'char', value: ch, line: li, col: i }); i++;
    }
    // end of line token
    tokens.push({ type: 'eol', value: '\n', line: li, col: lines[li].length });
  }
  return tokens;
}

export function parse(text: string): Node[] {
  const tokens = tokenize(text);
  let i = 0;
  function peek(n=0) { return tokens[i+n] }
  function next() { return tokens[i++] }
  function eof() { return i >= tokens.length }

  const program: Node = { type: 'Program', range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }, children: [] };

  type TokenOrRange = Token | Range | undefined;
  function makeRange(t1?: TokenOrRange, t2?: TokenOrRange): Range {
    if (!t1) return { start: { line:0, character:0 }, end: { line:0, character:0 } };
    const start = ('start' in (t1 as any)) ? (t1 as any).start : { line: (t1 as Token).line, character: (t1 as Token).col };
    let end: Pos;
    if (!t2) {
      end = ('start' in (t1 as any)) ? (t1 as any).end : { line: (t1 as Token).line, character: (t1 as Token).col + (t1 as Token).value.length };
    } else {
      end = ('start' in (t2 as any)) ? (t2 as any).end : { line: (t2 as Token).line, character: (t2 as Token).col + (t2 as Token).value.length };
    }
    return { start, end };
  }

  function consumeIf(type: string, value?: string) {
    const t = peek(); if (!t) return null; if (t.type === type && (value===undefined || t.value===value)) return next(); return null;
  }

  function parseIdentifier(): Node | null {
    const t = peek();
    if (t && t.type === 'identifier') { next(); return { type: 'Identifier', name: t.value, range: makeRange(t) }; }
    return null;
  }

  function parseQualifiedName(): Node | null {
    const first = consumeIf('identifier');
    if (!first) return null;
    let full = first.value;
    let end: TokenOrRange = first;
    while (peek() && peek().type === 'punct' && (peek().value === ':' || peek().value === '.')) {
      const sep = next();
      if (sep.value === ':' && peek() && peek().type === 'punct' && peek().value === ':') {
        next();
        const part = consumeIf('identifier');
        if (!part) break;
        full += '::' + part.value;
        end = part;
        continue;
      }
      if (sep.value === '.') {
        const part = consumeIf('identifier');
        if (!part) break;
        full += '.' + part.value;
        end = part;
        continue;
      }
      break;
    }
    return { type: 'Identifier', name: full, range: makeRange(first, end) } as Node;
  }

  function parseLiteral(): Node | null {
    const t = peek();
    if (!t) return null;
    if (t.type === 'string' || t.type === 'number') { next(); return { type: 'Literal', value: t.value, range: makeRange(t) } }
    return null;
  }

  function parsePrimary(): Node | null {
    const t = peek();
    if (!t) return null;
    if (t.type === 'identifier') {
      if (peek(1) && peek(1).type === 'punct' && peek(1).value === '(') {
        return parseCallExpression();
      }
      return parseQualifiedName();
    }
    if (t.type === 'string' || t.type === 'number') return parseLiteral();
    if (t.type === 'punct' && t.value === '(') {
      next();
      const inner = parseExpression();
      consumeIf('punct', ')');
      return inner;
    }
    return null;
  }

  function parseExpression(): Node | null {
    let left = parsePrimary();
    if (!left) return null;
    if (peek() && peek().type === 'keyword' && peek().value === 'as') {
      const asTok = next();
      const target = parseQualifiedName() || parseIdentifier();
      return { type: 'CallExpression', name: 'as', params: [left, target].filter(Boolean) as Node[], range: makeRange(left.range, target?.range || asTok) } as Node;
    }
    return left;
  }

  function parseCallExpression(): Node | null {
    const idTok = peek();
    if (!idTok || idTok.type !== 'identifier') return null;
    const id = parseQualifiedName();
    if (!id || !peek() || peek().type !== 'punct' || peek().value !== '(') return id;
    const start = idTok;
    next(); // consume (
    const args: Node[] = [];
    while (peek() && !(peek().type === 'punct' && peek().value === ')')) {
      const arg = parseExpression();
      if (arg) args.push(arg);
      if (peek() && peek().type === 'punct' && peek().value === ',') next();
      else break;
    }
    const endTok = consumeIf('punct', ')');
    return { type: 'CallExpression', name: id.name, params: args, range: makeRange(start, endTok || start) } as Node;
  }

  function parseCompositeDecl(kind: NodeKind): Node | null {
    const start = next();
    const nameNode = parseQualifiedName();
    if (!nameNode) return null;
    let body: Node | null = null;
    if (peek() && peek().type === 'punct' && peek().value === '{') {
      body = parseBlock();
    }
    return { type: kind, name: nameNode.name, children: body ? [body] : [], range: makeRange(start, (body && body.range) || nameNode.range) } as Node;
  }

  function parseParameters(): Node[] {
    const params: Node[] = [];
    if (!(peek() && peek().type === 'punct' && peek().value === '(')) return params;
    const start = next(); // (
    while (peek() && !(peek().type === 'punct' && peek().value === ')')) {
      const nameTok = consumeIf('identifier');
      if (!nameTok) break;
      let typeName: string | null = null;
      if (peek() && peek().type === 'punct' && peek().value === ':') { next(); const t = consumeIf('type') || consumeIf('identifier'); if (t) typeName = t.value }
      params.push({ type: 'Parameter', name: nameTok.value, range: makeRange(nameTok), value: typeName });
      if (peek() && peek().type === 'punct' && peek().value === ',') next();
    }
    consumeIf('punct', ')');
    return params;
  }

  function parseAssignment(): Node | null {
    const lhs = parseQualifiedName();
    if (!lhs) return null;
    let isDeclaration = false;
    if (peek() && peek().type === 'punct' && peek().value === ':') {
      next();
      if (!(peek() && peek().type === 'punct' && peek().value === '=')) return null;
      isDeclaration = true;
    }
    if (!peek() || peek().type !== 'punct' || peek().value !== '=') return null;
    const eq = next();
    const rhs = parseExpression();
    return { type: 'Assignment', name: lhs.name, children: rhs ? [rhs] : [], range: makeRange(lhs.range, rhs ? rhs.range : eq), isDeclaration } as Node;
  }

  function parseReceiverBlock(): Node | null {
    const start = next(); // for
    let receiver: Node | null = null;
    if (peek() && (peek().type === 'identifier' || peek().type === 'keyword')) {
      receiver = parseQualifiedName() || parseIdentifier();
    }
    if (peek() && peek().type === 'punct' && peek().value === ':') {
      next();
      const typeName = parseQualifiedName() || parseIdentifier();
      if (receiver && typeName) receiver.value = typeName.name;
    }
    if (peek() && peek().type === 'punct' && peek().value === '=') {
      next();
      consumeIf('punct', '>');
    }
    const body = peek() && peek().type === 'punct' && peek().value === '{' ? parseBlock() : null;
    const node: Node = { type: 'Block', name: receiver?.name, range: makeRange(start, (body && (body.range as any)) || start), children: [] };
    if (receiver) node.params = [receiver];
    if (body) node.children = [body];
    return node;
  }

  function parseBlock(): Node {
    const startTok = consumeIf('punct', '{');
    const start = startTok || peek();
    const body: Node[] = [];
    while (peek() && !(peek().type === 'punct' && peek().value === '}')) {
      const t = peek();
      if (!t) break;
      if (t.type === 'keyword' && t.value === 'return') {
        next(); const expr = parseExpression(); body.push({ type: 'Return', children: expr ? [expr] : [], range: makeRange(t, expr ? (expr.range as any) : t) }); consumeIf('punct',';'); continue;
      }
      if (t.type === 'keyword' && t.value === 'if') {
        const stmt = parseIf(); if (stmt) { body.push(stmt); continue }
      }
      if (t.type === 'keyword' && t.value === 'match') {
        const stmt = parseMatch(); if (stmt) { body.push(stmt); continue }
      }
      if (t.type === 'keyword' && t.value === 'for') {
        const stmt = parseReceiverBlock(); if (stmt) { body.push(stmt); continue }
      }
      if (t.type === 'keyword' && (t.value === 'const' || t.value === 'var' || t.value === 'let')) {
        const decl = parseConstOrVar(); if (decl) { body.push(decl); continue }
      }
      if (t.type === 'identifier') {
        const assignment = parseAssignment(); if (assignment) { body.push(assignment); consumeIf('punct',';'); continue }
      }
      if (t.type === 'punct' && t.value === '{') { body.push(parseBlock()); continue }
      const expr = parseExpression(); if (expr) { body.push(expr); consumeIf('punct',';'); continue }
      next();
    }
    const endTok = consumeIf('punct', '}');
    return { type: 'Block', children: body, range: makeRange(startTok||start, endTok||start) };
  }

  function parseFunction(): Node | null {
    const t = peek(); if (!t || t.type !== 'keyword' || t.value !== 'func') return null;
    const start = next();
    const nameTok = parseQualifiedName();
    const params = parseParameters();
    let returnType: string | null = null;
    if (peek() && peek().type === 'punct' && peek().value === '-') {
      next(); consumeIf('punct','>'); const rt = parseQualifiedName() || parseIdentifier(); if (rt && rt.name) returnType = rt.name;
    }
    if (peek() && peek().type === 'keyword' && peek().value === 'as') {
      next(); if (peek() && (peek().type === 'keyword' || peek().type === 'identifier')) next();
    }
    const body = peek() && peek().type === 'punct' && peek().value === '{' ? parseBlock() : null;
    return { type: 'Function', name: nameTok ? nameTok.name : undefined, params, returnType, children: body ? [body] : [], range: makeRange(start, (body && (body.range as any)) || start) } as Node;
  }

  function parseConstOrVar(): Node | null {
    const t = peek(); if (!t || t.type !== 'keyword' || (t.value !== 'const' && t.value !== 'var' && t.value !== 'let')) return null;
    const start = next();
    const nameTok = parseQualifiedName();
    if (!nameTok) return null;
    let init: Node | null = null;
    if (peek() && peek().type === 'punct' && (peek().value === '=' || peek().value === ':')) {
      const op = next();
      if (op.value === ':' && peek() && peek().type === 'punct' && peek().value === '=') next();
      init = parseExpression();
    }
    consumeIf('punct',';');
    return { type: t.value === 'const' ? 'Const' : 'Variable', name: nameTok.name, children: init ? [init] : [], range: makeRange(start, (init && (init.range as any)) || nameTok.range) } as Node;
  }

  function parseIf(): Node | null {
    const start = next();
    const condition = parseExpression();
    const thenBlock = peek() && peek().type === 'punct' && peek().value === '{' ? parseBlock() : null;
    let elseBlock: Node | null = null;
    if (peek() && peek().type === 'keyword' && peek().value === 'else') {
      next();
      elseBlock = peek() && peek().type === 'punct' && peek().value === '{' ? parseBlock() : null;
    }
    return { type: 'If', children: [condition].concat(thenBlock ? [thenBlock] : []).concat(elseBlock ? [elseBlock] : []), range: makeRange(start, (elseBlock && elseBlock.range) || (thenBlock && thenBlock.range) || condition?.range || start) } as Node;
  }

  function parseMatch(): Node | null {
    const start = next();
    const subject = parseExpression();
    const body = peek() && peek().type === 'punct' && peek().value === '{' ? parseBlock() : null;
    return { type: 'Match', children: [subject].concat(body ? [body] : []), range: makeRange(start, (body && body.range) || subject?.range || start) } as Node;
  }

  function parseNamespaceDecl(type: NodeKind): Node | null {
    const start = next();
    const name = parseQualifiedName();
    if (!name) return null;
    consumeIf('punct', ';');
    return { type, name: name.name, range: makeRange(start, name.range) } as Node;
  }

  function parseTopLevel() {
    while (!eof()) {
      const t = peek(); if (!t) break;
      if (t.type === 'keyword' && t.value === 'module') { const node = parseNamespaceDecl('Module'); if (node) { program.children!.push(node); continue } }
      if (t.type === 'keyword' && t.value === 'import') { const node = parseNamespaceDecl('Import'); if (node) { program.children!.push(node); continue } }
      if (t.type === 'keyword' && t.value === 'type') { const node = parseNamespaceDecl('Type'); if (node) { program.children!.push(node); continue } }
      if (t.type === 'keyword' && t.value === 'struct') { const node = parseCompositeDecl('Struct'); if (node) { program.children!.push(node); continue } }
      if (t.type === 'keyword' && t.value === 'enum') { const node = parseCompositeDecl('Enum'); if (node) { program.children!.push(node); continue } }
      if (t.type === 'keyword' && t.value === 'variant') { const node = parseCompositeDecl('Variant'); if (node) { program.children!.push(node); continue } }
      if (t.type === 'keyword' && t.value === 'for') { const node = parseReceiverBlock(); if (node) { program.children!.push(node); continue } }
      if (t.type === 'keyword' && (t.value === 'const' || t.value === 'var' || t.value === 'let')) { const decl = parseConstOrVar(); if (decl) { program.children!.push(decl); continue } }
      if (t.type === 'keyword' && t.value === 'func') { const fn = parseFunction(); if (fn) { program.children!.push(fn); continue } }
      if (t.type === 'keyword' && t.value === 'pub') {
        next();
        const nextTok = peek();
        if (nextTok && nextTok.type === 'keyword' && nextTok.value === 'func') {
          const fn = parseFunction(); if (fn) { fn.isPub = true; program.children!.push(fn); continue }
        }
        if (nextTok && nextTok.type === 'keyword' && (nextTok.value === 'const' || nextTok.value === 'var' || nextTok.value === 'let')) {
          const decl = parseConstOrVar(); if (decl) { decl.isPub = true; program.children!.push(decl); continue }
        }
        if (nextTok && nextTok.type === 'keyword' && (nextTok.value === 'struct' || nextTok.value === 'enum' || nextTok.value === 'variant')) {
          const kind = nextTok.value === 'struct' ? 'Struct' : nextTok.value === 'enum' ? 'Enum' : 'Variant';
          const node = parseCompositeDecl(kind as NodeKind);
          if (node) { node.isPub = true; program.children!.push(node); continue }
        }
      }
      if (t.type === 'eol') { next(); continue }
      const expr = parseExpression(); if (expr) { program.children!.push(expr); continue }
      next();
    }
  }

  parseTopLevel();
  return program.children || [];
}
