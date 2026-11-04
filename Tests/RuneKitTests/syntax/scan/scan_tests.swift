// Tests ported from: crates/rune-kit/src/syntax/scan/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

private struct Tok: Equatable, CustomStringConvertible {
    let text: String
    let kind: Syntax

    init(_ text: String, _ kind: Syntax) {
        self.text = text
        self.kind = kind
    }

    var description: String {
        "(\(String(reflecting: text)), \(kind))"
    }
}

private func sliceUtf8(_ src: String, _ a: UInt32, _ b: UInt32) -> String {
    let bytes = Array(src.utf8)
    return String(decoding: bytes[Int(a)..<Int(b)], as: UTF8.self)
}

private func toks(_ lang: syntaxScan.Lang, _ src: String) -> [Tok] {
    syntaxScan.highlight(lang, src).map { a, b, t in
        Tok(sliceUtf8(src, a, b), t)
    }
}

private func kindOf(_ lang: syntaxScan.Lang, _ src: String, _ text: String) -> Syntax? {
    toks(lang, src).first(where: { $0.text == text })?.kind
}

private func has(
    _ lang: syntaxScan.Lang,
    _ src: String,
    _ want: [(String, Syntax)],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let got = toks(lang, src)
    for (text, kind) in want {
        #expect(
            got.contains(Tok(text, kind)),
            "\(lang): no \(String(reflecting: text)) as \(kind) in \(got)",
            sourceLocation: sourceLocation
        )
    }
}

private func count(_ lang: syntaxScan.Lang, _ src: String, _ text: String, _ kind: Syntax) -> Int {
    toks(lang, src).filter { $0.text == text && $0.kind == kind }.count
}

@Suite("SyntaxScannerTests")
struct SyntaxScannerTests {
    @Test
    func fence_names_map_to_languages() {
        let cases: [(String, syntaxScan.Lang)] = [
            ("TypeScript", .ts),
            ("tsx", .tsx),
            ("jsx", .js),
            ("bash", .shell),
            ("yml", .yaml),
            ("rs", .rust),
            ("py", .python),
            ("Python3", .python),
            ("golang", .go),
            ("patch", .diff),
        ]
        for (name, lang) in cases {
            #expect(syntaxScan.Lang.fromName(name) == lang)
        }
        #expect(syntaxScan.Lang.fromName("brainfuck") == nil)
    }

    @Test
    func typescript() {
        let src = "// note\nexport async function load(id: string): Promise<User> {\n  const n = 0x1f + 2.5e-3;\n  return fetch(`/u/${id}`).then(r => r.json()) /* done */;\n}\nconst re = /a[/]b/g, half = n / 2;\nnode.type = null;"
        has(.ts, src, [
            ("// note", .comment),
            ("export", .keyword),
            ("function", .keyword),
            ("load", .function),
            ("string", .type),
            ("Promise", .type),
            ("User", .type),
            ("0x1f", .number),
            ("2.5e-3", .number),
            ("`/u/", .string),
            ("${", .punctuation),
            ("fetch", .function),
            ("json", .function),
            ("/* done */", .comment),
            ("/a[/]b/g", .string),
            ("null", .number),
        ])
        #expect(toks(.ts, "`${id}`").filter { $0.text == "id" }.count == 0)
        #expect(kindOf(.ts, src, "/ 2") == nil)
        #expect(kindOf(.ts, src, "type") == nil)
    }

    @Test
    func jsx_text_children_stay_plain() {
        let src = "return <Card title=\"Hi\" on={() => go(1)}>it's {n} items<br/></Card>;"
        has(.tsx, src, [
            ("Card", .type),
            ("title", .property),
            ("\"Hi\"", .string),
            ("go", .function),
            ("1", .number),
            ("br", .keyword),
        ])
        #expect(!toks(.tsx, src).contains { $0.text.contains("it's") })
        #expect(kindOf(.ts, "a <b", "b") == nil)
    }

