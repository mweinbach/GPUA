// Tests ported from: crates/util/src/size.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import ZedUtil

@Suite("Size Tests")
struct SizeTests {
    @Test func test_format_file_size_decimal() {
        #expect(formatFileSize(0, true) == "0B")
        #expect(formatFileSize(999, true) == "999B")
        #expect(formatFileSize(1000, true) == "1.0KB")
        #expect(formatFileSize(1500, true) == "1.5KB")
        #expect(formatFileSize(999999, true) == "1000.0KB")
        #expect(formatFileSize(1000000, true) == "1.0MB")
        #expect(formatFileSize(1500000, true) == "1.5MB")
        #expect(formatFileSize(10000000, true) == "10.0MB")
    }

    @Test func test_format_file_size_binary() {
        #expect(formatFileSize(0, false) == "0B")
        #expect(formatFileSize(1023, false) == "1023B")
        #expect(formatFileSize(1024, false) == "1.0KiB")
        #expect(formatFileSize(1536, false) == "1.5KiB")
        #expect(formatFileSize(1048575, false) == "1024.0KiB")
        #expect(formatFileSize(1048576, false) == "1.0MiB")
        #expect(formatFileSize(1572864, false) == "1.5MiB")
        #expect(formatFileSize(10485760, false) == "10.0MiB")
    }
}
