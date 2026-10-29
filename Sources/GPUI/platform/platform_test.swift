// Ported from: crates/gpui/src/platform/test.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// MARK: - Platform Test Re-exports
// Matches upstream crates/gpui/src/platform/test.rs which declares the test platform module
// and re-exports TestDispatcher, TestPlatform, TestDisplay, TestWindow, and ScreenCapture types.

public typealias PlatformTestDispatcher = TestDispatcher
public typealias PlatformTestPlatform = TestPlatform
public typealias PlatformTestDisplay = TestDisplay
public typealias PlatformTestWindow = TestWindow
