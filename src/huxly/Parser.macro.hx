package huxly;

import haxe.macro.Context;
import haxe.macro.Expr;
import huxly.internal.*;

class Parser {
  public static function build():Array<Field> {
    var symbols = new Map();
    for (field in Context.getBuildFields()) {
      switch (field.kind) {
        case FVar(null, e):
          if (symbols.exists(field.name))
            Context.fatalError("duplicate field", field.pos);
          symbols[field.name] = AstParser.parse(e);
        case _: Context.fatalError("only vars are allowed", field.pos);
      }
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
      .concat([macro return main()]);
    var ret = (macro class {
      public static function parseBytes(_huxly_input:haxe.io.Bytes)
        $b{parseBytes}
    }).fields;
    // TODO: allow statics and other non-parser fields
    return ret;
  }

  static var printer = new haxe.macro.Printer();

  /*
  static function resolveSymbols(parser:ParserExpr, symbols:Map<String, ParserExpr>):ParserExpr {
    return {expr: parser.expr, ast: (switch (parser.ast) {
      case Symbol(ident):
        var res = symbols[ident];
        if (res != null)
          return res;
        // Context.fatalError('no such symbol: ${ident}', parser.expr.pos);
        Pure(macro $i{ident});
      case Try(p): Try(resolveSymbols(p, symbols));
      case Look(p): Look(resolveSymbols(p, symbols));
      case NegLook(p): NegLook(resolveSymbols(p, symbols));
      case Apply(l, r): Apply(resolveSymbols(l, symbols), resolveSymbols(r, symbols));
      case Left(l, r): Left(resolveSymbols(l, symbols), resolveSymbols(r, symbols));
      case Right(l, r): Right(resolveSymbols(l, symbols), resolveSymbols(r, symbols));
      case Alternative(l, r): Alternative(resolveSymbols(l, symbols), resolveSymbols(r, symbols));
      case Branch(b, l, r): Branch(resolveSymbols(b, symbols), resolveSymbols(l, symbols), resolveSymbols(r, symbols));
      case _: parser.ast;
    })};
  }
  */
}
