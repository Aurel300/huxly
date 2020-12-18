package test;

import huxly.Parser.ofSyntax as p;

class TestCombinators extends Test {
  function testMany() {
    aeq(p(many(char("abc"))).parseString("abcd"), [97, 98, 99]);
    aeq(p(many(string("abc"))).parseString("abcabcabccba"), ["abc", "abc", "abc"]);
    aeq(p(many((try string("foo")) | string("bar"))).parseString("foobarbarfooofoo"), ["foo", "bar", "bar", "foo"]);
  }
}
