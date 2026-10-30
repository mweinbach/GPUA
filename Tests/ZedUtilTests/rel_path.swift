// Tests ported from: crates/util/src/rel_path.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import Foundation
@testable import ZedUtil

@Suite("RelPath Tests")
struct RelPathTests {
    @Test
    func test_rel_path_new() throws {
        #expect(throws: (any Error).self) { try RelPath.new(Path("/"), .local()) }
        #expect(throws: (any Error).self) { try RelPath.new(Path("//"), .local()) }
        #expect(throws: (any Error).self) { try RelPath.new(Path("/foo/"), .local()) }

        let path1 = try RelPath.new(Path("foo/"), .local())
        #expect(path1.value == rel_path("foo"))
        #expect(path1.isBorrowed)

        let path2 = try RelPath.new(Path(#"foo\"#), .Windows)
        #expect(path2.value == rel_path("foo"))
        #expect(path2.isBorrowed)

        #expect(
            try RelPath.new(Path("foo/bar/../baz/./quux/"), .local()).value ==
            rel_path("foo/baz/quux")
        )

        let path3 = try RelPath.new(Path("./foo/bar"), .Posix)
        #expect(path3.value == rel_path("foo/bar"))
        #expect(path3.isBorrowed)

        let path4 = try RelPath.new(Path(#".\foo"#), .Windows)
        #expect(path4.value == rel_path("foo"))
        #expect(path4.isBorrowed)

        let path5 = try RelPath.new(Path(#"./.\./foo/\/\"#), .Windows)
        #expect(path5.value == rel_path("foo"))
        #expect(path5.isBorrowed)

        let path6 = try RelPath.new(Path("foo/./bar"), .Posix)
        #expect(path6.value == rel_path("foo/bar"))
        #expect(path6.isOwned)

        let path7 = try RelPath.new(Path("./foo/bar"), .Windows)
        #expect(path7.value == rel_path("foo/bar"))
        #expect(path7.isBorrowed)

        let path8 = try RelPath.new(Path(#".\foo\bar"#), .Windows)
        #expect(path8.value == rel_path("foo/bar"))
        #expect(path8.isOwned)
    }

    @Test
    func test_rel_path_components() {
        let path = rel_path("foo/bar/baz")
        #expect(path.components().map { String($0) } == ["foo", "bar", "baz"])
        #expect(Array(path.components().reversed()).map { String($0) } == ["baz", "bar", "foo"])

        let emptyPath = rel_path("")
        var components = emptyPath.components().makeIterator()
        #expect(components.next() == nil)
    }

    @Test
    func test_rel_path_ancestors() {
        let path = rel_path("foo/bar/baz")
        var ancestors = path.ancestors().makeIterator()
        #expect(ancestors.next() == rel_path("foo/bar/baz"))
        #expect(ancestors.next() == rel_path("foo/bar"))
        #expect(ancestors.next() == rel_path("foo"))
        #expect(ancestors.next() == rel_path(""))
        #expect(ancestors.next() == nil)

        let pathFoo = rel_path("foo")
        var ancestorsFoo = pathFoo.ancestors().makeIterator()
        #expect(ancestorsFoo.next() == rel_path("foo"))
        #expect(ancestorsFoo.next() == RelPath.empty())
        #expect(ancestorsFoo.next() == nil)

        let pathEmpty = RelPath.empty()
        var ancestorsEmpty = pathEmpty.ancestors().makeIterator()
        #expect(ancestorsEmpty.next() == RelPath.empty())
        #expect(ancestorsEmpty.next() == nil)
    }

    @Test
    func test_rel_path_parent() {
        #expect(rel_path("foo/bar/baz").parent() == rel_path("foo/bar"))
        #expect(rel_path("foo").parent() == RelPath.empty())
        #expect(rel_path("").parent() == nil)
    }

    @Test
    func test_rel_path_partial_ord_is_compatible_with_std() throws {
        let testCases = ["a/b/c", "relative/path/with/dot.", "relative/path/with.dot"]
        for i in 0..<testCases.count {
            for j in 0..<testCases.count where i != j {
                let lhs = testCases[i]
                let rhs = testCases[j]
                let pathCmp = Path(lhs).cmp(Path(rhs))
                let relCmp = (try RelPath.unix(lhs)).cmp(try RelPath.unix(rhs))
                #expect(pathCmp == relCmp)
            }
        }
    }

    @Test
    func test_strip_prefix() throws {
        let parent = rel_path("")
        let child = rel_path(".foo")

        #expect(child.starts_with(parent))
        #expect(try child.strip_prefix(parent) == child)
    }

    @Test
    func test_rel_path_constructors_absolute_path() {
        #expect(throws: (any Error).self) { try RelPath.new(Path("/a/b"), .Windows) }
        #expect(throws: (any Error).self) { try RelPath.new(Path(#"\a\b"#), .Windows) }
        #expect(throws: (any Error).self) { try RelPath.new(Path("/a/b"), .Posix) }
        #expect(throws: (any Error).self) { try RelPath.new(Path("C:/a/b"), .Windows) }
        #expect(throws: (any Error).self) { try RelPath.new(Path(#"C:\a\b"#), .Windows) }
        #expect(throws: Never.self) { try RelPath.new(Path("C:/a/b"), .Posix) }
    }

    @Test
    func test_pop() {
        var path = rel_path("a/b").to_rel_path_buf()
        path.pop()
        #expect(path.as_rel_path().as_unix_str() == "a")
        path.pop()
        #expect(path.as_rel_path().as_unix_str() == "")
        path.pop()
        #expect(path.as_rel_path().as_unix_str() == "")
    }
}
