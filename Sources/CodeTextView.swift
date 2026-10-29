//
//  CodeTextView.swift
//  代码编辑器 —— 编辑视图与行号栏
//
//  交互设计参考主流编辑器（VS Code / Xcode）：
//  · 回车自动继承缩进，在括号内回车自动多缩进一层并补全闭合括号
//  · 输入左括号/引号自动补全右半，输入右半自动跳过，删除时成对删除
//  · Tab / Shift-Tab 支持多行选区整体缩进、退格
//  · 当前行底色、缩进参考线、括号匹配高亮（临时属性，不污染文档、不进撤销栈）
//

import AppKit

// MARK: - 行号栏

final class LineNumberRulerView: NSRulerView {

    weak var textView: NSTextView?
    var lineIndex: LineIndex
    var theme: EditorTheme = EditorTheme.light
    var showIndentGuides: Bool = true
    var tabWidth: Int = 4

    private var numberFont: NSFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var cachedSpaceWidth: CGFloat = 7

    init(scrollView: NSScrollView, textView: NSTextView, lineIndex: LineIndex) {
        self.textView = textView
        self.lineIndex = lineIndex
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
        updateFont(size: 11)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override var isFlipped: Bool { true }

    func updateFont(size: CGFloat) {
        numberFont = NSFont.monospacedDigitSystemFont(ofSize: max(8, size), weight: .regular)
        cachedSpaceWidth = ("0" as NSString).size(withAttributes: [.font: numberFont]).width
        updateThickness()
        needsDisplay = true
    }

    func updateThickness() {
        let digits = max(2, String(max(lineIndex.lineCount, 1)).count)
        ruleThickness = max(42, CGFloat(digits) * cachedSpaceWidth + 20)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        theme.gutterBackground.setFill()
        bounds.fill()

        theme.gutterBorder.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()

        let ns = textView.string as NSString
        let length = ns.length
        let visibleRect = textView.visibleRect
        guard visibleRect.height > 0 else { return }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let starts = lineIndex.starts
        guard !starts.isEmpty else { return }

        let firstLine = max(0, lineIndex.lineAndColumn(at: charRange.location).line - 1)
        let endLocation = max(charRange.location, charRange.location + charRange.length - 1)
        let lastLine = min(starts.count - 1, lineIndex.lineAndColumn(at: endLocation).line - 1)

        let caretLine = lineIndex.lineAndColumn(at: min(textView.selectedRange().location, length)).line - 1
        let currentAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: numberFont.pointSize, weight: .semibold),
            .foregroundColor: theme.gutterCurrent,
        ]
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: theme.gutterText,
        ]

        if caretLine >= firstLine && caretLine <= lastLine {
            if let rect = lineRect(forLine: caretLine, layoutManager: layoutManager, textView: textView) {
                theme.currentLine.setFill()
                rect.fill()
            }
        }

        var line = firstLine
        while line <= lastLine && line < starts.count {
            let start = starts[line]
            var lineY: CGFloat?
            if start < length {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: start)
                var rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                rect.origin.y += textView.textContainerInset.height
                lineY = rect.minY
            } else if start == 0 {
                lineY = textView.textContainerInset.height
            }

            if let lineY {
                let attributes = (line == caretLine) ? currentAttrs : normalAttrs
                let text = "\(line + 1)" as NSString
                let size = text.size(withAttributes: attributes)
                // 只转换 y（滚动时 textView 原点变化）；x 直接使用行号栏自身坐标系，
                // convert 返回的 x 是相对文本视图的偏移，直接使用会被裁剪出可视区
                let convertedY = convert(NSPoint(x: 0, y: lineY), from: textView).y
                text.draw(at: NSPoint(x: ruleThickness - 9 - size.width, y: convertedY),
                          withAttributes: attributes)
            }
            line += 1
        }
    }

    private func lineRect(forLine line: Int,
                          layoutManager: NSLayoutManager,
                          textView: NSTextView) -> NSRect? {
        let starts = lineIndex.starts
        guard line >= 0 && line < starts.count else { return nil }
        let length = (textView.string as NSString).length
        let start = starts[line]
        var rect: NSRect
        if start < length {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: start)
            rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        } else if length > 0 {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: length - 1)
            let lastRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            rect = NSRect(x: 0, y: lastRect.maxY, width: bounds.width,
                          height: layoutManager.defaultLineHeight(for: textView.font ?? NSFont.systemFont(ofSize: 12)))
        } else {
            rect = NSRect(x: 0, y: 0, width: bounds.width,
                          height: layoutManager.defaultLineHeight(for: textView.font ?? NSFont.systemFont(ofSize: 12)))
        }
        rect.origin.y += textView.textContainerInset.height
        rect.origin.x = 0
        rect.size.width = bounds.width
        return rect
    }
}

