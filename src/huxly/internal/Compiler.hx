package huxly.internal;

#if macro

class Compiler {
  /**
    Compiles a parser AST into a Haxe expression.
   */
  public static function compile(parser:Ast):Expr {
    var res = astToCfg(parser);
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
    function fresh(init:Expr):CfgVar {
      var name = '_huxly_var${varCtr++}';
      var ret:CfgVar = {
        decl: {
          expr: EVars([{
            name: name,
            type: null, // type,
            expr: init,
          }]),
          pos: Context.currentPos(),
        },
        ident: macro $i{name},
        used: false,
      };
      vars.push(ret);
      return ret;
    }
    var compiled:Map<Ast, Cfg> = [];
    Cfg.blockCtr = 0;
    var handlers:Array<Cfg> = [new Cfg()];
    handlers[0].body = macro throw "fail";
    function topHandler():Cfg return handlers[handlers.length - 1];
    function error():Expr {
      return macro {
        _huxly_state = $v{topHandler().id};
        continue;
      };
    }
    function write(v:CfgVar):Expr {
      return v.ident;
    }
    function read(v:CfgVar):Expr {
      v.used = true;
      return v.ident;
    }
    function c(a:Ast, prev:Cfg):Cfg {
      function mk(link:Null<Cfg>):Cfg {
        var ret = new Cfg();
        ret.error = topHandler();
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
          var ret = mk(prev);
          ret.result = fresh(macro null);
          ret.body = macro try $e{write(ret.result)} = $i{id}() catch (e:Dynamic) $e{error()};
          ret;
        case Pure(e):
          var ret = mk(prev);
          ret.result = fresh(macro null);
          ret.body = macro $e{write(ret.result)} = $e;
          ret;
        case Satisfy(e):
          var ret = mk(prev);
          ret.result = fresh(macro 0);
          ret.needChars = 1;
          var assign = macro $e{write(ret.result)} = _huxly_input.get(_huxly_inputPos++);
          ret.body = macro if (!$e{e(assign)}) $e{error()};
          ret;
        case Try(p):
          var pos = fresh(macro 0);
          var pre = mk(prev);
          pre.body = macro $e{write(pos)} = _huxly_inputPos;
          var handler = mk(null);
          handler.body = macro {
            _huxly_inputPos = $e{read(pos)};
            $e{error()};
          };
          handlers.push(handler);
          var mid = c(p, pre);
          handlers.pop();
          var post = mk(mid);
          handler.link(post);
          post.result = mid.result;
          post;
        case Look(p):
          var pos = fresh(macro 0);
          var pre = mk(prev);
          pre.body = macro $e{write(pos)} = _huxly_inputPos;
          var mid = c(p, pre);
          var post = mk(mid);
          post.body = macro _huxly_inputPos = $e{read(pos)};
          post.result = mid.result;
          post;
        case NegLook(p):
          var handler = mk(null);
          handler.result = null;
          handlers.push(handler);
          var mid = c(p, prev);
          handlers.pop();
          var post = mk(mid);
          post.result = null;
          post.body = error();
          handler;
        case Apply(l, r):
          var l = c(l, prev);
          var r = c(r, l);
          var post = mk(r);
          post.result = fresh(macro null);
          post.body = macro $e{write(post.result)} = $e{read(l.result)}($e{read(r.result)});
          post;
        case Left(l, r):
          var l = c(l, prev);
          var r = c(r, l);
          var post = mk(r);
          post.result = l.result;
          post;
        case Right(l, r):
          var l = c(l, prev);
          c(r, l);
        case Alternative(l, r):
          var pos = fresh(macro 0);
          var res = fresh(macro null);
          var pre = mk(prev);
          pre.body = macro $e{write(pos)} = _huxly_inputPos;
          var handler = mk(null);
          handler.body = macro if (_huxly_inputPos != $e{read(pos)}) $e{error()};
          handlers.push(handler);
          var l = c(l, pre);
          handlers.pop();
          var postL = mk(l);
          postL.body = macro $e{write(res)} = $e{read(l.result)};
          var r = c(r, handler);
          var postR = mk(r);
          postR.body = macro $e{write(res)} = $e{read(r.result)};
          var post = mk(postL);
          postR.link(post);
          post.result = res;
          post;
        case Empty:
          var ret = mk(prev);
          ret.result = null;
          ret.body = error();
          ret;
        case _: throw "!"; null;
      });
    }
    var initial = new Cfg();
    var body = c(ast, initial);
    var last = new Cfg();
    body.link(last);
    last.body = macro return $e{read(body.result)};
    return {vars: vars, cfg: initial};
  }

  static function simplify(cfg:Cfg):Void {
    var seen = new Map();
    var queue = [cfg];
    function mergeExpr(a:Expr, b:Expr):Expr {
      if (a == null) return b;
      if (b == null) return a;
      return (switch [a.expr, b.expr] {
        case [EBlock(as), EBlock(bs)]: {expr: EBlock(as.concat(bs)), pos: a.pos};
        case [EBlock(as), _]: {expr: EBlock(as.concat([b])), pos: a.pos};
        case [_, EBlock(bs)]: {expr: EBlock([a].concat(bs)), pos: a.pos};
        case [_, _]: {expr: EBlock([a, b]), pos: a.pos};
      });
    }
    while (queue.length > 0) {
      var curr = queue.shift();
      if (seen[curr.id]) continue;
      seen[curr.id] = true;
      if (curr.next.length == 1 && curr.next[0].prev.length == 1 && curr.error == curr.next[0].error) {
        var next = curr.next[0];
        curr.body = mergeExpr(curr.body, next.body);
        curr.needChars += next.needChars;
        curr.next = next.next;
        for (b in next.next) b.prev = b.prev.map(op -> op == next ? curr : op);
        if (curr.error != null) curr.error.prev.remove(next);
        queue.push(curr);
        seen[curr.id] = false;
      }
      if (curr.error != null && !seen[curr.error.id]) queue.push(curr.error);
      for (n in curr.next) if (!seen[n.id]) queue.push(n);
    }
  }

  /*
  static function propagateChars(cfg:Cfg):Void {
    cfg.iter(cfg -> {
      if (cfg.needChars > 0) {
        var curr = cfg;
        while (curr.prev.length == 1 && curr.prev[0].next.length == 1 && curr.error == curr.prev[0].error) {
          curr.prev[0].needChars += curr.needChars;
          curr.needChars = 0;
          curr = curr.prev[0];
        }
      }
    });
  }
  */

  static function cfgToExpr(vars:Array<CfgVar>, cfg:Cfg):Expr {
    var cases = [];
    function walk(e:Expr):Expr {
      return (switch (e.expr) {
        case EBinop(OpAssign, {expr: EConst(CIdent(id))}, init):
          if (!id.startsWith("_huxly_var"))
            return e;
          var cfgVar = vars[Std.parseInt(id.substr("_huxly_var".length))];
          if (!cfgVar.used)
            return init;
          trace(id, cfgVar.used);
          e;
        case _: haxe.macro.ExprTools.map(e, walk);
      });
    }
    cfg.iter(cfg -> {
      var body = [];
      if (cfg.needChars > 0) body.push(macro if (_huxly_inputPos + $v{cfg.needChars} > _huxly_input.length) {
        _huxly_state = $v{cfg.error.id};
        continue;
      });
      if (cfg.body != null) body.push(walk(cfg.body));
      if (cfg.next.length > 0) body.push(macro $v{cfg.next[0].id});
      cases.push({
        values: [macro $v{cfg.id}],
        guard: null,
        expr: macro $b{body},
      });
    });
    var switchExpr = {expr: ESwitch(macro _huxly_state, cases, macro return null), pos: Context.currentPos()};
    var block = [];
    block.push(macro var _huxly_state = $v{cfg.id});
    for (v in vars) if (v.used) block.push(v.decl);
    block.push(macro while (true) _huxly_state = $switchExpr);
    block.push(macro return null);
    return macro $b{block};
  }
}

