package huxly.internal;

#if macro

class AstTools {
  public static function mk(ast:Ast.AstKind<Ast>):Ast {
    return {expr: null, ast: ast};
  }

  public static function map(ast:Ast):Ast {
    return {expr: ast.expr, ast: (switch (ast.ast) {
      case Try(p): Try(map(p));
      case Look(p): Look(map(p));
      case NegLook(p): NegLook(map(p));
      case Apply(l, r): Apply(map(l), map(r));
      case Left(l, r): Left(map(l), map(r));
      case Right(l, r): Right(map(l), map(r));
      case Alternative(l, r): Alternative(map(l), map(r));
      case Branch(b, l, r): Branch(map(b), map(l), map(r));
      case _: ast.ast;
    })};
  }
}

#end
