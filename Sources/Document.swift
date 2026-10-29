//
//  Document.swift
//  记事本 —— 数据层：编码识别 / 行尾识别 / 文件读写 / 行号索引
//

import Foundation

// MARK: - 编码

enum TextEncoding: Int, CaseIterable {
    case utf8 = 0
    case utf8BOM
    case utf16LE
    case utf16BE
    case ansi

    var displayName: String {
        switch self {
        case .utf8:     return "UTF-8"
        case .utf8BOM:  return "UTF-8 带 BOM"
        case .utf16LE:  return "UTF-16 LE"
        case .utf16BE:  return "UTF-16 BE"
        case .ansi:     return "ANSI"
        }
    }

    var bomBytes: [UInt8] {
        switch self {
        case .utf8BOM:  return [0xEF, 0xBB, 0xBF]
        case .utf16LE:  return [0xFF, 0xFE]
        case .utf16BE:  return [0xFE, 0xFF]
        default:        return []
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8BOM: return .utf8
        case .utf16LE:        return .utf16LittleEndian
        case .utf16BE:        return .utf16BigEndian
        case .ansi:           return TextEncoding.gb18030
        }
    }

    /// Windows 的 "ANSI" 在中文系统即 GBK/GB18030。macOS 上取 GB18030（GBK 的超集）。
    static let gb18030: String.Encoding = {
        let cf = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: cf)
    }()
}

// MARK: - 行尾

enum LineEnding: Int, CaseIterable {
    case crlf = 0
    case lf
    case cr

    var displayName: String {
        switch self {
        case .crlf: return "Windows (CRLF)"
        case .lf:   return "Unix (LF)"
        case .cr:   return "Macintosh (CR)"
        }
    }

    var sequence: String {
        switch self {
        case .crlf: return "\r\n"
        case .lf:   return "\n"
        case .cr:   return "\r"
        }
    }

    static func detect(in data: Data) -> LineEnding {
        var crlf = 0, lf = 0, cr = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let limit = min(data.count, 1_000_000)
            guard let base = raw.baseAddress else { return }
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            var i = 0
            while i < limit {
                let b = bytes[i]
                if b == 13 {
                    if i + 1 < limit && bytes[i + 1] == 10 {
                        crlf += 1
                        i += 1
                    } else {
                        cr += 1
                    }
                } else if b == 10 {
                    lf += 1
                }
                i += 1
            }
        }
        if crlf >= lf && crlf >= cr && crlf > 0 { return .crlf }
        if lf >= cr && lf > 0 { return .lf }
        if cr > 0 { return .cr }
        return .crlf
    }
}

// MARK: - 读取结果

struct LoadedFile {
    var text: String
    var encoding: TextEncoding
    var lineEnding: LineEnding
    var byteCount: Int
}

enum FileError: LocalizedError {
    case unsupportedCharacters(TextEncoding)

    var errorDescription: String? {
        switch self {
        case .unsupportedCharacters(let enc):
            return "当前编码（\(enc.displayName)）无法表示文档中的部分字符。\n请改用 UTF-8 保存。"
        }
    }
}

// MARK: - 文件读写

enum TextFileIO {

    static func load(url: URL) throws -> LoadedFile {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let lineEnding = LineEnding.detect(in: data)
        let decoded = decode(data)
        let normalized = normalizeNewlines(decoded.text)
        return LoadedFile(text: normalized,
                          encoding: decoded.encoding,
                          lineEnding: lineEnding,
                          byteCount: data.count)
    }

