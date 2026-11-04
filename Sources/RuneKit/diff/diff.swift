// Ported from: crates/rune-kit/src/diff/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A diff view for reviewing changes: files of hunks, unified or split, with word changes,
//! syntax colours, expandable unchanged ranges, line annotations and line selection, on a
//! virtual list that keeps a fifty-thousand-line diff at frame rate.
//!
//! `diff.parse` reads a patch (`git diff`) and ``FileDiff/fromTexts(_:_:_:)`` diffs two texts.
//! The app keeps a ``DiffState`` of the files in its state and draws it with ``DiffView``.

/// Namespace mirroring `rune_kit::diff`.
public enum diff {
    public typealias FileDiff = RuneKit.FileDiff
    public typealias FileStatus = RuneKit.FileStatus
    public typealias Hunk = RuneKit.Hunk
    public typealias Line = RuneKit.Line
    public typealias LineKind = RuneKit.LineKind
    public typealias Side = RuneKit.DiffSide
    public typealias Annotation = RuneKit.Annotation
    public typealias DiffMode = RuneKit.DiffMode
    public typealias DiffState = RuneKit.DiffState
    public typealias Expand = RuneKit.Expand
    public typealias LineRange = RuneKit.LineRange
    public typealias LineRef = RuneKit.LineRef
    public typealias DiffView<S> = RuneKit.DiffView<S>

    /// Lines one expand step reveals.
    public static let EXPAND_STEP: UInt32 = RuneKit.EXPAND_STEP

    /// Every file in a unified diff, as `git diff`, `git show`, `git format-patch` or `diff -u`
    /// write them: renames, copies, mode changes, added and deleted files, binary files and
    /// `\ No newline at end of file` included.
    public static func parse(_ patch: String) -> [FileDiff] {
        parseDiffPatch(patch)
    }
}
