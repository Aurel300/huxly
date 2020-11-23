package huxly.internal;

#if macro

typedef Ast = {
  expr:Expr,
  ast:AstKind<Ast>,
};

enum AstKind<T> {
  Symbol(_:String);
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

#end
