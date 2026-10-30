// Tests ported from: crates/util/src/redact.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import ZedUtil

@Suite("Redact Tests")
struct RedactTests {
    @Test
    func test_redact_string_with_multiple_env_vars() {
        let input = "failed to spawn command cd \"/code/something\" && ANTHROPIC_API_KEY=\"sk-ant-api03-WOOOO\" COMMAND_MODE=\"unix2003\" GEMINI_API_KEY=\"AIGEMINIFACE\" HOME=\"/Users/foo\""
        let result = redactCommand(input)
        let expected = "failed to spawn command cd \"/code/something\" && ANTHROPIC_API_KEY=\"[REDACTED]\" COMMAND_MODE=\"unix2003\" GEMINI_API_KEY=\"[REDACTED]\" HOME=\"/Users/foo\""
        #expect(result == expected)
    }
}
