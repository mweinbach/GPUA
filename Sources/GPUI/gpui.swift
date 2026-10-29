// Ported from: crates/gpui/src/gpui.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// MARK: - GPUI Crate Root Declarations

/// The manifest directory for GPUI resources, matching upstream GPUI_MANIFEST_DIR.
public let gpuiManifestDir: String = ""

// Re-exports of crate-level types and protocols matching upstream gpui.rs
public typealias GPUIAppContext = AppContext
public typealias GPUIReservation<T> = Reservation<T>
public typealias GPUIEventEmitter<E> = EventEmitter<E>
public typealias GPUIBorrowAppContext = BorrowAppContext
public typealias GPUIGpuSpecs = GpuSpecs
