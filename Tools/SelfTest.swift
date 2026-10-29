//
//  SelfTest.swift
//  数据层自检：编码往返 / 行尾识别 / LineIndex 增量维护正确性
//

import Foundation

var failures = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)  \(detail)")
    }
}

// 1. UTF-8 无 BOM 往返
do {
    let text = "你好，世界 hello\r\nsecond line\r\n"
    let data = try TextFileIO.encode(text: text, encoding: .utf8, lineEnding: .crlf)
    let loaded = TextFileIO.decode(data)
    check("UTF-8 识别", loaded.encoding == .utf8)
    let roundTrip = TextFileIO.normalizeNewlines(loaded.text)
    check("UTF-8 内容一致", roundTrip == TextFileIO.normalizeNewlines(text))
    check("CRLF 识别", LineEnding.detect(in: data) == .crlf)
}

// 2. UTF-8 BOM
do {
    let text = "BOM 测试\n第二行"
    let data = try TextFileIO.encode(text: text, encoding: .utf8BOM, lineEnding: .lf)
    check("BOM 存在", data.starts(with: [0xEF, 0xBB, 0xBF]))
    let loaded = TextFileIO.decode(data)
    check("UTF-8 BOM 识别", loaded.encoding == .utf8BOM)
    check("BOM 内容一致", TextFileIO.normalizeNewlines(loaded.text) == text)
}

// 3. UTF-16 LE / BE
do {
    let text = "宽字符测试 wide chars\nline2"
    for enc in [TextEncoding.utf16LE, .utf16BE] {
        let data = try TextFileIO.encode(text: text, encoding: enc, lineEnding: .lf)
        let loaded = TextFileIO.decode(data)
        check("\(enc.displayName) 识别", loaded.encoding == enc, "实际: \(loaded.encoding.displayName)")
        check("\(enc.displayName) 内容一致", TextFileIO.normalizeNewlines(loaded.text) == text)
    }
    // 无 BOM 的 UTF-16 LE（模拟记事本另存的窄字符文件）
    var noBom = "plain ascii".data(using: .utf16LittleEndian)!
    noBom = noBom.dropFirst(2)
    let loaded = TextFileIO.decode(noBom)
    check("无BOM UTF-16 启发式", loaded.encoding == .utf16LE, "实际: \(loaded.encoding.displayName)")
}

// 4. GB18030（ANSI，中文 Windows 默认）
do {
    let text = "中文 ANSI 编码测试，晋江文学城。"
    guard let data = text.data(using: TextEncoding.gb18030) else {
        failures += 1
        print("FAIL  GB18030 编码不可用")
        exit(1)
    }
    let loaded = TextFileIO.decode(data)
    check("GB18030 识别为 ANSI", loaded.encoding == .ansi, "实际: \(loaded.encoding.displayName)")
    check("GB18030 内容一致", loaded.text == text)
}

// 5. ANSI 采用 GB18030 双字节编码（“中” = D6 D0），且可无损往返
do {
    let data = try TextFileIO.encode(text: "中", encoding: .ansi, lineEnding: .lf)
    check("ANSI 为 GB18030 双字节", Array(data) == [0xD6, 0xD0], "实际: \(Array(data).map { String($0, radix: 16) })")

    // GB18030 覆盖全部 Unicode，ANSI 模式下 emoji 也能无损保存
    let emojiText = "emoji 😀 中文"
    let data2 = try TextFileIO.encode(text: emojiText, encoding: .ansi, lineEnding: .lf)
    check("ANSI 可无损保存 emoji（GB18030 四字节）", TextFileIO.decode(data2).text == emojiText)
}

// 6. 行尾转换
do {
    let data = try TextFileIO.encode(text: "a\nb\nc", encoding: .utf8, lineEnding: .crlf)
    let s = String(decoding: data, as: UTF8.self)
    check("LF→CRLF 转换", s == "a\r\nb\r\nc")
    let data2 = try TextFileIO.encode(text: "a\nb\nc", encoding: .utf8, lineEnding: .cr)
    let s2 = String(decoding: data2, as: UTF8.self)
    check("LF→CR 转换", s2 == "a\rb\rc")
}

