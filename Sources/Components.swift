//
//  Components.swift
//  记事本 —— 界面组件：状态栏 / 查找替换栏 / 字体对话框 / 通用对话框
//

import AppKit

extension NSColor {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

// MARK: - 状态栏

final class StatusBarView: NSView {

    var onEncodingChange: ((TextEncoding) -> Void)?
    var onLineEndingChange: ((LineEnding) -> Void)?
    var onZoomChange: ((Int) -> Void)?
    var onZoomStep: ((Int) -> Void)?
    var onLanguageChange: ((Int) -> Void)?
    var onIndentChange: ((Int, Bool) -> Void)?

    private let positionLabel = NSTextField(labelWithString: "第 1 行，第 1 列")
    private let encodingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let lineEndingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let indentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let zoomSlider = NSSlider(value: 100, minValue: 10, maxValue: 500, target: nil, action: nil)
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let separator = NSBox()

    private var suppressCallbacks = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.dynamic(light: NSColor(calibratedWhite: 0.96, alpha: 1),
                                                 dark: NSColor(calibratedWhite: 0.16, alpha: 1)).cgColor

        let topLine = NSView()
        topLine.wantsLayer = true
        topLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        topLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topLine)

        positionLabel.font = NSFont.systemFont(ofSize: 11)
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(positionLabel)

        for popup in [encodingPopup, lineEndingPopup, languagePopup, indentPopup] {
            popup.isBordered = false
            popup.font = NSFont.systemFont(ofSize: 11)
            popup.controlSize = .small
            popup.translatesAutoresizingMaskIntoConstraints = false
            addSubview(popup)
        }

        lineEndingPopup.addItems(withTitles: LineEnding.allCases.map { $0.displayName })
        lineEndingPopup.target = self
        lineEndingPopup.action = #selector(lineEndingChanged(_:))

        for item in TextEncoding.allCases {
            let menuItem = NSMenuItem(title: item.displayName, action: nil, keyEquivalent: "")
            menuItem.tag = item.rawValue
            encodingPopup.menu?.addItem(menuItem)
        }
        encodingPopup.target = self
        encodingPopup.action = #selector(encodingChanged(_:))

        for (index, language) in Language.all.enumerated() {
            languagePopup.addItem(withTitle: language.displayName)
            languagePopup.lastItem?.tag = index
        }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        indentPopup.addItems(withTitles: ["空格: 2", "空格: 4", "空格: 8", "制表符"])
        indentPopup.target = self
        indentPopup.action = #selector(indentChanged(_:))

