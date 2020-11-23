package huxly.internal;

#if macro

class AstParser {
  /**
    Parses a Haxe expression using huxly syntax into a parser AST.
   */
  public static function parse(e:Expr):Ast {
    return {expr: e, ast: (switch (e.expr) {
      case EConst(CString(v)): Pure(e);
      case EConst(CInt(v)): Pure(e);
      case EConst(CIdent("true" | "false" | "null")): Pure(e);
      case EBlock([]): Empty;
      case EConst(CIdent("empty")): Empty;
      case EConst(CIdent("eof")): NegLook({expr: null, ast: Satisfy(e -> macro true)});
      case EConst(CIdent(ident)): Symbol(ident);
      case EBinop(OpShl, a, b): Left(parse(a), parse(b));
      case EBinop(OpShr, a, b): Right(parse(a), parse(b));
      case EBinop(OpMult, a, b): Apply(parse(a), parse(b));
      case EBinop(OpOr, a, b): Alternative(parse(a), parse(b));
      case ECall({expr: EConst(CIdent("pure"))}, [e]): Pure(e);
      case ECall({expr: EConst(CIdent("string"))}, [{expr: EConst(CString(v))}]):
        var res = macro $v{v};
        for (i in 0...v.length) {
          var cc = v.charCodeAt(v.length - i - 1);
          res = macro char($v{cc}) >> $res;
        }
        return parse(res);
      case ECall({expr: EConst(CIdent("sat"))}, [f]): Satisfy(e -> macro $f($e));
      case ECall({expr: EConst(CIdent("char"))}, [{expr: EConst(CInt(Std.parseInt(_) => c))}]): Satisfy(e -> macro $e == $v{c});
      case ECall({expr: EConst(CIdent("char"))}, [{expr: EConst(CString(c))}]):
        if (c.length == 1)
          Satisfy(e -> macro $e == $v{c.charCodeAt(0)});
        else if (c.length > 1)
          Satisfy(e -> {
            var res = macro false;
            for (i in 0...c.length) {
              res = macro $e == $v{c.charCodeAt(i)} || $res;
            }
            res;
          });
        else Context.fatalError("invalid char", e.pos);
      case ECall({expr: EConst(CIdent("branch"))}, [b, l, r]): Branch(parse(b), parse(l), parse(r));
      case EParenthesis(e): return parse(e);
      case ETry(e, []): Try(parse(e));
      case _: Context.fatalError("invalid parser", e.pos);
    })};
  }
}

#end
