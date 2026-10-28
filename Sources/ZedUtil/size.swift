// Ported from: crates/util/src/size.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public func formatFileSize(_ size: UInt64, _ useDecimal: Bool) -> String {
    if useDecimal {
        if size < 1000 {
            return "\(size)B"
        } else if size < 1000 * 1000 {
            return String(format: "%.1fKB", Double(size) / 1000.0)
        } else {
            return String(format: "%.1fMB", Double(size) / (1000.0 * 1000.0))
        }
    } else if size < 1024 {
        return "\(size)B"
    } else if size < 1024 * 1024 {
        return String(format: "%.1fKiB", Double(size) / 1024.0)
    } else {
        return String(format: "%.1fMiB", Double(size) / (1024.0 * 1024.0))
    }
}
