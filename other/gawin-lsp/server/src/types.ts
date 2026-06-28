export interface Position {
  line: number;
  character: number;
}

export interface Range {
  start: Position;
  end: Position;
}

export interface SymbolLocation {
  uri: string;
  range: Range;
}
