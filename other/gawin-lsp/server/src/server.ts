import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  CompletionItem,
  CompletionItemKind,
  TextDocumentSyncKind,
  DiagnosticSeverity,
  Range,
  Position,
  Location,
  TextEdit,
  WorkspaceEdit
} from "vscode-languageserver/node";
import { TextDocument } from 'vscode-languageserver-textdocument';

import { parse, Node } from "./parser";
import { analyze } from "./semantic";
import { WorkspaceIndex, buildSymbols } from "./symbols";
import { SemanticTokensBuilder } from "vscode-languageserver";

const connection = createConnection(ProposedFeatures.all);
const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

const workspaceIndex = new WorkspaceIndex();
const documentNodes = new Map<string, Node[]>();

connection.console.log('Gawin language server bootstrap starting');

connection.onInitialize((_params: InitializeParams) => {
  connection.console.log('Gawin language server initializing');
  return {
    capabilities: {
      semanticTokensProvider: {
        legend: {
          tokenTypes: ["keyword", "type", "variable", "function"],
          tokenModifiers: ["declaration"]
        },
        full: true
      },
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: { resolveProvider: false },
        referencesProvider: true,
      definitionProvider: true,
      hoverProvider: true,
      documentSymbolProvider: true,
      workspaceSymbolProvider: true,
      renameProvider: true
    }
  };
});

documents.onDidChangeContent((change: { document: TextDocument }) => {
  validateTextDocument(change.document.uri, change.document.getText());
});

documents.onDidClose((e: { document: TextDocument }) => {
  // clear diagnostics on close
  connection.sendDiagnostics({ uri: e.document.uri, diagnostics: [] });
  documentNodes.delete(e.document.uri);
});

async function validateTextDocument(uri: string, text: string) {
  let nodes: Node[] = [];
  try {
    nodes = parse(text);
    documentNodes.set(uri, nodes);
    workspaceIndex.setForUri(uri, nodes);

    // collect identifier references to populate workspace index
    function walkRefs(n?: Node) {
      if (!n) return;
      if (n.type === 'Identifier' && n.name) {
        workspaceIndex.addReference(n.name, { uri, range: n.range as any, kind: 'Identifier', isDefinition: false });
      }
      if (n.children) for (const c of n.children) walkRefs(c);
      if (n.params) for (const p of n.params) walkRefs(p);
    }
    for (const n of nodes) walkRefs(n as Node);

    const sem = analyze(nodes, text, workspaceIndex);
    const diags = sem.map(d => ({
      severity: DiagnosticSeverity.Error,
      range: Range.create(Position.create(d.line, 0), Position.create(d.line, 200)),
      message: d.message,
      source: "gawin-lsp"
    }));

    connection.sendDiagnostics({ uri, diagnostics: diags });
  } catch (error) {
    documentNodes.delete(uri);
    workspaceIndex.setForUri(uri, []);
    const message = error instanceof Error ? error.message : String(error);
    connection.console.error('[gawin] parse error: ' + message);
    connection.sendDiagnostics({ uri, diagnostics: [{
      severity: DiagnosticSeverity.Error,
      range: Range.create(Position.create(0, 0), Position.create(0, 1)),
      message: `Parse error: ${message}`,
      source: "gawin-lsp"
    }] });
  }
}

connection.onCompletion((_textDocumentPosition) => {
  // basic completion: keywords and known workspace symbols
  const items: CompletionItem[] = [];
  const kws = ["func","module","import","type","variant","pub","const","if","else","match","return"];
  for (const k of kws) items.push({ label: k, kind: CompletionItemKind.Keyword });
  for (const s of workspaceIndex.findAllSymbols()) items.push({ label: (s && (s as any).name) || (s && (s as any).uri) || '', kind: CompletionItemKind.Text });
  return items;
});

connection.onDefinition(params => {
  try {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;
    const line = params.position.line; const ch = params.position.character;
    const text = doc.getText();
    const nodes = documentNodes.get(params.textDocument.uri) || parse(text);
    for (const n of nodes) {
      if (!n.range) continue;
      if (n.range.start.line <= line && n.range.end.line >= line) {
        if (n.name) {
          const defs = workspaceIndex.findDefinitions(n.name);
          if (defs.length > 0) {
            return defs.map(d => Location.create(d.uri, Range.create(Position.create(d.range.start.line, d.range.start.character), Position.create(d.range.end.line, d.range.end.character))));
          }
        }
      }
    }
    return null;
  } catch {
    return null;
  }
});

connection.onReferences((params, _context) => {
  try {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return [];
    // find the identifier at the given position
    const line = params.position.line; const ch = params.position.character;
    const text = doc.getText();
    const nodes = documentNodes.get(params.textDocument.uri) || parse(text);
    function nodeAtPosition(list: any[]): any | null {
      for (const n of list) {
        if (!n.range) continue;
        if (n.range.start.line <= line && n.range.end.line >= line) {
          if (n.type === 'Identifier') return n;
          if (n.children) {
            const found = nodeAtPosition(n.children);
            if (found) return found;
          }
        }
      }
      return null;
    }
    const node = nodeAtPosition(nodes as any[]);
    if (!node || !node.name) return [];
    const occ = workspaceIndex.allOccurrences(node.name) || [];
    return occ.map((r: any) => Location.create(r.uri, Range.create(Position.create(r.range.start.line, r.range.start.character), Position.create(r.range.end.line, r.range.end.character))));
  } catch {
    return [];
  }
});