        zoomSlider.controlSize = .small
        zoomSlider.numberOfTickMarks = 0
        zoomSlider.isContinuous = true
        zoomSlider.target = self
        zoomSlider.action = #selector(zoomSliderChanged(_:))
        zoomSlider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomSlider)

        zoomLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.alignment = .right
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomLabel)

        let smallFont = NSFont.systemFont(ofSize: 11)
        let zoomOut = NSButton(title: "−", target: self, action: #selector(zoomOutTapped))
        zoomOut.isBordered = false
        zoomOut.font = NSFont.systemFont(ofSize: 13)
        zoomOut.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomOut)

        let zoomIn = NSButton(title: "＋", target: self, action: #selector(zoomInTapped))
        zoomIn.isBordered = false
        zoomIn.font = smallFont
        zoomIn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomIn)

        NSLayoutConstraint.activate([
            topLine.topAnchor.constraint(equalTo: topAnchor),
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),

            positionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            positionLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),

            zoomIn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            zoomIn.centerYAnchor.constraint(equalTo: centerYAnchor),

            zoomLabel.trailingAnchor.constraint(equalTo: zoomIn.leadingAnchor, constant: -2),
            zoomLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            zoomLabel.widthAnchor.constraint(equalToConstant: 40),

            zoomSlider.trailingAnchor.constraint(equalTo: zoomLabel.leadingAnchor, constant: -8),
            zoomSlider.centerYAnchor.constraint(equalTo: centerYAnchor),
            zoomSlider.widthAnchor.constraint(equalToConstant: 76),

            zoomOut.trailingAnchor.constraint(equalTo: zoomSlider.leadingAnchor, constant: -4),
            zoomOut.centerYAnchor.constraint(equalTo: centerYAnchor),
            zoomOut.widthAnchor.constraint(equalToConstant: 16),

            encodingPopup.trailingAnchor.constraint(equalTo: zoomOut.leadingAnchor, constant: -10),
            encodingPopup.centerYAnchor.constraint(equalTo: centerYAnchor),

            lineEndingPopup.trailingAnchor.constraint(equalTo: encodingPopup.leadingAnchor, constant: -2),
            lineEndingPopup.centerYAnchor.constraint(equalTo: centerYAnchor),

            indentPopup.trailingAnchor.constraint(equalTo: lineEndingPopup.leadingAnchor, constant: -2),
            indentPopup.centerYAnchor.constraint(equalTo: centerYAnchor),

            languagePopup.trailingAnchor.constraint(equalTo: indentPopup.leadingAnchor, constant: -2),
            languagePopup.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        separator.isHidden = true
    }

    func setPosition(line: Int, column: Int, selectionLength: Int = 0) {
        if selectionLength > 0 {
            positionLabel.stringValue = "第 \(line) 行，第 \(column) 列（已选 \(selectionLength)）"
        } else {
            positionLabel.stringValue = "第 \(line) 行，第 \(column) 列"
        }
    }

    func setLanguage(index: Int) {
        suppressCallbacks = true
        if index >= 0 && index < languagePopup.numberOfItems {
            languagePopup.selectItem(at: index)
        }
        suppressCallbacks = false
    }

    func setIndent(tabWidth: Int, softTabs: Bool) {
        suppressCallbacks = true
        let index: Int
        if softTabs {
            switch tabWidth {
            case 2: index = 0
            case 8: index = 1 + 1
            default: index = 1
            }
        } else {
            index = 3
        }
        indentPopup.selectItem(at: index)
        suppressCallbacks = false
    }

    func applyTheme(_ theme: EditorTheme) {
        wantsLayer = true
        layer?.backgroundColor = theme.gutterBackground.cgColor
        positionLabel.textColor = theme.isDark
            ? NSColor(hex: 0x9AA0A6)
            : NSColor(hex: 0x5A6068)
        zoomLabel.textColor = positionLabel.textColor
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard !suppressCallbacks else { return }
        onLanguageChange?(sender.indexOfSelectedItem)
    }

    @objc private func indentChanged(_ sender: NSPopUpButton) {
        guard !suppressCallbacks else { return }
        switch sender.indexOfSelectedItem {
        case 0: onIndentChange?(2, true)
        case 2: onIndentChange?(8, true)
        case 3: onIndentChange?(4, false)
        default: onIndentChange?(4, true)
        }
    }

    func setEncoding(_ encoding: TextEncoding) {
        suppressCallbacks = true
        encodingPopup.selectItem(withTag: encoding.rawValue)
        suppressCallbacks = false
    }

    func setLineEnding(_ ending: LineEnding) {
        suppressCallbacks = true
        lineEndingPopup.selectItem(at: ending.rawValue)
        suppressCallbacks = false
    }

    func setZoom(_ percent: Int) {
        suppressCallbacks = true
        zoomSlider.doubleValue = Double(percent)
        zoomLabel.stringValue = "\(percent)%"
        suppressCallbacks = false
    }

    @objc private func encodingChanged(_ sender: NSPopUpButton) {
        guard !suppressCallbacks else { return }
        if let enc = TextEncoding(rawValue: sender.selectedTag()) {
            onEncodingChange?(enc)
        }
    }

    @objc private func lineEndingChanged(_ sender: NSPopUpButton) {
        guard !suppressCallbacks else { return }
        if let eol = LineEnding(rawValue: sender.indexOfSelectedItem) {
            onLineEndingChange?(eol)
        }
    }

    @objc private func zoomSliderChanged(_ sender: NSSlider) {
        guard !suppressCallbacks else { return }
        let rounded = Int((sender.doubleValue / 5).rounded()) * 5
        onZoomChange?(max(10, min(500, rounded)))
    }

    @objc private func zoomInTapped() { onZoomStep?(1) }
    @objc private func zoomOutTapped() { onZoomStep?(-1) }
}

