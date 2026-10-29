# 代码编辑器（Code Editor for macOS）

原生 **Swift + AppKit** 实现的轻量代码编辑器：在 1:1 复刻 Windows 记事本全部能力的基础上，
新增语法高亮、行号栏、智能缩进与主题系统。启动快、打字跟手，10 MB 文件打开约 0.15 s。

- 平台：macOS 12.0+（Universal，Apple Silicon 与 Intel 原生）
- 许可：[MIT](LICENSE)
- 语言：Swift 5 / AppKit（无第三方依赖，无 WebView）

## 下载与安装

从仓库的 **Releases** 页面下载 `代码编辑器-2.0.0-macOS-universal.zip`（或 `.dmg`）：

```bash
# 方式一：zip
unzip 代码编辑器-2.0.0-macOS-universal.zip
mv 代码编辑器.app /Applications/

# 方式二：dmg
open 代码编辑器-2.0.0-macOS-universal.dmg
# 然后把「代码编辑器」拖进 Applications
```

应用为 ad-hoc 签名，首次打开若被 Gatekeeper 拦截，可在
「系统设置 → 隐私与安全性」点击「仍要打开」，或执行：

```bash
xattr -cr /Applications/代码编辑器.app
```

## 从源码构建

```bash
# 调试版（本机架构）
./build.sh
# 产物：build/代码编辑器.app

# Release 版（universal x86_64 + arm64，strip 后打包 zip / dmg）
./build_release.sh
# 产物：dist/代码编辑器-2.0.0-macOS-universal.{zip,dmg}
open "build/代码编辑器.app"
```

构建脚本自动完成：编译（Xcode 工具链）→ 组装 .app → 生成图标（CoreGraphics 绘制 + iconutil）
→ ad-hoc 签名 → 注册到 LaunchServices。`build_release.sh` 额外做双架构合并、符号裁剪与打包。

> 注意：本机 `xcode-select` 指向 CommandLineTools，其 Swift 头文件存在
> `SwiftBridging` modulemap 重复定义问题，构建脚本会自动改用
> `/Applications/Xcode.app` 内置工具链。

## 代码编辑能力（v2.0）