// MARK: - 代码编辑视图

final class CodeTextView: NSTextView {

    var onZoomScroll: ((Int) -> Void)?
    var onFileDrop: ((URL) -> Void)?

    var theme: EditorTheme = EditorTheme.light {
        didSet { applyTheme() }
    }

    /// 以下行为开关由窗口控制器同步
    var autoIndentEnabled = true
    var autoCloseEnabled = true
    var tabWidth = 4
    var softTabs = true
    var showIndentGuides = true
    var highlightCurrentLine = true
    var bracketMatchingEnabled = true

    private var bracketRanges: [NSRange] = []
    private var spaceWidth: CGFloat = 7

    // MARK: 外观

    func applyTheme() {
        drawsBackground = true
        backgroundColor = theme.background
        textColor = theme.text
        insertionPointColor = theme.text
        selectedTextAttributes = [.backgroundColor: theme.selection]
        updateSpaceWidth()
        needsDisplay = true
        clearBracketHighlight()
    }

    func updateSpaceWidth() {
        let font = self.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let container = textContainer else { return }

        if highlightCurrentLine {
            let ns = string as NSString
            let loc = min(selectedRange().location, ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect: NSRect
            if glyphRange.length > 0 {
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            } else if ns.length > 0 {
                let index = max(0, min(lineRange.location, ns.length - 1))
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
                let last = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                lineRect = NSRect(x: 0, y: last.maxY, width: bounds.width,
                                  height: layoutManager.defaultLineHeight(for: font ?? NSFont.systemFont(ofSize: 12)))
            } else {
                lineRect = NSRect(x: 0, y: 0, width: bounds.width,
                                  height: layoutManager.defaultLineHeight(for: font ?? NSFont.systemFont(ofSize: 12)))
            }
            lineRect.origin.x = 0
            lineRect.origin.y += textContainerInset.height
            lineRect.size.width = bounds.width
            theme.currentLine.setFill()
            lineRect.fill()
        }

        guard showIndentGuides, textContainerInset.width >= 0 else { return }

        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let ns = string as NSString
        let guideColor = theme.indentGuide
        let width: CGFloat = 1
        let insetHeight = textContainerInset.height

        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphs) { rect, _, _, glyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.location <= ns.length else { return }
            // 只处理真正的行首（跳过自动换行产生的续行）
            if charRange.location > 0 && ns.character(at: charRange.location - 1) != 10 { return }

            var column = 0
            var index = charRange.location
            while index < ns.length {
                let c = ns.character(at: index)
                if c == 32 {
                    column += 1
                } else if c == 9 {
                    column += self.tabWidth - (column % self.tabWidth)
                } else {
                    break
                }
                index += 1
            }
            let levels = column / max(1, self.tabWidth)
            guard levels > 0 else { return }
            guideColor.setFill()
            var level = 1
            let maxLevel = min(levels, 24)
            while level <= maxLevel {
                let x = self.textContainerInset.width + CGFloat(level * self.tabWidth) * self.spaceWidth - 0.5
                let guideRect = NSRect(x: x, y: rect.minY + insetHeight, width: width, height: rect.height)
                guideRect.fill()
                level += 1
            }
        }
    }

