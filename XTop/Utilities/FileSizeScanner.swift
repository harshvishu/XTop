import Foundation

enum FileSizeScanner {
    static func directorySize(atPath path: String) -> UInt64 {
        let fileManager = FileManager.default
        var total: UInt64 = 0

        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return 0
        }

        for case let element as String in enumerator {
            let fullPath = (path as NSString).appendingPathComponent(element)
            do {
                let attrs = try fileManager.attributesOfItem(atPath: fullPath)
                if let fileSize = attrs[.size] as? NSNumber {
                    total += fileSize.uint64Value
                }
            } catch {
                continue
            }
        }

        return total
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