    @Test
    func type_parameters_are_not_jsx_tags() {
        let after = "\nexport function after(n: number) { return n + 1; }"
        for head in [
            "const id = <T,>(x: T) => x;",
            "type Fn = <T>(x: T) => T;",
            "const f = <T extends object>(x: T) => x;",
        ] {
            let src = "\(head)\(after)"
            has(.tsx, src, [
                ("export", .keyword),
                ("after", .function),
                ("number", .type),
                ("1", .number),
            ])
        }
        let src = "const b = <b>(note)</b>;"
        #expect(count(.tsx, src, "b", .keyword) == 2)
        #expect(kindOf(.tsx, src, "note") == nil)
    }

    @Test
    func a_less_than_in_jsx_text_is_text() {
        let src = "const view = <div>a < b</div>;\nexport const after = 1;"
        has(.tsx, src, [("export", .keyword), ("1", .number)])
        #expect(count(.tsx, src, "div", .keyword) == 2)
        #expect(kindOf(.tsx, src, "b") == nil)
    }

    @Test
    func an_element_that_never_closes_gives_the_code_after_it_back() {
        for head in [
            "const el = <div>\n  unclosed text",
            "const el = <div className=\"a\"",
            "const el = <div <span>",
        ] {
            let src = "\(head)\nexport const after = 1;"
            has(.tsx, src, [("export", .keyword), ("1", .number)])
        }
        let src = "return (\n  <ul>\n    <li>one</li>\n    {items.map(i => <li>{i}</li>)}\n  </ul>\n);"
        has(.tsx, src, [("map", .function)])
        #expect(count(.tsx, src, "ul", .keyword) == 2)
        #expect(kindOf(.tsx, src, "one") == nil)
    }

    @Test
    func comments_inside_embedded_code_hide_their_brackets_and_quotes() {
        let after = "\nconst after = 1;"
        let cases: [(syntaxScan.Lang, String, String)] = [
            (.tsx, "<Card onClick={() => { /* don't */ run(); }} />", "/* don't */"),
            (.tsx, "<Card onClick={() => {\n  // {\n  run();\n}} />", "// {"),
            (.ts, "const s = `${a /* } */}`;", "/* } */"),
        ]
        for (lang, head, comment) in cases {
            let src = "\(head)\(after)"
            has(lang, src, [(comment, .comment), ("const", .keyword), ("1", .number)])
        }
        let shellSrc = "echo $( # )\n cmd )\necho after"
        has(.shell, shellSrc, [("# )", .comment), ("cmd", .function)])
        #expect(count(.shell, shellSrc, "echo", .function) == 2)
        let dollarHash = "n=$(echo $#); echo after"
        has(.shell, dollarHash, [("$#", .property)])
        #expect(count(.shell, dollarHash, "echo", .function) == 2)
    }

    @Test
    func an_apostrophe_in_nested_jsx_text_is_not_a_string() {
        let after = "\nexport const after = 1;"
        for (head, tag) in [
            ("return <div>{ok && <p>don't</p>}</div>;", "div"),
            ("const ul = <ul>{list.map(x => <li>it's {x}</li>)}</ul>;", "ul"),
        ] {
            let src = "\(head)\(after)"
            has(.tsx, src, [("export", .keyword), ("1", .number)])
            #expect(count(.tsx, src, tag, .keyword) == 2)
        }
        has(.tsx, "const ul = <ul>{list.map(x => <li>it's {x}</li>)}</ul>;\(after)", [("map", .function)])
        let src = "<i>{a < b ? 'x}' : <a title=\"}'\">y</a>}</i>;\(after)"
        has(.tsx, src, [("'x}'", .string), ("\"}'\"", .string), ("export", .keyword)])
        #expect(count(.tsx, src, "i", .keyword) == 2)
    }

    @Test
    func a_line_continuation_keeps_the_next_word_a_command() {
        #expect(count(.shell, "cargo build && \\\n  cargo test", "cargo", .function) == 2)
        #expect(count(.shell, "cargo build && \\\r\n  cargo test", "cargo", .function) == 2)
        #expect(kindOf(.shell, "cargo build \\\n  --release", "--release") == nil)
    }

