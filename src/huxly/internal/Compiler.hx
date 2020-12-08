package huxly.internal;

#if macro

import huxly.internal.Cfg.CfgVar;
import huxly.internal.Cfg.CfgBody;

class Compiler {
  /**
    Compiles a parser AST into a Haxe expression.
   */
  public static function compile(parser:Ast):Expr {
    var res = astToCfg(Optimiser.optimise(parser));
    res.cfg = optimiseEmpty(res.cfg);
    //checkLinks(res.cfg);
    optimiseCheckChars(res.cfg);
    //res.cfg.dump();
    var expr = cfgToExpr(res.vars, res.regs, res.cfg);
    //Sys.println(new haxe.macro.Printer().printExpr(expr));
    return expr;
  }

  static function astToCfg(ast:Ast):{vars:Array<CfgVar>, regs:Map<Int, CfgVar>, cfg:Cfg} {
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
    Cfg.blockCtr = 0;
    var handlers:Array<Cfg> = [new Cfg()];
    handlers[0].body = Fail;
    var regs:Map<Int, CfgVar> = [];
    var fixpoints:Map<Int, {retStack:CfgVar, retVar:CfgVar, cfg:Cfg, post:Cfg}> = [];
    function c(a:Ast, prev:Cfg):Cfg {
      function mk(link:Null<Cfg>, body:CfgBody, ?res:CfgVar):Cfg {
        var ret = new Cfg();
        ret.error = handlers[handlers.length - 1];
        ret.body = body;
        if (body != null) switch (body) {
          case CheckPos(v): v.used = true;
          case AssignVar(_, src): src.used = true;
          case Apply(_, l, r): l.used = r.used = true;
          case FixpointCall(stack, ret): stack.used = true;
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
        case Pure(e) | Impure(e):
          var res = fresh(false);
          mk(prev, AssignExpr(res, e), res);
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
        case Let(reg, init, p):
          regs[reg] = fresh(false);
          regs[reg].used = true;
          var pre = mk(prev, AssignExpr(regs[reg], init), regs[reg]);
          c(p, pre);
        case Reg(reg):
          var res = fresh(false);
          res.used = true; // TODO: registers are not resolved until later, need a separate variable usage stage
          mk(prev, AssignVar(res, regs[reg]), res);
        case Fixpoint(index, p):
          var retStack = fresh(false);
          var retVar = fresh(false);
          var jumpTarget = mk(null, None, retVar);
          var pre = mk(prev, AssignExpr(retStack, macro [$v{jumpTarget.id}]));
          var pre2 = mk(pre, None);
          var post = mk(null, FixpointReturn(retStack), retVar);
          fixpoints[index] = {
            retStack: retStack,
            retVar: retVar,
            cfg: pre2,
            post: post,
          };
          var ret = c(p, pre2);
          var retPost = mk(ret, AssignVar(retVar, ret.result), null);
          retPost.link(post);
          fixpoints.remove(index);
          post.link(jumpTarget);
          jumpTarget;
        case Recurse(index):
          if (!fixpoints.exists(index)) throw "!";
          var jumpTarget = mk(null, None, fixpoints[index].retVar);
          jumpTarget.jumpTarget = true;
          var pre = mk(prev, FixpointCall(fixpoints[index].retStack, jumpTarget));
          pre.link(fixpoints[index].cfg);
          fixpoints[index].post.link(jumpTarget);
          jumpTarget;
        case _: throw "!"; null;
      });
    }
    var initial = new Cfg();
    initial.body = None;
    var body = c(ast, initial);
    if (body.result != null) {
      var last = new Cfg();
      body.link(last);
      body.result.used = true;
      last.body = Return(body.result);
    }
    return {vars: vars, regs: regs, cfg: initial};
  }

