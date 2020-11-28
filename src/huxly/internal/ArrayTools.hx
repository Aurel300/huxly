package huxly.internal;

class ArrayTools {
  public static function replace<T>(arr:Array<T>, orig:T, rep:T):Array<T> {
    return arr.map(e -> e == orig ? rep : e);
  }
}