    static func decode(_ data: Data) -> (text: String, encoding: TextEncoding) {
        // 1. BOM 优先
        let bytes = [UInt8](data.prefix(3))
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            let body = data.dropFirst(3)
            return (String(data: Data(body), encoding: .utf8) ?? "", .utf8BOM)
        }
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
            return (String(data: data.dropFirst(2), encoding: .utf16LittleEndian) ?? "", .utf16LE)
        }
        if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
            return (String(data: data.dropFirst(2), encoding: .utf16BigEndian) ?? "", .utf16BE)
        }

        // 2. 无 BOM 的 UTF-16 启发式判断
        if let guessed = guessUTF16(data) {
            if let s = String(data: data, encoding: guessed.stringEncoding) {
                return (s, guessed)
            }
        }

        // 3. 严格 UTF-8
        if let s = String(data: data, encoding: .utf8) {
            return (s, .utf8)
        }

        // 4. GB18030（中文 Windows 的 ANSI）
        if let s = String(data: data, encoding: TextEncoding.gb18030) {
            return (s, .ansi)
        }

        // 5. 兜底
        return (String(decoding: data, as: UTF8.self), .utf8)
    }

    private static func guessUTF16(_ data: Data) -> TextEncoding? {
        guard data.count >= 4 && data.count % 2 == 0 else { return nil }
        let sampleCount = min(data.count, 8192)
        var zerosEven = 0, zerosOdd = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var i = 0
            while i < sampleCount {
                if raw[i] == 0 {
                    if i % 2 == 0 { zerosEven += 1 } else { zerosOdd += 1 }
                }
                i += 1
            }
        }
        let threshold = sampleCount / 4
        if zerosOdd > threshold && zerosEven < zerosOdd / 4 { return .utf16LE }
        if zerosEven > threshold && zerosOdd < zerosEven / 4 { return .utf16BE }
        return nil
    }

    /// 内部统一使用 "\n" 作为换行符，保存时再转换为目标行尾。
    /// 注意：不能用 String.contains("\r") —— 字素簇语义下 "\r\n" 中的 CR 匹配不到；
    /// 也不要用 replacingOccurrences（ICU 实现，7MB 文本要 1 秒），这里走 UTF-8 单遍字节重写。
    static func normalizeNewlines(_ text: String) -> String {
        let bytes = [UInt8](text.utf8)
        guard bytes.contains(13) else { return text }
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        var i = 0
        let count = bytes.count
        while i < count {
            let byte = bytes[i]
            if byte == 13 {
                out.append(10)
                if i + 1 < count && bytes[i + 1] == 10 {
                    i += 2
                } else {
                    i += 1
                }
                continue
            }
            out.append(byte)
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// 把内部 "\n" 转成目标行尾（同样避免 ICU 替换）
    static func applyLineEnding(_ text: String, _ ending: LineEnding) -> String {
        guard ending != .lf else { return text }
        let bytes = [UInt8](text.utf8)
        let sequence = [UInt8](ending.sequence.utf8)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count + bytes.count / 24 + 16)
        for byte in bytes {
            if byte == 10 {
                out.append(contentsOf: sequence)
            } else {
                out.append(byte)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func encode(text: String, encoding: TextEncoding, lineEnding: LineEnding) throws -> Data {
        let normalized = normalizeNewlines(text)
        let output = applyLineEnding(normalized, lineEnding)

        guard let body = output.data(using: encoding.stringEncoding, allowLossyConversion: false) else {
            throw FileError.unsupportedCharacters(encoding)
        }
        var data = Data(encoding.bomBytes)
        data.append(body)
        return data
    }
}

// MARK: - 文档元信息

final class TextDocument {
    var fileURL: URL?
    var encoding: TextEncoding = .utf8
    var lineEnding: LineEnding = .crlf
    var isModified: Bool = false

    var displayName: String {
        fileURL?.lastPathComponent ?? "无标题"
    }
}

// MARK: - 行号索引（二分查找，编辑时增量维护，保证大文件也跟手）

final class LineIndex {
    private(set) var starts: [Int] = [0]
    private(set) var length: Int = 0

    func rebuild(_ text: NSString) {
        length = text.length
        starts = [0]
        starts.reserveCapacity(max(16, length / 32))
        var buffer = [unichar](repeating: 0, count: 8192)
        var offset = 0
        while offset < length {
            let count = min(buffer.count, length - offset)
            text.getCharacters(&buffer, range: NSRange(location: offset, length: count))
            for i in 0..<count where buffer[i] == 10 {
                starts.append(offset + i + 1)
            }
            offset += count
        }
    }

    func lineAndColumn(at location: Int) -> (line: Int, column: Int) {
        guard !starts.isEmpty else { return (1, location + 1) }
        var low = 0, high = starts.count - 1, found = 0
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= location {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return (found + 1, location - starts[found] + 1)
    }

    var lineCount: Int { starts.count }

    /// 依据一次编辑更新索引。
    func update(text: NSString, editedRange: NSRange, changeInLength delta: Int) {
        let start = editedRange.location
        let newEnd = start + editedRange.length
        let oldEnd = newEnd - delta

        let lower = firstIndex(greaterThan: start)
        let upper = firstIndex(greaterThan: oldEnd)
        if upper > lower {
            starts.removeSubrange(lower..<upper)
        }
        if delta != 0 && lower < starts.count {
            for i in lower..<starts.count { starts[i] += delta }
        }

        // 扫描新文本中新增的换行
        var fresh: [Int] = []
        if editedRange.length > 0 {
            var buffer = [unichar](repeating: 0, count: 4096)
            var offset = start
            while offset < newEnd {
                let count = min(buffer.count, newEnd - offset)
                text.getCharacters(&buffer, range: NSRange(location: offset, length: count))
                for i in 0..<count where buffer[i] == 10 {
                    fresh.append(offset + i + 1)
                }
                offset += count
            }
        }
        if !fresh.isEmpty {
            let insertAt = firstIndex(greaterThan: start)
            starts.insert(contentsOf: fresh, at: insertAt)
        }
        length += delta
        if starts.isEmpty { starts = [0] }
    }

    private func firstIndex(greaterThan value: Int) -> Int {
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= value { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