// MARK: - 查找 / 替换栏

final class FindBarView: NSView, NSSearchFieldDelegate {

    var onFindNext: ((String, Bool, Bool) -> Void)?     // 关键字, 向上, 区分大小写
    var onReplace: ((String, String, Bool) -> Void)?
    var onReplaceAll: ((String, String, Bool) -> Void)?
    var onClose: (() -> Void)?

    private let findField = NSSearchField()
    private let replaceField = NSTextField()
    private let caseCheckbox = NSButton(checkboxWithTitle: "区分大小写", target: nil, action: nil)
    private let wrapCheckbox = NSButton(checkboxWithTitle: "循环查找", target: nil, action: nil)
    private let previousButton = NSButton(title: "上一个", target: nil, action: nil)
    private let nextButton = NSButton(title: "下一个", target: nil, action: nil)
    private let replaceButton = NSButton(title: "替换", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "全部替换", target: nil, action: nil)
    private var replaceRow: NSStackView!
    private var findRowHeight: NSLayoutConstraint!
    private var replaceRowHeight: NSLayoutConstraint!

    var isReplaceMode: Bool = false {
        didSet { applyMode() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.dynamic(light: NSColor(calibratedWhite: 0.97, alpha: 1),
                                                 dark: NSColor(calibratedWhite: 0.14, alpha: 1)).cgColor

        findField.placeholderString = "查找内容"
        findField.font = NSFont.systemFont(ofSize: 12)
        findField.target = self
        findField.action = #selector(findNextTapped)
        findField.delegate = self
        findField.translatesAutoresizingMaskIntoConstraints = false

        replaceField.placeholderString = "替换为"
        replaceField.font = NSFont.systemFont(ofSize: 12)
        replaceField.translatesAutoresizingMaskIntoConstraints = false

        caseCheckbox.font = NSFont.systemFont(ofSize: 11)
        caseCheckbox.state = .off
        wrapCheckbox.font = NSFont.systemFont(ofSize: 11)
        wrapCheckbox.state = .on

        for button in [previousButton, nextButton, replaceButton, replaceAllButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: 11)
            button.target = self
        }
        previousButton.action = #selector(findPreviousTapped)
        nextButton.action = #selector(findNextTapped)
        replaceButton.action = #selector(replaceTapped)
        replaceAllButton.action = #selector(replaceAllTapped)
        previousButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        replaceButton.translatesAutoresizingMaskIntoConstraints = false
        replaceAllButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")!,
                                   target: self, action: #selector(closeTapped))
        closeButton.isBordered = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let findRow = NSStackView()
        findRow.orientation = .horizontal
        findRow.spacing = 6
        findRow.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 0, right: 10)
        findRow.translatesAutoresizingMaskIntoConstraints = false
        [findField, caseCheckbox, wrapCheckbox, previousButton, nextButton, closeButton].forEach { findRow.addArrangedSubview($0) }

