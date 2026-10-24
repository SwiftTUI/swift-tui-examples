// Example texts and derived expectation data: CommonMark 0.31.2 by John MacFarlane.
// https://spec.commonmark.org/0.31.2/ — CC BY-SA 4.0:
// https://creativecommons.org/licenses/by-sa/4.0/
// Adaptations preserve the documented mrkdwn display contract; example numbers identify sources.

struct E1CommonMarkCase: Sendable {
  let example: Int
  let source: String
  let expected: String
}

let e1CommonMarkCases: [E1CommonMarkCase] = [
  .init(
    example: 62, source: "# foo\n## foo\n### foo\n#### foo\n##### foo\n###### foo\n",
    expected:
      "{\"blocks\":[{\"kind\":\"heading\",\"level\":1,\"text\":\"\",\"runs\":[{\"text\":\"foo\",\"traits\":[],\"destination\":null}]},{\"kind\":\"heading\",\"level\":2,\"text\":\"\",\"runs\":[{\"text\":\"foo\",\"traits\":[],\"destination\":null}]},{\"kind\":\"heading\",\"level\":3,\"text\":\"\",\"runs\":[{\"text\":\"foo\",\"traits\":[],\"destination\":null}]},{\"kind\":\"heading\",\"level\":4,\"text\":\"\",\"runs\":[{\"text\":\"foo\",\"traits\":[],\"destination\":null}]},{\"kind\":\"heading\",\"level\":5,\"text\":\"\",\"runs\":[{\"text\":\"foo\",\"traits\":[],\"destination\":null}]},{\"kind\":\"heading\",\"level\":6,\"text\":\"\",\"runs\":[{\"text\":\"foo\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 63, source: "####### foo\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"####### foo\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 64, source: "#5 bolt\n\n#hashtag\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"#5 bolt\",\"traits\":[],\"destination\":null}]},{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"#hashtag\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 80, source: "Foo *bar*\n=========\n\nFoo *bar*\n---------\n",
    expected:
      "{\"blocks\":[{\"kind\":\"heading\",\"level\":1,\"text\":\"\",\"runs\":[{\"text\":\"Foo \",\"traits\":[],\"destination\":null},{\"text\":\"bar\",\"traits\":[\"emphasis\"],\"destination\":null}]},{\"kind\":\"heading\",\"level\":2,\"text\":\"\",\"runs\":[{\"text\":\"Foo \",\"traits\":[],\"destination\":null},{\"text\":\"bar\",\"traits\":[\"emphasis\"],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 81, source: "Foo *bar\nbaz*\n====\n",
    expected:
      "{\"blocks\":[{\"kind\":\"heading\",\"level\":1,\"text\":\"\",\"runs\":[{\"text\":\"Foo \",\"traits\":[],\"destination\":null},{\"text\":\"bar baz\",\"traits\":[\"emphasis\"],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 82, source: "  Foo *bar\nbaz*\t\n====\n",
    expected:
      "{\"blocks\":[{\"kind\":\"heading\",\"level\":1,\"text\":\"\",\"runs\":[{\"text\":\"Foo \",\"traits\":[],\"destination\":null},{\"text\":\"bar baz\",\"traits\":[\"emphasis\"],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 43, source: "***\n---\n___\n",
    expected:
      "{\"blocks\":[{\"kind\":\"rule\",\"level\":null,\"text\":\"\",\"runs\":[]},{\"kind\":\"rule\",\"level\":null,\"text\":\"\",\"runs\":[]},{\"kind\":\"rule\",\"level\":null,\"text\":\"\",\"runs\":[]}],\"links\":[]}"
  ),
  .init(
    example: 44, source: "+++\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"+++\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 45, source: "===\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"===\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 119, source: "```\n<\n >\n```\n",
    expected:
      "{\"blocks\":[{\"kind\":\"code\",\"level\":null,\"text\":\"<\\n >\",\"runs\":[]}],\"links\":[]}"
  ),
  .init(
    example: 120, source: "~~~\n<\n >\n~~~\n",
    expected:
      "{\"blocks\":[{\"kind\":\"code\",\"level\":null,\"text\":\"<\\n >\",\"runs\":[]}],\"links\":[]}"
  ),
  .init(
    example: 121, source: "``\nfoo\n``\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"foo\",\"traits\":[\"code\"],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 107, source: "    a simple\n      indented code block\n",
    expected:
      "{\"blocks\":[{\"kind\":\"code\",\"level\":null,\"text\":\"a simple\\n  indented code block\",\"runs\":[]}],\"links\":[]}"
  ),
  .init(
    example: 219, source: "aaa\n\nbbb\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"aaa\",\"traits\":[],\"destination\":null}]},{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"bbb\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 220, source: "aaa\nbbb\n\nccc\nddd\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"aaa bbb\",\"traits\":[],\"destination\":null}]},{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"ccc ddd\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 221, source: "aaa\n\n\nbbb\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"aaa\",\"traits\":[],\"destination\":null}]},{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"bbb\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 12,
    source:
      "\\!\\\"\\#\\$\\%\\&\\'\\(\\)\\*\\+\\,\\-\\.\\/\\:\\;\\<\\=\\>\\?\\@\\[\\\\\\]\\^\\_\\`\\{\\|\\}\\~\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 13, source: "\\\t\\A\\a\\ \\3\\φ\\«\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"\\\\\\t\\\\A\\\\a\\\\ \\\\3\\\\φ\\\\«\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 14,
    source:
      "\\*not emphasized*\n\\<br/> not a tag\n\\[not a link](/foo)\n\\`not code`\n1\\. not a list\n\\* not a list\n\\# not a heading\n\\[foo]: /url \"not a reference\"\n\\&ouml; not a character entity\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"*not emphasized* <br/> not a tag [not a link](/foo) `not code` 1. not a list * not a list # not a heading [foo]: /url \\\"not a reference\\\" &ouml; not a character entity\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 25,
    source:
      "&nbsp; &amp; &copy; &AElig; &Dcaron;\n&frac34; &HilbertSpace; &DifferentialD;\n&ClockwiseContourIntegral; &ngE;\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"  & © Æ Ď ¾ ℋ ⅆ ∲ ≧̸\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 26, source: "&#35; &#1234; &#992; &#0;\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"# Ӓ Ϡ �\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 27, source: "&#X22; &#XD06; &#xcab;\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"\\\" ആ ಫ\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 328, source: "`foo`\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"foo\",\"traits\":[\"code\"],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 329, source: "`` foo ` bar ``\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"foo ` bar\",\"traits\":[\"code\"],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 330, source: "` `` `\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"``\",\"traits\":[\"code\"],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 350, source: "*foo bar*\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"foo bar\",\"traits\":[\"emphasis\"],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 351, source: "a * foo bar*\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"a * foo bar*\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 352, source: "a*\"foo\"*\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"a*\\\"foo\\\"*\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 482, source: "[link](/uri \"title\")\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"link\",\"traits\":[],\"destination\":\"/uri\"}]}],\"links\":[{\"destination\":\"/uri\",\"label\":\"link\"}]}"
  ),
  .init(
    example: 483, source: "[link](/uri)\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"link\",\"traits\":[],\"destination\":\"/uri\"}]}],\"links\":[{\"destination\":\"/uri\",\"label\":\"link\"}]}"
  ),
  .init(
    example: 484, source: "[](./target.md)\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[]}],\"links\":[{\"destination\":\"./target.md\",\"label\":\"\"}]}"
  ),
  .init(
    example: 594, source: "<http://foo.bar.baz>\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"http://foo.bar.baz\",\"traits\":[],\"destination\":\"http://foo.bar.baz\"}]}],\"links\":[{\"destination\":\"http://foo.bar.baz\",\"label\":\"http://foo.bar.baz\"}]}"
  ),
  .init(
    example: 595, source: "<https://foo.bar.baz/test?q=hello&id=22&boolean>\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"https://foo.bar.baz/test?q=hello&id=22&boolean\",\"traits\":[],\"destination\":\"https://foo.bar.baz/test?q=hello&id=22&boolean\"}]}],\"links\":[{\"destination\":\"https://foo.bar.baz/test?q=hello&id=22&boolean\",\"label\":\"https://foo.bar.baz/test?q=hello&id=22&boolean\"}]}"
  ),
  .init(
    example: 596, source: "<irc://foo.bar:2233/baz>\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"irc://foo.bar:2233/baz\",\"traits\":[],\"destination\":\"irc://foo.bar:2233/baz\"}]}],\"links\":[{\"destination\":\"irc://foo.bar:2233/baz\",\"label\":\"irc://foo.bar:2233/baz\"}]}"
  ),
  .init(
    example: 633, source: "foo  \nbaz\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"foo\\nbaz\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 634, source: "foo\\\nbaz\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"foo\\nbaz\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 635, source: "foo       \nbaz\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"foo\\nbaz\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 648, source: "foo\nbaz\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"foo baz\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 649, source: "foo \n baz\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"foo baz\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
  .init(
    example: 650, source: "hello $.;'there\n",
    expected:
      "{\"blocks\":[{\"kind\":\"paragraph\",\"level\":null,\"text\":\"\",\"runs\":[{\"text\":\"hello $.;'there\",\"traits\":[],\"destination\":null}]}],\"links\":[]}"
  ),
]
