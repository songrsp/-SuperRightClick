import Foundation
import CryptoKit

/// 文件哈希（流式读取，大文件也不爆内存）。
enum HashUtil {

    static func sha256(of path: String) -> String? {
        digest(path, hasher: SHA256())
    }

    static func md5(of path: String) -> String? {
        digest(path, hasher: Insecure.MD5())
    }

    private static func digest<H: HashFunction>(_ path: String, hasher: H) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var h = hasher
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1 << 20)   // 1MB
            if chunk.isEmpty { return false }
            h.update(data: chunk)
            return true
        }) {}
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