    // MARK: 括号匹配

    func updateBracketHighlight() {
        clearBracketHighlight()
        guard bracketMatchingEnabled else { return }
        let ns = string as NSString
        let selection = selectedRange()
        guard selection.length == 0 else { return }
        let loc = selection.location
        guard loc <= ns.length else { return }

        var index = -1
        if loc < ns.length, isBracket(ns.character(at: loc)) {
            index = loc
        } else if loc > 0, isBracket(ns.character(at: loc - 1)) {
            index = loc - 1
        }
        guard index >= 0 else { return }

        let opening = ns.character(at: index)
        let isOpen = isOpeningBracket(opening)
        guard let match = findMatch(for: index, opening: isOpen, in: ns) else { return }

        let color = theme.bracketHighlight
        guard let layoutManager else { return }
        for range in [NSRange(location: index, length: 1), NSRange(location: match, length: 1)] {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            bracketRanges.append(range)
        }
    }

    func clearBracketHighlight() {
        guard !bracketRanges.isEmpty, let layoutManager else { return }
        for range in bracketRanges {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
        }
        bracketRanges.removeAll()
    }

    private func isBracket(_ c: unichar) -> Bool {
        c == 40 || c == 41 || c == 91 || c == 93 || c == 123 || c == 125
    }

    private func isOpeningBracket(_ c: unichar) -> Bool { c == 40 || c == 91 || c == 123 }
    private func isClosingBracket(_ c: unichar) -> Bool { c == 41 || c == 93 || c == 125 }

    private func closer(for opener: unichar) -> unichar {
        switch opener {
        case 40: return 41
        case 91: return 93
        case 123: return 125
        default: return opener
        }
    }

