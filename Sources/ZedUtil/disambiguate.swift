// Ported from: crates/util/src/disambiguate.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

/// Computes the minimum detail level needed for each item so that no two items
/// share the same description. Items whose descriptions are unique at level 0
/// stay at 0; items that collide get their detail level incremented until either
/// the collision is resolved or increasing the level no longer changes the
/// description (preventing infinite loops for truly identical items).
///
/// The `getDescription` closure must return a sequence that eventually reaches
/// a "fixed point" where increasing `detail` no longer changes the output. If
/// an item reaches its fixed point, it is assumed it will no longer change and
/// will no longer be checked for collisions.
public func computeDisambiguationDetails<T, D: Hashable>(
    _ items: [T],
    getDescription: (T, Int) -> D
) -> [Int] {
    var details = [Int](repeating: 0, count: items.count)
    var descriptions = [D: [Int]]()
    var currentDescriptions: [D] = items.map { item in
        getDescription(item, 0)
    }

    while true {
        var anyCollisions = false
        descriptions.removeAll(keepingCapacity: true)

        for (index, item) in items.enumerated() {
            let detail = details[index]
            if detail > 0 {
                let newDescription = getDescription(item, detail)
                if newDescription == currentDescriptions[index] {
                    continue
                }
                currentDescriptions[index] = newDescription
            }
            descriptions[currentDescriptions[index], default: []].append(index)
        }

        for (_, indices) in descriptions {
            if indices.count > 1 {
                anyCollisions = true
                for index in indices {
                    details[index] += 1
                }
            }
        }

        if !anyCollisions {
            break
        }
    }

    return details
}