| 能力 | 说明 |
| --- | --- |
| 语法高亮 | 29 种语言：Swift / ObjC / C / C++ / C# / Java / Kotlin / Python / JS / TS / Go / Rust / Ruby / PHP / Shell / PowerShell / SQL / Lua / HTML / XML / CSS / SCSS / JSON / YAML / TOML / Markdown / Dockerfile / Makefile / 纯文本；按扩展名自动识别，状态栏可手动切换 |
| 行号栏 | 自绘 NSRulerView，当前行加亮，厚度随行数自适应 |
| 当前行 / 缩进参考线 / 括号匹配 | 全部走布局管理器临时属性，不污染文档、不进撤销栈 |
| 智能缩进 | 回车继承缩进，括号内回车自动加深一层并补全闭合括号 |
| 自动配对 | 括号/引号自动补全、选中包裹、跳过右半、成对删除；中文输入法（marked text）自动避让 |
| 代码操作 | ⌘/ 注释切换 · ⇧⌘D 复制行 · ⇧⌘K 删除行 · ⌥↑/⌥↓ 移动行 · ⌘]/⌘[ 缩进（均支持多行选区） |
| 缩进设置 | 空格 2/4/8 或制表符，Tab 宽度即段落 tabInterval，状态栏可切 |
| 主题 | 跟随系统 / Xcode 浅色 / Xcode 深色 / Monokai / Solarized 浅色 / GitHub 深色 |
| 偏好持久化 | 主题、缩进、行号、自动缩进、字体、缩放等全部写入 UserDefaults |

### 高亮实现要点（性能设计）

- **不用 NSRegularExpression**：一次 UTF-16 缓冲扫描，O(n)；1 MB Swift 约 0.29 s（仅打开时一次）。
- **增量着色**：token 列表做公共前缀/后缀 diff，打字时只对差异区间增删临时属性，
  开销与改动量成正比；多次按键在 RunLoop 上合并。
- **降级策略**：超过 2 MB 的文件自动关闭着色（行号与编辑不受影响）。

## 继承自记事本的能力

| 功能 | 状态 |
| --- | --- |
| 文件：新建 / 新窗口 / 打开 / 保存 / 另存为 / 页面设置 / 打印 | ✅ |
| 编辑：撤消 / 重做 / 剪切 / 复制 / 粘贴 / 删除 / 查找 / 替换 / 转到行 / F5 时间日期 | ✅ |
| 查看：缩放 10%–500%（⌘+滚轮 / 菜单 / 状态栏滑块）/ 状态栏开关 / 全屏 | ✅ |
| 状态栏：行·列 + 语言 + 缩进 + 行尾 + 编码 + 缩放，可点击切换 | ✅ |
| 编码：UTF-8 / UTF-8 BOM / UTF-16 LE·BE（含无 BOM 启发式识别）/ ANSI(GB18030) | ✅ |
| 行尾：Windows (CRLF) / Unix (LF) / Macintosh (CR)，另存为时可转换 | ✅ |
| 未保存三键提示、拖拽打开、多窗口级联、字体对话框 | ✅ |
| 文件关联：文本格式 Owner + 源码格式 Alternate（不抢占 IDE），「设为默认文本编辑器…」菜单只接管文本格式 | ✅ |

差异说明：Windows 的「ANSI」在中文系统上是代码页 936（GBK）；本实现使用其超集
GB18030，能无损保存全部 Unicode 字符（含 emoji），向后兼容 GBK 文件。

## 自检

```bash
# 语法引擎自检（49 项：多语言 token 正确性、语言识别、主题解析、性能基线）
mkdir -p /tmp/syntaxtest && cp Sources/Syntax.swift Tools/SyntaxTest.swift /tmp/syntaxtest/
mv /tmp/syntaxtest/SyntaxTest.swift /tmp/syntaxtest/main.swift
swiftc -O /tmp/syntaxtest/main.swift /tmp/syntaxtest/Syntax.swift -o /tmp/st && /tmp/st

# 数据层自检（20 项：编码往返、行尾识别、LineIndex 随机编辑对拍、性能基线）
mkdir -p /tmp/nptest && cp Sources/Document.swift Tools/SelfTest.swift /tmp/nptest/
mv /tmp/nptest/SelfTest.swift /tmp/nptest/main.swift
swiftc -O /tmp/nptest/main.swift /tmp/nptest/Document.swift -o /tmp/st2 && /tmp/st2
```

## 目录结构

```
Notepad/
├── Sources/
│   ├── main.swift                   # 进程入口
│   ├── App.swift                    # AppDelegate + 菜单栏（含「代码」菜单）+ 默认编辑器设置
│   ├── EditorWindowController.swift # 窗口、主题/语言/高亮调度、查找替换、菜单动作
│   ├── CodeTextView.swift           # 编辑视图（智能缩进/自动配对/括号匹配）+ 行号栏
│   ├── Syntax.swift                 # 语言定义、单遍词法扫描器、主题色板
│   ├── Document.swift               # 编码/行尾识别、文件读写、行号索引
│   └── Components.swift             # 状态栏、查找栏、字体对话框、通用对话框
├── Resources/
│   ├── Info.plist                   # 文件关联（文本 Owner + 源码 Alternate）
│   └── 使用说明.html                 # 帮助菜单内容
├── Tools/
│   ├── makeicon.swift               # 图标绘制
│   ├── SelfTest.swift               # 数据层自检（20 项）
│   └── SyntaxTest.swift             # 语法引擎自检（49 项）
├── build.sh                         # 调试版构建
├── build_release.sh                 # Release 构建（universal + zip/dmg）
├── LICENSE                          # MIT
└── .gitignore
```

## 贡献

欢迎 Issue 与 Pull Request。提交前请确保 `./build.sh` 可编译通过，并视情况运行自检脚本。
代码遵循 MIT 许可，你可以自由地复制、修改与再发布。

## 许可证

[MIT License](LICENSE) © 2026 代码编辑器 contributors
