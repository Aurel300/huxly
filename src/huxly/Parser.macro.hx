package huxly;

import haxe.ds.Either;
import haxe.macro.Context;
import haxe.macro.Expr;

class Parser {
  public static function build():Array<Field> {
    var symbols = new Map();
    for (field in Context.getBuildFields()) {
      switch (field.kind) {
        case FVar(null, e):
          if (symbols.exists(field.name))
            Context.fatalError("duplicate field", field.pos);
          symbols[field.name] = parse(e);
        case _: Context.fatalError("only vars are allowed", field.pos);
      }
    }
    if (!symbols.exists("main"))
      Context.fatalError("main parser not found", Context.currentPos());
    //symbols = [ for (id => parser in symbols) id => resolveSymbols(parser, symbols) ];

    var forwardDecls = [];
    var defs = [];
    for (id => parser in symbols) {
      var e = compile(optimise(parser));
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
    Sys.println(printer.printField(ret[0]));
    return ret;
  }

  static var printer = new haxe.macro.Printer();

  static function parse(e:Expr):ParserExpr {
    function walk(e:Expr):ParserExpr {
      return {expr: e, ast: (switch (e.expr) {
        case EConst(CString(v)): Pure(e);
        case EConst(CInt(v)): Pure(e);
        case EConst(CIdent("true" | "false" | "null")): Pure(e);
        case EBlock([]): Empty;
        case EConst(CIdent("empty")): Empty;
        case EConst(CIdent("eof")): NegLook({expr: null, ast: Satisfy(e -> macro true)});
        case EConst(CIdent(ident)): Symbol(ident);
        case EBinop(OpShl, a, b): Left(walk(a), walk(b));
        case EBinop(OpShr, a, b): Right(walk(a), walk(b));
        case EBinop(OpMult, a, b): Apply(walk(a), walk(b));
        case EBinop(OpOr, a, b): Alternative(walk(a), walk(b));
        case ECall({expr: EConst(CIdent("pure"))}, [e]): Pure(e);
        case ECall({expr: EConst(CIdent("string"))}, [{expr: EConst(CString(v))}]):
          var res = macro $v{v};
          for (i in 0...v.length) {
            //res = macro sat(c -> c == $v{v.charAt(v.length - i - 1)}) >> $res;
            var cc = v.charCodeAt(v.length - i - 1);
            res = macro char($v{cc}) >> $res;
          }
          return walk(res);
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
        case ECall({expr: EConst(CIdent("branch"))}, [b, l, r]): Branch(walk(b), walk(l), walk(r));
        case EParenthesis(e): return walk(e);
        case ETry(e, []): Try(walk(e));
        case _: Context.fatalError("invalid parser", e.pos);
      })};
    }
    return walk(e);
  }

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

  static final F_ID = macro e -> e;
  static function mk(ast:ParserAst<ParserExpr>):ParserExpr {
    return {expr: null, ast: ast};
  }
  static function optimise(parser:ParserExpr):ParserExpr {
    return optimise(mk(switch (parser.ast) {
      // Pure(id) * p = p
      case Apply({ast: Pure(F_ID)}, {ast: p}): p;
      // Pure(f) * Pure(x) = Pure(f(x))
      case Apply({ast: Pure(f)}, {ast: Pure(x)}): Pure(macro $f($x));
      // u * Pure(x) = Pure(f -> f(x)) * u
      case Apply(u, {ast: Pure(x)}): Apply(mk(Pure(macro f -> f($x))), optimise(u));
      // TODO 4
      // (p | q) | r = p | (q | r)
      case Alternative({ast: Alternative(p, q)}, r): Alternative(optimise(p), mk(Alternative(optimise(q), optimise(r))));
      // {} | p = p
      case Alternative({ast: Empty}, {ast: p}): p;
      // p | {} = p
      case Alternative({ast: p}, {ast: Empty}): p;
      // {} * p = {}
      case Apply({ast: Empty}, _): Empty;
      // Pure(x) | p = Pure(x)
      case Alternative({ast: Pure(x)}, _): Pure(x);
      //case Branch({ast: Pure(Left(x))}, p, q): Apply(p, mk(Pure(x)));
      //case Branch({ast: Pure(Right(y))}, p, q): Apply(q, mk(Pure(y)));
      //case Branch(b, Pure(f), Pure(g)): Apply(mk(Pure(Either(f, g))), b);
      // Branch(x >> y, p, q) = x >> Branch(y, p, q)
      case Branch({ast: Right(x, y)}, p, q): Right(optimise(x), mk(Branch(optimise(y), optimise(p), optimise(q))));
      //case Branch(b, p, {ast: Empty}): Branch(mk(Apply(mk(Pure(F_SWAP)), b)), Empty, p);
      // TODO 14
      // Try(Satisfy(f)) = Satisfy(f)
      case Try({ast: Satisfy(f)}): Satisfy(f);
      // Try(NegLook(p)) = NegLook(p)
      case Try({ast: NegLook(p)}): NegLook(optimise(p));
      // Look({}) = {}
      case Look({ast: Empty}): Empty;
      // Look(Pure(x)) = Pure(x)
      case Look({ast: Pure(x)}): Pure(x);
      // NegLook({}) = Pure(null) // null as Unit
      case NegLook({ast: Empty}): Pure(macro null);
      // NegLook(Pure(x)) = {}
      case NegLook({ast: Pure(x)}): Empty;
      // Look(Look(p)) = Look(p)
      case Look({ast: Look(p)}): Look(optimise(p));
      // Look(p) | Look(q) = Look(Try(p) | q)
      case Alternative({ast: Look(p)}, {ast: Look(q)}): Look(mk(Alternative(mk(Try(optimise(p))), optimise(q))));
      // NegLook(NegLook(p)) = Look(p)
      case NegLook({ast: NegLook(p)}): Look(optimise(p));
      // Look(NegLook(p)) = NegLook(p)
      case Look({ast: NegLook(p)}): NegLook(optimise(p));
      // NegLook(Look(p)) = NegLook(p)
      case NegLook({ast: Look(p)}): NegLook(optimise(p));
      // NegLook(Try(p) | q) = NegLook(p) >> NegLook(q)
      case NegLook({ast: Alternative({ast: Try(p)}, q)}): Right(mk(NegLook(optimise(p))), mk(NegLook(optimise(q))));
      // NegLook(p) | NegLook(q) = NegLook(Look(p) >> Look(q))
      case Alternative({ast: NegLook(p)}, {ast: NegLook(q)}): NegLook(mk(Right(mk(Look(optimise(p))), mk(Look(optimise(q))))));
      // Pure(x) >> p = p
      case Right({ast: Pure(_)}, {ast: p}): p;
      // p << Pure(x) = p
      case Left({ast: p}, {ast: Pure(_)}): p;
      // (p >> Pure(x)) >> q = p >> q
      case Right({ast: Right(p, {ast: Pure(_)})}, q): Right(optimise(p), optimise(q));
      case _: return parser;
    }));
  }

  static function compile(parser:ParserExpr):Expr {
    var varCtr = 0;
    var stack:Array<Expr> = [];
    var scopes = [[]];
    var into = scopes[0];
    function scope(f:()->Void):Array<Expr> {
      scopes.push(into = []);
      f();
      var ret = scopes.pop();
      into = scopes[scopes.length - 1];
      return ret;
    }
    var vars = [];
    function freshNoDecl(?type:ComplexType):Expr {
      var name = '_huxly_var${varCtr++}';
      return macro $i{name};
    }
    function fresh(?type:ComplexType):Expr {
      var name = '_huxly_var${varCtr++}';
      vars.push({
        expr: EVars([{
          name: name,
          type: type,
          expr: null,
        }]),
        pos: Context.currentPos(),
      });
      return macro $i{name};
    }
    function c(parser:ParserExpr):Void {
      switch (parser.ast) {
        case Symbol(id):
          var slot = fresh();
          stack.push(slot);
          into.push(macro $slot = $i{id}());
        case Pure(e): // stack -> Type(e), stack
          var slot = fresh();
          stack.push(slot);
          into.push(macro $slot = $e);
        case Satisfy(e): // stack -> Int, stack
          var slot = fresh((macro : Int));
          stack.push(slot);
          var char = macro _huxly_input.get(_huxly_inputPos >= _huxly_input.length ? throw "eof" : _huxly_inputPos++);
          into.push(macro $slot = $char);
          into.push(macro if (!$e{e(slot)}) throw "unsat");
        case Try(p):
          var p = scope(() -> c(p));
          var pos = fresh((macro : Int));
          into.push(macro $pos = _huxly_inputPos);
          into.push(macro try $b{p} catch (e:Dynamic) { _huxly_inputPos = $pos; throw "fail"; });
        case Look(p):
          var pos = fresh((macro : Int));
          into.push(macro $pos = _huxly_inputPos);
          c(p);
          //stack.pop();
          into.push(macro _huxly_inputPos = $pos);
        case NegLook(p):
          var pos = fresh((macro : Int));
          into.push(macro $pos = _huxly_inputPos);
          var p = scope(() -> c(p));
          stack.pop();
          stack.push(null);
          p.push(macro true);
          into.push(macro if (try $b{p} catch (e:Dynamic) { _huxly_inputPos = $pos; false; }) throw "neglook fail");
        case Apply(l, r): // stack -> Type(r), Type(l), stack -> Type(l(r)), stack
          c(l);
          var f = stack.pop();
          c(r);
          var arg = stack.pop();
          var slot = fresh();
          stack.push(slot);
          into.push(macro $slot = $f($arg));
        case Left(l, r): // stack -> Type(l), stack
          c(l);
          c(r);
          stack.pop();
        case Right(l, r): // stack -> Type(r), stack
          c(l);
          stack.pop();
          c(r);
        case Alternative(l, r):
          var res = fresh();
          var l = scope(() -> c(l));
          var lRes = stack.pop();
          l.push(macro $res = $lRes);
          var r = scope(() -> c(r));
          var rRes = stack.pop();
          r.push(macro $res = $rRes);
          var pos = fresh((macro : Int));
          into.push(macro $pos = _huxly_inputPos);
          stack.push(res);
          r.unshift(macro if (_huxly_inputPos != $pos) throw e);
          into.push(macro try $b{l} catch (e:Dynamic) $b{r});
        case Branch(b, l, r):
          c(b);
          var either = stack.pop();
          var leftSrc = freshNoDecl();
          stack.push(leftSrc);
          var l = scope(() -> c(l));
          var leftRes = stack.pop();
          var rightSrc = freshNoDecl();
          stack.push(rightSrc);
          var r = scope(() -> c(r));
          var rightRes = stack.pop();
          var res = fresh();
          stack.push(res);
          into.push(macro $res = (switch ($either) {
            case Left($leftSrc): $b{l}; $leftRes;
            case Right($rightSrc): $b{r}; $rightRes;
          }));
        case Empty: // stack -> null, stack
          stack.push(macro null);
          into.push(macro throw "empty");
        case _: trace(parser.ast); throw "!";
      }
    }
    c(parser);
    into = vars.concat(into);
    into.push(stack[stack.length - 1]);
    return macro $b{into};
  }
}

typedef ParserExpr = {
  expr:Expr,
  ast:ParserAst<ParserExpr>,
};

enum ParserAst<T> {
  // only allowed before symbol resolution
  Symbol(_:String);

  // main
  Pure(_:Expr);
  Satisfy(_:Expr->Expr);
  Try(_:T);
  Look(_:T);
  NegLook(_:T);
  Apply(l:T, r:T);
  Left(l:T, r:T);
  Right(l:T, r:T);
  Alternative(l:T, r:T);
  Empty;
  Branch(b:T, l:T, r:T);
}