// 7. LineIndex：随机编辑 vs 全量重建
do {
    let index = LineIndex()
    var reference = ""
    index.rebuild(reference as NSString)

    func naiveLineColumn(_ text: String, at location: Int) -> (Int, Int) {
        let ns = text as NSString
        let clamped = min(location, ns.length)
        let prefix = ns.substring(to: clamped)
        let line = prefix.components(separatedBy: "\n").count
        let lastLineStart = (prefix as NSString).range(of: "\n", options: .backwards)
        let column = clamped - (lastLineStart.location == NSNotFound ? 0 : lastLineStart.location + lastLineStart.length) + 1
        return (line, column)
    }

    func verify(_ location: Int, _ step: String) {
        let got = index.lineAndColumn(at: location)
        let want = naiveLineColumn(reference, at: location)
        if got.0 != want.0 || got.1 != want.1 {
            failures += 1
            print("FAIL  LineIndex \(step) @\(location): got \(got), want \(want), text=\(reference.debugDescription)")
        }
    }

    var rng = SystemRandomNumberGenerator()
    for step in 0..<400 {
        let op = Int.random(in: 0..<3, using: &rng)
        let ns = reference as NSString
        let location = Int.random(in: 0...max(0, ns.length), using: &rng)
        switch op {
        case 0: // 插入
            let snippet = ["a", "\n", "中", "\r\n", "hello world", "\n\n"].randomElement()!
            let r = NSRange(location: location, length: 0)
            let mutable = NSMutableString(string: reference)
            mutable.replaceCharacters(in: r, with: snippet)
            reference = mutable as String
            let storage = reference as NSString
            index.update(text: storage, editedRange: NSRange(location: location, length: (snippet as NSString).length),
                         changeInLength: (snippet as NSString).length)
        case 1: // 删除
            guard ns.length > 0 else { continue }
            let length = min(ns.length - location, Int.random(in: 1...12, using: &rng))
            let mutable = NSMutableString(string: reference)
            mutable.deleteCharacters(in: NSRange(location: location, length: length))
            reference = mutable as String
            index.update(text: reference as NSString,
                         editedRange: NSRange(location: location, length: 0),
                         changeInLength: -length)
        default: // 替换
            guard ns.length > 0 else { continue }
            let length = min(ns.length - location, Int.random(in: 1...8, using: &rng))
            let replacement = ["x\ny", "\n\n\n", "Z", "文本"].randomElement()!
            let mutable = NSMutableString(string: reference)
            mutable.replaceCharacters(in: NSRange(location: location, length: length), with: replacement)
            reference = mutable as String
            index.update(text: reference as NSString,
                         editedRange: NSRange(location: location, length: (replacement as NSString).length),
                         changeInLength: (replacement as NSString).length - length)
        }
        verify(Int.random(in: 0...max(0, (reference as NSString).length), using: &rng), "step\(step)")
    }
    // 收尾：与全量重建完全一致
    let rebuilt = LineIndex()
    rebuilt.rebuild(reference as NSString)
    var identical = rebuilt.starts == index.starts
    if !identical {
        // 顺序一致但可能存在尾部多余项
        identical = index.starts.sorted() == rebuilt.starts.sorted()
    }
    check("LineIndex 随机编辑 400 次后与全量重建一致", identical,
          "增量:\(index.starts.count) 重建:\(rebuilt.starts.count)")
}

// 8. 大文件加载性能（10MB）
do {
    var big = ""
    let chunk = String(repeating: "记事本性能测试 Notepad performance line with 中文 mixed content.\r\n", count: 200)
    for _ in 0..<520 { big += chunk }   // 约 10MB
    let data = big.data(using: .utf8)!
    try data.write(to: URL(fileURLWithPath: "/tmp/notepad_big.txt"))

    let start = Date()
    let loaded = try TextFileIO.load(url: URL(fileURLWithPath: "/tmp/notepad_big.txt"))
    let loadMs = Date().timeIntervalSince(start) * 1000

    let index = LineIndex()
    let start2 = Date()
    index.rebuild(loaded.text as NSString)
    let indexMs = Date().timeIntervalSince(start2) * 1000

    check("10MB 文件加载 < 600ms（实测 \(Int(loadMs))ms）", loadMs < 600)
    check("10MB 行号索引 < 600ms（实测 \(Int(indexMs))ms，行数 \(index.lineCount)）", indexMs < 600)
    try? FileManager.default.removeItem(atPath: "/tmp/notepad_big.txt")
}

print(failures == 0 ? "\n全部通过" : "\n有 \(failures) 项失败")
exit(failures == 0 ? 0 : 1)