typedef CfgVar = {
  decl:Expr,
  ident:Expr,
  used:Bool,
};

class Cfg {
  public static var blockCtr = 0;

  public var id:Int;
  public var result:CfgVar = null;
  public var body:Expr;
  public var error:Null<Cfg>;
  public var needChars:Int = 0;
  public var prev:Array<Cfg> = [];
  public var next:Array<Cfg> = [];

  public function new() {
    id = blockCtr++;
  }

  public function link(then:Cfg):Void {
    next.push(then);
    then.prev.push(this);
  }

  public function iter(f:Cfg->Void):Void {
    var seen = new Map();
    var queue = [this];
    while (queue.length > 0) {
      var curr = queue.shift();
      if (seen[curr.id]) continue;
      seen[curr.id] = true;
      f(curr);
      if (curr.error != null && !seen[curr.error.id]) queue.push(curr.error);
      for (n in curr.next) if (!seen[n.id]) queue.push(n);
    }
  }

  public function dump():Void {
    var printer = new haxe.macro.Printer();
    iter(curr -> {
      Sys.println('// block ${curr.id}');
      if (curr.needChars > 0) Sys.println('// need chars: ${curr.needChars}');
      if (curr.body != null)
        Sys.println(printer.printExpr(curr.body));
      else
        Sys.println("// no body");
      if (curr.error != null) Sys.println('// error handler: ${curr.error.id}');
      if (curr.result != null) Sys.println('// result: ${printer.printExpr(curr.result.ident)}');
      if (curr.next.length > 0) Sys.println('// next: ${curr.next.map(b -> b.id).join(", ")}');
      Sys.println("");
    });
  }
}

#end
