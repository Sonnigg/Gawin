import * as path from 'path';
import * as vscode from 'vscode';
import { LanguageClient, TransportKind } from 'vscode-languageclient/node';

let client: LanguageClient | null = null;
let outputChannel: vscode.OutputChannel;

export function activate(context: vscode.ExtensionContext) {
  outputChannel = vscode.window.createOutputChannel('Gawin Language Server');
  context.subscriptions.push(outputChannel);
  outputChannel.appendLine('[gawin] activating extension...');

  const serverModule = context.asAbsolutePath(path.join('server_out','server.js'));

  const serverOptions = {
    run: { module: serverModule, transport: TransportKind.ipc },
    debug: { module: serverModule, transport: TransportKind.ipc }
  };

  const clientOptions = {
    documentSelector: [{ scheme: 'file', language: 'gawin' }, { scheme: 'file', language: 'g' }, { scheme: 'file', language: 'gw' }],
    workspaceFolder: vscode.workspace.workspaceFolders ? vscode.workspace.workspaceFolders[0] : undefined
  };

  client = new LanguageClient('gawin-lsp', 'Gawin Language Server', serverOptions, clientOptions);
  client.onDidChangeState((event) => {
    outputChannel.appendLine(`[gawin] client state: ${event.oldState} -> ${event.newState}`);
  });

  client.start().then(
    () => outputChannel.appendLine('[gawin] language client started successfully'),
    (error: unknown) => {
      const message = error instanceof Error ? error.message : String(error);
      outputChannel.appendLine('[gawin] language client failed to start: ' + message);
      console.error(error);
    }
  );
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) return undefined;
  return client.stop();
}
