//
//  App.swift
//  代码编辑器 —— 应用入口、菜单栏、文件关联、默认编辑器设置
//

import AppKit

enum AppInfo {
    static let name = "代码编辑器"
    static let version = "2.0.0"
    /// 纯文本格式：可一键接管系统默认打开方式
    static let textExtensions = [
        "txt", "log", "ini", "inf", "cfg", "conf", "csv", "md", "markdown",
        "json", "xml", "yml", "yaml", "srt", "properties", "toml"
    ]
    /// 与 Resources/Info.plist 中 CFBundleDocumentTypes 保持一致（含源码格式）
    static let boundExtensions = textExtensions + [
        "swift", "h", "m", "mm", "c", "cc", "cpp", "hpp", "cs", "java", "kt", "kts",
        "py", "pyw", "js", "mjs", "cjs", "jsx", "ts", "tsx", "go", "rs", "rb", "php",
        "sh", "bash", "zsh", "ps1", "sql", "lua", "html", "htm", "css", "scss", "less",
        "vue", "svelte", "plist", "svg", "gradle", "mk", "dockerfile", "bat", "cmd", "reg"
    ]
}

enum EditorPrefs {
    static let theme = "EditorThemeID"
    static let autoIndent = "EditorAutoIndent"
    static let autoClose = "EditorAutoClose"
    static let softTabs = "EditorSoftTabs"
    static let tabWidth = "EditorTabWidth"
    static let lineNumbers = "EditorLineNumbers"
    static let indentGuides = "EditorIndentGuides"
    static let currentLine = "EditorCurrentLine"
    static let bracketMatch = "EditorBracketMatch"
    static let wordWrap = "EditorWordWrap"
    static let fontName = "EditorFontName"
    static let fontSize = "EditorFontSize"
    static let zoom = "EditorZoom"
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    static private(set) var shared: AppDelegate?

    private var controllers: [EditorWindowController] = []
    private var lastCascade: NSPoint?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.mainMenu = MainMenuBuilder.build()
        if controllers.isEmpty {
            newWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 窗口

    @objc func newWindow(_ sender: Any?) {
        openInNewWindow(url: nil)
    }

    func openInNewWindow(url: URL?) {
        let controller = EditorWindowController()
        controller.onWindowClosed = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)

        if let window = controller.window {
            if let last = lastCascade {
                lastCascade = window.cascadeTopLeft(from: last)
            } else {
                window.center()
                if let screen = window.screen ?? NSScreen.main {
                    lastCascade = NSPoint(x: max(40, window.frame.minX + 28),
                                          y: min(screen.frame.maxY - 40, window.frame.maxY))
                }
            }
            window.makeKeyAndOrderFront(nil)
        }
        if let url {
            controller.open(url: url)
        } else {
            controller.focusTextView()
        }
    }

    /// 供拖拽 / 菜单调用：在新窗口打开文件
    @objc func openFileInNewWindow(_ sender: Any?) {
        guard let url = sender as? URL else { return }
        openInNewWindow(url: url)
    }

    // MARK: 文件打开

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let empty = controllers.first(where: {
                $0.textDocument.fileURL == nil && !$0.textDocument.isModified && $0.window?.isVisible == true
            }) {
                empty.open(url: url)
            } else {
                openInNewWindow(url: url)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for controller in controllers {
            guard let window = controller.window, window.isVisible else { continue }
            window.performClose(nil)
            if window.isVisible {
                return .terminateCancel
            }
        }
        return .terminateNow
    }

    // MARK: 菜单动作

    @objc func showAbout(_ sender: Any?) {
        Dialogs.about(version: AppInfo.version)
    }

    @objc func showShortcuts(_ sender: Any?) {
        Dialogs.shortcuts()
    }

