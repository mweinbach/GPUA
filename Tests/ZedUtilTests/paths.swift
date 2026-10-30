// Tests ported from: crates/util/src/paths.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import Foundation
@testable import ZedUtil

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

private func checkEqual<T: Equatable>(_ a: [(T, Bool)], _ b: [(T, Bool)]) -> Bool {
    guard a.count == b.count else { return false }
    for i in 0..<a.count {
        if a[i].0 != b[i].0 || a[i].1 != b[i].1 {
            return false
        }
    }
    return true
}

@Suite("Paths Tests")
struct PathsTests {
    @Test
    func compare_paths_with_dots() {
        var paths: [(Path, Bool)] = [
            (Path("test_dirs"), false),
            (Path("test_dirs/1.46"), false),
            (Path("test_dirs/1.46/bar_1"), true),
            (Path("test_dirs/1.46/bar_2"), true),
            (Path("test_dirs/1.45"), false),
            (Path("test_dirs/1.45/foo_2"), true),
            (Path("test_dirs/1.45/foo_1"), true),
        ]
        paths.sort { compare_paths($0, $1) == .less }
        let expected: [(Path, Bool)] = [
            (Path("test_dirs"), false),
            (Path("test_dirs/1.45"), false),
            (Path("test_dirs/1.45/foo_1"), true),
            (Path("test_dirs/1.45/foo_2"), true),
            (Path("test_dirs/1.46"), false),
            (Path("test_dirs/1.46/bar_1"), true),
            (Path("test_dirs/1.46/bar_2"), true),
        ]
        #expect(checkEqual(paths, expected))

        var paths2: [(Path, Bool)] = [
            (Path("root1/one.txt"), true),
            (Path("root1/one.two.txt"), true),
        ]
        paths2.sort { compare_paths($0, $1) == .less }
        let expected2: [(Path, Bool)] = [
            (Path("root1/one.txt"), true),
            (Path("root1/one.two.txt"), true),
        ]
        #expect(checkEqual(paths2, expected2))
    }