    private func findMatch(for index: Int, opening: Bool, in ns: NSString) -> Int? {
        let limit = 300_000
        if opening {
            let open = ns.character(at: index)
            let close = closer(for: open)
            var depth = 0
            var i = index
            let end = min(ns.length, index + limit)
            while i < end {
                let c = ns.character(at: i)
                if c == open { depth += 1 }
                if c == close {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i += 1
            }
        } else {
            let close = ns.character(at: index)
            let open: unichar
            switch close {
            case 41: open = 40
            case 93: open = 91
            case 125: open = 123
            default: return nil
            }
            var depth = 0
            var i = index
            let start = max(0, index - limit)
            while i >= start {
                let c = ns.character(at: i)
                if c == close { depth += 1 }
                if c == open {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i -= 1
            }
        }
        return nil
    }

    // MARK: 输入行为

    private var isComposing: Bool { hasMarkedText() }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = string as? String else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let target = replacementRange.location == NSNotFound ? selectedRange() : replacementRange

        guard autoCloseEnabled, !isComposing, text.utf16.count == 1,
              let scalar = text.unicodeScalars.first, scalar.isASCII else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let typed = unichar(scalar.value)
        let ns = self.string as NSString

        if let closing = Self.closingCounterpart[typed] {
            // 输入右半：若右侧已是该字符则跳过
            if target.length == 0, target.location < ns.length, ns.character(at: target.location) == closing {
                setSelectedRange(NSRange(location: target.location + 1, length: 0))
                return
            }
            // 选中文本时用括号包裹
            if target.length > 0 {
                let selected = ns.substring(with: target)
                let replacement = text + selected + String(decoding: [closing], as: UTF16.self)
                super.insertText(replacement, replacementRange: target)
                setSelectedRange(NSRange(location: target.location + 1, length: target.length))
                return
            }
            // 引号：紧跟在单词后面不自动补全（避免 don't 这类场景）
            if typed == 34 || typed == 39 || typed == 96 {
                if target.location > 0 {
                    let prev = ns.character(at: target.location - 1)
                    if isWordCharacter(prev) { super.insertText(text, replacementRange: target); return }
                }
            }
            super.insertText(text + String(decoding: [closing], as: UTF16.self), replacementRange: target)
            setSelectedRange(NSRange(location: target.location + 1, length: 0))
            return
        }

        if isClosingBracket(typed) || typed == 34 || typed == 39 || typed == 96 {
            if target.length == 0, target.location < ns.length, ns.character(at: target.location) == typed {
                setSelectedRange(NSRange(location: target.location + 1, length: 0))
                return
            }
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        guard autoCloseEnabled, !isComposing else { super.deleteBackward(sender); return }
        let ns = string as NSString
        let selection = selectedRange()
        guard selection.length == 0, selection.location > 0, selection.location < ns.length else {
            super.deleteBackward(sender)
            return
        }
        let prev = ns.character(at: selection.location - 1)
        let next = ns.character(at: selection.location)
        if let expected = Self.closingCounterpart[prev], expected == next {
            super.insertText("", replacementRange: NSRange(location: selection.location - 1, length: 2))
            return
        }
        super.deleteBackward(sender)
    }

    override func insertNewline(_ sender: Any?) {
        guard autoIndentEnabled, !isComposing, selectedRange().length == 0 else {
            super.insertNewline(sender)
            return
        }
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        let prefix = ns.substring(with: NSRange(location: lineRange.location, length: max(0, loc - lineRange.location)))

        var indent = ""
        for ch in prefix {
            if ch == " " || ch == "\t" { indent.append(ch) } else { break }
        }

        let before = loc > 0 ? ns.substring(with: NSRange(location: loc - 1, length: 1)) : ""
        let after = loc < ns.length ? ns.substring(with: NSRange(location: loc, length: 1)) : ""
        let expand = !before.isEmpty && !after.isEmpty
            && "([{".contains(before) && ")]}".contains(after)
        let unit = indentUnit()

        if expand {
            let insertion = "\n" + indent + unit + "\n" + indent
            super.insertText(insertion, replacementRange: NSRange(location: loc, length: 0))
            setSelectedRange(NSRange(location: loc + 1 + (indent as NSString).length + (unit as NSString).length,
                                     length: 0))
        } else {
            super.insertText("\n" + indent, replacementRange: NSRange(location: loc, length: 0))
        }
    }

    override func insertTab(_ sender: Any?) {
        if selectedRange().length > 0 {
            indentSelectedLines(outdent: false)
            return
        }
        if softTabs {
            let column = currentColumn()
            let count = max(1, tabWidth - (column % tabWidth))
            super.insertText(String(repeating: " ", count: count), replacementRange: selectedRange())
        } else {
            super.insertText("\t", replacementRange: selectedRange())
        }
    }

    override func insertBacktab(_ sender: Any?) {
        indentSelectedLines(outdent: true)
    }

    private func indentUnit() -> String {
        softTabs ? String(repeating: " ", count: tabWidth) : "\t"
    }

    private func currentColumn() -> Int {
        let ns = string as NSString
        let loc = min(selectedRange().location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        var column = 0
        var i = lineRange.location
        while i < loc {
            let c = ns.character(at: i)
            if c == 9 {
                column += tabWidth - (column % tabWidth)
            } else {
                column += 1
            }
            i += 1
        }
        return column
    }

    private func isWordCharacter(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 128
    }

    private static let closingCounterpart: [unichar: unichar] = [
        40: 41,   // ( )
        91: 93,   // [ ]
        123: 125, // { }
        34: 34,   // "
        39: 39,   // '
        96: 96,   // `
    ]

    // MARK: 行操作

    /// 选区覆盖的整行范围（若选区结束于下一行行首，不把该行算进来）
    private func selectedLineRange(in ns: NSString) -> NSRange {
        var selection = selectedRange()
        if selection.length > 0, selection.location + selection.length < ns.length,
           ns.character(at: selection.location + selection.length - 1) == 10 {
            selection.length -= 1
        }
        return ns.lineRange(for: selection)
    }

    func indentSelectedLines(outdent: Bool) {
        let ns = string as NSString
        let range = selectedLineRange(in: ns)

        let replacement = NSMutableString()
        let unit = indentUnit()
        var removedTotal = 0
        var lineStart = range.location

        while lineStart < range.location + range.length {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = ns.substring(with: lineRange)
            if outdent {
                var drop = 0
                if softTabs {
                    while drop < min(tabWidth, line.utf16.count) && (line as NSString).character(at: drop) == 32 {
                        drop += 1
                    }
                } else {
                    if line.hasPrefix("\t") { drop = 1 }
                }
                removedTotal += drop
                replacement.append(String(line.dropFirst(drop)))
            } else {
                replacement.append(unit)
                replacement.append(line)
            }
            lineStart = lineRange.location + lineRange.length
        }

        guard range.length > 0 else { return }
        let fullRange = range
        guard super.shouldChangeText(in: fullRange, replacementString: replacement as String) else { return }

        undoManager?.beginUndoGrouping()
        textStorage?.replaceCharacters(in: fullRange, with: replacement as String)
        undoManager?.endUndoGrouping()
        didChangeText()

        _ = removedTotal
        // 保持整段缩进后的选区：直接选中受影响的行，行为可预期
        setSelectedRange(NSRange(location: fullRange.location, length: replacement.length))
    }

    func toggleComment(language: Language) {
        guard let token = language.lineComments.first else { NSSound.beep(); return }
        let ns = string as NSString
        let range = selectedLineRange(in: ns)
        guard range.length > 0 else { return }

        var lines: [(range: NSRange, text: String)] = []
        var cursor = range.location
        while cursor < range.location + range.length {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            lines.append((lineRange, ns.substring(with: lineRange)))
            cursor = lineRange.location + lineRange.length
        }
        guard !lines.isEmpty else { return }

        // 判断是否已全部注释（非空行都要以注释符开头）
        var allCommented = true
        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let body = line.text.drop { $0 == " " || $0 == "\t" }
            if !body.hasPrefix(token) { allCommented = false; break }
        }

        let replacement = NSMutableString()
        var deltaAtStart = 0
        var deltaTotal = 0
        for (index, line) in lines.enumerated() {
            let text = line.text
            let hasNewline = text.hasSuffix("\n")
            var body = hasNewline ? String(text.dropLast()) : text
            let leading = body.prefix { $0 == " " || $0 == "\t" }
            let indent = String(leading)
            let content = String(body.dropFirst(indent.count))

            if allCommented {
                var stripped = content
                if stripped.hasPrefix(token + " ") {
                    stripped.removeFirst(token.count + 1)
                } else if stripped.hasPrefix(token) {
                    stripped.removeFirst(token.count)
                }
                let removed = content.utf16.count - stripped.utf16.count
                body = indent + stripped
                if index == 0 { deltaAtStart = -removed }
                deltaTotal -= removed
            } else {
                if content.isEmpty {
                    deltaTotal += 0
                } else {
                    body = indent + token + " " + content
                    if index == 0 { deltaAtStart = token.utf16.count + 1 }
                    deltaTotal += token.utf16.count + 1
                }
            }
            if hasNewline { body += "\n" }
            replacement.append(body)
        }

        guard super.shouldChangeText(in: range, replacementString: replacement as String) else { return }
        undoManager?.beginUndoGrouping()
        textStorage?.replaceCharacters(in: range, with: replacement as String)
        undoManager?.endUndoGrouping()
        didChangeText()

        let selected = selectedRange()
        let newStart = max(range.location, selected.location + deltaAtStart)
        setSelectedRange(NSRange(location: newStart, length: max(0, selected.length + deltaTotal - deltaAtStart)))
    }

    func moveSelectedLines(up: Bool) {
        let ns = string as NSString
        var selection = selectedRange()
        if selection.length > 0, selection.location + selection.length < ns.length,
           ns.character(at: selection.location + selection.length - 1) == 10 {
            selection.length -= 1
        }
        let blockRange = ns.lineRange(for: selection)

        let upperRange: NSRange
        let lowerRange: NSRange
        if up {
            guard blockRange.location > 0 else { NSSound.beep(); return }
            upperRange = ns.lineRange(for: NSRange(location: blockRange.location - 1, length: 0))
            lowerRange = blockRange
        } else {
            let after = blockRange.location + blockRange.length
            guard after < ns.length else { NSSound.beep(); return }
            upperRange = blockRange
            lowerRange = ns.lineRange(for: NSRange(location: after, length: 0))
        }

        let upper = ns.substring(with: upperRange)
        let lower = ns.substring(with: lowerRange)
        let addedNewline = !lower.hasSuffix("\n")
        let combined: String
        if addedNewline {
            combined = lower + "\n" + String(upper.dropLast())
        } else {
            combined = lower + upper
        }

        let replaceRange = NSRange(location: upperRange.location,
                                   length: upperRange.length + lowerRange.length)
        guard super.shouldChangeText(in: replaceRange, replacementString: combined) else { return }
        undoManager?.beginUndoGrouping()
        textStorage?.replaceCharacters(in: replaceRange, with: combined)
        undoManager?.endUndoGrouping()
        didChangeText()

        let offsetInBlock = selection.location - blockRange.location
        let newStart: Int
        if up {
            newStart = upperRange.location + offsetInBlock
        } else {
            newStart = upperRange.location + lower.utf16.count + (addedNewline ? 1 : 0) + offsetInBlock
        }
        setSelectedRange(NSRange(location: newStart, length: selection.length))
        scrollRangeToVisible(NSRange(location: newStart, length: 0))
    }

    func duplicateSelectedLines() {
        let ns = string as NSString
        let blockRange = selectedLineRange(in: ns)
        var block = ns.substring(with: blockRange)
        if !block.hasSuffix("\n") { block += "\n" }

        let insertAt = blockRange.location + blockRange.length
        guard super.shouldChangeText(in: NSRange(location: insertAt, length: 0), replacementString: block) else { return }
        undoManager?.beginUndoGrouping()
        textStorage?.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: block)
        undoManager?.endUndoGrouping()
        didChangeText()

        let selection = selectedRange()
        setSelectedRange(NSRange(location: selection.location + (block as NSString).length,
                                 length: selection.length))
        scrollRangeToVisible(NSRange(location: selectedRange().location, length: 0))
    }

    func deleteSelectedLines() {
        let ns = string as NSString
        var range = selectedLineRange(in: ns)
        if range.location + range.length >= ns.length, range.location > 0,
           !ns.substring(with: range).hasSuffix("\n") {
            range = NSRange(location: range.location - 1, length: range.length + 1)
        }
        guard range.length > 0 else { return }
        guard super.shouldChangeText(in: range, replacementString: "") else { return }
        undoManager?.beginUndoGrouping()
        textStorage?.replaceCharacters(in: range, with: "")
        undoManager?.endUndoGrouping()
        didChangeText()
        setSelectedRange(NSRange(location: min(range.location, (string as NSString).length), length: 0))
    }

    // MARK: 滚轮缩放 / 拖入文件

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY
            if abs(delta) > 0.01 {
                onZoomScroll?(delta > 0 ? 1 : -1)
                return
            }
        }
        super.scrollWheel(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if fileURL(from: sender) != nil { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if fileURL(from: sender) != nil { return .copy }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = fileURL(from: sender) {
            onFileDrop?(url)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func fileURL(from info: NSDraggingInfo) -> URL? {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let first = urls.first else { return nil }
        return first
    }
}
