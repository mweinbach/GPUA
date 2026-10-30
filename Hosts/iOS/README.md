# GPUIiOS Host Shell (`Hosts/iOS`)

Native Swift + XcodeGen iOS host shell for GPUA (`Sources/GPUIiOS`), ported from upstream `hosts/ios/` per [ADR-0011](../../docs/adr/0011-mobile-and-web-host-shells.md).

Unlike the upstream Rust host project (which invokes `cargo gpui host build-rust ios` in a pre-build script and links a static `-lgpui_ios` C archive from Objective-C `main.m`), this host references the root `GPUA` SwiftPM package directly (`path: ../..`) and launches `GPUIiOS` from a native Swift 6 `@main` `UIApplicationDelegate` (`runner/AppMain.swift`).

## Prerequisites

- macOS with Xcode 16+ and an iOS 17.0+ Simulator runtime installed
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Generate the Xcode Project

```sh
cd Hosts/iOS
xcodegen generate
```

`GPUIiOS.xcodeproj` and `Hosts/iOS/build/` are gitignored; `project.yml` is the source of truth.

## Build for iOS Simulator

```sh
xcodebuild \
  -project Hosts/iOS/GPUIiOS.xcodeproj \
  -scheme GPUIiOS \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Run a Specific Demo in Simulator

`AppMain.swift` resolves the initial demo in the same priority order as upstream `hosts/ios/runner/main.m`:

1. `GPUI_IOS_DEMO` environment variable (`SIMCTL_CHILD_GPUI_IOS_DEMO` via `simctl launch`)
2. Command-line argument matching one of the built-in demo names (`hello_world`, `text`, `scrollable`, `input`, `gradient`, `shadow`, `flex_wrap`, `grid_layout`, etc.)
3. Most recently launched demo stored in `UserDefaults` (`GPUI_IOS_LAST_DEMO`)
4. Default fallback: `"hello_world"`

Example launch on a booted simulator:

```sh
SIMCTL_CHILD_GPUI_IOS_DEMO=scrollable xcrun simctl launch booted dev.glasshq.GPUIiOS
```

## Deep Links (`gpui://`)

`Info.plist` registers the `gpui` URL scheme (`CFBundleURLTypes`) and forwards incoming URLs through `gpui_ios_handle_open_url` to `Platform.onOpenUrls`:

```sh
xcrun simctl openurl booted "gpui://demo/hello_world"
```

## Physical Device Signing

Open `Hosts/iOS/GPUIiOS.xcodeproj` in Xcode and select your Apple Developer Team under **Signing & Capabilities** (or pass `DEVELOPMENT_TEAM=<TEAM_ID>` to `xcodebuild`).
