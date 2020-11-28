package huxly.internal;

#if macro

class AstParser {
  public static final DF_CONST_TRUE = _ -> macro true;
  public static final DF_ID = e -> e;

  static final STDLIB_IDENT:Map<String, Ast.AstKind<Ast>> = [
    "empty" => Empty,
    "item" => Satisfy(DF_CONST_TRUE),
    "eof" => NegLook(mk(Satisfy(DF_CONST_TRUE))),
  ];

  /**
    Parses a Haxe expression using huxly syntax into a parser AST.
   */
  public static function parse(e:Expr):Ast {
    return {expr: e, ast: (switch [e, e.expr] {
      case [_, EConst(CString(v))]: Pure(e);
      case [_, EConst(CInt(v))]: Pure(e);
      case [(macro true) | (macro false) | (macro null), _]: Pure(e);
      case [macro {}, _]: Empty;
      case [_, EConst(CIdent(STDLIB_IDENT[_] => stdlib))] if (stdlib != null): stdlib;
      case [_, EConst(CIdent(ident))]: Symbol(ident);
      case [macro $a << $b, _]: Left(parse(a), parse(b));
      case [macro $a >> $b, _]: Right(parse(a), parse(b));
      case [macro $a * $b, _]: Apply(parse(a), parse(b));
      case [macro $a | $b, _]: Alternative(parse(a), parse(b));
      case [macro pure($e), _]: Pure(e);
      case [_, ECall({expr: EConst(CIdent("string"))}, [{expr: EConst(CString(v))}])]:
        var res = macro $v{v};
        for (i in 0...v.length) {
          var cc = v.charCodeAt(v.length - i - 1);
          res = macro char($v{cc}) >> $res;
        }
        return parse(res);
      case [macro sat($f), _]: Satisfy(e -> macro $f($e));
      case [macro notFollowedBy($e), _]: NegLook(parse(e));
      case [_, ECall({expr: EConst(CIdent("char"))}, [{expr: EConst(CInt(Std.parseInt(_) => c))}])]:
        Satisfy(e -> macro $e == $v{c});
      case [_, ECall({expr: EConst(CIdent("char"))}, [{expr: EConst(CString(c))}])]:
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
      case [macro branch($b, $l, $r), _]: Branch(parse(b), parse(l), parse(r));
      case [macro ($e), _]: return parse(e);
      case [macro try $e, _]: Try(parse(e));
      case _: Context.fatalError("invalid parser", e.pos);
    })};
  }
}

#end
