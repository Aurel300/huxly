package huxly.internal;

#if macro

class Optimiser {
  static final F_ID = macro e -> e;

  /**
    Optimises a parser AST to simpler/fewer terms.
   */
  public static function optimise(parser:Ast):Ast {
    return optimise(mk(switch (parser.ast) {
      // Pure(id) * p = p
      case Apply({ast: Pure(F_ID)}, {ast: p}): p;
      // Pure(f) * Pure(x) = Pure(f(x))
      case Apply({ast: Pure(f)}, {ast: Pure(x)}): Pure(macro $f($x));
      // u * Pure(x) = Pure(f -> f(x)) * u
      case Apply(u, {ast: Pure(x)}): Apply(mk(Pure(macro f -> f($x))), optimise(u));
      // TODO 4
      // (p | q) | r = p | (q | r)
      case Alternative({ast: Alternative(p, q)}, r): Alternative(optimise(p), mk(Alternative(optimise(q), optimise(r))));
      // {} | p = p
      case Alternative({ast: Empty}, {ast: p}): p;
      // p | {} = p
      case Alternative({ast: p}, {ast: Empty}): p;
      // {} * p = {}
      case Apply({ast: Empty}, _): Empty;
      // Pure(x) | p = Pure(x)
      case Alternative({ast: Pure(x)}, _): Pure(x);
      //case Branch({ast: Pure(Left(x))}, p, q): Apply(p, mk(Pure(x)));
      //case Branch({ast: Pure(Right(y))}, p, q): Apply(q, mk(Pure(y)));
      //case Branch(b, Pure(f), Pure(g)): Apply(mk(Pure(Either(f, g))), b);
      // Branch(x >> y, p, q) = x >> Branch(y, p, q)
      case Branch({ast: Right(x, y)}, p, q): Right(optimise(x), mk(Branch(optimise(y), optimise(p), optimise(q))));
      //case Branch(b, p, {ast: Empty}): Branch(mk(Apply(mk(Pure(F_SWAP)), b)), Empty, p);
      // TODO 14
      // Try(Satisfy(f)) = Satisfy(f)
      case Try({ast: Satisfy(f)}): Satisfy(f);
      // Try(NegLook(p)) = NegLook(p)
      case Try({ast: NegLook(p)}): NegLook(optimise(p));
      // Look({}) = {}
      case Look({ast: Empty}): Empty;
      // Look(Pure(x)) = Pure(x)
      case Look({ast: Pure(x)}): Pure(x);
      // NegLook({}) = Pure(null) // null as Unit
      case NegLook({ast: Empty}): Pure(macro null);
      // NegLook(Pure(x)) = {}
      case NegLook({ast: Pure(x)}): Empty;
      // Look(Look(p)) = Look(p)
      case Look({ast: Look(p)}): Look(optimise(p));
      // Look(p) | Look(q) = Look(Try(p) | q)
      case Alternative({ast: Look(p)}, {ast: Look(q)}): Look(mk(Alternative(mk(Try(optimise(p))), optimise(q))));
      // NegLook(NegLook(p)) = Look(p)
      case NegLook({ast: NegLook(p)}): Look(optimise(p));
      // Look(NegLook(p)) = NegLook(p)
      case Look({ast: NegLook(p)}): NegLook(optimise(p));
      // NegLook(Look(p)) = NegLook(p)
      case NegLook({ast: Look(p)}): NegLook(optimise(p));
      // NegLook(Try(p) | q) = NegLook(p) >> NegLook(q)
      case NegLook({ast: Alternative({ast: Try(p)}, q)}): Right(mk(NegLook(optimise(p))), mk(NegLook(optimise(q))));
      // NegLook(p) | NegLook(q) = NegLook(Look(p) >> Look(q))
      case Alternative({ast: NegLook(p)}, {ast: NegLook(q)}): NegLook(mk(Right(mk(Look(optimise(p))), mk(Look(optimise(q))))));
      // Pure(x) >> p = p
      case Right({ast: Pure(_)}, {ast: p}): p;
      // p << Pure(x) = p
      case Left({ast: p}, {ast: Pure(_)}): p;
      // (p >> Pure(x)) >> q = p >> q
      case Right({ast: Right(p, {ast: Pure(_)})}, q): Right(optimise(p), optimise(q));
      case _: return parser;
    }));
  }
}

#end
