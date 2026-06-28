# Gawin Language Server (prototype)

This repository contains a TypeScript-based Language Server and VS Code extension prototype for the Gawin language.

Structure:

- `server/` — language server implementation (parser, symbols, semantic checks)
- `client/` — VS Code extension that launches the language server and reuses existing syntax highlighting from `g_syntax_highlighting`

Build:

```
cd gawin-lsp
npm install
npm run build
```

Development:

Run the server and client builds in watch mode and use the VS Code Extension Development Host to load the extension.

Notes:

- The implementation is intentionally lightweight and uses the repository's existing tmLanguage grammar for token definitions.
- Many LSP features are scaffolded and should be expanded (incremental parsing, full semantic analysis, formatting, folding, and tests).
