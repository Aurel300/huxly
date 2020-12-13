package huxly;

import haxe.macro.Context;
import haxe.macro.Expr;
import huxly.internal.*;

class Parser {
  static var printer = new haxe.macro.Printer();

  public static function build():Array<Field> {
    var cls = Context.getLocalClass().get();
    var returnType = haxe.macro.TypeTools.toComplexType(cls.superClass.params[0]);
    var rawSymbols = [];
    for (field in Context.getBuildFields()) {
      switch (field.kind) {
        // TODO: allow statics and other non-parser fields
        case FVar(null, e): rawSymbols.push({name: field.name, expr: e});
        case _: Context.fatalError("only vars are allowed", field.pos);
      }
    }
    return (macro class {
      public static function parseBytes(_huxly_input:haxe.io.Bytes):$returnType
        $e{buildSyntax(rawSymbols)}
      public static function parseString(s:String):$returnType
        return parseBytes(haxe.io.Bytes.ofString(s));
    }).fields;
  }

  public static function ofSyntax(syntax:Expr):Expr {
    var rawSymbols = [];
    switch (syntax.expr) {
      case EBlock(es) if (es.length > 0):
        for (expr in es) switch (expr.expr) {
          case EVars(vars):
            for (v in vars) {
              if (v.expr == null) Context.fatalError("expected expression", expr.pos);
              rawSymbols.push({name: v.name, expr: v.expr});
            }
          case _: Context.fatalError("invalid syntax", expr.pos);
        }
      case _:
        rawSymbols.push({name: "main", expr: syntax});
    }
    return macro new huxly.InlineParser(function (_huxly_input:haxe.io.Bytes) {
      $e{buildSyntax(rawSymbols)}
    });
  }

  static function buildSyntax(rawSymbols:Array<{name:String, expr:Expr}>):Expr {
    var symbols = new Map();
    for (s in rawSymbols) {
      if (symbols.exists(s.name))
        Context.fatalError("duplicate field", s.expr.pos);
      symbols[s.name] = AstParser.parse(s.expr);
    }
    if (!symbols.exists("main"))
      Context.fatalError("main parser not found", Context.currentPos());
    //symbols = [ for (id => parser in symbols) id => resolveSymbols(parser, symbols) ];
    var forwardDecls = [];
    var defs = [];
    for (id => parser in symbols) {
      var e = Compiler.compile(Optimiser.optimise(parser));
      Sys.println(id);
      Sys.println(printer.printExpr(e));
      forwardDecls.push(macro var $id = null);
      defs.push(macro $i{id} = () -> $e);
    }
    var parseBytes = [macro var _huxly_inputPos = 0]
      .concat(forwardDecls)
      .concat(defs)
      .concat([macro @:pos(symbols["main"].expr.pos) return main()]);
    return macro $b{parseBytes};
  }
}
