package huxly.internal;

#if macro

import huxly.internal.Cfg.CfgVar;
import huxly.internal.Cfg.CfgBody;

class Compiler {
  /**
    Compiles a parser AST into a Haxe expression.
   */
  public static function compile(parser:Ast):Expr {
    var res = astToCfg(parser);
    res.cfg = optimiseEmpty(res.cfg);
    optimiseCheckChars(res.cfg);
    //simplify(res.cfg);
    //propagateChars(res.cfg);
    //cfg.dump();
    var expr = cfgToExpr(res.vars, res.cfg);
    //Sys.println(new haxe.macro.Printer().printExpr(expr));
    return expr;
  }

  static function astToCfg(ast:Ast):{vars:Array<CfgVar>, cfg:Cfg} {
    var varCtr = 0;
    var vars:Array<CfgVar> = [];
    function fresh(isInt:Bool):CfgVar {
      var ret:CfgVar = {
        id: varCtr++,
        isInt: isInt,
        used: false,
      };
      vars.push(ret);
      return ret;
    }
    var compiled:Map<Ast, Cfg> = [];
    Cfg.blockCtr = 0;
    var handlers:Array<Cfg> = [new Cfg()];
    handlers[0].body = Fail;
    function c(a:Ast, prev:Cfg):Cfg {
      function mk(link:Null<Cfg>, body:CfgBody, ?res:CfgVar):Cfg {
        var ret = new Cfg();
        ret.error = handlers[handlers.length - 1];
        ret.body = body;
        if (body != null) switch (body) {
          case CheckPos(v): v.used = true;
          case AssignVar(_, src): src.used = true;
          case Apply(_, l, r): l.used = r.used = true;
          case SetPos(v): v.used = true;
          case Return(v): v.used = true;
          case _:
        }
        ret.result = res;
        if (link != null) {
          link.link(ret);
        }
        return ret;
      }
      // TODO: caching
      /*var cached = compiled[a];
      if (cached != null) {
        if (cached.prev.indexOf(prev) == -1) cached.prev.push(prev);
        return cached;
      }*/
      return (switch (a.ast) {
        case Symbol(id):
          // TODO: stack frames, TCO
          //c(symbols[id], prev);
          var res = fresh(false);
          mk(prev, Call(res, id), res);
        case Pure(e = {expr:
          EConst(CIdent("true" | "false" | "null") | CInt(_) | CFloat(_) | CString(_)) | EFunction(_, _)
        }):
          // TODO: better inlinability check
          var res = fresh(false);
          res.inlineExpr = e;
          mk(prev, None, res);
        case Pure(e):
          var res = fresh(false);
          mk(prev, AssignPure(res, e), res);
        case Satisfy(e):
          var res = fresh(true);
          var pre = mk(prev, CheckChars(1));
          mk(pre, CheckSatisfy(res, e), res);
        case Try(p):
          var pos = fresh(true);
          var pre = mk(prev, GetPos(pos));
          var handler = mk(null, SetPos(pos));
          mk(handler, Fail);
          handlers.push(handler);
          var mid = c(p, pre);
          handlers.pop();
          mk(mid, None, mid.result);
        case Look(p):
          var pos = fresh(true);
          var pre = mk(prev, GetPos(pos));
          var mid = c(p, pre);
          mk(mid, SetPos(pos), mid.result);
        case NegLook(p):
          var handler = mk(null, None);
          handlers.push(handler);
          var mid = c(p, prev);
          handlers.pop();
          mk(mid, Fail);
          handler;
        case Apply(l, r):
          var res = fresh(false);
          var l = c(l, prev);
          var r = c(r, l);
          mk(r, Apply(res, l.result, r.result), res);
        case Left(l, r):
          var l = c(l, prev);
          var r = c(r, l);
          mk(r, None, l.result);
        case Right(l, r):
          var l = c(l, prev);
          c(r, l);
        case Alternative(l, r):
          var pos = fresh(true);
          var res = fresh(false);
          var pre = mk(prev, GetPos(pos));
          var handler = mk(null, CheckPos(pos));
          handlers.push(handler);
          var l = c(l, pre);
          handlers.pop();
          var postL = mk(l, AssignVar(res, l.result));
          var r = c(r, handler);
          var postR = mk(r, AssignVar(res, r.result));
          var post = mk(postL, None, res);
          postR.link(post);
          post;
        case Empty:
          mk(prev, Fail);
        case _: throw "!"; null;
      });
    }
    var initial = new Cfg();
    initial.body = None;
    var body = c(ast, initial);
    var last = new Cfg();
    body.link(last);
    body.result.used = true;
    last.body = Return(body.result);
    return {vars: vars, cfg: initial};
  }

  static function optimiseEmpty(root:Cfg):Cfg {
    var ret = root;
    root.iter(cfg -> {
      if (cfg.body != None || cfg.next == null) return;
      if (cfg == ret) ret = cfg.next;
      cfg.remove();
    });
    return ret;
  }

