package huxly.internal;

#if macro

class Compiler {
  /**
    Compiles a parser AST into a Haxe expression.
   */
  public static function compile(parser:Ast):Expr {
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
    function c(parser:Ast):Void {
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

#end