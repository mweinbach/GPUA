// Ported from: crates/gpui/src/_ownership_and_data_flow.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// # GPUI Ownership and Data Flow Guide
///
/// In GPUI, every model or view in the application is owned by a single top-level object called `App`.
/// When a new entity or view is created, the application is given ownership of their state to enable
/// participation in app services and interaction with other entities.
///
/// ## Entity Handles
/// Calling `cx.new(...)` returns an `Entity<T>` handle. By itself, this handle doesn't provide direct
/// mutable access to the entity's state. It is an inert identifier maintaining a reference-counted
/// pointer to the underlying object owned by the app.
///
/// ## Observation and Subscription
/// Entities can observe state changes via `cx.observe(...)` and notify observers via `cx.notify()`.
/// Entities can also emit typed events by conforming to `EventEmitter<Event>` and subscribing with
/// `cx.subscribe(...)`.
public enum OwnershipAndDataFlowGuide {}
