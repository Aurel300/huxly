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
    var varCtr = 0;
    var regs:Array<{
      ident:String,
      reg:Int,
    }> = [];
    function lookupReg(ident:String):Null<Int> {
      for (ri in 0...regs.length) {
        var i = regs.length - ri - 1;
        if (regs[ri].ident == ident) return regs[ri].reg;
      }
      return null;
    }
    var fixpointCtr = 0;
    var fixpoints:Array<{
      ident:String,
      index:Int,
    }> = [];
    function lookupFixpoint(ident:String):Null<Int> {
      for (ri in 0...fixpoints.length) {
        var i = fixpoints.length - ri - 1;
        if (fixpoints[ri].ident == ident) return fixpoints[ri].index;
      }
      return null;
    }
    function resolveRegisters(e:Expr):Expr {
      return (switch (e.expr) {
        case EConst(CIdent(lookupReg(_) => reg)) if (reg != null): macro _huxly_registers[$v{reg}];
        case _: e.map(resolveRegisters);
      });
    }
    function parse(e:Expr):Ast {
      return {expr: e, ast: (switch [e, e.expr] {
        case [_, EConst(CString(v))]: Pure(e);
        case [_, EConst(CInt(v))]: Pure(e);
        case [(macro true) | (macro false) | (macro null), _]: Pure(e);
        case [macro empty, _]: Empty;
        case [macro {}, _]: Empty;
        case [_, EConst(CIdent(lookupReg(_) => reg))] if (reg != null): Reg(reg);
        case [_, EConst(CIdent(lookupFixpoint(_) => index))] if (index != null): Recurse(index);
        case [_, EConst(CIdent(STDLIB_IDENT[_] => stdlib))] if (stdlib != null): stdlib;
        case [_, EConst(CIdent(ident))]: Symbol(ident);
        case [macro $a << $b, _]: Left(parse(a), parse(b));
        case [macro $a >> $b, _]: Right(parse(a), parse(b));
        case [macro $a * $b, _]: Apply(parse(a), parse(b));
        case [macro $a | $b, _]: Alternative(parse(a), parse(b));
        case [macro pure($e), _]: Pure(resolveRegisters(e));
        case [macro impure($e), _]: Impure(resolveRegisters(e));
        case [_, ECall({expr: EConst(CIdent("string"))}, [{expr: EConst(CString(v))}])]:
          var res = macro $v{v};
          for (i in 0...v.length) {
            var cc = v.charCodeAt(v.length - i - 1);
            res = macro char($v{cc}) >> $res;
          }
          return parse(res);
        case [macro sat($f), _]: Satisfy(e -> macro $e{resolveRegisters(f)}($e));
        case [macro notFollowedBy($e), _]: NegLook(parse(e));
        case [_, ECall({expr: EConst(CIdent("char"))}, [{expr: EConst(CInt(Std.parseInt(_) => c))}])]:
          Satisfy(e -> macro $e == $v{c});
        case [_, ECall({expr: EConst(CIdent("char"))}, [{
          expr: EBinop(OpInterval, {expr: EConst(CString(min))}, {expr: EConst(CString(max))})
        }])]:
          if (min.length != 1 || max.length != 1) Context.fatalError("invalid character range", e.pos);
          var min = min.charCodeAt(0);
          var max = max.charCodeAt(0);
          if (min > max) Context.fatalError("invalid character range", e.pos);
          Satisfy(e -> macro { var _cc = $e; $v{min} <= _cc && _cc <= $v{max}});
        case [_, ECall({expr: EConst(CIdent("char"))}, [{expr: EConst(CString(c))}])]:
          if (c.length == 1)
            Satisfy(e -> macro $e == $v{c.charCodeAt(0)});
          else if (c.length > 1)
            Satisfy(e -> {
              var res = macro false;
              for (i in 0...c.length) {
                res = macro $res || _cc == $v{c.charCodeAt(i)};
              }
              macro { var _cc = $e; $res; };
            });
          else Context.fatalError("invalid char", e.pos);
        case [macro branch($b, $l, $r), _]: Branch(parse(b), parse(l), parse(r));
        case [macro let($i{ident} = $init, $p), _]:
          init = resolveRegisters(init);
          var reg = varCtr++;
          regs.push({
            ident: ident,
            reg: reg,
          });
          var sub = parse(p);
          regs.pop();
          Let(reg, init, sub);
        case [macro fixpoint($i{ident}, $p), _]:
          var index = fixpointCtr++;
          fixpoints.push({
            ident: ident,
            index: index,
          });
          var sub = parse(p);
          fixpoints.pop();
          Fixpoint(index, sub);
        case [macro ($e), _]: return parse(e);
        case [macro try $e, _]: Try(parse(e));
        case _: Context.fatalError("invalid parser", e.pos);
      })};
    }
    return parse(e);
  }
}

#end
