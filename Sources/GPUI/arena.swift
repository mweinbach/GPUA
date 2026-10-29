// Ported from: crates/gpui/src/arena.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

private struct ArenaElement {
    let value: UnsafeMutableRawPointer
    let deallocator: (UnsafeMutableRawPointer) -> Void
}

private final class Chunk {
    let start: UnsafeMutableRawPointer
    let size: Int
    var offset: Int

    init(size: Int) {
        self.size = size
        self.offset = 0
        self.start = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    }

    deinit {
        start.deallocate()
    }

    func allocate(size: Int, alignment: Int) -> UnsafeMutableRawPointer? {
        let currentAddr = Int(bitPattern: start.advanced(by: offset))
        let remainder = currentAddr % alignment
        let padding = remainder == 0 ? 0 : (alignment - remainder)
        let newOffset = offset + padding + size

        if newOffset <= self.size {
            let ptr = start.advanced(by: offset + padding)
            self.offset = newOffset
            return ptr
        } else {
            return nil
        }
    }

    func reset() {
        self.offset = 0
    }
}

// PORT NOTE: Reference cell tracking validity of ArenaBox references across clear() invocations.
private final class ArenaValidFlag: @unchecked Sendable {
    var isValid: Bool = true
}

/// An arena memory allocator for fast allocation of homogeneous or heterogeneous items with batch release.
public struct Arena {
    private var chunks: [Chunk]
    private var elements: [ArenaElement]
    private var valid: ArenaValidFlag
    private var currentChunkIndex: Int
    private var chunkSize: Int

    public init(chunkSize: Int) {
        self.chunkSize = Swift.max(1, chunkSize)
        self.chunks = [Chunk(size: self.chunkSize)]
        self.elements = []
        self.valid = ArenaValidFlag()
        self.currentChunkIndex = 0
    }

    public static func new(_ chunkSize: Int) -> Arena {
        Arena(chunkSize: chunkSize)
    }

    public func capacity() -> Int {
        chunks.count * chunkSize
    }

    public mutating func clear() {
        valid.isValid = false
        valid = ArenaValidFlag()
        for element in elements {
            element.deallocator(element.value)
        }
        elements.removeAll(keepingCapacity: true)
        for i in 0...currentChunkIndex {
            chunks[i].reset()
        }
        currentChunkIndex = 0
    }

    public mutating func alloc<T>(_ f: () -> T) -> ArenaBox<T> {
        let size = MemoryLayout<T>.size
        let alignment = MemoryLayout<T>.alignment
        var currentChunk = chunks[currentChunkIndex]
        let rawPtr: UnsafeMutableRawPointer

        if let ptr = currentChunk.allocate(size: size, alignment: alignment) {
            rawPtr = ptr
        } else {
            currentChunkIndex += 1
            if currentChunkIndex >= chunks.count {
                chunks.append(Chunk(size: chunkSize))
            }
            currentChunk = chunks[currentChunkIndex]
            guard let ptr = currentChunk.allocate(size: size, alignment: alignment) else {
                fatalError("Arena chunk size of \(chunkSize) is too small to allocate \(size) bytes")
            }
            rawPtr = ptr
        }

        let typedPtr = rawPtr.bindMemory(to: T.self, capacity: 1)
        typedPtr.initialize(to: f())

        elements.append(ArenaElement(value: rawPtr) { ptr in
            let typed = ptr.assumingMemoryBound(to: T.self)
            typed.deinitialize(count: 1)
        })

        return ArenaBox(pointer: typedPtr, valid: valid)
    }
}

/// A handle to a value allocated in an Arena.
public struct ArenaBox<T> {
    public let pointer: UnsafeMutablePointer<T>
    private let valid: ArenaValidFlag

    fileprivate init(pointer: UnsafeMutablePointer<T>, valid: ArenaValidFlag) {
        self.pointer = pointer
        self.valid = valid
    }

    public var pointee: T {
        _read {
            validate()
            yield pointer.pointee
        }
        _modify {
            validate()
            yield &pointer.pointee
        }
    }

    public func map<U>(_ f: (inout T) -> UnsafeMutablePointer<U>) -> ArenaBox<U> {
        validate()
        return ArenaBox<U>(pointer: f(&pointer.pointee), valid: valid)
    }

    private func validate() {
        precondition(valid.isValid, "attempted to dereference an ArenaRef after its Arena was cleared")
    }
}
