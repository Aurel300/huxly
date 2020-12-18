package test;

class TestCsv extends Test {
  function testCsv() {
    aeq(TestCsvParser.parseString(""), []);
    aeq(TestCsvParser.parseString("a,b\n"), [["a", "b"]]);
    aeq(TestCsvParser.parseString("a,b,\n"), [["a", "b", ""]]);
    aeq(TestCsvParser.parseString("\n\n\n,,,c,\n"), [[""], [""], [""], ["", "", "", "c", ""]]);
  }
}

class TestCsvParser extends huxly.Parser<Array<Array<String>>> {
  var main = endBy(line, char("\n")) << eof;
  var line = sepBy(cell, char(","));
  var cell = pure(e -> e.map(String.fromCharCode).join("")) * many(noneOf(",\n"));
}
