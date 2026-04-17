import Foundation

/// Fixed-capacity FIFO buffer backed by a contiguous array with head/count
/// pointers. Appending past capacity overwrites the oldest element; explicit
/// `popFirst()` drops the oldest. Indexing and iteration are in insertion
/// order (oldest first).
struct RingBuffer<Element>: Sequence {
    let capacity: Int

    private var storage: [Element?]
    private var head: Int = 0
    private(set) var count: Int = 0

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    var isEmpty: Bool { count == 0 }
    var isFull: Bool { count == capacity }

    var first: Element? {
        guard count > 0 else { return nil }
        return storage[head]
    }

    var last: Element? {
        guard count > 0 else { return nil }
        return storage[(head + count - 1) % capacity]
    }

    subscript(index: Int) -> Element {
        precondition(index >= 0 && index < count, "RingBuffer index out of bounds")
        return storage[(head + index) % capacity]!
    }

    /// Append a new element. If the buffer is full, the oldest element is
    /// overwritten. Callers that need a side effect on eviction should check
    /// `isFull` and call `popFirst()` first.
    mutating func append(_ element: Element) {
        let writeIndex = (head + count) % capacity
        storage[writeIndex] = element
        if count < capacity {
            count += 1
        } else {
            head = (head + 1) % capacity
        }
    }

    /// Remove and return the oldest element.
    @discardableResult
    mutating func popFirst() -> Element? {
        guard count > 0 else { return nil }
        let element = storage[head]
        storage[head] = nil
        head = (head + 1) % capacity
        count -= 1
        return element
    }

    mutating func removeAll() {
        for i in 0..<capacity { storage[i] = nil }
        head = 0
        count = 0
    }

    func makeIterator() -> AnyIterator<Element> {
        var index = 0
        return AnyIterator {
            guard index < self.count else { return nil }
            let element = self[index]
            index += 1
            return element
        }
    }
}