    @Test
    func python() {
        let src = "def f(a, *, b=None):\n    \"\"\"Doc with 'quotes'\n    and lines.\"\"\"\n    return {k: v for k, v in a.items() if v is not None}\n\nclass Config(BaseModel):\n    PORT = 8080\n    path: list[str] = []\n\n@app.route(\"/x\")\nasync def view(req):\n    await req.send(rb'\\x00', 0o17, 1_000.5j)"
        has(.python, src, [
            ("def", .keyword),
            ("f", .function),
            ("None", .number),
            ("\"\"\"Doc with 'quotes'\n    and lines.\"\"\"", .string),
            ("for", .keyword),
            ("in", .keyword),
            ("items", .function),
            ("is", .keyword),
            ("not", .keyword),
            ("class", .keyword),
            ("Config", .type),
            ("BaseModel", .type),
            ("PORT", .number),
            ("8080", .number),
            ("list", .type),
            ("str", .type),
            ("@app.route", .keyword),
            ("\"/x\"", .string),
            ("async", .keyword),
            ("view", .function),
            ("await", .keyword),
            ("send", .function),
            ("rb'\\x00'", .string),
            ("0o17", .number),
            ("1_000.5j", .number),
        ])
        #expect(kindOf(.python, src, "v") == nil)
        #expect(kindOf(.python, "x = a.items", "items") == nil)
    }

    @Test
    func python_f_strings_colour_their_fields() {
        let src = "f\"{d['k']:>10} {{literal}} {n + 1}\" + F'{x}' + \"{plain}\""
        has(.python, src, [
            ("f\"", .string),
            ("'k'", .string),
            (" {{literal}} ", .string),
            ("1", .number),
            ("F'", .string),
            ("\"{plain}\"", .string),
        ])
        #expect(count(.python, src, "{", .punctuation) == 3)
        has(.python, "f'{oops' + 1", [("f'{oops'", .string), ("1", .number)])
    }

    @Test
    func python_soft_keywords_only_start_statements() {
        let src = "match command.split():\n    case [\"go\", where]:\n        pass\n    case _:  # anything\n        pass\nmatch = re.match(p, s)\ncase(1)"
        #expect(count(.python, src, "match", .keyword) == 1)
        #expect(count(.python, src, "case", .keyword) == 2)
        has(.python, src, [("match", .function), ("case", .function)])
    }

    @Test
    func go() {
        let src = "type Server struct {\n\tAddr string\n\tdone chan error\n}\n\nfunc (s *Server) Run(ctx context.Context) error {\n\tpath := `C:\\dir\\`\n\tgo s.loop()\n\treturn NewError(\"x\", iota, 0x1F)\n}"
        has(.go, src, [
            ("type", .keyword),
            ("Server", .type),
            ("struct", .keyword),
            ("string", .type),
            ("chan", .keyword),
            ("error", .type),
            ("func", .keyword),
            ("Run", .function),
            ("`C:\\dir\\`", .string),
            ("go", .keyword),
            ("loop", .function),
            ("return", .keyword),
            ("NewError", .function),
            ("iota", .number),
            ("0x1F", .number),
        ])
        #expect(kindOf(.go, src, "go") == .keyword)
        #expect(kindOf(.go, src, "Addr") == nil)
        #expect(kindOf(.go, "s := Server{Addr: \":80\"}", "Addr") == nil)
        #expect(kindOf(.go, "s := Server{Addr: \":80\"}", "Server") == .type)
        #expect(kindOf(.go, src, "Context") == nil)
    }

    @Test
    func diff_lines() {
        let src = "--- a/f\n+++ b/f\r\n@@ -1 +1 @@ fn x\n-a\r\n+b\n same\n+\n"
        let want: [Tok] = [
            Tok("--- a/f", .comment),
            Tok("+++ b/f", .comment),
            Tok("@@ -1 +1 @@ fn x", .comment),
            Tok("-a", .deleted),
            Tok("+b", .inserted),
            Tok("+", .inserted),
        ]
        #expect(toks(.diff, src) == want)
    }