    @objc func openHelp(_ sender: Any?) {
        guard let url = Bundle.main.url(forResource: "使用说明", withExtension: "html") else {
            Dialogs.shortcuts()
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func setAsDefaultEditor(_ sender: Any?) {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            Dialogs.error(title: "暂时无法设置",
                          message: "请先以 .app 形式安装（运行 build.sh 生成 代码编辑器.app）后再设置默认打开方式。")
            return
        }

        let alert = NSAlert()
        alert.messageText = "将代码编辑器设为默认文本编辑器？"
        alert.informativeText = "系统会把 \(AppInfo.textExtensions.count) 种文本格式（txt、log、ini、csv、md、json 等）的默认打开方式指向本应用。源码格式（.swift/.py/.js 等）只做「可打开」注册，不会抢占 Xcode 等 IDE 的默认地位。"
        alert.addButton(withTitle: "设为默认")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let sampleDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeEditorDefaultSamples", isDirectory: true)
        try? FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)

        var failures: [String] = []
        for ext in AppInfo.textExtensions {
            let sample = sampleDir.appendingPathComponent("sample.\(ext)")
            if !FileManager.default.fileExists(atPath: sample.path) {
                try? Data(" ".utf8).write(to: sample)
            }
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenFileAt: sample)
            let handler = NSWorkspace.shared.urlForApplication(toOpen: sample)
            if handler?.standardizedFileURL != appURL.standardizedFileURL {
                failures.append(ext)
            }
        }

        if failures.isEmpty {
            let done = NSAlert()
            done.messageText = "已设为默认文本编辑器"
            done.informativeText = "双击任意 .txt 文件即可用代码编辑器打开。"
            done.addButton(withTitle: "好")
            done.runModal()
        } else {
            Dialogs.error(title: "部分格式未能设置",
                          message: "以下格式需要手动设置：\(failures.joined(separator: "、"))\n可在「显示简介 → 打开方式」中指定。")
        }
    }
}

// MARK: - 菜单栏

enum MainMenuBuilder {