        replaceRow = NSStackView()
        replaceRow.orientation = .horizontal
        replaceRow.spacing = 6
        replaceRow.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 6, right: 10)
        replaceRow.translatesAutoresizingMaskIntoConstraints = false
        [replaceField, replaceButton, replaceAllButton].forEach { replaceRow.addArrangedSubview($0) }

        addSubview(findRow)
        addSubview(replaceRow)

        let topLine = NSView()
        topLine.wantsLayer = true
        topLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        topLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topLine)

        findRowHeight = findRow.heightAnchor.constraint(equalToConstant: 30)
        replaceRowHeight = replaceRow.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            topLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),

            findRow.topAnchor.constraint(equalTo: topAnchor),
            findRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            findRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            findRowHeight,

            replaceRow.topAnchor.constraint(equalTo: findRow.bottomAnchor),
            replaceRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            replaceRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            replaceRowHeight,

            findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            previousButton.widthAnchor.constraint(equalToConstant: 58),
            nextButton.widthAnchor.constraint(equalToConstant: 58),
            replaceButton.widthAnchor.constraint(equalToConstant: 52),
            replaceAllButton.widthAnchor.constraint(equalToConstant: 72),
        ])
        applyMode()
    }

    private func applyMode() {
        replaceRowHeight.constant = isReplaceMode ? 30 : 0
        replaceRow.isHidden = !isReplaceMode
        findRowHeight.constant = 34
    }

    func activate(replaceMode: Bool, keyword: String?) {
        isReplaceMode = replaceMode
        if let keyword, !keyword.isEmpty, findField.stringValue.isEmpty {
            findField.stringValue = keyword
        }
        window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
    }

    var keyword: String { findField.stringValue }
    var replacement: String { replaceField.stringValue }
    var caseSensitive: Bool { caseCheckbox.state == .on }
    var wraps: Bool { wrapCheckbox.state == .on }

    func setKeyword(_ text: String) {
        findField.stringValue = text
    }

    func applyTheme(_ theme: EditorTheme) {
        wantsLayer = true
        layer?.backgroundColor = theme.gutterBackground.cgColor
    }

    func focusFindField() {
        window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    @objc private func findNextTapped() {
        onFindNext?(keyword, false, caseSensitive)
    }

    @objc private func findPreviousTapped() {
        onFindNext?(keyword, true, caseSensitive)
    }

    @objc private func replaceTapped() {
        onReplace?(keyword, replacement, caseSensitive)
    }

    @objc private func replaceAllTapped() {
        onReplaceAll?(keyword, replacement, caseSensitive)
    }

    @objc private func closeTapped() {
        onClose?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onFindNext?(keyword, false, caseSensitive)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onClose?()
            return true
        }
        return false
    }
}

// MARK: - 字体对话框

/// 字体示例预览框（自绘，保证大字号的垂直居中与裁剪）
final class FontSampleView: NSView {

