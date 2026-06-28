# G Syntax Highlighting

Syntax highlighting, snippets, and file icon support for `Gawin` language files (`.gawin`, `.gwin`, `.gw` and `g.mod`).

## Features

- Syntax highlighting for `Gawin` source files
- Code snippets for common constructs
- File icon support for `.gawin`, `.gwin`, `.gw` and `g.mod` when using the default VS Code file icon theme

## Files

- `package.json` - extension manifest
- `language-configuration.json` - comment/bracket/auto-closing rules
- `syntaxes/g.tmLanguage.json` - TextMate grammar for Gawin
- `snippets/g.json` - editor snippets for Gawin
- `g_logo.png` - file icon asset
- `g_logo_ext.png` - file extension icon asset
- `g_meta_ext.png` - file extension icon asset for metadata files

## Build

1. Open a terminal in `g_syntax_highlighting`.
2. Install dependencies:

```bash
npm install
```

3. Package the extension:

```bash
npm run package
```

This creates a `.vsix` package in the same folder.

## Install

In VS Code, choose `Extensions` ▸ `...` ▸ `Install from VSIX...`, then select the generated `.vsix` file.

## Notes

The file icon theme is included as part of the extension and will show `g_logo.png` for `.gawin`, `.gwin`, `.gw` and `g.mod` files when the icon theme is active.
