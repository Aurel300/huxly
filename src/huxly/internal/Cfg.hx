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
  AssignPure(v:CfgVar, e:Expr);
  AssignVar(v:CfgVar, src:CfgVar);
  Apply(v:CfgVar, l:CfgVar, r:CfgVar);
  Call(v:CfgVar, id:String);
  GetPos(v:CfgVar);
  SetPos(v:CfgVar);
  Return(v:CfgVar);
  Fail;
}

class Cfg {
  public static function swap(a:Cfg, b:Cfg):Void {
    if (a.next != b || b.prev.length != 1 || b.prev[0] != a || a.error != b.error) throw "cannot swap";
    var origPrev = a.prev;
    var origNext = b.next;
    a.next = origNext;
    a.prev = [b];
    b.next = a;
    b.prev = origPrev;
    for (p in origPrev) p.next = b;
    if (origNext != null) origNext.prev = origNext.prev.replace(b, a);
  }

  public static var blockCtr = 0;

  public var id:Int;
  public var result:CfgVar = null;
  public var body:CfgBody;
  public var error:Null<Cfg>;
  public var prev:Array<Cfg> = [];
  public var next:Cfg;

  public function new() {
    id = blockCtr++;
  }

  public function link(then:Cfg):Void {
    if (next != null) throw "duplicate next link";
    next = then;
    then.prev.push(this);
  }

  public function remove():Void {
    if (next == null) {
      for (p in prev) {
        p.next = null;
      }
      return;
    }
    next.prev.remove(this);
    for (p in prev) {
      if (next.prev.indexOf(p) == -1)
        next.prev.push(p);
      p.next = next;
    }
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
      if (curr.next != null && !seen[curr.next.id]) queue.push(curr.next);
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
