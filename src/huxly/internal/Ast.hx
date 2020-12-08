package huxly.internal;

#if macro

typedef Ast = {
  expr:Expr,
  ast:AstKind<Ast>,
};

enum AstKind<T> {
  Symbol(_:String);
  Reg(_:Int);
  Pure(_:Expr);
  Impure(_:Expr);
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
  Let(reg:Int, init:Expr, _:T);
  Recurse(index:Int);
  Fixpoint(index:Int, _:T);
}

#end
