import * as assert from 'assert';
import { parse } from '../src/parser';
import { analyze } from '../src/semantic';

describe('semantic', () => {
  it('reports undefined symbols', () => {
    const src = `func main() { println(x) }`;
    const nodes = parse(src);
    const diags = analyze(nodes, src);
    const messages = diags.map(d => d.message);
    assert.ok(messages.some(m => m.includes("Undefined symbol 'x'")));
  });

  it('reports duplicate declarations in a file', () => {
    const src = `func a() {}\nfunc a() {}`;
    const nodes = parse(src);
    const diags = analyze(nodes, src);
    const messages = diags.map(d => d.message);
    assert.ok(messages.some(m => m.includes("Duplicate Function declaration 'a'")));
  });
});