    var sampleFont: NSFont = NSFont.systemFont(ofSize: 18) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let text = "AaBbYyZz   中文字体示例   " + (sampleFont.displayName ?? "") + "   " + String(format: "%g", sampleFont.pointSize) + " pt"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: sampleFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let height = min(bounds.height - 8, attributed.size().height + 4)
        let rect = NSRect(x: 6, y: (bounds.height - height) / 2, width: bounds.width - 12, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        attributed.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class FontChooserController: NSObject {

    private var familyPopup: NSPopUpButton!
    private var stylePopup: NSPopUpButton!
    private var sizeCombo: NSComboBox!
    private var sampleView: FontSampleView!
    private var accessory: NSView!
    private var result: NSFont?
    private var families: [String] = []

    /// 以模态对话框呈现。采用 NSAlert + accessoryView：尺寸、模态行为、按钮都由系统保证，
    /// 避免裸窗口 + Auto Layout 在 order front 时被压缩尺寸的问题。
    static func present(current: NSFont, modalFor parent: NSWindow?) -> NSFont? {
        let controller = FontChooserController()
        return controller.run(current: current, parent: parent)
    }

    private func run(current: NSFont, parent: NSWindow?) -> NSFont? {
        families = NSFontManager.shared.availableFontFamilies.sorted()
        buildAccessory()

        let family = current.familyName ?? families.first ?? "Helvetica"
        if familyPopup.indexOfItem(withTitle: family) >= 0 {
            familyPopup.selectItem(withTitle: family)
        }
        let traits = NSFontManager.shared.traits(of: current)
        refreshStyleItems(family: familyPopup.titleOfSelectedItem ?? family,
                          preferredTag: styleIndex(bold: traits.contains(.boldFontMask),
                                                   italic: traits.contains(.italicFontMask)))
        sizeCombo.stringValue = String(format: "%g", current.pointSize)
        updatePreview()

        let alert = NSAlert()
        alert.messageText = "字体"
        alert.accessoryView = accessory
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        alert.layout()

        if let parent {
            let frame = alert.window.frame
            let parentFrame = parent.frame
            alert.window.setFrameOrigin(NSPoint(x: parentFrame.midX - frame.width / 2,
                                                y: parentFrame.midY - frame.height / 2))
        }

        let response = alert.runModal()
        window?.orderOut(nil)
        guard response == .alertFirstButtonReturn else { return nil }
        result = selectedFont
        return result
    }

    private func buildAccessory() {
        let width: CGFloat = 420
        let height: CGFloat = 206
        accessory = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let labelFont = NSFont.systemFont(ofSize: 12)
        func makeLabel(_ text: String, y: CGFloat) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = labelFont
            label.alignment = .right
            label.frame = NSRect(x: 0, y: y + 5, width: 62, height: 18)
            return label
        }

        let fontLabel = makeLabel("字体(F):", y: 170)
        let styleLabel = makeLabel("字形(Y):", y: 136)
        let sizeLabel = makeLabel("大小(S):", y: 102)

        familyPopup = NSPopUpButton(frame: NSRect(x: 70, y: 165, width: width - 70, height: 26), pullsDown: false)
        familyPopup.addItems(withTitles: families)
        familyPopup.target = self
        familyPopup.action = #selector(familyChanged)

        stylePopup = NSPopUpButton(frame: NSRect(x: 70, y: 131, width: width - 70, height: 26), pullsDown: false)
        stylePopup.target = self
        stylePopup.action = #selector(updatePreview)

        sizeCombo = NSComboBox(frame: NSRect(x: 70, y: 97, width: 120, height: 26))
        sizeCombo.addItems(withObjectValues: ["8", "9", "10", "11", "12", "14", "16", "18", "20",
                                              "22", "24", "26", "28", "36", "48", "72"])
        sizeCombo.target = self
        sizeCombo.action = #selector(updatePreview)
        sizeCombo.completes = true
        sizeCombo.delegate = self

        sampleView = FontSampleView(frame: NSRect(x: 0, y: 0, width: width, height: 84))
        sampleView.autoresizingMask = [.width, .maxYMargin]

        [fontLabel, styleLabel, sizeLabel].forEach { accessory.addSubview($0) }
        accessory.addSubview(familyPopup)
        accessory.addSubview(stylePopup)
        accessory.addSubview(sizeCombo)
        accessory.addSubview(sampleView)
    }

    private func styleIndex(bold: Bool, italic: Bool) -> Int {
        switch (bold, italic) {
        case (false, false): return 0
        case (false, true):  return 1
        case (true, false):  return 2
        case (true, true):   return 3
        }
    }

    private var selectedFont: NSFont {
        let family = familyPopup.titleOfSelectedItem ?? "Helvetica"
        let rawSize = Double(sizeCombo.stringValue.trimmingCharacters(in: .whitespaces)) ?? 12
        let size = max(1, min(1638, rawSize))
        let tag = stylePopup.selectedItem?.tag ?? 0
        let bold = tag == 2 || tag == 3
        let italic = tag == 1 || tag == 3

        var font = NSFont(name: family, size: CGFloat(size)) ?? NSFont.systemFont(ofSize: CGFloat(size))
        font = NSFontManager.shared.convert(font, toHaveTrait: bold ? .boldFontMask : .unboldFontMask)
        font = NSFontManager.shared.convert(font, toHaveTrait: italic ? .italicFontMask : .unitalicFontMask)
        return font
    }

    /// 只列出该字体族实际拥有的字形（与 Windows 记事本的字体对话框一致）
    private func refreshStyleItems(family: String, preferredTag: Int) {
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        var available: Set<Int> = [0]
        for member in members {
            guard member.count >= 4, let traits = member[3] as? NSNumber else { continue }
            let mask = NSFontTraitMask(rawValue: traits.uintValue)
            let isBold = mask.contains(.boldFontMask)
            let isItalic = mask.contains(.italicFontMask)
            if isBold && isItalic { available.insert(3) }
            else if isBold { available.insert(2) }
            else if isItalic { available.insert(1) }
        }

        let items: [(title: String, tag: Int)] = [
            ("常规", 0), ("斜体", 1), ("粗体", 2), ("粗斜体", 3),
        ].filter { available.contains($0.tag) }

        stylePopup.removeAllItems()
        for item in items {
            stylePopup.addItem(withTitle: item.title)
            stylePopup.lastItem?.tag = item.tag
        }
        if let index = items.firstIndex(where: { $0.tag == preferredTag }) {
            stylePopup.selectItem(at: index)
        } else {
            stylePopup.selectItem(at: 0)
        }
    }

    @objc private func familyChanged() {
        refreshStyleItems(family: familyPopup.titleOfSelectedItem ?? "Helvetica",
                          preferredTag: stylePopup.selectedItem?.tag ?? 0)
        updatePreview()
    }

    @objc private func updatePreview() {
        sampleView.sampleFont = selectedFont
        // 实时把字号规范化为合法值，避免空/非法输入导致预览异常
        if let value = Double(sizeCombo.stringValue), value >= 1, value <= 1638 { return }
    }

    private var window: NSWindow? { NSApp.modalWindow }
}

extension FontChooserController: NSComboBoxDelegate {
    func comboBoxSelectionDidChange(_ notification: Notification) {
        updatePreview()
    }
}

// MARK: - 通用对话框

enum Dialogs {

