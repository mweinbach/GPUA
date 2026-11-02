// Ported from: crates/rune/src/cold.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A field most elements leave at its default, kept behind a reference-counted box so `El`
//! and `Node` stay small to move and free to clone across commits.

// PORT NOTE: Uses Swift copy-on-write (`isKnownUniquelyReferenced`) over a private reference box,
// matching Rust's `Option<Rc<T>>` + `Rc::make_mut` semantics in idiomatic Swift.
protocol ColdEmpty {
    static var emptyValue: Self { get }
}

final class ColdStorage<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

struct Cold<T: ColdEmpty> {
    private var box: ColdStorage<T>?

    init() {
        self.box = nil
    }

    init(owned value: T) {
        self.box = ColdStorage(value)
    }

    var isEmpty: Bool {
        box == nil
    }

    var valueOrEmpty: T {
        box?.value ?? T.emptyValue
    }

    var value: T {
        get { box?.value ?? T.emptyValue }
        set {
            if box == nil {
                box = ColdStorage(newValue)
            } else if !isKnownUniquelyReferenced(&box) {
                box = ColdStorage(newValue)
            } else {
                box!.value = newValue
            }
        }
    }

    var getIfSome: T? {
        box?.value
    }

    func get() -> T? {
        box?.value
    }

    mutating func modify<R>(_ body: (inout T) -> R) -> R {
        if box == nil {
            box = ColdStorage(T.emptyValue)
        } else if !isKnownUniquelyReferenced(&box) {
            box = ColdStorage(box!.value)
        }
        return body(&box!.value)
    }

    mutating func modifyIfPresent(_ body: (inout T) -> Void) {
        guard box != nil else { return }
        if !isKnownUniquelyReferenced(&box) {
            box = ColdStorage(box!.value)
        }
        body(&box!.value)
    }

    static func ptrEq(_ a: Cold<T>, _ b: Cold<T>) -> Bool {
        switch (a.box, b.box) {
        case (nil, nil): return true
        case (let x?, let y?): return x === y
        default: return false
        }
    }
}

/// A heap-allocated value shared across `MemoCache`, `El` and `Node`, copied only when mutated.
struct SharedBox<T> {
    private var storage: ColdStorage<T>

    init(_ value: T) {
        self.storage = ColdStorage(value)
    }

    var value: T {
        get { storage.value }
        set {
            if !isKnownUniquelyReferenced(&storage) {
                storage = ColdStorage(newValue)
            } else {
                storage.value = newValue
            }
        }
    }

    mutating func modify<R>(_ body: (inout T) -> R) -> R {
        if !isKnownUniquelyReferenced(&storage) {
            storage = ColdStorage(storage.value)
        }
        return body(&storage.value)
    }

    static func ptrEq(_ a: SharedBox<T>, _ b: SharedBox<T>) -> Bool {
        a.storage === b.storage
    }
}
