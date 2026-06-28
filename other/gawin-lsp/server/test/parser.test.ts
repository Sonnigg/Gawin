import * as assert from 'assert';
import { parse } from '../src/parser';

describe('parser', () => {
  it('parses module and functions', () => {
    const src = `module myMod\nfunc hello() {}`;
    const nodes = parse(src);
    const kinds = nodes.map(n => n.type).sort();
    assert.deepStrictEqual(kinds, ['Function','Module'].sort());
  });

  it('parses const and function with params', () => {
    const src = `module myMod\nconst x = 42\nfunc add(a:number) { return a }`;
    const nodes = parse(src);
    const kinds = nodes.map(n => n.type).sort();
    assert.ok(kinds.includes('Module'));
    assert.ok(kinds.includes('Const'));
    assert.ok(kinds.includes('Function'));
  });
});