    @Test
    func json_keys_are_properties() {
        has(.json, "{\"name\": \"rune\", \"n\": -1.5, \"ok\": true, \"x\": null}", [
            ("\"name\"", .property),
            ("\"rune\"", .string),
            ("1.5", .number),
            ("true", .number),
            ("null", .number),
            ("{", .punctuation),
        ])
    }

    @Test
    func rust() {
        let src = "#[derive(Debug)]\npub fn get<'a>(s: &'a str) -> Option<u8> {\n    let c = 'x';\n    println!(\"{}\", r#\"raw \"q\"\"#);\n    /* outer /* inner */ still */ Some(b'\\n')\n}"
        has(.rust, src, [
            ("pub", .keyword),
            ("fn", .keyword),
            ("get", .function),
            ("'a", .keyword),
            ("str", .type),
            ("Option", .type),
            ("u8", .type),
            ("'x'", .string),
            ("println!", .function),
            ("r#\"raw \"q\"\"#", .string),
            ("/* outer /* inner */ still */", .comment),
            ("Some", .type),
            ("b'\\n'", .string),
        ])
    }

    @Test
    func swift() {
        let src = "@MainActor\nstruct Row: View {\n  let title: String = \"\"\"\n  hi\n  \"\"\"\n  func body() -> some View { Text(title).padding(8) }\n}\n#if DEBUG\nlet x = nil"
        has(.swift, src, [
            ("@MainActor", .keyword),
            ("struct", .keyword),
            ("Row", .type),
            ("View", .type),
            ("\"\"\"\n  hi\n  \"\"\"", .string),
            ("func", .keyword),
            ("body", .function),
            ("some", .keyword),
            ("padding", .function),
            ("8", .number),
            ("#if", .keyword),
            ("nil", .number),
        ])
    }

    @Test
    func shell() {
        let src = "#!/bin/bash\nFOO=1 npm run build --if-present # build\nif [ -n \"$HOME/${X}\" ]; then\n  echo $(git rev-parse HEAD) | tee out.txt\nfi\ncat <<EOF\n$not a var\nEOF\nls"
        has(.shell, src, [
            ("#!/bin/bash", .comment),
            ("FOO", .property),
            ("npm", .function),
            ("# build", .comment),
            ("if", .keyword),
            ("[", .punctuation),
            ("\"", .string),
            ("$HOME", .property),
            ("${X}", .property),
            ("then", .keyword),
            ("echo", .function),
            ("$(", .punctuation),
            ("git", .function),
            ("tee", .function),
            ("fi", .keyword),
            ("cat", .function),
            ("EOF", .string),
            ("ls", .function),
        ])
        #expect(kindOf(.shell, src, "run") == nil)
        #expect(toks(.shell, src).contains { $0.text.contains("$not a var") && $0.kind == .string })
    }

    @Test
    func html_with_script_and_style() {
        let src = "<!-- c -->\n<a href=\"/x\" data-id=7>Tom &amp; Jerry</a>\n<script>const a = 1;</script>\n<style>p { color: red; }</style>"
        has(.html, src, [
            ("<!-- c -->", .comment),
            ("a", .keyword),
            ("href", .property),
            ("\"/x\"", .string),
            ("7", .string),
            ("&amp;", .number),
            ("const", .keyword),
            ("1", .number),
            ("color", .property),
        ])
        #expect(kindOf(.html, src, "Tom") == nil)
    }

    @Test
    func css() {
        let src = "@media (min-width: 600px) {\n  .card:hover > a, #main { color: #fff !important; margin: -4px 0 calc(1em + 2%); --gap: 4px; }\n}"
        has(.css, src, [
            ("@media", .keyword),
            ("600px", .number),
            (".card", .type),
            (":hover", .keyword),
            ("#main", .type),
            ("color", .property),
            ("#fff", .number),
            ("!important", .keyword),
            ("-4px", .number),
            ("calc", .function),
            ("1em", .number),
            ("2%", .number),
            ("--gap", .property),
        ])
    }