  static function optimiseEmpty(root:Cfg):Cfg {
    var ret = root;
    root.iter(cfg -> {
      if (cfg.body != None || cfg.next.length != 1 || cfg.prev.length != 1) return;
      if (cfg == ret) ret = cfg.next[0];
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

  static function checkLinks(root:Cfg):Void {
    root.iter(cfg -> {
      var expected = (switch (cfg.body) {
        case FixpointReturn(_): -1;
        case Return(v): 0;
        case Fail: 0;
        case _: 1;
      });
      if (expected == -1) return;
      if (cfg.next.length != expected) throw 'next link count mismatch ${cfg.id}';
    });
  }

  static function cfgToExpr(vars:Array<CfgVar>, regs:Map<Int, CfgVar>, cfg:Cfg):Expr {
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
    function writeNA(v:CfgVar):Expr {
      if (v.inlineExpr != null) throw "cannot write to inlined var";
      return v.ident;
    }
    var cases = [];
    var generated = new Map();
    function error(cfg:Cfg):Expr {
      return cfg.error != null ? macro {
        _huxly_state = $v{cfg.error.id};
        continue;
      } : macro throw "fail";
    }
    function resolveRegisters(e:Expr):Expr {
      return (switch (e) {
        case macro _huxly_registers[$n]:
          var reg = (switch (n.expr) {
            case EConst(CInt(Std.parseInt(_) => reg)): reg;
            case _: throw "!";
          });
          if (!regs.exists(reg)) throw "!";
          read(regs[reg]);
        case _: e.map(resolveRegisters);
      });
    }
    final fuseBlocks = true;
    final fuseConditions = true;
    cfg.iter(cfg -> {
      if (generated[cfg.id]) return;
      var body = [];
      var curr = cfg;
      do {
        generated[curr.id] = true;
        if (curr.body != None) body.push(switch (curr.body) {
          case CheckChars(_) | CheckSatisfy(_, _) | CheckPos(_):
            var cond = macro false;
            var require = 0;
            var advance = 0;
            do {
              generated[curr.id] = true;
              switch (curr.body) {
                case CheckChars(n): require += n;
                case CheckSatisfy(v, e): cond = macro $cond || !($e{e(write(v, macro _huxly_input.get(_huxly_inputPos + $v{advance++})))});
                case CheckPos(v): cond = macro $cond || _huxly_inputPos != $e{read(v)};
                case _: throw "!";
              }
              if (!fuseConditions) break;
              if (curr.next.length != 1
                || curr.next[0].prev.length != 1
                || !curr.next[0].body.match(CheckChars(_) | CheckSatisfy(_, _) | CheckPos(_))
                || curr.error != curr.next[0].error) break;
              curr = curr.next[0];
            } while (curr != null && curr.prev.length == 1);
            if (require > 0) cond = macro _huxly_inputPos + $v{require} > _huxly_input.length || $cond;
            advance > 0
              ? macro if ($cond) $e{error(curr)} else _huxly_inputPos += $v{advance}
              : macro if ($cond) $e{error(curr)};
          case AssignExpr(v, e): write(v, e);
          case AssignVar(v, src): write(v, read(src));
          case Apply(v, l, r): write(v, macro $e{read(l)}($e{read(r)}));
          case FixpointCall(stack, ret): macro $e{writeNA(stack)}.push($v{ret.id});
          case FixpointReturn(stack): macro {
              _huxly_state = $e{read(stack)}.pop();
              continue;
            };
          case Call(v, id): write(v, macro try $i{id}() catch (e:Dynamic) $e{error(curr)});
          case GetPos(v): write(v, macro _huxly_inputPos);
          case SetPos(v): macro _huxly_inputPos = $e{read(v)};
          case Return(v): macro return $e{read(v)};
          case Fail: error(curr);
          case _: throw "!";
        });
        if (!fuseBlocks) break;
        if (curr.next.length != 1 || curr.next[0].prev.length != 1) break;
        curr = curr.next[0];
      } while (curr != null && curr.prev.length == 1);
      body.push(curr.next.length == 1 ? macro $v{curr.next[0].id} : macro -1);
      cases.push({
        values: [macro $v{cfg.id}],
        guard: null,
        expr: resolveRegisters(macro $b{body}),
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