connection.onRenameRequest(async (params: any) => {
  // params: { textDocument, position, newName }
  const newName: string = params.newName;
  let oldName: string | null = params.oldName ?? null;
  if (!oldName) {
    const doc = documents.get(params.textDocument.uri);
    if (doc) {
      const line = doc.getText().split(/\r?\n/)[params.position.line] || '';
      const ch = params.position.character || 0;
      const m = /[A-Za-z_][A-Za-z0-9_]*/g;
      let match: RegExpExecArray | null;
      while ((match = m.exec(line)) !== null) {
        if (match.index <= ch && m.lastIndex >= ch) { oldName = match[0]; break; }
      }
    }
  }
  if (!oldName) return null;
  const edits: { [uri: string]: TextEdit[] } = {};
  // Replace every occurrence (definitions + references)
  const occ = workspaceIndex.allOccurrences(oldName);
  for (const d of occ) {
    const uri = d.uri;
    const doc = documents.get(uri);
    if (!doc) continue;
    const range = Range.create(Position.create(d.range.start.line, d.range.start.character), Position.create(d.range.end.line, d.range.end.character));
    const edit: TextEdit = TextEdit.replace(range, newName);
    edits[uri] = edits[uri] || [];
    edits[uri].push(edit);
  }
  const we: WorkspaceEdit = { changes: edits } as any;
  return we;
});

connection.onHover(async (params) => {
  try {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;
    const text = doc.getText();
    const nodes = documentNodes.get(params.textDocument.uri) || parse(text);
    const line = params.position.line; const ch = params.position.character;
    function nodeAtPosition(list: Node[]): Node | null {
      for (const n of list) {
        if (!n.range) continue;
        if (n.range.start.line <= line && n.range.end.line >= line) {
          if (n.type === 'Identifier') return n;
          if (n.children) {
            const found = nodeAtPosition(n.children);
            if (found) return found;
          }
        }
      }
      return null;
    }
    const idNode = nodeAtPosition(nodes);
    if (!idNode || !idNode.name) return null;

    const name = idNode.name;
    const localDefs = (documentNodes.get(params.textDocument.uri) || []).filter(n => n.name === name && (n.type === 'Function' || n.type === 'Type' || n.type === 'Module' || n.type === 'Const' || n.type === 'Variable'));
    let def = localDefs[0];
    let defUri = params.textDocument.uri;
    if (!def) {
      const defs = workspaceIndex.findDefinitions(name);
      if (defs.length > 0) { def = { type: (defs[0].kind as any), name: name, range: defs[0].range } as Node; defUri = defs[0].uri }
    }
    const refs = workspaceIndex.allOccurrences(name) || [];
    let md = `**${name}**\n\n`;
    if (def) {
      if (def.type === 'Function') {
        const fn = def as any;
        const paramsSig = (fn.params || []).map((p: any) => `${p.name}${p.value ? ': '+p.value : ''}`).join(', ');
        const ret = fn.returnType ? ` -> ${fn.returnType}` : '';
        md += `func ${name}(${paramsSig})${ret}\n\n`;
      } else {
        md += `${def.type} ${name}\n\n`;
      }
      md += `Defined in: ${defUri}\n\n`;
    } else {
      md += '_definition not found_\n\n';
    }
    md += `References: ${refs.length}`;
    return { contents: { kind: 'markdown', value: md } };
  } catch {
    return null;
  }
});



// Simple formatter: indent blocks by braces
connection.onDocumentFormatting((params, token) => {
  try {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return [];
    const lines = doc.getText().split(/\r?\n/);
    const out: string[] = [];
    let indent = 0;
    for (let line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('}')) indent = Math.max(0, indent-1);
      out.push('    '.repeat(indent) + trimmed);
      if (trimmed.endsWith('{')) indent++;
    }
    const full = out.join('\n');
    return [TextEdit.replace(Range.create(Position.create(0,0), Position.create(lines.length+1,0)), full)];
  } catch {
    return [];
  }
});

connection.languages.semanticTokens.on((params) => {
  const builder = new SemanticTokensBuilder();
  const nodes = documentNodes.get(params.textDocument.uri) || [];
  
  function walk(n: Node) {
    if (n.type === 'Identifier') {
      builder.push(n.range.start.line, n.range.start.character, n.name!.length, 2, 0); // 2 = variable
    }
    if (n.children) n.children.forEach(walk);
  }
  nodes.forEach(walk);
  return builder.build();
});

documents.listen(connection);
connection.console.log('Gawin language server listening for messages');
connection.listen();
