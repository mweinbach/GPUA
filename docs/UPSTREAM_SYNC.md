# Upstream Sync

GPUA tracks **[Glass-HQ/gpui](https://github.com/Glass-HQ/gpui)**, pinned to one commit in [`porting.json`](../porting.json). Every Swift file records the upstream commit it was last synced to (`// Upstream commit:`).

## Bumping the pin

```sh
Scripts/port.py fetch --full          # full history is needed for diffs between commits
Scripts/port.py bump <new-commit>     # updates porting.json, prints changed upstream files
Scripts/port.py scaffold              # stubs for any new upstream files
Scripts/port.py stale                 # ported files whose upstream changed, with diffstats
Scripts/port.py status --write
Scripts/port.py check
```

Do the bump in its own PR (`chore: bump upstream to <sha>`). It adds stubs and updates the status doc, but changes no Swift logic.

## Re-porting a stale file

1. `git -C .upstream/gpui diff <file-commit> <pinned-commit> -- <upstream path>`
2. Apply the same change to the Swift file, following the porting guide.
3. Set `// Upstream commit:` to the pinned commit.
4. One PR per file or cluster: `sync(GPUI): elements/div.rs to <sha>`.

## Deleted or moved upstream files

- **Deleted:** `check` reports the Swift file as an orphan. Delete it (and its paired test file) in the bump PR.
- **Renamed/moved:** move the Swift file to the new mapped path (`Scripts/port.py map`) and update `// Ported from:`. Use `git mv` so history follows.

## New upstream crates

Add an entry to `porting.json` with a `decision` (`port`, `skip`, `replace`, or `deferred`). If it's `port`, add the target to `Package.swift` with the same dependencies as the crate's `Cargo.toml`, then run `scaffold`.

## Contributing back

If porting turns up an upstream bug, fix it upstream first when you can and link the PR in a `// PORT NOTE:`. Keep GPUA's behavior identical to the pinned upstream until the fix lands and we bump.
