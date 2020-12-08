package huxly.internal;

#if macro

typedef CfgVar = {
  id:Int,
  isInt:Bool,
  used:Bool,
  ?inlineExpr:Expr,
  ?name:String,
  ?ident:Expr,
};

enum CfgBody {
  None;
  CheckChars(n:Int);
  CheckSatisfy(v:CfgVar, e:Expr->Expr);
  CheckPos(v:CfgVar);
  AssignExpr(v:CfgVar, e:Expr);
  AssignVar(v:CfgVar, src:CfgVar);
  Apply(v:CfgVar, l:CfgVar, r:CfgVar);
  FixpointCall(stack:CfgVar, ret:Cfg);
  FixpointReturn(stack:CfgVar);
  Call(v:CfgVar, id:String);
  GetPos(v:CfgVar);
  SetPos(v:CfgVar);
  Return(v:CfgVar);
  Fail;
}

class Cfg {
  public static function swap(a:Cfg, b:Cfg):Void {
    if (a.jumpTarget || b.jumpTarget) throw "cannot swap jump target";
    if (a.next.length != 1 || a.next[0] != b || b.prev.length != 1 || b.prev[0] != a || a.error != b.error) throw "cannot swap";
    var origPrev = a.prev;
    var origNext = b.next;
    a.next = origNext;
    a.prev = [b];
    b.next = [a];
    b.prev = origPrev;
    for (p in origPrev) p.next = p.next.replace(a, b);
    for (n in origNext) n.prev = n.prev.replace(b, a);
  }

  public static var blockCtr = 0;

  public var id:Int;
  public var result:CfgVar = null;
  public var body:CfgBody;
  public var error:Null<Cfg>;
  public var prev:Array<Cfg> = [];
  public var next:Array<Cfg> = [];
  public var jumpTarget:Bool = false;

  public function new() {
    id = blockCtr++;
  }

  public function link(then:Cfg):Void {
    next.push(then);
    then.prev.push(this);
  }

  public function remove():Void {
    if (jumpTarget) throw "cannot remove jump target";
    if (next.length == 0) {
      for (p in prev) {
        p.next.remove(this);
      }
      return;
    }
    var n = next[0];
    if (prev.length == 0) {
      n.prev.remove(this);
      return;
    }
    if (next.length != 1 || prev.length != 1) throw "cannot remove";
    var p = prev[0];
    n.prev = n.prev.replace(this, p);
    p.next = p.next.replace(this, n);
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
      for (n in curr.next) {
        if (n != null && !seen[n.id]) queue.push(n);
      }
    }
  }

  /*public function dump():Void {
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
  }*/
}

#end