    @Test
    func compare_paths_with_same_name_different_extensions() {
        var paths: [(Path, Bool)] = [
            (Path("test_dirs/file.rs"), true),
            (Path("test_dirs/file.txt"), true),
            (Path("test_dirs/file.md"), true),
            (Path("test_dirs/file"), true),
            (Path("test_dirs/file.a"), true),
        ]
        paths.sort { compare_paths($0, $1) == .less }
        let expected: [(Path, Bool)] = [
            (Path("test_dirs/file"), true),
            (Path("test_dirs/file.a"), true),
            (Path("test_dirs/file.md"), true),
            (Path("test_dirs/file.rs"), true),
            (Path("test_dirs/file.txt"), true),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_paths_case_semi_sensitive() {
        var paths: [(Path, Bool)] = [
            (Path("test_DIRS"), false),
            (Path("test_DIRS/foo_1"), true),
            (Path("test_DIRS/foo_2"), true),
            (Path("test_DIRS/bar"), true),
            (Path("test_DIRS/BAR"), true),
            (Path("test_dirs"), false),
            (Path("test_dirs/foo_1"), true),
            (Path("test_dirs/foo_2"), true),
            (Path("test_dirs/bar"), true),
            (Path("test_dirs/BAR"), true),
        ]
        paths.sort { compare_paths($0, $1) == .less }
        let expected: [(Path, Bool)] = [
            (Path("test_dirs"), false),
            (Path("test_dirs/bar"), true),
            (Path("test_dirs/BAR"), true),
            (Path("test_dirs/foo_1"), true),
            (Path("test_dirs/foo_2"), true),
            (Path("test_DIRS"), false),
            (Path("test_DIRS/bar"), true),
            (Path("test_DIRS/BAR"), true),
            (Path("test_DIRS/foo_1"), true),
            (Path("test_DIRS/foo_2"), true),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_paths_mixed_case_numeric_ordering() {
        var entries: [(Path, Bool)] = [
            (Path(".config"), false),
            (Path("Dir1"), false),
            (Path("dir01"), false),
            (Path("dir2"), false),
            (Path("Dir02"), false),
            (Path("dir10"), false),
            (Path("Dir10"), false),
        ]
        entries.sort { compare_paths($0, $1) == .less }
        let ordered = entries.map { $0.0.rawValue }
        #expect(ordered == [".config", "Dir1", "dir01", "dir2", "Dir02", "dir10", "Dir10"])
    }

    @Test
    func compare_rel_paths_mixed_case_insensitive() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("zebra.txt"), true),
            (try! RelPath.unix("Apple"), false),
            (try! RelPath.unix("banana.rs"), true),
            (try! RelPath.unix("Carrot"), false),
            (try! RelPath.unix("aardvark.txt"), true),
        ]
        paths.sort { compare_rel_paths_mixed($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("aardvark.txt"), true),
            (try! RelPath.unix("Apple"), false),
            (try! RelPath.unix("banana.rs"), true),
            (try! RelPath.unix("Carrot"), false),
            (try! RelPath.unix("zebra.txt"), true),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_files_first_basic() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("zebra.txt"), true),
            (try! RelPath.unix("Apple"), false),
            (try! RelPath.unix("banana.rs"), true),
            (try! RelPath.unix("Carrot"), false),
            (try! RelPath.unix("aardvark.txt"), true),
        ]
        paths.sort { compare_rel_paths_files_first($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("aardvark.txt"), true),
            (try! RelPath.unix("banana.rs"), true),
            (try! RelPath.unix("zebra.txt"), true),
            (try! RelPath.unix("Apple"), false),
            (try! RelPath.unix("Carrot"), false),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_files_first_case_insensitive() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("Zebra.txt"), true),
            (try! RelPath.unix("apple"), false),
            (try! RelPath.unix("Banana.rs"), true),
            (try! RelPath.unix("carrot"), false),
            (try! RelPath.unix("Aardvark.txt"), true),
        ]
        paths.sort { compare_rel_paths_files_first($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("Aardvark.txt"), true),
            (try! RelPath.unix("Banana.rs"), true),
            (try! RelPath.unix("Zebra.txt"), true),
            (try! RelPath.unix("apple"), false),
            (try! RelPath.unix("carrot"), false),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_files_first_numeric() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("file10.txt"), true),
            (try! RelPath.unix("dir2"), false),
            (try! RelPath.unix("file2.txt"), true),
            (try! RelPath.unix("dir10"), false),
            (try! RelPath.unix("file1.txt"), true),
        ]
        paths.sort { compare_rel_paths_files_first($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("file1.txt"), true),
            (try! RelPath.unix("file2.txt"), true),
            (try! RelPath.unix("file10.txt"), true),
            (try! RelPath.unix("dir2"), false),
            (try! RelPath.unix("dir10"), false),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_mixed_case() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("README.md"), true),
            (try! RelPath.unix("readme.txt"), true),
            (try! RelPath.unix("ReadMe.rs"), true),
        ]
        paths.sort { compare_rel_paths_mixed($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("README.md"), true),
            (try! RelPath.unix("ReadMe.rs"), true),
            (try! RelPath.unix("readme.txt"), true),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_mixed_files_and_dirs() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("file2.txt"), true),
            (try! RelPath.unix("Dir1"), false),
            (try! RelPath.unix("file1.txt"), true),
            (try! RelPath.unix("dir2"), false),
        ]
        paths.sort { compare_rel_paths_mixed($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("Dir1"), false),
            (try! RelPath.unix("dir2"), false),
            (try! RelPath.unix("file1.txt"), true),
            (try! RelPath.unix("file2.txt"), true),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_mixed_with_nested_paths() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("src/main.rs"), true),
            (try! RelPath.unix("Cargo.toml"), true),
            (try! RelPath.unix("src"), false),
            (try! RelPath.unix("target"), false),
        ]
        paths.sort { compare_rel_paths_mixed($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("Cargo.toml"), true),
            (try! RelPath.unix("src"), false),
            (try! RelPath.unix("src/main.rs"), true),
            (try! RelPath.unix("target"), false),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_files_first_with_nested() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("src/lib.rs"), true),
            (try! RelPath.unix("README.md"), true),
            (try! RelPath.unix("src"), false),
            (try! RelPath.unix("tests"), false),
        ]
        paths.sort { compare_rel_paths_files_first($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("README.md"), true),
            (try! RelPath.unix("src"), false),
            (try! RelPath.unix("src/lib.rs"), true),
            (try! RelPath.unix("tests"), false),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_mixed_dotfiles() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix(".gitignore"), true),
            (try! RelPath.unix("README.md"), true),
            (try! RelPath.unix(".github"), false),
            (try! RelPath.unix("src"), false),
        ]
        paths.sort { compare_rel_paths_mixed($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix(".github"), false),
            (try! RelPath.unix(".gitignore"), true),
            (try! RelPath.unix("README.md"), true),
            (try! RelPath.unix("src"), false),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_files_first_dotfiles() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix(".gitignore"), true),
            (try! RelPath.unix("README.md"), true),
            (try! RelPath.unix(".github"), false),
            (try! RelPath.unix("src"), false),
        ]
        paths.sort { compare_rel_paths_files_first($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix(".gitignore"), true),
            (try! RelPath.unix("README.md"), true),
            (try! RelPath.unix(".github"), false),
            (try! RelPath.unix("src"), false),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_mixed_same_stem_different_extension() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("file.rs"), true),
            (try! RelPath.unix("file.md"), true),
            (try! RelPath.unix("file.txt"), true),
        ]
        paths.sort { compare_rel_paths_mixed($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("file.md"), true),
            (try! RelPath.unix("file.rs"), true),
            (try! RelPath.unix("file.txt"), true),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_files_first_same_stem() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("main.rs"), true),
            (try! RelPath.unix("main.c"), true),
            (try! RelPath.unix("main"), false),
        ]
        paths.sort { compare_rel_paths_files_first($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("main.c"), true),
            (try! RelPath.unix("main.rs"), true),
            (try! RelPath.unix("main"), false),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func compare_rel_paths_mixed_deep_nesting() {
        var paths: [(RelPath, Bool)] = [
            (try! RelPath.unix("a/b/c.txt"), true),
            (try! RelPath.unix("A/B.txt"), true),
            (try! RelPath.unix("a.txt"), true),
            (try! RelPath.unix("A.txt"), true),
        ]
        paths.sort { compare_rel_paths_mixed($0, $1) == .less }
        let expected: [(RelPath, Bool)] = [
            (try! RelPath.unix("a/b/c.txt"), true),
            (try! RelPath.unix("A/B.txt"), true),
            (try! RelPath.unix("a.txt"), true),
            (try! RelPath.unix("A.txt"), true),
        ]
        #expect(checkEqual(paths, expected))
    }

    @Test
    func path_with_position_parse_posix_path() {
        #expect(
            PathWithPosition.parse_str("test_file") ==
            PathWithPosition(path: Path("test_file"), row: nil, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("a:bc:.zip:1") ==
            PathWithPosition(path: Path("a:bc:.zip"), row: 1, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("one.second.zip:1") ==
            PathWithPosition(path: Path("one.second.zip"), row: 1, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("test_file:10:1:") ==
            PathWithPosition(path: Path("test_file"), row: 10, column: 1)
        )
        #expect(
            PathWithPosition.parse_str("test_file.rs:") ==
            PathWithPosition(path: Path("test_file.rs"), row: nil, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("test_file.rs:1:") ==
            PathWithPosition(path: Path("test_file.rs"), row: 1, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("ab\ncd") ==
            PathWithPosition(path: Path("ab\ncd"), row: nil, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("👋\nab") ==
            PathWithPosition(path: Path("👋\nab"), row: nil, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("Types.hs:(617,9)-(670,28):") ==
            PathWithPosition(path: Path("Types.hs"), row: 617, column: 9)
        )
    }

    @Test
    func path_with_position_parse_posix_path_with_suffix() {
        #if !os(Windows)
        #expect(
            PathWithPosition.parse_str("foo/bar:34:in") ==
            PathWithPosition(path: Path("foo/bar"), row: 34, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("foo/bar.rs:1902:::15:") ==
            PathWithPosition(path: Path("foo/bar.rs:1902"), row: 15, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("app-editors:zed-0.143.6:20240710-201212.log:34:") ==
            PathWithPosition(path: Path("app-editors:zed-0.143.6:20240710-201212.log"), row: 34, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("crates/file_finder/src/file_finder.rs:1902:13:") ==
            PathWithPosition(path: Path("crates/file_finder/src/file_finder.rs"), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str("crate/utils/src/test:today.log:34") ==
            PathWithPosition(path: Path("crate/utils/src/test:today.log"), row: 34, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("/testing/out/src/file_finder.odin(7:15)") ==
            PathWithPosition(path: Path("/testing/out/src/file_finder.odin"), row: 7, column: 15)
        )
        #else
        #expect(
            PathWithPosition.parse_str("foo/bar:34:in", style: .Posix) ==
            PathWithPosition(path: Path("foo/bar"), row: 34, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("foo/bar.rs:1902:::15:", style: .Posix) ==
            PathWithPosition(path: Path("foo/bar.rs:1902"), row: 15, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("app-editors:zed-0.143.6:20240710-201212.log:34:", style: .Posix) ==
            PathWithPosition(path: Path("app-editors:zed-0.143.6:20240710-201212.log"), row: 34, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("crates/file_finder/src/file_finder.rs:1902:13:", style: .Posix) ==
            PathWithPosition(path: Path("crates/file_finder/src/file_finder.rs"), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str("crate/utils/src/test:today.log:34", style: .Posix) ==
            PathWithPosition(path: Path("crate/utils/src/test:today.log"), row: 34, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("/testing/out/src/file_finder.odin(7:15)", style: .Posix) ==
            PathWithPosition(path: Path("/testing/out/src/file_finder.odin"), row: 7, column: 15)
        )
        #endif
    }

    @Test
    func path_with_position_parse_windows_path() {
        #if os(Windows)
        #expect(
            PathWithPosition.parse_str(#"crates\utils\paths.rs"#) ==
            PathWithPosition(path: Path(#"crates\utils\paths.rs"#), row: nil, column: nil)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs"#) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: nil, column: nil)
        )
        #else
        #expect(
            PathWithPosition.parse_str(#"crates\utils\paths.rs"#, style: .Windows) ==
            PathWithPosition(path: Path(#"crates\utils\paths.rs"#), row: nil, column: nil)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs"#, style: .Windows) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: nil, column: nil)
        )
        #endif
    }

    @Test
    func path_with_position_parse_windows_path_with_suffix() {
        #if os(Windows)
        #expect(
            PathWithPosition.parse_str(#"crates\utils\paths.rs:101"#) ==
            PathWithPosition(path: Path(#"crates\utils\paths.rs"#), row: 101, column: nil)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs:1:20"#) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs"#), row: 1, column: 20)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs(1902,13)"#) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs:1902:13:"#) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs:1902:13:15:"#) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs:1902"#), row: 13, column: 15)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs:1902:::15:"#) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs:1902"#), row: 15, column: nil)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs(1902,13):"#) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs(1902):"#) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs"#), row: 1902, column: nil)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs:1902:13:"#) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs(1902,13):"#) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs(1902):"#) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: 1902, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("crates/utils/paths.rs:101") ==
            PathWithPosition(path: Path(#"crates\utils\paths.rs"#), row: 101, column: nil)
        )
        #else
        #expect(
            PathWithPosition.parse_str(#"crates\utils\paths.rs:101"#, style: .Windows) ==
            PathWithPosition(path: Path(#"crates\utils\paths.rs"#), row: 101, column: nil)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs:1:20"#, style: .Windows) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs"#), row: 1, column: 20)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs(1902,13)"#, style: .Windows) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs:1902:13:"#, style: .Windows) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs:1902:13:15:"#, style: .Windows) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs:1902"#), row: 13, column: 15)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs:1902:::15:"#, style: .Windows) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs:1902"#), row: 15, column: nil)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs(1902,13):"#, style: .Windows) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"\\?\C:\Users\someone\test_file.rs(1902):"#, style: .Windows) ==
            PathWithPosition(path: Path(#"\\?\C:\Users\someone\test_file.rs"#), row: 1902, column: nil)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs:1902:13:"#, style: .Windows) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs(1902,13):"#, style: .Windows) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: 1902, column: 13)
        )
        #expect(
            PathWithPosition.parse_str(#"C:\Users\someone\test_file.rs(1902):"#, style: .Windows) ==
            PathWithPosition(path: Path(#"C:\Users\someone\test_file.rs"#), row: 1902, column: nil)
        )
        #expect(
            PathWithPosition.parse_str("crates/utils/paths.rs:101", style: .Windows) ==
            PathWithPosition(path: Path(#"crates\utils\paths.rs"#), row: 101, column: nil)
        )
        #endif
    }

    @Test
    func test_path_compact() {
        let path = home_dir().join("some_file.txt")
        #if os(macOS) || os(Linux)
        #expect(path.compact().to_str() == "~/some_file.txt")
        #else
        #expect(path.compact().to_str() == path.to_str())
        #endif
    }

    @Test
    func test_extension_or_hidden_file_name() {
        #expect(Path("/a/b/c/file_name.rs").extension_or_hidden_file_name() == "rs")
        #expect(Path("/a/b/c/file.name.rs").extension_or_hidden_file_name() == "rs")
        #expect(Path("/a/b/c/long.file.name.rs").extension_or_hidden_file_name() == "rs")
        #expect(Path("/a/b/c/.gitignore").extension_or_hidden_file_name() == "gitignore")
        #expect(Path("/a/b/c/.eslintrc.js").extension_or_hidden_file_name() == "eslintrc.js")
    }

    @Test
    func test_sanitized_path() {
        #if os(Windows)
        let path1 = Path(#"C:\Users\someone\test_file.rs"#)
        let sanitized1 = SanitizedPath(path1)
        #expect(sanitized1.description == #"C:\Users\someone\test_file.rs"#)

        let path2 = Path(#"\\?\C:\Users\someone\test_file.rs"#)
        let sanitized2 = SanitizedPath(path2)
        #expect(sanitized2.description == #"C:\Users\someone\test_file.rs"#)
        #else
        let path1 = Path(#"C:\Users\someone\test_file.rs"#)
        let sanitized1 = SanitizedPath(path1)
        #expect(sanitized1.description == #"C:\Users\someone\test_file.rs"#)
        #endif
    }

    @Test
    func test_compare_numeric_segments() {
        func compare(_ a: String, _ b: String) -> Ordering {
            var aIter = PeekableIterator(a.makeIterator())
            var bIter = PeekableIterator(b.makeIterator())
            let result = compare_numeric_segments(&aIter, &bIter)
            #expect(aIter.next().map { $0.isNumber } != true, "Iterator a should have consumed all digits")
            #expect(bIter.next().map { $0.isNumber } != true, "Iterator b should have consumed all digits")
            return result
        }

        #expect(compare("0", "0") == .equal)
        #expect(compare("1", "2") == .less)
        #expect(compare("9", "10") == .less)
        #expect(compare("10", "9") == .greater)
        #expect(compare("99", "100") == .less)

        #expect(compare("0", "00") == .less)
        #expect(compare("00", "0") == .greater)
        #expect(compare("01", "1") == .greater)
        #expect(compare("001", "1") == .greater)
        #expect(compare("001", "01") == .greater)

        #expect(compare("000100", "100") == .greater)
        #expect(compare("100", "0100") == .less)
        #expect(compare("0100", "00100") == .less)

        #expect(compare("9999999999", "10000000000") == .less)
        #expect(compare("340282366920938463463374607431768211455", "340282366920938463463374607431768211456") == .less)
        #expect(compare("340282366920938463463374607431768211456", "340282366920938463463374607431768211455") == .greater)

        var aIter = PeekableIterator("123abc".makeIterator())
        var bIter = PeekableIterator("456def".makeIterator())
        _ = compare_numeric_segments(&aIter, &bIter)
        var remA = ""
        while let c = aIter.next() { remA.append(c) }
        var remB = ""
        while let c = bIter.next() { remB.append(c) }
        #expect(remA == "abc")
        #expect(remB == "def")
    }

    @Test
    func test_natural_sort() {
        #expect(natural_sort("a", "b") == .less)
        #expect(natural_sort("b", "a") == .greater)
        #expect(natural_sort("a", "a") == .equal)

        #expect(natural_sort("a", "A") == .less)
        #expect(natural_sort("A", "a") == .greater)
        #expect(natural_sort("aA", "aa") == .greater)
        #expect(natural_sort("aa", "aA") == .less)

        #expect(natural_sort("1", "2") == .less)
        #expect(natural_sort("2", "10") == .less)
        #expect(natural_sort("02", "10") == .less)
        #expect(natural_sort("02", "2") == .greater)

        #expect(natural_sort("a1", "a2") == .less)
        #expect(natural_sort("a2", "a10") == .less)
        #expect(natural_sort("a02", "a2") == .greater)
        #expect(natural_sort("a1b", "a1c") == .less)

        #expect(natural_sort("1a2", "1a10") == .less)
        #expect(natural_sort("1a10", "1a2") == .greater)
        #expect(natural_sort("2a1", "10a1") == .less)

        #expect(natural_sort("a-1", "a-2") == .less)
        #expect(natural_sort("a_1", "a_2") == .less)
        #expect(natural_sort("a.1", "a.2") == .less)

        #expect(natural_sort("文1", "文2") == .less)
        #expect(natural_sort("文2", "文10") == .less)
        #expect(natural_sort("🔤1", "🔤2") == .less)

        #expect(natural_sort("", "") == .equal)
        #expect(natural_sort("", "a") == .less)
        #expect(natural_sort("a", "") == .greater)
        #expect(natural_sort(" ", "  ") == .less)

        #expect(natural_sort("File-1.txt", "File-2.txt") == .less)
        #expect(natural_sort("File-02.txt", "File-2.txt") == .greater)
        #expect(natural_sort("File-2.txt", "File-10.txt") == .less)
        #expect(natural_sort("File_A1", "File_A2") == .less)
        #expect(natural_sort("File_a1", "File_A1") == .less)
    }

    @Test
    func test_compare_paths() {
        func compare(_ a: String, _ isAFile: Bool, _ b: String, _ isBFile: Bool) -> Ordering {
            compare_paths((Path(a), isAFile), (Path(b), isBFile))
        }

        #expect(compare("a", true, "b", true) == .less)
        #expect(compare("b", true, "a", true) == .greater)
        #expect(compare("a", true, "a", true) == .equal)

        #expect(compare("a", true, "a", false) == .greater)
        #expect(compare("a", false, "a", true) == .less)
        #expect(compare("b", false, "a", true) == .less)

        #expect(compare("a.txt", true, "a.md", true) == .greater)
        #expect(compare("a.md", true, "a.txt", true) == .less)
        #expect(compare("a", true, "a.txt", true) == .less)

        #expect(compare("dir/a", true, "dir/b", true) == .less)
        #expect(compare("dir1/a", true, "dir2/a", true) == .less)
        #expect(compare("dir/sub/a", true, "dir/a", true) == .less)

        #expect(compare("Dir/file", true, "dir/file", true) == .greater)
        #expect(compare("dir/File", true, "dir/file", true) == .greater)
        #expect(compare("dir/file", true, "Dir/File", true) == .less)

        #expect(compare(".hidden", true, "visible", true) == .less)
        #expect(compare("_special", true, "normal", true) == .less)
        #expect(compare(".config", false, ".data", false) == .less)

        #expect(compare("dir1/file", true, "dir2/file", true) == .less)
        #expect(compare("dir2/file", true, "dir10/file", true) == .less)
        #expect(compare("dir02/file", true, "dir2/file", true) == .greater)

        #expect(compare("/a", true, "/b", true) == .less)
        #expect(compare("/", false, "/a", true) == .less)

        #expect(compare("project/src/main.rs", true, "project/src/lib.rs", true) == .greater)
        #expect(compare("project/tests/test_1.rs", true, "project/tests/test_2.rs", true) == .less)
        #expect(compare("project/v1.0.0/README.md", true, "project/v1.10.0/README.md", true) == .less)
    }

    @Test
    func test_natural_sort_case_sensitivity() {
        #expect(natural_sort("a", "A") == .less)
        #expect(natural_sort("A", "a") == .greater)
        #expect(natural_sort("a", "a") == .equal)
        #expect(natural_sort("A", "A") == .equal)

        #expect(natural_sort("aaa", "AAA") == .less)
        #expect(natural_sort("AAA", "aaa") == .greater)
        #expect(natural_sort("aAa", "AaA") == .less)

        #expect(natural_sort("a", "b") == .less)
        #expect(natural_sort("A", "b") == .less)
        #expect(natural_sort("a", "B") == .less)
    }

    @Test
    func test_natural_sort_with_numbers() {
        #expect(natural_sort("file1", "file2") == .less)
        #expect(natural_sort("file2", "file10") == .less)
        #expect(natural_sort("file10", "file2") == .greater)

        #expect(natural_sort("1file", "2file") == .less)
        #expect(natural_sort("file1text", "file2text") == .less)
        #expect(natural_sort("text1file", "text2file") == .less)

        #expect(natural_sort("file1-2", "file1-10") == .less)
        #expect(natural_sort("2-1file", "10-1file") == .less)

        #expect(natural_sort("file002", "file2") == .greater)
        #expect(natural_sort("file002", "file10") == .less)

        #expect(natural_sort("file999999999999999999999", "file999999999999999999998") == .greater)
        #expect(natural_sort("file340282366920938463463374607431768211454", "file340282366920938463463374607431768211455") == .less)
        #expect(natural_sort("file340282366920938463463374607431768211456", "file340282366920938463463374607431768211455") == .greater)
        #expect(natural_sort("file3402823669209384634633746074317682114560", "file340282366920938463463374607431768211455") == .greater)
        #expect(natural_sort("file0340282366920938463463374607431768211455", "file340282366920938463463374607431768211455") == .greater)
        #expect(natural_sort("file999999999999999999999999999999999999999999999999", "file9999999999999999999999999999999999999999999999999") == .less)
    }

    @Test
    func test_natural_sort_case_sensitive() {
        #expect(natural_sort("File1", "file2") == .less)
        #expect(natural_sort("file1", "File2") == .less)

        #expect(natural_sort("Dir1", "dir01") == .less)
        #expect(natural_sort("dir2", "Dir02") == .less)
        #expect(natural_sort("dir2", "dir02") == .less)

        #expect(natural_sort("dir1", "Dir1") == .less)
        #expect(natural_sort("dir02", "Dir02") == .less)
        #expect(natural_sort("dir10", "Dir10") == .less)
    }

    @Test
    func test_natural_sort_edge_cases() {
        #expect(natural_sort("", "") == .equal)
        #expect(natural_sort("", "a") == .less)
        #expect(natural_sort("a", "") == .greater)

        #expect(natural_sort("file-1", "file_1") == .less)
        #expect(natural_sort("file.1", "file_1") == .less)
        #expect(natural_sort("file 1", "file_1") == .less)

        #expect(natural_sort("file①", "file②") == .less)
        #expect(natural_sort("file⑩", "file②") == .greater)
        #expect(natural_sort("file漢", "file字") == .greater)

        #expect(natural_sort("file-1a", "file-1b") == .less)
        #expect(natural_sort("file-1.2", "file-1.10") == .less)
        #expect(natural_sort("file-1.10", "file-1.2") == .greater)
    }

    @Test
    func test_multiple_extensions() {
        #expect(Path("/a/b/c/file_name").multiple_extensions() == nil)
        #expect(Path("/a/b/c/file_name.tsx").multiple_extensions() == nil)
        #expect(Path("/a/b/c/file_name.stories.tsx").multiple_extensions() == "stories.tsx")
        #expect(Path("/a/b/c/long.app.tar.gz").multiple_extensions() == "app.tar.gz")
    }

    @Test
    func test_strip_path_suffix() {
        let base1 = Path("/a/b/c/file_name")
        let suffix1 = Path("file_name")
        #expect(strip_path_suffix(base1, suffix1) == Path("/a/b/c"))

        let base2 = Path("/a/b/c/file_name.tsx")
        let suffix2 = Path("file_name.tsx")
        #expect(strip_path_suffix(base2, suffix2) == Path("/a/b/c"))

        let base3 = Path("/a/b/c/file_name.stories.tsx")
        let suffix3 = Path("c/file_name.stories.tsx")
        #expect(strip_path_suffix(base3, suffix3) == Path("/a/b"))

        let base4 = Path("/a/b/c/long.app.tar.gz")
        let suffix4 = Path("b/c/long.app.tar.gz")
        #expect(strip_path_suffix(base4, suffix4) == Path("/a"))

        let base5 = Path("/a/b/c/long.app.tar.gz")
        let suffix5 = Path("/a/b/c/long.app.tar.gz")
        #expect(strip_path_suffix(base5, suffix5) == Path(""))

        let base6 = Path("/a/b/c/long.app.tar.gz")
        let suffix6 = Path("/a/b/c/no_match.app.tar.gz")
        #expect(strip_path_suffix(base6, suffix6) == nil)

        let base7 = Path("/a/b/c/long.app.tar.gz")
        let suffix7 = Path("app.tar.gz")
        #expect(strip_path_suffix(base7, suffix7) == nil)
    }

    @Test
    func test_strip_prefix() {
        let cases: [(PathStyle, String, String, RelPath?)] = [
            (.Posix, "/a/b/c", "/a/b", rel_path("c")),
            (.Posix, "/a/b/c", "/a/b/", rel_path("c")),
            (.Posix, "/a/b/c", "/", rel_path("a/b/c")),
            (.Posix, "/a/b/c", "", nil),
            (.Posix, "/a/b//c", "/a/b/", nil),
            (.Posix, "/a/bc", "/a/b", nil),
            (.Posix, "/a/b/c", "/a/b/c", rel_path("")),
            (.Windows, #"C:\a\b\c"#, #"C:\a\b"#, rel_path("c")),
            (.Windows, #"C:\a\b\c"#, #"C:\a\b\"#, rel_path("c")),
            (.Windows, #"C:\a\b\c"#, #"C:\"#, rel_path("a/b/c")),
            (.Windows, #"C:\a\b\c"#, "", nil),
            (.Windows, #"C:\a\b\\c"#, #"C:\a\b\"#, nil),
            (.Windows, #"C:\a\bc"#, #"C:\a\b"#, nil),
            (.Windows, #"C:\a\b/c"#, #"C:\a\b"#, rel_path("c")),
            (.Windows, #"C:\a\b/c"#, #"C:\a\b\"#, rel_path("c")),
            (.Windows, #"C:\a\b/c"#, #"C:\a\b/"#, rel_path("c")),
        ]

        for (style, child, parent, expected) in cases {
            let actual = style.strip_prefix(Path(child), Path(parent))
            #expect(actual?.value == expected, "strip_prefix failed for \(child) with parent \(parent)")
        }

    }

    @Test
    func test_wsl_path() {
        #expect(WslPath.from_path("/a/b/c") == nil)
        #expect(WslPath.from_path(#"\\wsl.localhost"#) == nil)
        #expect(WslPath.from_path(#"\\wsl.localhost\Distro"#) == WslPath(distro: "Distro", path: "/"))
        #expect(WslPath.from_path(#"\\wsl.localhost\Distro\blue"#) == WslPath(distro: "Distro", path: "/blue"))
        #expect(WslPath.from_path(#"\\wsl$\archlinux\tomato\.\paprika\..\aubergine.txt"#) == WslPath(distro: "archlinux", path: "/tomato/paprika/../aubergine.txt"))
        #expect(WslPath.from_path(#"\\windows.localhost\Distro\foo"#) == nil)
    }

    @Test
    func test_url_to_file_path_ext_posix_basic() {
        let url1 = URL(string: "file:///home/user/file.txt")!
        #expect(url1.to_file_path_ext(.Posix) == .success(Path("/home/user/file.txt")))

        let url2 = URL(string: "file:///")!
        #expect(url2.to_file_path_ext(.Posix) == .success(Path("/")))

        let url3 = URL(string: "file:///a/b/c/d/e")!
        #expect(url3.to_file_path_ext(.Posix) == .success(Path("/a/b/c/d/e")))
    }

    @Test
    func test_url_to_file_path_ext_posix_percent_encoding() {
        let url1 = URL(string: "file:///home/user/file%20with%20spaces.txt")!
        #expect(url1.to_file_path_ext(.Posix) == .success(Path("/home/user/file with spaces.txt")))

        let url2 = URL(string: "file:///path%2Fwith%2Fencoded%2Fslashes")!
        #expect(url2.to_file_path_ext(.Posix) == .success(Path("/path/with/encoded/slashes")))

        let url3 = URL(string: "file:///special%23chars%3F.txt")!
        #expect(url3.to_file_path_ext(.Posix) == .success(Path("/special#chars?.txt")))
    }

    @Test
    func test_url_to_file_path_ext_posix_localhost() {
        let url = URL(string: "file://localhost/home/user/file.txt")!
        #expect(url.to_file_path_ext(.Posix) == .success(Path("/home/user/file.txt")))
    }

    @Test
    func test_url_to_file_path_ext_posix_rejects_host() {
        let url = URL(string: "file://somehost/home/user/file.txt")!
        #expect(url.to_file_path_ext(.Posix).isFailure)
    }

    @Test
    func test_url_to_file_path_ext_posix_windows_drive_letter() {
        let url1 = URL(string: "file:///C:")!
        #expect(url1.to_file_path_ext(.Posix) == .success(Path("/C:/")))

        let url2 = URL(string: "file:///D|")!
        #expect(url2.to_file_path_ext(.Posix) == .success(Path("/D|/")))
    }

    @Test
    func test_url_to_file_path_ext_windows_basic() {
        let url1 = URL(string: "file:///C:/Users/user/file.txt")!
        #expect(url1.to_file_path_ext(.Windows) == .success(Path(#"C:\Users\user\file.txt"#)))

        let url2 = URL(string: "file:///D:/folder/subfolder/file.rs")!
        #expect(url2.to_file_path_ext(.Windows) == .success(Path(#"D:\folder\subfolder\file.rs"#)))

        let url3 = URL(string: "file:///C:/")!
        #expect(url3.to_file_path_ext(.Windows) == .success(Path(#"C:\"#)))
    }

    @Test
    func test_url_to_file_path_ext_windows_encoded_drive_letter() {
        let url1 = URL(string: "file:///C%3A/Users/file.txt")!
        #expect(url1.to_file_path_ext(.Windows) == .success(Path(#"C:\Users\file.txt"#)))

        let url2 = URL(string: "file:///c%3a/Users/file.txt")!
        #expect(url2.to_file_path_ext(.Windows) == .success(Path(#"c:\Users\file.txt"#)))

        let url3 = URL(string: "file:///D%3A/folder/file.txt")!
        #expect(url3.to_file_path_ext(.Windows) == .success(Path(#"D:\folder\file.txt"#)))

        let url4 = URL(string: "file:///d%3A/folder/file.txt")!
        #expect(url4.to_file_path_ext(.Windows) == .success(Path(#"d:\folder\file.txt"#)))
    }

    @Test
    func test_url_to_file_path_ext_windows_unc_path() {
        let url1 = URL(string: "file://server/share/path/file.txt")!
        #expect(url1.to_file_path_ext(.Windows) == .success(Path(#"\\server\share\path\file.txt"#)))

        let url2 = URL(string: "file://server/share")!
        #expect(url2.to_file_path_ext(.Windows) == .success(Path(#"\\server\share"#)))
    }

    @Test
    func test_url_to_file_path_ext_windows_percent_encoding() {
        let url1 = URL(string: "file:///C:/Users/user/file%20with%20spaces.txt")!
        #expect(url1.to_file_path_ext(.Windows) == .success(Path(#"C:\Users\user\file with spaces.txt"#)))

        let url2 = URL(string: "file:///C:/special%23chars%3F.txt")!
        #expect(url2.to_file_path_ext(.Windows) == .success(Path(#"C:\special#chars?.txt"#)))
    }

    @Test
    func test_url_to_file_path_ext_windows_invalid_drive() {
        let url1 = URL(string: "file:///1:/path/file.txt")!
        #expect(url1.to_file_path_ext(.Windows).isFailure)

        let url2 = URL(string: "file:///CC:/path/file.txt")!
        #expect(url2.to_file_path_ext(.Windows).isFailure)

        let url3 = URL(string: "file:///C/path/file.txt")!
        #expect(url3.to_file_path_ext(.Windows).isFailure)

        let url4 = URL(string: "file:///invalid")!
        #expect(url4.to_file_path_ext(.Windows).isFailure)
    }

    @Test
    func test_url_to_file_path_ext_non_file_scheme() {
        let url1 = URL(string: "http://example.com/path")!
        #expect(url1.to_file_path_ext(.Posix).isFailure)
        #expect(url1.to_file_path_ext(.Windows).isFailure)

        let url2 = URL(string: "https://example.com/path")!
        #expect(url2.to_file_path_ext(.Posix).isFailure)
        #expect(url2.to_file_path_ext(.Windows).isFailure)
    }

    @Test
    func test_url_to_file_path_ext_windows_localhost() {
        let url = URL(string: "file://localhost/C:/Users/file.txt")!
        #expect(url.to_file_path_ext(.Windows) == .success(Path(#"C:\Users\file.txt"#)))
    }
}
