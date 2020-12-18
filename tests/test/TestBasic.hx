package test;

import huxly.Parser.ofSyntax as p;

class TestBasic extends Test {
  function testDefinitionVariants() {
    eq(p(123).parseString(""), 123);
    eq(p(pure(123)).parseString(""), 123);
    eq(p({
      var main = pure(123);
    }).parseString(""), 123);
    eq(TestBasicClassVariant.parseString(""), 123);
  }

  function testPure() {
    eq(p(123).parseString(""), 123);
    eq(p("foo").parseString(""), "foo");
    eq(p(true).parseString(""), true);
    aeq(p(pure([])).parseString(""), []);
  }

  function testString() {
    eq(p(string("abc")).parseString("abc"), "abc");
    eq(p(string("abc")).parseString("abcdef"), "abc");
    exc(() -> p(string("abc")).parseString("xyz"));
    exc(() -> p(string("abc")).parseString("xyzabc"));
  }

  function testChar() {
    eq(p(char("abc")).parseString("a"), "a".code);
    eq(p(char("a"..."z")).parseString("a"), "a".code);
    eq(p(char("a"..."z")).parseString("z"), "z".code);
    exc(() -> p(char("a")).parseString("b"));
  }

  function testEof() {
    exc(() -> p(eof).parseString("a"));
    eq(p(eof).parseString(""), null);
  }

  function testSyntax() {
    eq(p(1 >> 2).parseString(""), 2);
    eq(p(1 << 2).parseString(""), 1);
    eq(p(pure(e -> e * 2) * 1).parseString(""), 2);
    eq(p(1 | 2).parseString(""), 1);
    eq(p(empty | 2).parseString(""), 2);
    eq(p(1 | {}).parseString(""), 1);
    exc(() -> p({}).parseString(""));
  }

  function testClosure() {
    var x = "foo";
    eq(p(pure(x)).parseString(""), "foo");

    var arr = [];
    eq(p(impure(arr.push(1)) >> impure(arr.push(2)) >> pure(123)).parseString(""), 123);
    aeq(arr, [1, 2]);
  }
}

// for testDefinitionVariants
class TestBasicClassVariant extends huxly.Parser<Int> {
  var main = pure(123);
}
