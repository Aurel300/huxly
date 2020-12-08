package huxly;

class InlineParser<T> {
  public final parseBytes:haxe.io.Bytes->T;

  public function new(parseBytes:haxe.io.Bytes->T) {
    this.parseBytes = parseBytes;
  }

  public function parseString(s:String):T {
    return parseBytes(haxe.io.Bytes.ofString(s));
  }
}