    @Test
    func sql() {
        let src = "-- users\nSELECT id, count(*) AS n FROM \"users\" WHERE name = 'O''Brien' AND age > $1 LIMIT 10;\nCREATE TABLE t (id uuid PRIMARY KEY, ok boolean DEFAULT false);"
        has(.sql, src, [
            ("-- users", .comment),
            ("SELECT", .keyword),
            ("count", .function),
            ("AS", .keyword),
            ("\"users\"", .property),
            ("'O''Brien'", .string),
            ("$1", .property),
            ("10", .number),
            ("uuid", .type),
            ("boolean", .type),
            ("false", .number),
        ])
    }

    @Test
    func yaml() {
        let src = "---\nname: rune # the name\nversion: 1.2\nanchors: &base\n  - item\n  - key: \"v\"\n    on: true\nscript: |\n  echo hi\n  # not a comment\nflow: [a, 1, {b: c}]\nafter: x"
        has(.yaml, src, [
            ("---", .punctuation),
            ("name", .property),
            ("rune", .string),
            ("# the name", .comment),
            ("1.2", .number),
            ("&base", .type),
            ("-", .punctuation),
            ("item", .string),
            ("key", .property),
            ("\"v\"", .string),
            ("on", .property),
            ("true", .number),
            ("echo hi", .string),
            ("# not a comment", .string),
            ("1", .number),
            ("b", .property),
            ("c", .string),
            ("after", .property),
        ])
    }

