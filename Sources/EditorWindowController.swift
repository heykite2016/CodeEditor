//
//  EditorWindowController.swift
//  记事本 —— 编辑器窗口：文本视图 / 状态栏 / 查找替换 / 全部菜单动作
//

import AppKit
import UniformTypeIdentifiers

// MARK: - 编辑器窗口

final class EditorWindowController: NSWindowController, NSWindowDelegate,
                                    NSTextViewDelegate, NSTextStorageDelegate, NSMenuItemValidation {

    let textDocument: TextDocument
    var onWindowClosed: (() -> Void)?

    private var textView: CodeTextView!
    private var scrollView: NSScrollView!
    private var statusBar: StatusBarView!
    private var findBar: FindBarView!
    private var ruler: LineNumberRulerView!

    private var findBarHeight: NSLayoutConstraint!
    private var statusBarHeight: NSLayoutConstraint!

    private let lineIndex = LineIndex()
    private let highlighter = SyntaxHighlighter()
    private var baseFont: NSFont = EditorWindowController.defaultFont()
    private var zoomPercent: Int = 100
    private var wordWrapEnabled: Bool = false
    private var statusBarVisible: Bool = true
    private var lastFindKeyword: String = ""

    private var language: Language = .plain
    private var theme: EditorTheme = .light
    private var themeID = EditorTheme.autoID
    private var lastTokens: [SyntaxToken] = []
    private var highlightScheduled = false
    private var scrollObserver: NSObjectProtocol?

    // 代码编辑行为（持久化到 UserDefaults）
    private var autoIndent = true
    private var autoClose = true
    private var softTabs = true
    private var tabWidth = 4
    private var showLineNumbers = true
    private var showIndentGuides = true
    private var highlightCurrentLine = true
    private var bracketMatching = true
    private var highlightEnabled = true

    private static let zoomLevels = [10, 25, 50, 75, 100, 125, 150, 175, 200, 250, 300, 400, 500]

    static func defaultFont() -> NSFont {
        for name in ["Consolas", "Menlo", "Monaco", "Courier New"] {
            if let font = NSFont(name: name, size: 12) { return font }
        }
        return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    // MARK: 生命周期

    init(textDocument: TextDocument = TextDocument()) {
        self.textDocument = textDocument
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 520, height: 300)
        window.tabbingMode = .disallowed
        window.title = "无标题 - \(AppInfo.name)"
        super.init(window: window)

        loadPreferences()
        window.delegate = self
        window.nextResponder = self
        buildInterface()
        applyTheme()
        updateTitle()
        updateStatus()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(systemAppearanceChanged),
                                               name: NSApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: 界面构建

    func focusTextView() {
        window?.makeFirstResponder(textView)
    }

    private func buildInterface() {
        guard let window, let contentView = window.contentView else { return }
        contentView.wantsLayer = true

        // 文本视图
        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 1040, height: 660))
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.usesInspectorBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isIncrementalSearchingEnabled = false
        if #available(macOS 10.12.2, *) { textView.isAutomaticTextCompletionEnabled = false }
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineFragmentPadding = 2
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 1040, height: CGFloat.greatestFiniteMagnitude)
        textView.registerForDraggedTypes([.fileURL])
        textView.font = baseFont

        textView.theme = theme
        textView.autoIndentEnabled = autoIndent
        textView.autoCloseEnabled = autoClose
        textView.tabWidth = tabWidth
        textView.softTabs = softTabs
        textView.showIndentGuides = showIndentGuides
        textView.highlightCurrentLine = highlightCurrentLine
        textView.bracketMatchingEnabled = bracketMatching
        textView.typingAttributes = typingAttributes(for: baseFont)

        textView.onZoomScroll = { [weak self] step in self?.stepZoom(step) }
        textView.onFileDrop = { [weak self] url in
            guard let self else { return }
            if self.textDocument.isModified || self.textDocument.fileURL != nil || !self.textView.string.isEmpty {
                AppDelegate.shared?.openInNewWindow(url: url)
            } else {
                self.open(url: url)
            }
        }

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true

        ruler = LineNumberRulerView(scrollView: scrollView, textView: textView, lineIndex: lineIndex)
        ruler.theme = theme
        ruler.showIndentGuides = showIndentGuides
        ruler.tabWidth = tabWidth
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showLineNumbers

        statusBar = StatusBarView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.onEncodingChange = { [weak self] encoding in self?.changeEncoding(to: encoding) }
        statusBar.onLineEndingChange = { [weak self] ending in self?.changeLineEnding(to: ending) }
        statusBar.onZoomChange = { [weak self] percent in self?.applyZoom(percent) }
        statusBar.onZoomStep = { [weak self] step in self?.stepZoom(step) }
        statusBar.onLanguageChange = { [weak self] index in self?.selectLanguage(at: index) }
        statusBar.onIndentChange = { [weak self] width, soft in self?.setIndentation(tabWidth: width, softTabs: soft) }

        findBar = FindBarView()
        findBar.translatesAutoresizingMaskIntoConstraints = false
        findBar.isHidden = true
        findBar.onFindNext = { [weak self] keyword, backwards, caseSensitive in
            self?.find(keyword: keyword, backwards: backwards, caseSensitive: caseSensitive, wrap: true)
        }
        findBar.onReplace = { [weak self] keyword, replacement, caseSensitive in
            self?.replaceCurrent(keyword: keyword, replacement: replacement, caseSensitive: caseSensitive)
        }
        findBar.onReplaceAll = { [weak self] keyword, replacement, caseSensitive in
            self?.replaceAll(keyword: keyword, replacement: replacement, caseSensitive: caseSensitive)
        }
        findBar.onClose = { [weak self] in self?.hideFindBar() }

        contentView.addSubview(findBar)
        contentView.addSubview(scrollView)
        contentView.addSubview(statusBar)

        findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
        statusBarHeight = statusBar.heightAnchor.constraint(equalToConstant: 26)

        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            findBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            findBarHeight,

            scrollView.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBarHeight,
        ])

        self.textView = textView
        textView.textStorage?.delegate = self

        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                object: scrollView.contentView,
                                                                queue: .main) { [weak self] _ in
            self?.ruler?.needsDisplay = true
        }

        setWordWrap(wordWrapEnabled)
        applyZoom(zoomPercent)
        updateRulerMetrics()
    }

    private func typingAttributes(for font: NSFont) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        paragraph.defaultTabInterval = spaceWidth * CGFloat(max(1, tabWidth))
        paragraph.tabStops = []
        return [.font: font, .foregroundColor: theme.text, .paragraphStyle: paragraph]
    }

    private func updateRulerMetrics() {
        guard let ruler else { return }
        ruler.updateFont(size: min(13, max(9, baseFont.pointSize * CGFloat(zoomPercent) / 100 - 1)))
        ruler.tabWidth = tabWidth
        ruler.showIndentGuides = showIndentGuides
        ruler.needsDisplay = true
    }

    // MARK: 文件操作

    func open(url: URL) {
        do {
            let loaded = try TextFileIO.load(url: url)
            textDocument.fileURL = url
            textDocument.encoding = loaded.encoding
            textDocument.lineEnding = loaded.lineEnding
            textDocument.isModified = false

            textView.string = loaded.text
            lineIndex.rebuild(textView.string as NSString)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))

            if loaded.byteCount > 4_000_000 {
                setWordWrap(false)
            }

            setLanguage(Language.detect(fileName: url.lastPathComponent), notifyStatusBar: true)
            highlightNow()
            ruler?.needsDisplay = true

            window?.isDocumentEdited = false
            window?.representedURL = url
            updateTitle()
            updateStatus()
            window?.makeFirstResponder(textView)
        } catch {
            Dialogs.error(title: "无法打开文件", message: error.localizedDescription)
        }
    }

    @objc func newDocument(_ sender: Any?) {
        guard confirmDiscardChangesIfNeeded() else { return }
        textDocument.fileURL = nil
        textDocument.isModified = false
        textView.string = ""
        lineIndex.rebuild(textView.string as NSString)
        setLanguage(.plain, notifyStatusBar: true)
        highlightNow()
        window?.isDocumentEdited = false
        window?.representedURL = nil
        updateTitle()
        updateStatus()
        ruler?.needsDisplay = true
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.message = "打开代码或文本文件"
        panel.prompt = "打开"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if textDocument.isModified || !textView.string.isEmpty || textDocument.fileURL != nil {
            AppDelegate.shared?.openInNewWindow(url: url)
        } else {
            open(url: url)
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        if let url = textDocument.fileURL {
            _ = save(to: url)
        } else {
            _ = saveDocumentAs(sender)
        }
    }

    @objc @discardableResult
    func saveDocumentAs(_ sender: Any?) -> Bool {
        let panel = NSSavePanel()
        panel.title = "另存为"
        panel.prompt = "保存"
        panel.nameFieldStringValue = textDocument.fileURL?.lastPathComponent ?? "无标题.txt"
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 58))
        let encodingLabel = NSTextField(labelWithString: "编码(E):")
        encodingLabel.frame = NSRect(x: 12, y: 32, width: 60, height: 18)
        encodingLabel.font = NSFont.systemFont(ofSize: 11)
        let encodingPopup = NSPopUpButton(frame: NSRect(x: 76, y: 28, width: 180, height: 24), pullsDown: false)
        encodingPopup.controlSize = .small
        encodingPopup.font = NSFont.systemFont(ofSize: 11)
        for item in TextEncoding.allCases {
            let menuItem = NSMenuItem(title: item.displayName, action: nil, keyEquivalent: "")
            menuItem.tag = item.rawValue
            encodingPopup.menu?.addItem(menuItem)
        }
        encodingPopup.selectItem(withTag: textDocument.encoding.rawValue)

        let eolLabel = NSTextField(labelWithString: "行尾(L):")
        eolLabel.frame = NSRect(x: 12, y: 6, width: 60, height: 18)
        eolLabel.font = NSFont.systemFont(ofSize: 11)
        let eolPopup = NSPopUpButton(frame: NSRect(x: 76, y: 2, width: 180, height: 24), pullsDown: false)
        eolPopup.controlSize = .small
        eolPopup.font = NSFont.systemFont(ofSize: 11)
        eolPopup.addItems(withTitles: LineEnding.allCases.map { $0.displayName })
        eolPopup.selectItem(at: textDocument.lineEnding.rawValue)

        [encodingLabel, encodingPopup, eolLabel, eolPopup].forEach { accessory.addSubview($0) }
        panel.accessoryView = accessory

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let chosenEncoding = TextEncoding(rawValue: encodingPopup.selectedTag()) ?? textDocument.encoding
        let chosenEOL = LineEnding(rawValue: eolPopup.indexOfSelectedItem) ?? textDocument.lineEnding
        textDocument.encoding = chosenEncoding
        textDocument.lineEnding = chosenEOL

        if !save(to: url) {
            return false
        }
        window?.representedURL = url
        return true
    }

    @discardableResult
    private func save(to url: URL) -> Bool {
        do {
            let data = try TextFileIO.encode(text: textView.string,
                                             encoding: textDocument.encoding,
                                             lineEnding: textDocument.lineEnding)
            try data.write(to: url, options: .atomic)
            let previousURL = textDocument.fileURL
            textDocument.fileURL = url
            textDocument.isModified = false
            window?.isDocumentEdited = false
            if previousURL != url {
                setLanguage(Language.detect(fileName: url.lastPathComponent), notifyStatusBar: true)
                highlightNow()
            }
            updateTitle()
            updateStatus()
            return true
        } catch {
            Dialogs.error(title: "无法保存文件", message: error.localizedDescription)
            return false
        }
    }

    @objc func pageSetup(_ sender: Any?) {
        let info = printInfo()
        guard let window else { return }
        NSPageLayout().beginSheet(with: info, modalFor: window, delegate: nil,
                                  didEnd: nil, contextInfo: nil)
    }

    @objc func printDocument(_ sender: Any?) {
        let info = printInfo()
        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        guard let window else { return }
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func printInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        return info
    }

    // MARK: 编辑

    @objc func deleteSelection(_ sender: Any?) {
        let range = textView.selectedRange()
        if range.length > 0 {
            textView.insertText("", replacementRange: range)
        } else if range.location < (textView.string as NSString).length {
            textView.insertText("", replacementRange: NSRange(location: range.location, length: 1))
        }
    }

    @objc func insertTimeDate(_ sender: Any?) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm yyyy/M/d"
        let stamp = formatter.string(from: Date())
        textView.insertText(stamp, replacementRange: textView.selectedRange())
    }

    // MARK: 查找 / 替换

    @objc func showFind(_ sender: Any?) {
        showFindBar(replaceMode: false)
    }

    @objc func showReplace(_ sender: Any?) {
        showFindBar(replaceMode: true)
    }

    private func showFindBar(replaceMode: Bool) {
        let keyword = currentSelectedText()
        findBarHeight.constant = replaceMode ? 64 : 34
        findBar.isHidden = false
        findBar.activate(replaceMode: replaceMode, keyword: keyword.isEmpty ? nil : keyword)
        if !keyword.isEmpty { findBar.setKeyword(keyword) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func hideFindBar() {
        findBarHeight.constant = 0
        findBar.isHidden = true
        window?.makeFirstResponder(textView)
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func currentSelectedText() -> String {
        let range = textView.selectedRange()
        guard range.length > 0, range.length < 500 else { return "" }
        return (textView.string as NSString).substring(with: range)
    }

    @objc func findNextMenuItem(_ sender: Any?) {
        performFindFromMenu(backwards: false)
    }

    @objc func findPreviousMenuItem(_ sender: Any?) {
        performFindFromMenu(backwards: true)
    }

    private func performFindFromMenu(backwards: Bool) {
        let keyword = lastFindKeyword.isEmpty ? currentSelectedText() : lastFindKeyword
        if keyword.isEmpty {
            showFindBar(replaceMode: false)
            return
        }
        lastFindKeyword = keyword
        if findBar.isHidden == false { findBar.setKeyword(keyword) }
        find(keyword: keyword, backwards: backwards, caseSensitive: findBar.caseSensitive, wrap: true)
    }

    @discardableResult
    private func find(keyword: String, backwards: Bool, caseSensitive: Bool, wrap: Bool) -> Bool {
        guard !keyword.isEmpty else { return false }
        lastFindKeyword = keyword
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        var options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        if backwards { options.insert(.backwards) }

        var found = NSRange(location: NSNotFound, length: 0)
        if backwards {
            let start = max(0, selection.location)
            found = text.range(of: keyword, options: options,
                               range: NSRange(location: 0, length: start))
            if found.location == NSNotFound && wrap && text.length > 0 {
                found = text.range(of: keyword, options: options,
                                   range: NSRange(location: 0, length: text.length))
            }
        } else {
            let start = selection.location + selection.length
            if start <= text.length {
                found = text.range(of: keyword, options: options,
                                   range: NSRange(location: start, length: text.length - start))
            }
            if found.location == NSNotFound && wrap && text.length > 0 {
                found = text.range(of: keyword, options: options,
                                   range: NSRange(location: 0, length: min(text.length, start)))
            }
        }

        guard found.location != NSNotFound else {
            NSSound.beep()
            return false
        }
        textView.setSelectedRange(found)
        textView.scrollRangeToVisible(found)
        textView.showFindIndicator(for: found)
        window?.makeFirstResponder(textView)
        return true
    }

    private func replaceCurrent(keyword: String, replacement: String, caseSensitive: Bool) {
        guard !keyword.isEmpty else { return }
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let matches: Bool
        if selection.length > 0 && selection.length <= (text.length) {
            let selected = text.substring(with: selection)
            matches = caseSensitive ? (selected == keyword)
                                    : selected.compare(keyword, options: .caseInsensitive) == .orderedSame
        } else {
            matches = false
        }
        if matches {
            textView.insertText(replacement, replacementRange: selection)
        }
        find(keyword: keyword, backwards: false, caseSensitive: caseSensitive, wrap: true)
    }

    private func replaceAll(keyword: String, replacement: String, caseSensitive: Bool) {
        guard !keyword.isEmpty else { return }
        let text = textView.string as NSString
        var options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        options.insert(.literal)
        var searchRange = NSRange(location: 0, length: text.length)
        var ranges: [NSRange] = []
        while searchRange.length > 0 {
            let found = text.range(of: keyword, options: options, range: searchRange)
            if found.location == NSNotFound { break }
            ranges.append(found)
            let next = found.location + max(found.length, 1)
            if next > text.length { break }
            searchRange = NSRange(location: next, length: text.length - next)
        }
        guard !ranges.isEmpty else {
            NSSound.beep()
            return
        }
        guard let storage = textView.textStorage else { return }
        textView.undoManager?.beginUndoGrouping()
        storage.beginEditing()
        for range in ranges.reversed() {
            storage.replaceCharacters(in: range, with: replacement)
        }
        storage.endEditing()
        textView.undoManager?.endUndoGrouping()
        textView.didChangeText()
        updateStatus()
        findBar.focusFindField()
    }

    // MARK: 转到行

    @objc func goToLine(_ sender: Any?) {
        let total = max(lineIndex.lineCount, 1)
        guard let line = Dialogs.goToLine(maxLine: total) else { return }
        let text = textView.string as NSString
        let start: Int
        if line - 1 < lineIndex.starts.count {
            start = min(lineIndex.starts[line - 1], text.length)
        } else {
            start = text.length
        }
        let range = text.lineRange(for: NSRange(location: start, length: 0))
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
        textView.scrollRangeToVisible(range)
        window?.makeFirstResponder(textView)
    }

    // MARK: 格式

    @objc func toggleWordWrap(_ sender: Any?) {
        setWordWrap(!wordWrapEnabled)
        savePreference(wordWrapEnabled, EditorPrefs.wordWrap)
    }

    private func setWordWrap(_ enabled: Bool) {
        wordWrapEnabled = enabled
        guard let textView, let scrollView else { return }

        if enabled {
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                           height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.height]
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                           height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
            textView.sizeToFit()
        }
        textView.needsDisplay = true
    }

    @objc func showFontPanel(_ sender: Any?) {
        guard let window else { return }
        let currentFont = NSFont(descriptor: baseFont.fontDescriptor,
                                size: baseFont.pointSize) ?? baseFont
        guard let chosen = FontChooserController.present(current: currentFont, modalFor: window) else { return }
        baseFont = chosen
        savePreference(chosen.fontName, EditorPrefs.fontName)
        savePreference(Double(chosen.pointSize), EditorPrefs.fontSize)
        applyZoom(zoomPercent)
        window.makeFirstResponder(textView)
    }

    @objc func toggleStatusBar(_ sender: Any?) {
        statusBarVisible.toggle()
        statusBarHeight.constant = statusBarVisible ? 26 : 0
        statusBar.isHidden = !statusBarVisible
        window?.contentView?.layoutSubtreeIfNeeded()
        if statusBarVisible { updateStatus() }
    }

    // MARK: - 偏好设置

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        themeID = defaults.string(forKey: EditorPrefs.theme) ?? EditorTheme.autoID
        autoIndent = defaults.object(forKey: EditorPrefs.autoIndent) as? Bool ?? true
        autoClose = defaults.object(forKey: EditorPrefs.autoClose) as? Bool ?? true
        softTabs = defaults.object(forKey: EditorPrefs.softTabs) as? Bool ?? true
        tabWidth = defaults.object(forKey: EditorPrefs.tabWidth) as? Int ?? 4
        showLineNumbers = defaults.object(forKey: EditorPrefs.lineNumbers) as? Bool ?? true
        showIndentGuides = defaults.object(forKey: EditorPrefs.indentGuides) as? Bool ?? true
        highlightCurrentLine = defaults.object(forKey: EditorPrefs.currentLine) as? Bool ?? true
        bracketMatching = defaults.object(forKey: EditorPrefs.bracketMatch) as? Bool ?? true
        wordWrapEnabled = defaults.object(forKey: EditorPrefs.wordWrap) as? Bool ?? false
        zoomPercent = defaults.object(forKey: EditorPrefs.zoom) as? Int ?? 100

        if let name = defaults.string(forKey: EditorPrefs.fontName),
           let size = defaults.object(forKey: EditorPrefs.fontSize) as? Double,
           let font = NSFont(name: name, size: CGFloat(size)) {
            baseFont = font
        }
        theme = resolveTheme()
    }

    private func savePreference(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func resolveTheme() -> EditorTheme {
        let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return EditorTheme.resolved(id: themeID, isDark: isDark)
    }

    // MARK: - 主题

    func applyTheme() {
        theme = resolveTheme()
        guard let window else { return }
        // 非「跟随系统」时强制窗口外观，保证标题栏、弹窗与编辑器配色一致
        if themeID == EditorTheme.autoID {
            window.appearance = nil
        } else {
            window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        }
        window.backgroundColor = theme.background
        textView?.theme = theme
        textView?.typingAttributes = typingAttributes(for: currentFont())
        scrollView?.backgroundColor = theme.background
        statusBar?.applyTheme(theme)
        findBar?.applyTheme(theme)
        ruler?.theme = theme
        ruler?.needsDisplay = true
        resetHighlight()
        highlightNow()
        textView?.needsDisplay = true
    }

    @objc func systemAppearanceChanged() {
        guard themeID == EditorTheme.autoID, theme.id != resolveTheme().id else { return }
        applyTheme()
    }

    private func currentFont() -> NSFont {
        let size = max(1, baseFont.pointSize * CGFloat(zoomPercent) / 100)
        return NSFont(descriptor: baseFont.fontDescriptor, size: size) ?? baseFont
    }

    private func setThemeID(_ id: String) {
        themeID = id
        savePreference(id, EditorPrefs.theme)
        applyTheme()
    }

    // MARK: - 语言与高亮

    func setLanguage(_ newLanguage: Language, notifyStatusBar: Bool = true) {
        language = newLanguage
        highlightEnabled = true
        if notifyStatusBar, let statusBar {
            let index = Language.all.firstIndex { $0.id == newLanguage.id } ?? 0
            statusBar.setLanguage(index: index)
        }
        statusBar?.setIndent(tabWidth: tabWidth, softTabs: softTabs)
        updateStatus()
    }

    private func selectLanguage(at index: Int) {
        guard index >= 0 && index < Language.all.count else { return }
        setLanguage(Language.all[index])
        highlightNow()
        textView?.needsDisplay = true
    }

    @objc func changeLanguageFromMenu(_ sender: NSMenuItem) {
        selectLanguage(at: sender.tag)
    }

    @objc func detectLanguageAction(_ sender: Any?) {
        setLanguage(Language.detect(fileName: textDocument.fileURL?.lastPathComponent))
        highlightNow()
        textView?.needsDisplay = true
    }

    @objc func changeThemeFromMenu(_ sender: NSMenuItem) {
        let ids = EditorTheme.all.map { $0.id }
        guard sender.tag >= 0 && sender.tag < ids.count else { return }
        setThemeID(ids[sender.tag])
    }

    @objc func useSystemTheme(_ sender: Any?) {
        setThemeID(EditorTheme.autoID)
    }

    private func scheduleHighlight() {
        guard highlightEnabled, !highlightScheduled else { return }
        highlightScheduled = true
        // 合并同一轮事件里的多次编辑，避免每次按键都重排属性
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.highlightScheduled = false
            self.highlightNow()
        }
    }

    func highlightNow() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let text = textView.string as NSString
        let tokens: [SyntaxToken]
        if language.flavor == .plain || text.length == 0 || text.length > SyntaxHighlighter.maxHighlightLength {
            tokens = []
        } else {
            tokens = highlighter.tokenize(text, language: language)
        }
        applyTokens(tokens, layoutManager: layoutManager, textLength: text.length)
    }

    private func resetHighlight() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        if length > 0 {
            layoutManager.removeTemporaryAttribute(.foregroundColor,
                                                   forCharacterRange: NSRange(location: 0, length: length))
        }
        lastTokens = []
    }

    /// 只更新发生变化的 token 区间：打字开销与改动量成正比，而不是与文件大小成正比
    private func applyTokens(_ tokens: [SyntaxToken], layoutManager: NSLayoutManager, textLength: Int) {
        let old = lastTokens
        var prefix = 0
        let minCount = min(old.count, tokens.count)
        while prefix < minCount,
              old[prefix].range == tokens[prefix].range,
              old[prefix].kind == tokens[prefix].kind {
            prefix += 1
        }
        var suffix = 0
        while suffix < minCount - prefix,
              old[old.count - 1 - suffix].range == tokens[tokens.count - 1 - suffix].range,
              old[old.count - 1 - suffix].kind == tokens[tokens.count - 1 - suffix].kind {
            suffix += 1
        }

        let oldSlice = old[prefix..<(old.count - suffix)]
        let newSlice = tokens[prefix..<(tokens.count - suffix)]

        if !oldSlice.isEmpty {
            let start = oldSlice.first!.range.location
            let last = oldSlice.last!
            let end = last.range.location + last.range.length
            let clampedStart = min(start, textLength)
            let clampedEnd = min(end, textLength)
            if clampedEnd > clampedStart {
                layoutManager.removeTemporaryAttribute(.foregroundColor,
                                                       forCharacterRange: NSRange(location: clampedStart,
                                                                                 length: clampedEnd - clampedStart))
            }
        }

        for token in newSlice {
            guard token.range.location + token.range.length <= textLength else { continue }
            layoutManager.addTemporaryAttribute(.foregroundColor,
                                                value: theme.color(for: token.kind),
                                                forCharacterRange: token.range)
        }
        lastTokens = tokens
    }

    // MARK: - 编辑器选项

    @objc func toggleLineNumbers(_ sender: Any?) {
        showLineNumbers.toggle()
        scrollView?.rulersVisible = showLineNumbers
        savePreference(showLineNumbers, EditorPrefs.lineNumbers)
        ruler?.needsDisplay = true
    }

    @objc func toggleIndentGuides(_ sender: Any?) {
        showIndentGuides.toggle()
        textView?.showIndentGuides = showIndentGuides
        ruler?.showIndentGuides = showIndentGuides
        savePreference(showIndentGuides, EditorPrefs.indentGuides)
        textView?.needsDisplay = true
    }

    @objc func toggleAutoIndent(_ sender: Any?) {
        autoIndent.toggle()
        textView?.autoIndentEnabled = autoIndent
        savePreference(autoIndent, EditorPrefs.autoIndent)
    }

    @objc func toggleAutoClose(_ sender: Any?) {
        autoClose.toggle()
        textView?.autoCloseEnabled = autoClose
        savePreference(autoClose, EditorPrefs.autoClose)
    }

    @objc func toggleBracketMatching(_ sender: Any?) {
        bracketMatching.toggle()
        textView?.bracketMatchingEnabled = bracketMatching
        if bracketMatching { textView?.updateBracketHighlight() } else { textView?.clearBracketHighlight() }
        savePreference(bracketMatching, EditorPrefs.bracketMatch)
    }

    @objc func toggleCurrentLineHighlight(_ sender: Any?) {
        highlightCurrentLine.toggle()
        textView?.highlightCurrentLine = highlightCurrentLine
        savePreference(highlightCurrentLine, EditorPrefs.currentLine)
        textView?.needsDisplay = true
    }

    @objc func setIndentWidth2(_ sender: Any?) { setIndentation(tabWidth: 2, softTabs: softTabs) }
    @objc func setIndentWidth4(_ sender: Any?) { setIndentation(tabWidth: 4, softTabs: softTabs) }
    @objc func setIndentWidth8(_ sender: Any?) { setIndentation(tabWidth: 8, softTabs: softTabs) }

    @objc func toggleSoftTabs(_ sender: Any?) {
        setIndentation(tabWidth: tabWidth, softTabs: !softTabs)
    }

    func setIndentation(tabWidth width: Int, softTabs soft: Bool) {
        tabWidth = max(1, min(12, width))
        softTabs = soft
        textView?.tabWidth = tabWidth
        textView?.softTabs = softTabs
        textView?.typingAttributes = typingAttributes(for: currentFont())
        ruler?.tabWidth = tabWidth
        statusBar?.setIndent(tabWidth: tabWidth, softTabs: softTabs)
        savePreference(tabWidth, EditorPrefs.tabWidth)
        savePreference(softTabs, EditorPrefs.softTabs)
        textView?.needsDisplay = true
        ruler?.needsDisplay = true
        updateStatus()
    }

    // MARK: - 代码操作

    @objc func toggleCommentAction(_ sender: Any?) {
        textView?.toggleComment(language: language)
        scheduleHighlight()
        ruler?.needsDisplay = true
    }

    @objc func duplicateLineAction(_ sender: Any?) {
        textView?.duplicateSelectedLines()
        scheduleHighlight()
    }

    @objc func deleteLineAction(_ sender: Any?) {
        textView?.deleteSelectedLines()
        scheduleHighlight()
    }

    @objc func moveLineUpAction(_ sender: Any?) {
        textView?.moveSelectedLines(up: true)
        scheduleHighlight()
    }

    @objc func moveLineDownAction(_ sender: Any?) {
        textView?.moveSelectedLines(up: false)
        scheduleHighlight()
    }

    @objc func indentMoreAction(_ sender: Any?) {
        textView?.indentSelectedLines(outdent: false)
        scheduleHighlight()
    }

    @objc func indentLessAction(_ sender: Any?) {
        textView?.indentSelectedLines(outdent: true)
        scheduleHighlight()
    }

    @objc func toggleWordWrapAction(_ sender: Any?) {
        setWordWrap(!wordWrapEnabled)
        savePreference(wordWrapEnabled, EditorPrefs.wordWrap)
    }

    // MARK: 缩放

    @objc func zoomIn(_ sender: Any?) { stepZoom(1) }
    @objc func zoomOut(_ sender: Any?) { stepZoom(-1) }
    @objc func zoomReset(_ sender: Any?) { applyZoom(100) }

    private func stepZoom(_ direction: Int) {
        let levels = EditorWindowController.zoomLevels
        let current = zoomPercent
        if direction > 0 {
            for level in levels where level > current { applyZoom(level); return }
            applyZoom(levels.last ?? 500)
        } else {
            for level in levels.reversed() where level < current { applyZoom(level); return }
            applyZoom(levels.first ?? 10)
        }
    }

    private func applyZoom(_ percent: Int) {
        let clamped = max(10, min(500, percent))
        zoomPercent = clamped
        guard let textView, let statusBar else { return }
        let font = currentFont()
        let selection = textView.selectedRange()

        textView.font = font
        textView.typingAttributes = typingAttributes(for: font)
        textView.updateSpaceWidth()
        textView.setSelectedRange(NSRange(location: min(selection.location, (textView.string as NSString).length),
                                          length: 0))
        statusBar.setZoom(clamped)
        updateRulerMetrics()
        textView.needsDisplay = true
        savePreference(clamped, EditorPrefs.zoom)
    }

    // MARK: 编码 / 行尾

    private func changeEncoding(to encoding: TextEncoding) {
        textDocument.encoding = encoding
        // 未修改的文件按新编码重新解码，行为与 Windows 记事本一致
        if !textDocument.isModified, let url = textDocument.fileURL, let data = try? Data(contentsOf: url) {
            let bodyData: Data
            if encoding.bomBytes.isEmpty {
                bodyData = data
            } else if data.starts(with: encoding.bomBytes) {
                bodyData = data.dropFirst(encoding.bomBytes.count)
            } else {
                bodyData = data
            }
            if let text = String(data: bodyData, encoding: encoding.stringEncoding) {
                textView.string = TextFileIO.normalizeNewlines(text)
                lineIndex.rebuild(textView.string as NSString)
            }
        }
        textDocument.isModified = true
        window?.isDocumentEdited = true
        updateStatus()
    }

    private func changeLineEnding(to ending: LineEnding) {
        textDocument.lineEnding = ending
        textDocument.isModified = true
        window?.isDocumentEdited = true
        updateStatus()
    }

    // MARK: 状态同步

    private func updateTitle() {
        window?.title = "\(textDocument.displayName) - \(AppInfo.name)"
    }

    func updateStatus() {
        guard statusBar != nil, textView != nil else { return }
        let selection = textView.selectedRange()
        let (line, column) = lineIndex.lineAndColumn(at: selection.location)
        statusBar.setPosition(line: line, column: column, selectionLength: selection.length)
        statusBar.setEncoding(textDocument.encoding)
        statusBar.setLineEnding(textDocument.lineEnding)
        statusBar.setZoom(zoomPercent)
        statusBar.setIndent(tabWidth: tabWidth, softTabs: softTabs)
        if let index = Language.all.firstIndex(where: { $0.id == language.id }) {
            statusBar.setLanguage(index: index)
        }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        textDocument.isModified = true
        window?.isDocumentEdited = true
        scheduleHighlight()
        updateStatus()
        ruler?.needsDisplay = true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        textView?.updateBracketHighlight()
        updateStatus()
        ruler?.needsDisplay = true
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        lineIndex.update(text: textStorage.string as NSString,
                         editedRange: editedRange, changeInLength: delta)
        ruler?.updateThickness()
    }

    // MARK: 窗口

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard textDocument.isModified else { return true }
        switch Dialogs.askToSave(name: textDocument.displayName) {
        case .save:
            if let url = textDocument.fileURL { return save(to: url) }
            return saveDocumentAs(sender)
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed?()
    }

    private func confirmDiscardChangesIfNeeded() -> Bool {
        guard textDocument.isModified else { return true }
        switch Dialogs.askToSave(name: textDocument.displayName) {
        case .save:
            if let url = textDocument.fileURL { return save(to: url) }
            return saveDocumentAs(nil)
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    // MARK: 菜单校验

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleWordWrap(_:)), #selector(toggleWordWrapAction(_:)):
            menuItem.state = wordWrapEnabled ? .on : .off
            return true
        case #selector(toggleStatusBar(_:)):
            menuItem.state = statusBarVisible ? .on : .off
            return true
        case #selector(toggleLineNumbers(_:)):
            menuItem.state = showLineNumbers ? .on : .off
            return true
        case #selector(toggleIndentGuides(_:)):
            menuItem.state = showIndentGuides ? .on : .off
            return true
        case #selector(toggleCurrentLineHighlight(_:)):
            menuItem.state = highlightCurrentLine ? .on : .off
            return true
        case #selector(toggleAutoIndent(_:)):
            menuItem.state = autoIndent ? .on : .off
            return true
        case #selector(toggleAutoClose(_:)):
            menuItem.state = autoClose ? .on : .off
            return true
        case #selector(toggleBracketMatching(_:)):
            menuItem.state = bracketMatching ? .on : .off
            return true
        case #selector(toggleSoftTabs(_:)):
            menuItem.state = softTabs ? .on : .off
            return true
        case #selector(setIndentWidth2(_:)):
            menuItem.state = (tabWidth == 2 && softTabs) ? .on : .off
            return true
        case #selector(setIndentWidth4(_:)):
            menuItem.state = (tabWidth == 4 && softTabs) ? .on : .off
            return true
        case #selector(setIndentWidth8(_:)):
            menuItem.state = (tabWidth == 8 && softTabs) ? .on : .off
            return true
        case #selector(useSystemTheme(_:)):
            menuItem.state = themeID == EditorTheme.autoID ? .on : .off
            return true
        case #selector(changeThemeFromMenu(_:)):
            let ids = EditorTheme.all.map { $0.id }
            menuItem.state = (menuItem.tag < ids.count && ids[menuItem.tag] == themeID) ? .on : .off
            return true
        case #selector(changeLanguageFromMenu(_:)):
            menuItem.state = (menuItem.tag < Language.all.count
                               && Language.all[menuItem.tag].id == language.id) ? .on : .off
            return true
        case #selector(zoomOut(_:)):
            return zoomPercent > 10
        case #selector(zoomIn(_:)):
            return zoomPercent < 500
        case #selector(saveDocument(_:)):
            return textDocument.isModified || textDocument.fileURL == nil
        case #selector(findNextMenuItem(_:)), #selector(findPreviousMenuItem(_:)),
             #selector(goToLine(_:)):
            return (textView.string as NSString).length > 0
        case #selector(toggleCommentAction(_:)), #selector(duplicateLineAction(_:)),
             #selector(deleteLineAction(_:)), #selector(moveLineUpAction(_:)),
             #selector(moveLineDownAction(_:)), #selector(indentMoreAction(_:)),
             #selector(indentLessAction(_:)):
            return (textView.string as NSString).length > 0
        default:
            return true
        }
    }
}

extension Notification.Name {
    static let notepadOpenFile = Notification.Name("NotepadOpenFileNotification")
}