    private static func item(_ title: String,
                             _ action: Selector?,
                             key: String = "",
                             modifiers: NSEvent.ModifierFlags = .command,
                             tag: Int = 0) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty {
            menuItem.keyEquivalentModifierMask = modifiers
        }
        menuItem.tag = tag
        return menuItem
    }


    static func build() -> NSMenu {
        let mainMenu = NSMenu()

        // 应用菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: AppInfo.name)
        appMenu.addItem(item("关于\(AppInfo.name)", #selector(AppDelegate.showAbout(_:))))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(item("设为默认文本编辑器…", #selector(AppDelegate.setAsDefaultEditor(_:))))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(item("隐藏\(AppInfo.name)", #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(item("隐藏其他", #selector(NSApplication.hideOtherApplications(_:)),
                             key: "h", modifiers: [.command, .option]))
        appMenu.addItem(item("显示全部", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(item("退出\(AppInfo.name)", #selector(NSApplication.terminate(_:)), key: "q"))
        appMenuItem.submenu = appMenu

        // 文件
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(item("新建(N)", #selector(EditorWindowController.newDocument(_:)), key: "n"))
        fileMenu.addItem(item("新窗口(W)", #selector(AppDelegate.newWindow(_:)), key: "n",
                              modifiers: [.command, .shift]))
        fileMenu.addItem(item("打开(O)…", #selector(EditorWindowController.openDocument(_:)), key: "o"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(item("保存(S)", #selector(EditorWindowController.saveDocument(_:)), key: "s"))
        fileMenu.addItem(item("另存为(A)…", #selector(EditorWindowController.saveDocumentAs(_:)),
                              key: "s", modifiers: [.command, .shift]))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(item("页面设置(U)…", #selector(EditorWindowController.pageSetup(_:)),
                              key: "p", modifiers: [.command, .shift]))
        fileMenu.addItem(item("打印(P)…", #selector(EditorWindowController.printDocument(_:)), key: "p"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(item("关闭窗口(W)", #selector(NSWindow.performClose(_:)), key: "w"))
        fileMenu.addItem(item("退出(X)", #selector(NSApplication.terminate(_:)), key: "q"))
        fileMenuItem.submenu = fileMenu

        // 编辑
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(item("撤消(U)", Selector(("undo:")), key: "z"))
        editMenu.addItem(item("重做(R)", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(item("剪切(T)", #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(item("复制(C)", #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(item("粘贴(P)", #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(item("删除(L)", #selector(EditorWindowController.deleteSelection(_:))))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(item("查找(F)…", #selector(EditorWindowController.showFind(_:)), key: "f"))
        editMenu.addItem(item("查找下一个(N)", #selector(EditorWindowController.findNextMenuItem(_:)), key: "g"))
        editMenu.addItem(item("查找上一个(V)", #selector(EditorWindowController.findPreviousMenuItem(_:)),
                              key: "g", modifiers: [.command, .shift]))
        editMenu.addItem(item("替换(R)…", #selector(EditorWindowController.showReplace(_:)),
                              key: "f", modifiers: [.command, .option]))
        editMenu.addItem(item("转到行(G)…", #selector(EditorWindowController.goToLine(_:)), key: "l"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(item("全选(A)", #selector(NSText.selectAll(_:)), key: "a"))
        editMenu.addItem(item("时间/日期(D)", #selector(EditorWindowController.insertTimeDate(_:)),
                              key: "\u{F708}", modifiers: []))
        editMenuItem.submenu = editMenu

        // 代码
        let codeMenuItem = NSMenuItem()
        mainMenu.addItem(codeMenuItem)
        let codeMenu = NSMenu(title: "代码")
        codeMenu.addItem(item("注释/取消注释(/)", #selector(EditorWindowController.toggleCommentAction(_:)),
                              key: "/"))
        codeMenu.addItem(NSMenuItem.separator())
        codeMenu.addItem(item("复制当前行(D)", #selector(EditorWindowController.duplicateLineAction(_:)),
                              key: "d", modifiers: [.command, .shift]))
        codeMenu.addItem(item("删除当前行(K)", #selector(EditorWindowController.deleteLineAction(_:)),
                              key: "k", modifiers: [.command, .shift]))
        codeMenu.addItem(item("上移行(U)", #selector(EditorWindowController.moveLineUpAction(_:)),
                              key: "\u{F700}", modifiers: [.option]))
        codeMenu.addItem(item("下移行(D)", #selector(EditorWindowController.moveLineDownAction(_:)),
                              key: "\u{F701}", modifiers: [.option]))
        codeMenu.addItem(NSMenuItem.separator())
        codeMenu.addItem(item("增加缩进(])", #selector(EditorWindowController.indentMoreAction(_:)), key: "]"))
        codeMenu.addItem(item("减少缩进([)", #selector(EditorWindowController.indentLessAction(_:)), key: "["))

        // 语言
        let languageItem = NSMenuItem(title: "语言", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: "语言")
        languageMenu.addItem(item("按扩展名自动检测", #selector(EditorWindowController.detectLanguageAction(_:)),
                                  key: "", modifiers: [], tag: -1))
        languageMenu.addItem(NSMenuItem.separator())
        for (index, language) in Language.all.enumerated() {
            languageMenu.addItem(item(language.displayName,
                                      #selector(EditorWindowController.changeLanguageFromMenu(_:)),
                                      tag: index))
        }
        languageItem.submenu = languageMenu
        codeMenu.addItem(languageItem)

        // 主题
        let themeItem = NSMenuItem(title: "主题", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "主题")
        themeMenu.addItem(item("跟随系统", #selector(EditorWindowController.useSystemTheme(_:))))
        themeMenu.addItem(NSMenuItem.separator())
        for (index, theme) in EditorTheme.all.enumerated() {
            themeMenu.addItem(item(theme.name, #selector(EditorWindowController.changeThemeFromMenu(_:)),
                                   tag: index))
        }
        themeItem.submenu = themeMenu
        codeMenu.addItem(themeItem)

        codeMenu.addItem(NSMenuItem.separator())
        codeMenu.addItem(item("显示行号", #selector(EditorWindowController.toggleLineNumbers(_:))))
        codeMenu.addItem(item("缩进参考线", #selector(EditorWindowController.toggleIndentGuides(_:))))
        codeMenu.addItem(item("当前行高亮", #selector(EditorWindowController.toggleCurrentLineHighlight(_:))))
        codeMenu.addItem(item("括号匹配", #selector(EditorWindowController.toggleBracketMatching(_:))))
        codeMenu.addItem(NSMenuItem.separator())
        codeMenu.addItem(item("自动缩进", #selector(EditorWindowController.toggleAutoIndent(_:))))
        codeMenu.addItem(item("自动补全括号", #selector(EditorWindowController.toggleAutoClose(_:))))
        codeMenu.addItem(item("自动换行", #selector(EditorWindowController.toggleWordWrapAction(_:))))

        let indentItem = NSMenuItem(title: "缩进", action: nil, keyEquivalent: "")
        let indentMenu = NSMenu(title: "缩进")
        indentMenu.addItem(item("2 个空格", #selector(EditorWindowController.setIndentWidth2(_:))))
        indentMenu.addItem(item("4 个空格", #selector(EditorWindowController.setIndentWidth4(_:))))
        indentMenu.addItem(item("8 个空格", #selector(EditorWindowController.setIndentWidth8(_:))))
        indentMenu.addItem(NSMenuItem.separator())
        indentMenu.addItem(item("使用制表符", #selector(EditorWindowController.toggleSoftTabs(_:))))
        indentItem.submenu = indentMenu
        codeMenu.addItem(indentItem)
        codeMenuItem.submenu = codeMenu

        // 格式
        let formatMenuItem = NSMenuItem()
        mainMenu.addItem(formatMenuItem)
        let formatMenu = NSMenu(title: "格式")
        formatMenu.addItem(item("自动换行(W)", #selector(EditorWindowController.toggleWordWrap(_:))))
        formatMenu.addItem(item("字体(F)…", #selector(EditorWindowController.showFontPanel(_:))))
        formatMenuItem.submenu = formatMenu

        // 查看
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "查看")
        let zoomItem = NSMenuItem(title: "缩放(Z)", action: nil, keyEquivalent: "")
        let zoomMenu = NSMenu(title: "缩放")
        zoomMenu.addItem(item("放大(I)", #selector(EditorWindowController.zoomIn(_:)), key: "="))
        zoomMenu.addItem(item("缩小(O)", #selector(EditorWindowController.zoomOut(_:)), key: "-"))
        zoomMenu.addItem(item("恢复默认缩放(R)", #selector(EditorWindowController.zoomReset(_:)), key: "0"))
        zoomItem.submenu = zoomMenu
        viewMenu.addItem(zoomItem)
        viewMenu.addItem(item("显示行号(L)", #selector(EditorWindowController.toggleLineNumbers(_:))))
        viewMenu.addItem(item("状态栏(S)", #selector(EditorWindowController.toggleStatusBar(_:))))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(item("进入全屏(F)", #selector(NSWindow.toggleFullScreen(_:)),
                              key: "f", modifiers: [.command, .control]))
        viewMenuItem.submenu = viewMenu

        // 帮助
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "帮助")
        helpMenu.addItem(item("查看帮助(H)", #selector(AppDelegate.openHelp(_:))))
        helpMenu.addItem(item("键盘快捷键(K)", #selector(AppDelegate.showShortcuts(_:))))
        helpMenu.addItem(NSMenuItem.separator())
        helpMenu.addItem(item("关于\(AppInfo.name)(A)", #selector(AppDelegate.showAbout(_:))))
        helpMenuItem.submenu = helpMenu

        return mainMenu
    }
}