    @Test
    func ranges_are_ordered_and_on_char_boundaries() {
        let delim = "\(String(repeating: "a", count: 63))é"
        let heredoc = "cat << \(delim)\nhi\n\(delim)\nls"
        let body = "hi\n\(delim)"
        has(.shell, heredoc, [("cat", .function), (body, .string), ("ls", .function)])

        let capUtf8 = "let x = 1;\n\(String(repeating: "🎉", count: syntaxScan.MAX_SOURCE / 4 + 4))"
        let pieces: [String] = [
            "\"", "'", "`", "\"\"\"", "'''", "r#\"", "\"#", "b\"", "b'", "f\"", "f'{", "${", "$(", "/*", "*/", "//",
            "<!--", "-->", "<![CDATA[", "]]>", "<script>", "</script>", "<style>", "<<EOF\n", "<<-\t", "\\", "\\uD800",
            "\\u{D800}", "\\x00", "\r\n", "\r", "\n", "\t", " ", "é", "🎉", "日本語", "a", "1_000.5e-2", ":", "|", ">",
            "- ", "@", "#", "$", "&amp;", "=", "(", ")", "[", "]", "{", "}", "/", "+",
        ]
        var fuzz: [String] = []
        fuzz.reserveCapacity(64)
        var seed: UInt64 = 0x9e37_79b9_7f4a_7c15
        for len in 1...64 {
            var s = ""
            for _ in 0..<len {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                s += pieces[Int(seed >> 32) % pieces.count]
            }
            fuzz.append(s)
        }
        let fixed: [String] = [
            "const café = \"naïve 🎉\"; // ✓\n<p>é</p> `${'ü'}`",
            "echo \\🎉 123 \\é",
            heredoc,
            capUtf8,
        ]
        let langs: [syntaxScan.Lang] = [
            .js, .ts, .tsx, .rust, .swift, .go, .python, .shell, .html,
            .css, .sql, .yaml, .json, .diff,
        ]
        for src in fixed + fuzz {
            let bytes = Array(src.utf8)
            let end = syntaxScan.colouredLen(src)
            #expect(syntaxScan.isCharBoundary(bytes, end))
            for lang in langs {
                var raw = syntaxScan.Out()
                syntaxScan.scan(lang, bytes, 0, end, &raw, 0)
                #expect(raw.tokens.allSatisfy { a, b, _ in
                    syntaxScan.isCharBoundary(bytes, Int(a)) && syntaxScan.isCharBoundary(bytes, Int(b))
                })
                let t = syntaxScan.highlight(lang, src)
                if t.count >= 2 {
                    for idx in 0..<(t.count - 1) {
                        #expect(t[idx].1 <= t[idx + 1].0)
                    }
                }
                #expect(t.allSatisfy { a, b, _ in
                    a < b && Int(b) <= end
                        && syntaxScan.isCharBoundary(bytes, Int(a))
                        && syntaxScan.isCharBoundary(bytes, Int(b))
                })
            }
        }
    }

    @Test
    func hostile_input_finishes_quickly_and_stays_bounded() {
        let n = syntaxScan.MAX_SOURCE - 64
        let inputs: [String] = [
            String(repeating: "\"", count: n),
            String(repeating: "/*", count: n / 2),
            String(repeating: "`${", count: n / 3),
            String(repeating: "{", count: n),
            String(repeating: "<a b={", count: n / 6),
            String(repeating: "(/", count: n / 2),
            "r\(String(repeating: "#", count: n))\"",
            String(repeating: "$($(", count: n / 4),
            String(repeating: "'", count: n),
            String(repeating: "a", count: n),
            String(repeating: "<script>", count: n / 8),
            String(repeating: "- ", count: n / 2),
            String(repeating: "x: |\n", count: n / 5),
            String(repeating: "@media{", count: n / 7),
            String(repeating: "f'{", count: n / 3),
            String(repeating: "f\"{'", count: n / 4),
            String(repeating: "\"\"\"", count: n / 3),
            String(repeating: "`", count: n),
            String(repeating: "match x\n", count: n / 8),
        ]
        let clock = ContinuousClock()
        let t0 = clock.now
        let langs: [syntaxScan.Lang] = [
            .js, .tsx, .rust, .swift, .go, .python, .shell, .html, .css, .sql, .yaml, .json, .diff,
        ]
        for src in inputs {
            for lang in langs {
                let t = syntaxScan.highlight(lang, src)
                #expect(t.count <= syntaxScan.MAX_TOKENS)
            }
        }
        let elapsed = t0.duration(to: clock.now)
        // PORT NOTE: Allow 30s wall-clock headroom for unoptimized Debug (`-Onone`) parallel test
        // runs under heavy multi-core load while still catching any superlinear blowup.
        #expect(elapsed < .seconds(30))
    }

    @Test
    func colour_stops_at_the_caps() {
        let line = "// one comment per line, each its own range\n"
        let big = String(repeating: line, count: syntaxScan.MAX_SOURCE / line.utf8.count + 10)
        let last = Int(syntaxScan.highlight(.rust, big).last!.1)
        #expect(last <= syntaxScan.MAX_SOURCE && last > syntaxScan.MAX_SOURCE - line.utf8.count)
        let many = String(repeating: "1 ", count: syntaxScan.MAX_TOKENS + 10)
        #expect(syntaxScan.highlight(.js, many).count == syntaxScan.MAX_TOKENS)
    }

    @Test
    func goldens() {
        let goldens: [(syntaxScan.Lang, String, [(String, Syntax)])] = [
            (.rust, "fn main() {\n    let v: Vec<u8> = vec![1, 2]; // two\n    println!(\"{}\", v.len());\n}", [
                ("fn", .keyword), ("main", .function), ("()", .punctuation), ("{", .punctuation), ("let", .keyword), (":", .punctuation),
                ("Vec", .type), ("<", .punctuation), ("u8", .type), (">", .punctuation), ("=", .punctuation), ("vec!", .function), ("[", .punctuation),
                ("1", .number), (",", .punctuation), ("2", .number), ("];", .punctuation), ("// two", .comment), ("println!", .function),
                ("(", .punctuation), ("\"{}\"", .string), (",", .punctuation), (".", .punctuation), ("len", .function), ("());", .punctuation),
                ("}", .punctuation),
            ]),
            (.js, "const xs = [1, 2].map((x) => x * 2); // double\nconsole.log(`n=${xs.length}`, /a+/g);", [
                ("const", .keyword), ("=", .punctuation), ("[", .punctuation), ("1", .number), (",", .punctuation), ("2", .number),
                ("].", .punctuation), ("map", .function), ("((", .punctuation), (")", .punctuation), ("=>", .punctuation), ("*", .punctuation),
                ("2", .number), (");", .punctuation), ("// double", .comment), (".", .punctuation), ("log", .function), ("(", .punctuation),
                ("`n=", .string), ("${", .punctuation), (".", .punctuation), ("}", .punctuation), ("`", .string), (",", .punctuation),
                ("/a+/g", .string), (");", .punctuation),
            ]),
            (.ts, "interface User { id: number; name?: string }\nexport function greet(u: User): string {\n  return `hi ${u.name ?? \"anon\"}`;\n}", [
                ("interface", .keyword), ("User", .type), ("{", .punctuation), (":", .punctuation), ("number", .type), (";", .punctuation),
                ("?:", .punctuation), ("string", .type), ("}", .punctuation), ("export", .keyword), ("function", .keyword), ("greet", .function),
                ("(", .punctuation), (":", .punctuation), ("User", .type), ("):", .punctuation), ("string", .type), ("{", .punctuation),
                ("return", .keyword), ("`hi ", .string), ("${", .punctuation), (".", .punctuation), ("??", .punctuation), ("\"anon\"", .string),
                ("}", .punctuation), ("`", .string), (";", .punctuation), ("}", .punctuation),
            ]),
            (.python, "@dataclass\nclass Point:\n    x: int = 0  # origin\n    def dist(self, other: \"Point\") -> float:\n        return math.hypot(self.x - other.x, f\"{self.y!r}\")\nprint(None, True, 1e3, r'\\d+', b\"x\")", [
                ("@dataclass", .keyword), ("class", .keyword), ("Point", .type), (":", .punctuation), (":", .punctuation), ("int", .type),
                ("=", .punctuation), ("0", .number), ("# origin", .comment), ("def", .keyword), ("dist", .function), ("(", .punctuation),
                ("self", .keyword), (",", .punctuation), (":", .punctuation), ("\"Point\"", .string), (")", .punctuation), ("->", .punctuation),
                ("float", .type), (":", .punctuation), ("return", .keyword), (".", .punctuation), ("hypot", .function), ("(", .punctuation),
                ("self", .keyword), (".", .punctuation), ("-", .punctuation), (".", .punctuation), (",", .punctuation), ("f\"", .string),
                ("{", .punctuation), ("self", .keyword), (".", .punctuation), ("!", .punctuation), ("}", .punctuation), ("\"", .string),
                (")", .punctuation), ("print", .function), ("(", .punctuation), ("None", .number), (",", .punctuation), ("True", .number),
                (",", .punctuation), ("1e3", .number), (",", .punctuation), ("r'\\d+'", .string), (",", .punctuation), ("b\"x\"", .string),
                (")", .punctuation),
            ]),
            (.go, "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfor i := 0; i < 3; i++ {\n\t\tfmt.Println(`raw\\n`, 'x', nil) // done\n\t}\n}", [
                ("package", .keyword), ("import", .keyword), ("\"fmt\"", .string), ("func", .keyword), ("main", .function), ("()", .punctuation),
                ("{", .punctuation), ("for", .keyword), (":=", .punctuation), ("0", .number), (";", .punctuation), ("<", .punctuation), ("3", .number),
                (";", .punctuation), ("++", .punctuation), ("{", .punctuation), (".", .punctuation), ("Println", .function), ("(", .punctuation),
                ("`raw\\n`", .string), (",", .punctuation), ("'x'", .string), (",", .punctuation), ("nil", .number), (")", .punctuation),
                ("// done", .comment), ("}", .punctuation), ("}", .punctuation),
            ]),
            (.swift, "struct Point { var x: Double = 0 }\nlet p = Point(x: 1.5) // origin\nprint(\"\\(p.x)\")", [
                ("struct", .keyword), ("Point", .type), ("{", .punctuation), ("var", .keyword), (":", .punctuation), ("Double", .type),
                ("=", .punctuation), ("0", .number), ("}", .punctuation), ("let", .keyword), ("=", .punctuation), ("Point", .type),
                ("(", .punctuation), (":", .punctuation), ("1.5", .number), (")", .punctuation), ("// origin", .comment), ("print", .function),
                ("(", .punctuation), ("\"\\(p.x)\"", .string), (")", .punctuation),
            ]),
            (.json, "{\"a\": [1, true, null], \"b\": \"x\\\"y\"}", [
                ("{", .punctuation), ("\"a\"", .property), (":", .punctuation), ("[", .punctuation), ("1", .number), (",", .punctuation),
                ("true", .number), (",", .punctuation), ("null", .number), ("],", .punctuation), ("\"b\"", .property), (":", .punctuation),
                ("\"x\\\"y\"", .string), ("}", .punctuation),
            ]),
            (.shell, "export PATH=\"$HOME/bin:$PATH\"\nfor f in *.txt; do wc -l \"$f\"; done # count", [
                ("export", .keyword), ("\"", .string), ("$HOME", .property), ("/bin:", .string), ("$PATH", .property), ("\"", .string),
                ("for", .keyword), ("in", .keyword), (";", .punctuation), ("do", .keyword), ("wc", .function), ("\"", .string), ("$f", .property),
                ("\"", .string), (";", .punctuation), ("done", .keyword), ("# count", .comment),
            ]),
            (.sql, "SELECT name, COUNT(*) FROM users WHERE id = 1 -- one\nGROUP BY name;", [
                ("SELECT", .keyword), (",", .punctuation), ("COUNT", .function), ("(*)", .punctuation), ("FROM", .keyword), ("WHERE", .keyword),
                ("=", .punctuation), ("1", .number), ("-- one", .comment), ("GROUP", .keyword), ("BY", .keyword), (";", .punctuation),
            ]),
            (.html, "<div class=\"a\"><!-- hi --><b>x</b></div>", [
                ("<", .punctuation), ("div", .keyword), ("class", .property), ("=", .punctuation), ("\"a\"", .string), (">", .punctuation),
                ("<!-- hi -->", .comment), ("<", .punctuation), ("b", .keyword), (">", .punctuation), ("</", .punctuation), ("b", .keyword),
                ("></", .punctuation), ("div", .keyword), (">", .punctuation),
            ]),
            (.css, ".btn:hover { color: #fff; padding: 4px 8px; } /* hover */", [
                (".btn", .type), (":hover", .keyword), ("{", .punctuation), ("color", .property), (":", .punctuation), ("#fff", .number),
                (";", .punctuation), ("padding", .property), (":", .punctuation), ("4px", .number), ("8px", .number), (";", .punctuation),
                ("}", .punctuation), ("/* hover */", .comment),
            ]),
            (.yaml, "name: ci\non: [push]\nenv:\n  DEBUG: true # verbose\n  N: 3", [
                ("name", .property), (":", .punctuation), ("ci", .string), ("on", .property), (":", .punctuation), ("[", .punctuation),
                ("push", .string), ("]", .punctuation), ("env", .property), (":", .punctuation), ("DEBUG", .property), (":", .punctuation),
                ("true", .number), ("# verbose", .comment), ("N", .property), (":", .punctuation), ("3", .number),
            ]),
            (.diff, "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n context\n-old\n+new\n\\ No newline at end of file", [
                ("diff --git a/x b/x", .comment), ("--- a/x", .comment), ("+++ b/x", .comment), ("@@ -1,2 +1,2 @@", .comment), ("-old", .deleted),
                ("+new", .inserted), ("\\ No newline at end of file", .comment),
            ]),
        ]
        for (lang, src, wantPairs) in goldens {
            let want = wantPairs.map { Tok($0.0, $0.1) }
            #expect(toks(lang, src) == want, "\(lang)")
        }
    }
}
