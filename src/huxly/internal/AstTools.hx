package huxly.internal;

#if macro

class AstTools {
  public static function mk(ast:Ast.AstKind<Ast>):Ast {
    return {expr: null, ast: ast};
  }

  public static function map(ast:Ast, f:Ast->Ast):Ast {
    return {expr: ast.expr, ast: (switch (ast.ast) {
      case Try(p): Try(f(p));
      case Look(p): Look(f(p));
      case NegLook(p): NegLook(f(p));
      case Apply(l, r): Apply(f(l), f(r));
      case Left(l, r): Left(f(l), f(r));
      case Right(l, r): Right(f(l), f(r));
      case Alternative(l, r): Alternative(f(l), f(r));
      case Branch(b, l, r): Branch(f(b), f(l), f(r));
      case Let(reg, init, p): Let(reg, init, f(p));
      case Fixpoint(index, p): Fixpoint(index, f(p));
      case _: ast.ast;
    })};
  }
}

#end
