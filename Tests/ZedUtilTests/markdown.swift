// Tests ported from: crates/util/src/markdown.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import ZedUtil

@Suite("Markdown Tests")
struct MarkdownTests {
    @Test
    func test_markdown_escaped() {
        let input = ##"""

        # Heading

        Another heading
        ===

        Another heading variant
        ---

        Paragraph with [link](https://example.com) and `code`, *emphasis*, and ~strikethrough~.

        ```
        code block
        ```

        List with varying leaders:
          - Item 1
          * Item 2
          + Item 3

        Some math:  $`\sqrt{3x-1}+(1+x)^2`$

        HTML entity: &nbsp;
        
"""##

        let expected = ##"""

        \# Heading

        Another heading
        \=\=\=

        Another heading variant
        \-\-\-

        Paragraph with \[link](https://example.com) and \`code\`, \*emphasis\*, and \~strikethrough\~.

        \`\`\`
        code block
        \`\`\`

        List with varying leaders:
          \- Item 1
          \* Item 2
          \+ Item 3

        Some math:  \$\`\\sqrt{3x\-1}\+(1\+x)\^2\`\$

        HTML entity: \&nbsp;
        
"""##

        #expect(MarkdownEscaped(input).description == expected)
    }

    @Test
    func test_markdown_inline_code() {
        #expect(MarkdownInlineCode(" ").description == "` `")
        #expect(MarkdownInlineCode("text").description == "`text`")
        #expect(MarkdownInlineCode("text ").description == "`text `")
        #expect(MarkdownInlineCode(" text ").description == "`  text  `")
        #expect(MarkdownInlineCode("`").description == "`` ` ``")
        #expect(MarkdownInlineCode("``").description == "``` `` ```")
        #expect(MarkdownInlineCode("`text`").description == "`` `text` ``")
        #expect(
            MarkdownInlineCode("some `text` no leading or trailing backticks").description ==
                "``some `text` no leading or trailing backticks``"
        )
    }

    @Test
    func test_count_max_consecutive_chars() {
        #expect(
            countMaxConsecutiveChars("``a```b``", "`") == 3,
            "the highest seen consecutive segment of backticks counts"
        )
        #expect(
            countMaxConsecutiveChars("```a``b`", "`") == 3,
            "it can't be downgraded later"
        )
    }

    @Test
    func test_heading_slug_and_url_fragments() {
        #expect(generateHeadingSlug("Hello World") == "hello-world")
        #expect(generateHeadingSlug("  My Great Header 123!  ") == "my-great-header-123")
        let (path1, frag1) = splitLocalUrlFragment("docs/guide.md#section-1")
        #expect(path1 == "docs/guide.md")
        #expect(frag1 == "section-1")
        let (path2, frag2) = splitLocalUrlFragment("https://zed.dev/docs#faq")
        #expect(path2 == "https://zed.dev/docs#faq")
        #expect(frag2 == nil)
    }
}