  static function optimiseCheckChars(root:Cfg):Void {
    var queue = [];
    root.iter(cfg -> {
      if (cfg.body.match(CheckChars(_))) {
        queue.push(cfg);
      }
    });
    while (queue.length > 0) {
      var curr = queue.pop();
      var currN = (switch (curr.body) {
        case CheckChars(n): n;
        case _: throw "!";
      });
      while (curr.prev.length == 1 && curr.error == curr.prev[0].error) {
        var prev = curr.prev[0];
        switch (prev.body) {
          case CheckChars(n):
            prev.body = CheckChars(n + currN);
            if (queue.indexOf(prev) == -1) queue.push(prev);
            curr.remove();
            break;
          case CheckSatisfy(_) | AssignVar(_, _): Cfg.swap(prev, curr);
          case _: break;
        }
      }
    }
  }

  static function cfgToExpr(vars:Array<CfgVar>, cfg:Cfg):Expr {
    for (v in vars) {
      if (v.used) {
        v.name = '_huxly_var${v.id}';
        v.ident = macro $i{v.name};
      }
    }
    function read(v:CfgVar):Expr {
      if (v.inlineExpr != null)
        return v.inlineExpr;
      return v.ident;
    }
    function write(v:CfgVar, e:Expr):Expr {
      if (v.inlineExpr != null) throw "cannot write to inlined var";
      if (v.used)
        return macro $e{v.ident} = $e;
      return e;
    }
    var cases = [];
    var generated = new Map();
    function error(cfg:Cfg):Expr {
      return cfg.error != null ? macro {
        _huxly_state = $v{cfg.error.id};
        continue;
      } : macro throw "fail";
    }
    cfg.iter(cfg -> {
      if (generated[cfg.id]) return;
      var body = [];
      var curr = cfg;
      do {
        generated[curr.id] = true;
        if (curr.body != None) body.push(switch (curr.body) {
          //*
          case CheckChars(_) | CheckSatisfy(_, _) | CheckPos(_):
            var cond = macro false;
            var advance = 0;
            do {
              generated[curr.id] = true;
              cond = macro $cond || $e{(switch (curr.body) {
                case CheckChars(n): macro _huxly_inputPos + $v{n} > _huxly_input.length;
                case CheckSatisfy(v, e): macro !($e{e(write(v, macro _huxly_input.get(_huxly_inputPos + $v{advance++})))});
                case CheckPos(v): macro _huxly_inputPos != $e{read(v)};
                case _: throw "!";
              })};
              if (curr.next == null
                || curr.next.prev.length != 1
                || !curr.next.body.match(CheckChars(_) | CheckSatisfy(_, _) | CheckPos(_))
                || curr.error != curr.next.error) break;
              curr = curr.next;
            } while (curr != null && curr.prev.length == 1);
            macro if ($cond) $e{error(curr)} else _huxly_inputPos += $v{advance};
          /*/
          case CheckChars(n): macro if (_huxly_inputPos + $v{n} > _huxly_input.length) $e{error(curr)};
          case CheckSatisfy(v, e):
            var assign = write(v, macro _huxly_input.get(_huxly_inputPos++));
            macro if (!$e{e(assign)}) $e{error(curr)};
          case CheckPos(v): macro if (_huxly_inputPos != $e{read(v)}) $e{error(curr)};
          //*/
          case AssignPure(v, e): write(v, e);
          case AssignVar(v, src): write(v, read(src));
          case Apply(v, l, r): write(v, macro $e{read(l)}($e{read(r)}));
          case Call(v, id): write(v, macro try $i{id}() catch (e:Dynamic) $e{error(curr)});
          case GetPos(v): write(v, macro _huxly_inputPos);
          case SetPos(v): macro _huxly_inputPos = $e{read(v)};
          case Return(v): macro return $e{read(v)};
          case Fail: error(curr);
          case _: throw "!";
        });
        if (curr.next == null || curr.next.prev.length != 1) break;
        curr = curr.next;
      } while (curr != null && curr.prev.length == 1);
      body.push(curr.next != null ? macro $v{curr.next.id} : macro -1);
      cases.push({
        values: [macro $v{cfg.id}],
        guard: null,
        expr: macro $b{body},
      });
    });
    var switchExpr = {expr: ESwitch(macro _huxly_state, cases, macro return null), pos: Context.currentPos()};
    var block = [];
    block.push(macro var _huxly_state = $v{cfg.id});
    block.push({expr: EVars([ for (v in vars) if (v.used) {
      name: v.name,
      type: v.isInt ? (macro : Int) : null,
      expr: v.isInt ? macro 0 : macro null,
    } ]), pos: Context.currentPos()});
    block.push(macro while (true) _huxly_state = $switchExpr);
    block.push(macro return null);
    return macro $b{block};
  }
}

#end
