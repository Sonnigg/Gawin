"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const node_1 = require("vscode-languageserver/node");
const vscode_languageserver_textdocument_1 = require("vscode-languageserver-textdocument");
const parser_1 = require("./parser");
const semantic_1 = require("./semantic");
const symbols_1 = require("./symbols");
const vscode_languageserver_1 = require("vscode-languageserver");
const connection = (0, node_1.createConnection)(node_1.ProposedFeatures.all);
const documents = new node_1.TextDocuments(vscode_languageserver_textdocument_1.TextDocument);
const workspaceIndex = new symbols_1.WorkspaceIndex();
const documentNodes = new Map();
connection.console.log('Gawin language server bootstrap starting');
connection.onInitialize((_params) => {
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
            textDocumentSync: node_1.TextDocumentSyncKind.Incremental,
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
documents.onDidChangeContent((change) => {
    validateTextDocument(change.document.uri, change.document.getText());
});
documents.onDidClose((e) => {
    // clear diagnostics on close
    connection.sendDiagnostics({ uri: e.document.uri, diagnostics: [] });
    documentNodes.delete(e.document.uri);
});
async function validateTextDocument(uri, text) {
    let nodes = [];
    try {
        nodes = (0, parser_1.parse)(text);
        documentNodes.set(uri, nodes);
        workspaceIndex.setForUri(uri, nodes);
        // collect identifier references to populate workspace index
        function walkRefs(n) {
            if (!n)
                return;
            if (n.type === 'Identifier' && n.name) {
                workspaceIndex.addReference(n.name, { uri, range: n.range, kind: 'Identifier', isDefinition: false });
            }
            if (n.children)
                for (const c of n.children)
                    walkRefs(c);
            if (n.params)
                for (const p of n.params)
                    walkRefs(p);
        }
        for (const n of nodes)
            walkRefs(n);
        const sem = (0, semantic_1.analyze)(nodes, text, workspaceIndex);
        const diags = sem.map(d => ({
            severity: node_1.DiagnosticSeverity.Error,
            range: node_1.Range.create(node_1.Position.create(d.line, 0), node_1.Position.create(d.line, 200)),
            message: d.message,
            source: "gawin-lsp"
        }));
        connection.sendDiagnostics({ uri, diagnostics: diags });
    }
    catch (error) {
        documentNodes.delete(uri);
        workspaceIndex.setForUri(uri, []);
        const message = error instanceof Error ? error.message : String(error);
        connection.console.error('[gawin] parse error: ' + message);
        connection.sendDiagnostics({ uri, diagnostics: [{
                    severity: node_1.DiagnosticSeverity.Error,
                    range: node_1.Range.create(node_1.Position.create(0, 0), node_1.Position.create(0, 1)),
                    message: `Parse error: ${message}`,
                    source: "gawin-lsp"
                }] });
    }
}
connection.onCompletion((_textDocumentPosition) => {
    // basic completion: keywords and known workspace symbols
    const items = [];
    const kws = ["func", "module", "import", "type", "variant", "pub", "const", "if", "else", "match", "return"];
    for (const k of kws)
        items.push({ label: k, kind: node_1.CompletionItemKind.Keyword });
    for (const s of workspaceIndex.findAllSymbols())
        items.push({ label: (s && s.name) || (s && s.uri) || '', kind: node_1.CompletionItemKind.Text });
    return items;
});
connection.onDefinition(params => {
    try {
        const doc = documents.get(params.textDocument.uri);
        if (!doc)
            return null;
        const line = params.position.line;
        const ch = params.position.character;
        const text = doc.getText();
        const nodes = documentNodes.get(params.textDocument.uri) || (0, parser_1.parse)(text);
        for (const n of nodes) {
            if (!n.range)
                continue;
            if (n.range.start.line <= line && n.range.end.line >= line) {
                if (n.name) {
                    const defs = workspaceIndex.findDefinitions(n.name);
                    if (defs.length > 0) {
                        return defs.map(d => node_1.Location.create(d.uri, node_1.Range.create(node_1.Position.create(d.range.start.line, d.range.start.character), node_1.Position.create(d.range.end.line, d.range.end.character))));
                    }
                }
            }
        }
        return null;
    }
    catch {
        return null;
    }
});
connection.onReferences((params, _context) => {
    try {
        const doc = documents.get(params.textDocument.uri);
        if (!doc)
            return [];
        // find the identifier at the given position
        const line = params.position.line;
        const ch = params.position.character;
        const text = doc.getText();
        const nodes = documentNodes.get(params.textDocument.uri) || (0, parser_1.parse)(text);
        function nodeAtPosition(list) {
            for (const n of list) {
                if (!n.range)
                    continue;
                if (n.range.start.line <= line && n.range.end.line >= line) {
                    if (n.type === 'Identifier')
                        return n;
                    if (n.children) {
                        const found = nodeAtPosition(n.children);
                        if (found)
                            return found;
                    }
                }
            }
            return null;
        }
        const node = nodeAtPosition(nodes);
        if (!node || !node.name)
            return [];
        const occ = workspaceIndex.allOccurrences(node.name) || [];
        return occ.map((r) => node_1.Location.create(r.uri, node_1.Range.create(node_1.Position.create(r.range.start.line, r.range.start.character), node_1.Position.create(r.range.end.line, r.range.end.character))));
    }
    catch {
        return [];
    }
});
connection.onRenameRequest(async (params) => {
    // params: { textDocument, position, newName }
    const newName = params.newName;
    let oldName = params.oldName ?? null;
    if (!oldName) {
        const doc = documents.get(params.textDocument.uri);
        if (doc) {
            const line = doc.getText().split(/\r?\n/)[params.position.line] || '';
            const ch = params.position.character || 0;
            const m = /[A-Za-z_][A-Za-z0-9_]*/g;
            let match;
            while ((match = m.exec(line)) !== null) {
                if (match.index <= ch && m.lastIndex >= ch) {
                    oldName = match[0];
                    break;
                }
            }
        }
    }
    if (!oldName)
        return null;
    const edits = {};
    // Replace every occurrence (definitions + references)
    const occ = workspaceIndex.allOccurrences(oldName);
    for (const d of occ) {
        const uri = d.uri;
        const doc = documents.get(uri);
        if (!doc)
            continue;
        const range = node_1.Range.create(node_1.Position.create(d.range.start.line, d.range.start.character), node_1.Position.create(d.range.end.line, d.range.end.character));
        const edit = node_1.TextEdit.replace(range, newName);
        edits[uri] = edits[uri] || [];
        edits[uri].push(edit);
    }
    const we = { changes: edits };
    return we;
});
connection.onHover(async (params) => {
    try {
        const doc = documents.get(params.textDocument.uri);
        if (!doc)
            return null;
        const text = doc.getText();
        const nodes = documentNodes.get(params.textDocument.uri) || (0, parser_1.parse)(text);
        const line = params.position.line;
        const ch = params.position.character;
        function nodeAtPosition(list) {
            for (const n of list) {
                if (!n.range)
                    continue;
                if (n.range.start.line <= line && n.range.end.line >= line) {
                    if (n.type === 'Identifier')
                        return n;
                    if (n.children) {
                        const found = nodeAtPosition(n.children);
                        if (found)
                            return found;
                    }
                }
            }
            return null;
        }
        const idNode = nodeAtPosition(nodes);
        if (!idNode || !idNode.name)
            return null;
        const name = idNode.name;
        const localDefs = (documentNodes.get(params.textDocument.uri) || []).filter(n => n.name === name && (n.type === 'Function' || n.type === 'Type' || n.type === 'Module' || n.type === 'Const' || n.type === 'Variable'));
        let def = localDefs[0];
        let defUri = params.textDocument.uri;
        if (!def) {
            const defs = workspaceIndex.findDefinitions(name);
            if (defs.length > 0) {
                def = { type: defs[0].kind, name: name, range: defs[0].range };
                defUri = defs[0].uri;
            }
        }
        const refs = workspaceIndex.allOccurrences(name) || [];
        let md = `**${name}**\n\n`;
        if (def) {
            if (def.type === 'Function') {
                const fn = def;
                const paramsSig = (fn.params || []).map((p) => `${p.name}${p.value ? ': ' + p.value : ''}`).join(', ');
                const ret = fn.returnType ? ` -> ${fn.returnType}` : '';
                md += `func ${name}(${paramsSig})${ret}\n\n`;
            }
            else {
                md += `${def.type} ${name}\n\n`;
            }
            md += `Defined in: ${defUri}\n\n`;
        }
        else {
            md += '_definition not found_\n\n';
        }
        md += `References: ${refs.length}`;
        return { contents: { kind: 'markdown', value: md } };
    }
    catch {
        return null;
    }
});
// Simple formatter: indent blocks by braces
connection.onDocumentFormatting((params, token) => {
    try {
        const doc = documents.get(params.textDocument.uri);
        if (!doc)
            return [];
        const lines = doc.getText().split(/\r?\n/);
        const out = [];
        let indent = 0;
        for (let line of lines) {
            const trimmed = line.trim();
            if (trimmed.startsWith('}'))
                indent = Math.max(0, indent - 1);
            out.push('    '.repeat(indent) + trimmed);
            if (trimmed.endsWith('{'))
                indent++;
        }
        const full = out.join('\n');
        return [node_1.TextEdit.replace(node_1.Range.create(node_1.Position.create(0, 0), node_1.Position.create(lines.length + 1, 0)), full)];
    }
    catch {
        return [];
    }
});
connection.languages.semanticTokens.on((params) => {
    const builder = new vscode_languageserver_1.SemanticTokensBuilder();
    const nodes = documentNodes.get(params.textDocument.uri) || [];
    function walk(n) {
        if (n.type === 'Identifier') {
            builder.push(n.range.start.line, n.range.start.character, n.name.length, 2, 0); // 2 = variable
        }
        if (n.children)
            n.children.forEach(walk);
    }
    nodes.forEach(walk);
    return builder.build();
});
documents.listen(connection);
connection.console.log('Gawin language server listening for messages');
connection.listen();