    enum SaveChoice { case save, discard, cancel }

    @discardableResult
    static func askToSave(name: String) -> SaveChoice {
        let alert = NSAlert()
        alert.messageText = "是否将更改保存到 \(name)？"
        alert.informativeText = "如果不保存，你的更改将会丢失。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .save
        case .alertSecondButtonReturn: return .discard
        default:                       return .cancel
        }
    }

    static func error(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    static func goToLine(maxLine: Int) -> Int? {
        let alert = NSAlert()
        alert.messageText = "转到行"
        alert.informativeText = "行号 (1 - \(maxLine)):"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "1"
        alert.accessoryView = field
        alert.addButton(withTitle: "转到")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard let value = Int(field.stringValue.trimmingCharacters(in: .whitespaces)),
              value >= 1, value <= max(maxLine, 1) else {
            return nil
        }
        return value
    }

    static func about(version: String) {
        let alert = NSAlert()
        alert.messageText = AppInfo.name
        alert.informativeText = """
        版本 \(version) · 原生 AppKit 实现

        语法高亮（\(Language.all.count) 种语言）· 行号栏 · 当前行/括号匹配高亮
        智能缩进 · 括号自动配对 · 注释切换 · 行移动/复制/删除
        6 套主题 · 多光标外的常用编辑能力 · 查找替换 · 打印

        编码：UTF-8、UTF-8 带 BOM、UTF-16 LE/BE、ANSI(GB18030)
        行尾：Windows (CRLF)、Unix (LF)、Macintosh (CR)

        数据层全部字节级实现，10 MB 文件打开约 0.15 s，
        打字时语法着色只更新改动区间，长文件同样跟手。
        """
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    static func shortcuts() {
        let alert = NSAlert()
        alert.messageText = "键盘快捷键"
        alert.informativeText = """
        ⌘N 新建        ⌘⇧N 新窗口      ⌘O 打开
        ⌘S 保存        ⌘⇧S 另存为      ⌘P 打印
        ⌘Z 撤消        ⌘⇧Z 重做        ⌘X/⌘C/⌘V 剪切/复制/粘贴
        ⌘F 查找        ⌘G 查找下一个   ⌘⇧G 查找上一个
        ⌥⌘F 替换       ⌘L 转到行       F5 插入时间/日期

        ⌘/ 注释切换    ⇧⌘D 复制行      ⇧⌘K 删除行
        ⌥↑/⌥↓ 移动行   ⌘] / ⌘[ 缩进    Tab / ⇧Tab 缩进
        ⌘= 放大        ⌘- 缩小        ⌘0 恢复默认缩放
        ⌘+滚轮 缩放     ⌃⌘F 全屏       ⌘W 关闭窗口
        """
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
