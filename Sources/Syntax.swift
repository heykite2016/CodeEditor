//
//  Syntax.swift
//  代码编辑器 —— 语言定义 / 单遍词法扫描 / 主题色板
//
//  设计要点：
//  · 不用 NSRegularExpression（每行多次匹配、回溯、对象开销大），
//    改为一次 UTF-16 缓冲扫描，O(n) 且常数很小；10 万字符通常在 5ms 以内。
//  · 输出「非默认色」的 token 列表，渲染层只对差异区间做临时属性更新，
//    打字时属性更新量与改动量成正比，而不是与文件大小成正比。
//

import AppKit

// MARK: - Token

enum TokenKind {
    case keyword
    case type
    case string
    case comment
    case number
    case function
    case constant
    case attribute
    case tag
    case attributeName
    case key
    case heading
    case link
    case emphasis
}

struct SyntaxToken {
    let range: NSRange
    let kind: TokenKind
}

// MARK: - 语言定义

struct Language {

    enum Flavor {
        case plain        // 纯文本
        case generic      // C 系 / 脚本类通用扫描
        case markdown
        case html         // HTML / XML
        case css
        case json
        case yaml
        case ini
    }

    let id: String
    let displayName: String
    let extensions: [String]
    let fileNames: [String]
    let keywords: Set<String>
    let types: Set<String>
    let constants: Set<String>
    /// func / def / function 之类的声明关键字：其后的标识符按函数名着色
    let funcDeclarationKeywords: Set<String>
    /// class / struct / interface 之类的声明关键字：其后的标识符按类型名着色
    let typeDeclarationKeywords: Set<String>
    let lineComments: [String]
    let blockComments: [(open: String, close: String)]
    let quotes: String
    let tripleQuotes: Bool
    let caseInsensitive: Bool
    let flavor: Flavor

    // 预编译成 UTF-16 序列，扫描时直接比对 code unit
    let lineCommentSequences: [[unichar]]
    let blockCommentPairs: [(open: [unichar], close: [unichar])]
    let quoteSet: Set<unichar>

    init(id: String,
         name: String,
         ext: [String] = [],
         fileNames: [String] = [],
         keywords: Set<String> = [],
         types: Set<String> = [],
         constants: Set<String> = [],
         funcDecl: Set<String> = [],
         typeDecl: Set<String> = [],
         lineComments: [String] = [],
         blockComments: [(String, String)] = [],
         quotes: String = "\"'",
         tripleQuotes: Bool = false,
         caseInsensitive: Bool = false,
         flavor: Flavor = .generic) {
        self.id = id
        self.displayName = name
        self.extensions = ext
        self.fileNames = fileNames
        self.keywords = keywords
        self.types = types
        self.constants = constants
        self.funcDeclarationKeywords = funcDecl
        self.typeDeclarationKeywords = typeDecl
        self.lineComments = lineComments
        self.blockComments = blockComments.map { (open: $0.0, close: $0.1) }
        self.quotes = quotes
        self.tripleQuotes = tripleQuotes
        self.caseInsensitive = caseInsensitive
        self.flavor = flavor
        self.lineCommentSequences = lineComments.map { Array($0.utf16) }
        self.blockCommentPairs = blockComments.map { (Array($0.0.utf16), Array($0.1.utf16)) }
        self.quoteSet = Set(quotes.utf16)
    }
}

private func words(_ text: String) -> Set<String> {
    Set(text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init))
}

extension Language {

    static let plain = Language(id: "plain", name: "纯文本", ext: ["txt", "log", "text", "srt"],
                                flavor: .plain)

    static let swift = Language(
        id: "swift", name: "Swift", ext: ["swift"],
        keywords: words("""
        associatedtype class deinit enum extension fileprivate func import init inout internal let open operator \
        private precedencegroup protocol public rethrows static struct subscript typealias var break case catch \
        continue default defer do else fallthrough for guard if in repeat return throw switch where while as any \
        await async actor some nonisolated isolated consuming borrowing throws try yield does not support
        """),
        types: words("Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Double Float Float80 Bool String Character Void Any AnyObject"),
        constants: words("true false nil self super"),
        funcDecl: words("func init deinit subscript"),
        typeDecl: words("class struct enum protocol extension typealias associatedtype actor"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'", tripleQuotes: true)

    static let c = Language(
        id: "c", name: "C", ext: ["c", "h"],
        keywords: words("""
        auto break case char const continue default do double else enum extern float for goto if inline int long \
        register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while \
        _Bool _Complex _Atomic
        """),
        types: words("size_t ssize_t ptrdiff_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t FILE"),
        constants: words("NULL true false TRUE FALSE"),
        typeDecl: words("struct enum union typedef"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'")

    static let cpp = Language(
        id: "cpp", name: "C++", ext: ["cpp", "cc", "cxx", "hpp", "hh", "hxx", "ipp", "tpp"],
        keywords: words("""
        alignas alignof and and_eq asm bitand bitor bool break case catch char char16_t char32_t class compl const \
        constexpr const_cast continue decltype default delete do double dynamic_cast else enum explicit export extern \
        false float for friend goto if inline int long mutable namespace new noexcept not not_eq nullptr operator or \
        or_eq private protected public register reinterpret_cast return short signed sizeof static static_assert \
        static_cast struct switch template this thread_local throw true try typedef typeid typename union unsigned \
        using virtual void volatile wchar_t while override final consteval constinit concept requires co_await \
        co_return co_yield auto
        """),
        types: words("size_t std string wstring vector map set unordered_map unordered_set shared_ptr unique_ptr optional"),
        constants: words("nullptr true false NULL"),
        typeDecl: words("class struct enum union namespace using typedef template concept"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'")

    static let objc = Language(
        id: "objc", name: "Objective-C", ext: ["m", "mm"],
        keywords: words("""
        auto break case char const continue default do double else enum extern float for goto if inline int long \
        register return short signed sizeof static struct switch typedef union unsigned void volatile while \
        @interface @implementation @end @protocol @property @synthesize @dynamic @selector @encode @try @catch \
        @finally @throw @autoreleasepool @synchronized @optional @required @public @private @protected @package \
        self super nil YES NO in out inout bycopy byref oneway
        """),
        types: words("id instancetype BOOL NSInteger NSUInteger CGFloat NSString NSArray NSDictionary NSObject NSError NSURL UIView"),
        constants: words("nil Nil NULL YES NO"),
        typeDecl: words("@interface @implementation @protocol @property"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'")

    static let csharp = Language(
        id: "csharp", name: "C#", ext: ["cs"],
        keywords: words("""
        abstract as base bool break byte case catch char checked class const continue decimal default delegate do \
        double else enum event explicit extern false finally fixed float for foreach goto if implicit in int \
        interface internal is lock long namespace new null object operator out override params private protected \
        public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true \
        try typeof uint ulong unchecked unsafe ushort using virtual void volatile while async await var record init
        """),
        types: words("String Int32 Int64 Boolean Double Decimal Object List Dictionary Task IEnumerable"),
        constants: words("true false null"),
        typeDecl: words("class struct interface enum namespace record"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'")

    static let java = Language(
        id: "java", name: "Java", ext: ["java"],
        keywords: words("""
        abstract assert boolean break byte case catch char class const continue default do double else enum extends \
        final finally float for goto if implements import instanceof int interface long native new package private \
        protected public return short static strictfp super switch synchronized this throw throws transient try void \
        volatile while var record sealed permits yield non-sealed
        """),
        types: words("String Integer Long Double Float Boolean Object List Map Set ArrayList HashMap"),
        constants: words("true false null"),
        typeDecl: words("class interface enum record"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'", tripleQuotes: true)

    static let kotlin = Language(
        id: "kotlin", name: "Kotlin", ext: ["kt", "kts"],
        keywords: words("""
        as break class continue do else false for fun if in interface is null object package return super this throw \
        true try typealias typeof val var when while by catch constructor delegate dynamic field file finally get \
        import init param property receiver set setparam where actual abstract annotation companion const crossinline \
        data enum expect external final infix inline inner internal lateinit noinline open operator out override \
        private protected public reified sealed suspend tailrec vararg
        """),
        types: words("Int Long Double Float Boolean String Char Any Unit List Map Set Array"),
        constants: words("true false null"),
        funcDecl: words("fun"),
        typeDecl: words("class interface object enum data sealed companion"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'", tripleQuotes: true)

    static let python = Language(
        id: "python", name: "Python", ext: ["py", "pyw", "pyi", "pyx"],
        keywords: words("""
        and as assert async await break class continue def del elif else except finally for from global if import in \
        is lambda nonlocal not or pass raise return try while with yield match case
        """),
        types: words("int float str bool list dict set tuple bytes object type Exception ValueError TypeError"),
        constants: words("True False None NotImplemented Ellipsis self cls"),
        funcDecl: words("def"),
        typeDecl: words("class"),
        lineComments: ["#"], blockComments: [],
        quotes: "\"'", tripleQuotes: true)

    static let javascript = Language(
        id: "javascript", name: "JavaScript", ext: ["js", "mjs", "cjs", "jsx"],
        keywords: words("""
        break case catch class const continue debugger default delete do else export extends finally for function if \
        import in instanceof let new return super switch this throw try typeof var void while with yield async await \
        of static get set from as
        """),
        types: words("Array Object String Number Boolean Function Promise Map Set Date RegExp JSON Math Error"),
        constants: words("true false null undefined NaN Infinity"),
        funcDecl: words("function"),
        typeDecl: words("class"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'`", tripleQuotes: false)

    static let typescript = Language(
        id: "typescript", name: "TypeScript", ext: ["ts", "tsx", "mts", "cts"],
        keywords: words("""
        break case catch class const continue debugger default delete do else export extends finally for function if \
        import in instanceof let new return super switch this throw try typeof var void while with yield async await \
        of static get set from as interface type enum namespace declare abstract implements private protected public \
        readonly keyof infer never unknown any satisfies asserts is override
        """),
        types: words("Array Object String Number Boolean Function Promise Map Set Date RegExp JSON Math Error Record Partial Readonly"),
        constants: words("true false null undefined NaN Infinity"),
        funcDecl: words("function"),
        typeDecl: words("class interface type enum namespace"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'`")

    static let go = Language(
        id: "go", name: "Go", ext: ["go"],
        keywords: words("""
        break case chan const continue default defer else fallthrough for func go goto if import interface map \
        package range return select struct switch type var nil
        """),
        types: words("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr"),
        constants: words("true false nil iota"),
        funcDecl: words("func"),
        typeDecl: words("type struct interface"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'`")

    static let rust = Language(
        id: "rust", name: "Rust", ext: ["rs"],
        keywords: words("""
        as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod \
        move mut pub ref return self Self static struct super trait true type unsafe use where while yield
        """),
        types: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box"),
        constants: words("true false None Some Ok Err"),
        funcDecl: words("fn"),
        typeDecl: words("struct enum trait impl type mod"),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'")

    static let ruby = Language(
        id: "ruby", name: "Ruby", ext: ["rb", "rake", "gemspec"],
        keywords: words("""
        alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or \
        redo rescue retry return self super then true undef unless until when while yield require require_relative \
        include extend attr_accessor attr_reader attr_writer
        """),
        types: words("String Integer Float Array Hash Symbol Proc Range"),
        constants: words("true false nil"),
        funcDecl: words("def"),
        typeDecl: words("class module"),
        lineComments: ["#"], blockComments: [],
        quotes: "\"'", tripleQuotes: false)

    static let php = Language(
        id: "php", name: "PHP", ext: ["php", "phtml"],
        keywords: words("""
        abstract and array as break callable case catch class clone const continue declare default die do echo else \
        elseif empty enddeclare endfor endforeach endif endswitch endwhile eval exit extends final finally fn for \
        foreach function global goto if implements include include_once instanceof insteadof interface isset list \
        match namespace new or print private protected public readonly require require_once return static switch \
        throw trait try unset use var while xor yield
        """),
        types: words("int float string bool array object mixed void iterable"),
        constants: words("true false null TRUE FALSE NULL"),
        funcDecl: words("function fn"),
        typeDecl: words("class interface trait"),
        lineComments: ["//", "#"], blockComments: [("/*", "*/")],
        quotes: "\"'")

    static let shell = Language(
        id: "shell", name: "Shell", ext: ["sh", "bash", "zsh", "fish", "command", "env"],
        keywords: words("""
        if then else elif fi for while until do done case esac function return in select time local export readonly \
        declare typeset unset shift source alias unalias echo printf read cd pwd exit break continue test eval exec \
        trap set
        """),
        types: words("true false"),
        constants: words("true false"),
        funcDecl: words("function"),
        lineComments: ["#"], blockComments: [],
        quotes: "\"'`")

    static let powershell = Language(
        id: "powershell", name: "PowerShell", ext: ["ps1", "psm1", "psd1"],
        keywords: words("""
        begin break catch class continue data define do dynamicparam else elseif end enum exit filter finally for \
        foreach from function if in inlineScript param process return switch throw trap try until using var while \
        workflow
        """),
        types: words("string int bool array hashtable object"),
        constants: words("true false null $null"),
        funcDecl: words("function filter"),
        lineComments: ["#"], blockComments: [("<#", "#>")],
        quotes: "\"'", caseInsensitive: true)

    static let sql = Language(
        id: "sql", name: "SQL", ext: ["sql", "ddl", "dml"],
        keywords: words("""
        select from where insert into values update set delete create table alter drop index view join left right \
        inner outer full cross on group by order having limit offset union all distinct as and or not null is in \
        like between exists case when then else end primary key foreign references default unique constraint \
        cascade transaction commit rollback begin grant revoke
        """),
        types: words("int integer bigint smallint varchar char text date datetime timestamp decimal numeric float double boolean blob"),
        constants: words("null true false"),
        lineComments: ["--"], blockComments: [("/*", "*/")],
        quotes: "\"'", caseInsensitive: true)

    static let lua = Language(
        id: "lua", name: "Lua", ext: ["lua"],
        keywords: words("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"),
        types: words("string number boolean table function thread userdata"),
        constants: words("true false nil"),
        funcDecl: words("function"),
        lineComments: ["--"], blockComments: [("--[[", "]]")],
        quotes: "\"'")

    static let html = Language(
        id: "html", name: "HTML", ext: ["html", "htm", "xhtml", "vue", "svelte", "ejs", "hbs"],
        keywords: words("html head body div span a p ul ol li table tr td th script style link meta title h1 h2 h3 h4 h5 h6 form input button select option textarea img section header footer nav main article aside canvas svg video audio source iframe label"),
        lineComments: [], blockComments: [("<!--", "-->")],
        quotes: "\"'", flavor: .html)

    static let xml = Language(
        id: "xml", name: "XML", ext: ["xml", "plist", "svg", "xib", "storyboard", "xsd", "xsl", "xslt", "rss"],
        lineComments: [], blockComments: [("<!--", "-->")],
        quotes: "\"'", flavor: .html)

    static let css = Language(
        id: "css", name: "CSS", ext: ["css"],
        keywords: words("""
        color background background-color display position margin padding border font width height min-width max-width \
        min-height max-height flex grid align-items justify-content gap top left right bottom overflow z-index \
        transform transition animation opacity border-radius box-shadow cursor content visibility
        """),
        lineComments: [], blockComments: [("/*", "*/")],
        quotes: "\"'", flavor: .css)

    static let scss = Language(
        id: "scss", name: "SCSS / Less", ext: ["scss", "sass", "less"],
        keywords: words("""
        color background display position margin padding border font width height flex grid align-items justify-content \
        gap top left right bottom overflow z-index transform transition animation opacity mixin include extend import \
        use forward
        """),
        lineComments: ["//"], blockComments: [("/*", "*/")],
        quotes: "\"'", flavor: .css)

    static let json = Language(
        id: "json", name: "JSON", ext: ["json", "jsonc", "geojson", "webmanifest"],
        keywords: words("true false null"),
        constants: words("true false null"),
        quotes: "\"", flavor: .json)

    static let yaml = Language(
        id: "yaml", name: "YAML", ext: ["yml", "yaml"],
        constants: words("true false null yes no on off"),
        lineComments: ["#"], quotes: "\"'", flavor: .yaml)

    static let toml = Language(
        id: "toml", name: "TOML / INI", ext: ["toml", "ini", "inf", "cfg", "conf", "properties", "editorconfig", "env"],
        lineComments: ["#", ";"], quotes: "\"'", flavor: .ini)

    static let markdown = Language(
        id: "markdown", name: "Markdown", ext: ["md", "markdown", "mdown", "mkd"],
        lineComments: [], quotes: "", flavor: .markdown)

    static let dockerfile = Language(
        id: "dockerfile", name: "Dockerfile", ext: ["dockerfile"], fileNames: ["dockerfile", "containerfile"],
        keywords: words("FROM RUN CMD LABEL MAINTAINER EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL"),
        lineComments: ["#"], quotes: "\"'", caseInsensitive: true)

    static let makefile = Language(
        id: "makefile", name: "Makefile", ext: ["mk", "make"], fileNames: ["makefile", "gnumakefile"],
        keywords: words("ifeq ifneq ifdef ifndef else endif include export define endef override"),
        lineComments: ["#"], quotes: "\"'")

    static let all: [Language] = [
        plain, swift, objc, c, cpp, csharp, java, kotlin, python, javascript, typescript,
        go, rust, ruby, php, shell, powershell, sql, lua,
        html, xml, css, scss, json, yaml, toml, markdown, dockerfile, makefile,
    ]

    static func language(id: String) -> Language {
        all.first { $0.id == id } ?? plain
    }

    static func detect(fileName: String?) -> Language {
        guard let fileName = fileName, !fileName.isEmpty else { return plain }
        let lower = fileName.lowercased()
        if let exact = all.first(where: { $0.fileNames.contains(lower) }) { return exact }
        let ext = (lower as NSString).pathExtension
        guard !ext.isEmpty else { return plain }
        return all.first { $0.extensions.contains(ext) } ?? plain
    }
}

// MARK: - 词法扫描

final class SyntaxHighlighter {

    /// 超过该长度不再做整篇高亮（保持纯文本，行号/编辑依旧流畅）
    static let maxHighlightLength = 2_000_000

    func tokenize(_ text: NSString, language: Language) -> [SyntaxToken] {
        let length = text.length
        guard length > 0, language.flavor != .plain else { return [] }
        var chars = [unichar](repeating: 0, count: length)
        chars.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            text.getCharacters(base, range: NSRange(location: 0, length: length))
        }
        switch language.flavor {
        case .plain:    return []
        case .markdown: return scanMarkdown(chars)
        case .html:     return scanHTML(chars)
        case .css:      return scanCSS(chars, language: language)
        case .json:     return scanJSON(chars, language: language)
        case .yaml:     return scanYAML(chars, language: language)
        case .ini:      return scanINI(chars, language: language)
        case .generic:  return scanGeneric(chars, language: language)
        }
    }

    // MARK: 通用扫描（C 系 / 脚本语言）

    private func scanGeneric(_ chars: [unichar], language: Language) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        tokens.reserveCapacity(chars.count / 12)
        let n = chars.count
        var i = 0
        var pendingTypeName = false
        var pendingFuncName = false
        var lineHasCode = false

        while i < n {
            let c = chars[i]

            if c == 10 {
                lineHasCode = false
                i += 1
                continue
            }
            if c == 32 || c == 9 || c == 13 {
                i += 1
                continue
            }

            // 行注释
            var matchedComment = false
            for seq in language.lineCommentSequences where matches(chars, i, seq, n) {
                let start = i
                while i < n && chars[i] != 10 { i += 1 }
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .comment))
                matchedComment = true
                break
            }
            if matchedComment { continue }

            // 块注释
            var matchedBlock = false
            for pair in language.blockCommentPairs where matches(chars, i, pair.open, n) {
                let start = i
                i += pair.open.count
                while i < n && !matches(chars, i, pair.close, n) { i += 1 }
                if i < n { i += pair.close.count }
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .comment))
                matchedBlock = true
                break
            }
            if matchedBlock { continue }

            // 字符串
            if language.quoteSet.contains(c) {
                let start = i
                var triple = false
                if language.tripleQuotes, i + 2 < n, chars[i + 1] == c, chars[i + 2] == c {
                    triple = true
                    i += 3
                } else {
                    i += 1
                }
                while i < n {
                    let ch = chars[i]
                    if ch == 92 { // 反斜杠转义
                        i += min(2, n - i)
                        continue
                    }
                    if ch == 10 && !triple { break }
                    if ch == c {
                        if triple {
                            if i + 2 < n && chars[i + 1] == c && chars[i + 2] == c {
                                i += 3
                                break
                            }
                            i += 1
                            continue
                        }
                        i += 1
                        break
                    }
                    i += 1
                }
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .string))
                lineHasCode = true
                continue
            }

            // 数字
            if isDigit(c) || (c == 46 && i + 1 < n && isDigit(chars[i + 1])) {
                let start = i
                i = scanNumber(chars, i)
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .number))
                lineHasCode = true
                continue
            }

            // 预处理指令（C 系）
            if c == 35 && !lineHasCode && language.id != "python" && language.id != "shell" {
                let start = i
                i += 1
                while i < n && isIdentPart(chars[i]) { i += 1 }
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .attribute))
                lineHasCode = true
                continue
            }

            // 标识符 / 关键字
            if isIdentStart(c) {
                let start = i
                while i < n && isIdentPart(chars[i]) { i += 1 }
                let word = String(decoding: chars[start..<i], as: UTF16.self)
                let lookup = language.caseInsensitive ? word.lowercased() : word

                var kind: TokenKind?
                if language.keywords.contains(lookup) {
                    kind = .keyword
                } else if language.types.contains(lookup) {
                    kind = .type
                } else if language.constants.contains(lookup) {
                    kind = .constant
                } else if pendingTypeName {
                    kind = .type
                } else if pendingFuncName {
                    kind = .function
                } else if nextNonSpaceChar(chars, i) == 40 { // 后面紧跟 "(" → 函数调用
                    kind = .function
                } else if c >= 65 && c <= 90 && language.id != "sql" {
                    // 大写开头的标识符按类型着色（对标 Xcode 的语义高亮观感）
                    kind = .type
                }
                if let kind {
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: kind))
                }

                pendingTypeName = language.typeDeclarationKeywords.contains(lookup)
                pendingFuncName = language.funcDeclarationKeywords.contains(lookup)
                lineHasCode = true
                continue
            }

            // @ 注解 / 属性
            if c == 64, i + 1 < n, isIdentStart(chars[i + 1]) {
                let start = i
                i += 1
                while i < n && isIdentPart(chars[i]) { i += 1 }
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .attribute))
                lineHasCode = true
                continue
            }

            pendingTypeName = false
            pendingFuncName = false
            lineHasCode = true
            i += 1
        }
        return tokens
    }

    // MARK: Markdown

    private func scanMarkdown(_ chars: [unichar]) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let n = chars.count
        var lineStart = 0
        var inFence = false
        var fenceChar: unichar = 0
        var fenceCount = 0
        var i = 0

        while lineStart < n {
            var lineEnd = lineStart
            while lineEnd < n && chars[lineEnd] != 10 { lineEnd += 1 }
            let lineLength = lineEnd - lineStart

            var indent = 0
            while indent < lineLength && (chars[lineStart + indent] == 32 || chars[lineStart + indent] == 9) { indent += 1 }
            let contentStart = lineStart + indent

            // 围栏代码块
            if contentStart + 2 < lineEnd {
                let c = chars[contentStart]
                if c == 96 || c == 126 {
                    var run = 0
                    while contentStart + run < lineEnd && chars[contentStart + run] == c { run += 1 }
                    if run >= 3 {
                        if !inFence {
                            inFence = true
                            fenceChar = c
                            fenceCount = run
                            tokens.append(SyntaxToken(range: NSRange(location: contentStart, length: min(run, lineLength - indent)), kind: .keyword))
                        } else if c == fenceChar && run >= fenceCount {
                            inFence = false
                            tokens.append(SyntaxToken(range: NSRange(location: contentStart, length: min(run, lineLength - indent)), kind: .keyword))
                        }
                        lineStart = lineEnd + 1
                        continue
                    }
                }
            }

            if inFence {
                if lineLength > 0 {
                    tokens.append(SyntaxToken(range: NSRange(location: lineStart, length: lineLength), kind: .string))
                }
                lineStart = lineEnd + 1
                continue
            }

            // 标题
            if contentStart < lineEnd && chars[contentStart] == 35 {
                var level = 0
                while contentStart + level < lineEnd && chars[contentStart + level] == 35 { level += 1 }
                if level <= 6 && contentStart + level < lineEnd && chars[contentStart + level] == 32 {
                    tokens.append(SyntaxToken(range: NSRange(location: contentStart, length: lineEnd - contentStart), kind: .heading))
                    lineStart = lineEnd + 1
                    continue
                }
            }

            // 引用
            if contentStart < lineEnd && chars[contentStart] == 62 {
                tokens.append(SyntaxToken(range: NSRange(location: contentStart, length: min(2, lineEnd - contentStart)), kind: .keyword))
                i = contentStart + 1
            } else {
                i = lineStart
            }

            // 行内标记：`code`、**bold**、[text](url)
            while i < lineEnd {
                let c = chars[i]
                if c == 96 {
                    var j = i + 1
                    while j < lineEnd && chars[j] != 96 { j += 1 }
                    if j < lineEnd {
                        let end = min(j + 1, lineEnd)
                        tokens.append(SyntaxToken(range: NSRange(location: i, length: end - i), kind: .string))
                        i = end
                        continue
                    }
                }
                if c == 42 || c == 95 { // * 或 _
                    var run = 0
                    while i + run < lineEnd && chars[i + run] == c { run += 1 }
                    var j = i + run
                    var close = -1
                    while j < lineEnd {
                        if chars[j] == c {
                            var cr = 0
                            while j + cr < lineEnd && chars[j + cr] == c { cr += 1 }
                            if cr >= run { close = j + cr; break }
                            j += cr
                        } else {
                            j += 1
                        }
                    }
                    if close > 0 {
                        tokens.append(SyntaxToken(range: NSRange(location: i, length: close - i), kind: .emphasis))
                        i = close
                        continue
                    }
                }
                if c == 91 { // [text](url)
                    var j = i + 1
                    while j < lineEnd && chars[j] != 93 { j += 1 }
                    if j + 1 < lineEnd && chars[j] == 93 && chars[j + 1] == 40 {
                        var k = j + 2
                        while k < lineEnd && chars[k] != 41 { k += 1 }
                        if k < lineEnd {
                            tokens.append(SyntaxToken(range: NSRange(location: i, length: k + 1 - i), kind: .link))
                            i = k + 1
                            continue
                        }
                    }
                }
                i += 1
            }

            // 列表标记
            if contentStart < lineEnd, chars[contentStart] == 45 || chars[contentStart] == 43 || chars[contentStart] == 42 {
                if contentStart + 1 < lineEnd && chars[contentStart + 1] == 32 {
                    tokens.append(SyntaxToken(range: NSRange(location: contentStart, length: 2), kind: .keyword))
                }
            }

            lineStart = lineEnd + 1
        }
        return tokens
    }

    // MARK: HTML / XML

    private func scanHTML(_ chars: [unichar]) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let n = chars.count
        var i = 0

        while i < n {
            let c = chars[i]
            if c == 60 { // <
                if matches(chars, i, Array("<!--".utf16), n) {
                    let start = i
                    i += 4
                    while i < n && !matches(chars, i, Array("-->".utf16), n) { i += 1 }
                    if i < n { i += 3 }
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .comment))
                    continue
                }

                let start = i
                i += 1
                if i < n && (chars[i] == 47 || chars[i] == 33 || chars[i] == 63) { i += 1 }
                let nameStart = i
                while i < n && isTagNameChar(chars[i]) { i += 1 }
                if i > nameStart {
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .tag))
                }

                // 属性区
                while i < n && chars[i] != 62 {
                    let ch = chars[i]
                    if ch == 32 || ch == 9 || ch == 10 || ch == 13 || ch == 47 {
                        i += 1
                        continue
                    }
                    if isTagNameChar(ch) {
                        let attrStart = i
                        while i < n && chars[i] != 32 && chars[i] != 9 && chars[i] != 10
                                && chars[i] != 13 && chars[i] != 61 && chars[i] != 62 {
                            i += 1
                        }
                        tokens.append(SyntaxToken(range: NSRange(location: attrStart, length: i - attrStart), kind: .attributeName))
                        while i < n && (chars[i] == 32 || chars[i] == 9) { i += 1 }
                        if i < n && chars[i] == 61 {
                            i += 1
                            while i < n && (chars[i] == 32 || chars[i] == 9) { i += 1 }
                            if i < n && (chars[i] == 34 || chars[i] == 39) {
                                let quote = chars[i]
                                let valueStart = i
                                i += 1
                                while i < n && chars[i] != quote { i += 1 }
                                if i < n { i += 1 }
                                tokens.append(SyntaxToken(range: NSRange(location: valueStart, length: i - valueStart), kind: .string))
                            } else {
                                let valueStart = i
                                while i < n && chars[i] != 32 && chars[i] != 62 && chars[i] != 9 { i += 1 }
                                if i > valueStart {
                                    tokens.append(SyntaxToken(range: NSRange(location: valueStart, length: i - valueStart), kind: .string))
                                }
                            }
                        }
                        continue
                    }
                    i += 1
                }
                if i < n && chars[i] == 62 {
                    tokens.append(SyntaxToken(range: NSRange(location: i, length: 1), kind: .tag))
                    i += 1
                }
                continue
            }

            if c == 38 { // &entity;
                let start = i
                var j = i + 1
                while j < n && j - start <= 12 && chars[j] != 59 && chars[j] != 32 && chars[j] != 10 { j += 1 }
                if j < n && chars[j] == 59 {
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: j + 1 - start), kind: .constant))
                    i = j + 1
                    continue
                }
            }
            i += 1
        }
        return tokens
    }

    // MARK: CSS

    private func scanCSS(_ chars: [unichar], language: Language) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let n = chars.count
        var i = 0
        var inBlock = false
        var selectorStart = -1

        func flushSelector(upTo end: Int) {
            guard selectorStart >= 0, end > selectorStart else { return }
            tokens.append(SyntaxToken(range: NSRange(location: selectorStart, length: end - selectorStart), kind: .tag))
            selectorStart = -1
        }

        while i < n {
            let c = chars[i]

            if matches(chars, i, Array("/*".utf16), n) {
                let start = i
                i += 2
                while i < n && !matches(chars, i, Array("*/".utf16), n) { i += 1 }
                if i < n { i += 2 }
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .comment))
                continue
            }

            if c == 34 || c == 39 {
                let quote = c
                let start = i
                i += 1
                while i < n && chars[i] != quote && chars[i] != 10 { i += 1 }
                if i < n && chars[i] == quote { i += 1 }
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .string))
                continue
            }

            if c == 123 { // {
                flushSelector(upTo: i)
                inBlock = true
                i += 1
                continue
            }
            if c == 125 { // }
                inBlock = false
                i += 1
                continue
            }

            if !inBlock {
                if c == 64 { // @media / @import
                    let start = i
                    i += 1
                    while i < n && isIdentPart(chars[i]) { i += 1 }
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .keyword))
                    continue
                }
                if c == 10 || c == 32 || c == 9 || c == 44 { // 选择器分隔
                    if selectorStart < 0 && c != 10 && c != 32 && c != 9 { selectorStart = i }
                    i += 1
                    continue
                }
                if selectorStart < 0 { selectorStart = i }
                i += 1
                continue
            }

            // 声明区：属性名
            if isIdentStart(c) || c == 45 {
                let start = i
                i += 1
                while i < n && (isIdentPart(chars[i]) || chars[i] == 45) { i += 1 }
                let word = String(decoding: chars[start..<i], as: UTF16.self)
                var j = i
                while j < n && (chars[j] == 32 || chars[j] == 9) { j += 1 }
                if j < n && chars[j] == 58 {
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .attributeName))
                } else if language.keywords.contains(word.lowercased()) || word.hasPrefix("--") {
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .keyword))
                }
                continue
            }

            // 数字 / 颜色
            if isDigit(c) || (c == 35 && i + 1 < n && isHexDigit(chars[i + 1])) {
                let start = i
                if c == 35 { i += 1 }
                while i < n && (isHexDigit(chars[i]) || chars[i] == 46 || chars[i] == 37) { i += 1 }
                while i < n && isIdentPart(chars[i]) { i += 1 } // 单位 px / em / %
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .number))
                continue
            }

            if c == 33 { // !important
                let start = i
                i += 1
                while i < n && isIdentPart(chars[i]) { i += 1 }
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .keyword))
                continue
            }

            i += 1
        }
        flushSelector(upTo: n)
        return tokens
    }

    // MARK: JSON

    private func scanJSON(_ chars: [unichar], language: Language) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let n = chars.count
        var i = 0
        while i < n {
            let c = chars[i]
            if c == 34 {
                let start = i
                i += 1
                while i < n {
                    if chars[i] == 92 { i += 2; continue }
                    if chars[i] == 34 { i += 1; break }
                    if chars[i] == 10 { break }
                    i += 1
                }
                var j = i
                while j < n && (chars[j] == 32 || chars[j] == 9 || chars[j] == 10 || chars[j] == 13) { j += 1 }
                let kind: TokenKind = (j < n && chars[j] == 58) ? .key : .string
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: kind))
                continue
            }
            if c == 45 || isDigit(c) {
                if c == 45 || isDigit(c) {
                    let start = i
                    if c == 45 { i += 1 }
                    while i < n && (isDigit(chars[i]) || chars[i] == 46 || chars[i] == 101 || chars[i] == 69
                                    || chars[i] == 43 || chars[i] == 45) { i += 1 }
                    if i > start {
                        tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .number))
                        continue
                    }
                }
            }
            if isIdentStart(c) {
                let start = i
                while i < n && isIdentPart(chars[i]) { i += 1 }
                let word = String(decoding: chars[start..<i], as: UTF16.self)
                if language.constants.contains(word) {
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .constant))
                }
                continue
            }
            i += 1
        }
        return tokens
    }

    // MARK: YAML

    private func scanYAML(_ chars: [unichar], language: Language) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let n = chars.count
        var lineStart = 0
        while lineStart < n {
            var lineEnd = lineStart
            while lineEnd < n && chars[lineEnd] != 10 { lineEnd += 1 }

            var i = lineStart
            while i < lineEnd && (chars[i] == 32 || chars[i] == 9) { i += 1 }

            if i < lineEnd && chars[i] == 35 {
                tokens.append(SyntaxToken(range: NSRange(location: i, length: lineEnd - i), kind: .comment))
                lineStart = lineEnd + 1
                continue
            }

            // key:
            let keyStart = i
            while i < lineEnd && (isIdentPart(chars[i]) || chars[i] == 45 || chars[i] == 46) { i += 1 }
            if i > keyStart && i < lineEnd && chars[i] == 58 {
                tokens.append(SyntaxToken(range: NSRange(location: keyStart, length: i - keyStart), kind: .key))
                i += 1
            }

            // 值
            while i < lineEnd {
                let c = chars[i]
                if c == 35 && i > lineStart && chars[i - 1] == 32 {
                    tokens.append(SyntaxToken(range: NSRange(location: i, length: lineEnd - i), kind: .comment))
                    break
                }
                if c == 34 || c == 39 {
                    let quote = c
                    let start = i
                    i += 1
                    while i < lineEnd && chars[i] != quote { i += 1 }
                    if i < lineEnd { i += 1 }
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .string))
                    continue
                }
                if isDigit(c) || (c == 45 && i + 1 < lineEnd && isDigit(chars[i + 1])) {
                    let start = i
                    if c == 45 { i += 1 }
                    while i < lineEnd && (isDigit(chars[i]) || chars[i] == 46 || chars[i] == 58) { i += 1 }
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .number))
                    continue
                }
                if isIdentStart(c) {
                    let start = i
                    while i < lineEnd && isIdentPart(chars[i]) { i += 1 }
                    let word = String(decoding: chars[start..<i], as: UTF16.self)
                    if language.constants.contains(word.lowercased()) {
                        tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .constant))
                    }
                    continue
                }
                i += 1
            }
            lineStart = lineEnd + 1
        }
        return tokens
    }

    // MARK: INI / TOML

    private func scanINI(_ chars: [unichar], language: Language) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let n = chars.count
        var lineStart = 0
        while lineStart < n {
            var lineEnd = lineStart
            while lineEnd < n && chars[lineEnd] != 10 { lineEnd += 1 }

            var i = lineStart
            while i < lineEnd && (chars[i] == 32 || chars[i] == 9) { i += 1 }

            if i < lineEnd, chars[i] == 35 || chars[i] == 59 {
                tokens.append(SyntaxToken(range: NSRange(location: i, length: lineEnd - i), kind: .comment))
                lineStart = lineEnd + 1
                continue
            }

            if i < lineEnd && chars[i] == 91 { // [section]
                let start = i
                while i < lineEnd && chars[i] != 93 { i += 1 }
                if i < lineEnd { i += 1 }
                tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .tag))
                lineStart = lineEnd + 1
                continue
            }

            let keyStart = i
            while i < lineEnd && (isIdentPart(chars[i]) || chars[i] == 45 || chars[i] == 46) { i += 1 }
            if i > keyStart && i < lineEnd && chars[i] == 61 {
                tokens.append(SyntaxToken(range: NSRange(location: keyStart, length: i - keyStart), kind: .key))
                i += 1
            }

            while i < lineEnd {
                let c = chars[i]
                if c == 34 || c == 39 {
                    let quote = c
                    let start = i
                    i += 1
                    while i < lineEnd && chars[i] != quote { i += 1 }
                    if i < lineEnd { i += 1 }
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .string))
                    continue
                }
                if isDigit(c) {
                    let start = i
                    while i < lineEnd && (isDigit(chars[i]) || chars[i] == 46) { i += 1 }
                    tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .number))
                    continue
                }
                if isIdentStart(c) {
                    let start = i
                    while i < lineEnd && isIdentPart(chars[i]) { i += 1 }
                    let word = String(decoding: chars[start..<i], as: UTF16.self)
                    if language.constants.contains(word.lowercased()) || word == "true" || word == "false" {
                        tokens.append(SyntaxToken(range: NSRange(location: start, length: i - start), kind: .constant))
                    }
                    continue
                }
                i += 1
            }
            lineStart = lineEnd + 1
        }
        return tokens
    }

    // MARK: 扫描辅助

    private func matches(_ chars: [unichar], _ index: Int, _ pattern: [unichar], _ n: Int) -> Bool {
        guard !pattern.isEmpty, index + pattern.count <= n else { return false }
        var k = 0
        while k < pattern.count {
            if chars[index + k] != pattern[k] { return false }
            k += 1
        }
        return true
    }

    private func scanNumber(_ chars: [unichar], _ index: Int) -> Int {
        let n = chars.count
        var i = index
        if chars[i] == 48 && i + 1 < n {
            let next = chars[i + 1]
            if next == 120 || next == 88 { // 0x
                i += 2
                while i < n && (isHexDigit(chars[i]) || chars[i] == 95) { i += 1 }
                return i
            }
            if next == 98 || next == 66 { // 0b
                i += 2
                while i < n && (chars[i] == 48 || chars[i] == 49 || chars[i] == 95) { i += 1 }
                return i
            }
            if next == 111 || next == 79 { // 0o
                i += 2
                while i < n && (chars[i] >= 48 && chars[i] <= 55 || chars[i] == 95) { i += 1 }
                return i
            }
        }
        var seenDot = false
        var seenExp = false
        while i < n {
            let c = chars[i]
            if isDigit(c) || c == 95 {
                i += 1
                continue
            }
            if c == 46 && !seenDot && !seenExp {
                seenDot = true
                i += 1
                continue
            }
            if (c == 101 || c == 69) && !seenExp {
                seenExp = true
                i += 1
                if i < n && (chars[i] == 43 || chars[i] == 45) { i += 1 }
                continue
            }
            break
        }
        // 类型后缀：f / u / l / i64 ……
        while i < n && isIdentPart(chars[i]) && i - index < 24 {
            let c = chars[i]
            if isDigit(c) { i += 1; continue }
            let lower = c | 0x20
            if lower == 102 || lower == 117 || lower == 108 || lower == 105 { // f u l i
                i += 1
                continue
            }
            break
        }
        return i
    }

    private func nextNonSpaceChar(_ chars: [unichar], _ index: Int) -> unichar? {
        var i = index
        let n = chars.count
        while i < n && (chars[i] == 32 || chars[i] == 9) { i += 1 }
        return i < n ? chars[i] : nil
    }

    private func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

    private func isHexDigit(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)
    }

    private func isIdentStart(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c >= 128
    }

    private func isIdentPart(_ c: unichar) -> Bool {
        isIdentStart(c) || isDigit(c)
    }

    private func isTagNameChar(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || isDigit(c) || c == 45 || c == 58 || c == 95 || c == 46
    }
}

// MARK: - 主题

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

struct EditorTheme {

    let id: String
    let name: String
    let isDark: Bool

    let background: NSColor
    let text: NSColor
    let keyword: NSColor
    let type: NSColor
    let string: NSColor
    let comment: NSColor
    let number: NSColor
    let function: NSColor
    let constant: NSColor
    let attribute: NSColor
    let tag: NSColor
    let attributeName: NSColor
    let key: NSColor
    let heading: NSColor
    let link: NSColor
    let emphasis: NSColor

    let currentLine: NSColor
    let selection: NSColor
    let gutterBackground: NSColor
    let gutterText: NSColor
    let gutterCurrent: NSColor
    let gutterBorder: NSColor
    let indentGuide: NSColor
    let bracketHighlight: NSColor

    func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword:       return keyword
        case .type:          return type
        case .string:        return string
        case .comment:       return comment
        case .number:        return number
        case .function:      return function
        case .constant:      return constant
        case .attribute:     return attribute
        case .tag:           return tag
        case .attributeName: return attributeName
        case .key:           return key
        case .heading:       return heading
        case .link:          return link
        case .emphasis:      return emphasis
        }
    }

    static let autoID = "auto"

    static let light = EditorTheme(
        id: "light", name: "Xcode 浅色", isDark: false,
        background: NSColor(hex: 0xFFFFFF), text: NSColor(hex: 0x1F1F24),
        keyword: NSColor(hex: 0xAD3DA4), type: NSColor(hex: 0x3F6E74),
        string: NSColor(hex: 0xC41A16), comment: NSColor(hex: 0x5D6C79),
        number: NSColor(hex: 0x1C00CF), function: NSColor(hex: 0x4B21B0),
        constant: NSColor(hex: 0x272AD8), attribute: NSColor(hex: 0x947100),
        tag: NSColor(hex: 0x4B21B0), attributeName: NSColor(hex: 0x947100),
        key: NSColor(hex: 0x643820), heading: NSColor(hex: 0x4B21B0),
        link: NSColor(hex: 0x0F68A0), emphasis: NSColor(hex: 0x643820),
        currentLine: NSColor(hex: 0xF1F5FB), selection: NSColor(hex: 0xB3D7FF),
        gutterBackground: NSColor(hex: 0xF7F7F8), gutterText: NSColor(hex: 0x9AA0A6),
        gutterCurrent: NSColor(hex: 0x3B3B3F), gutterBorder: NSColor(hex: 0xE3E3E6),
        indentGuide: NSColor(hex: 0xE2E4E9), bracketHighlight: NSColor(hex: 0xD3E3F5))

    static let dark = EditorTheme(
        id: "dark", name: "Xcode 深色", isDark: true,
        background: NSColor(hex: 0x1F1F24), text: NSColor(hex: 0xDFDFE0),
        keyword: NSColor(hex: 0xFC5FA3), type: NSColor(hex: 0x5DD8FF),
        string: NSColor(hex: 0xFC6A5D), comment: NSColor(hex: 0x7F8C98),
        number: NSColor(hex: 0xD0BF69), function: NSColor(hex: 0x67B7A4),
        constant: NSColor(hex: 0x41A1C0), attribute: NSColor(hex: 0xFFBF00),
        tag: NSColor(hex: 0x5DD8FF), attributeName: NSColor(hex: 0xFFBF00),
        key: NSColor(hex: 0x9EF1B6), heading: NSColor(hex: 0xFC5FA3),
        link: NSColor(hex: 0x5DD8FF), emphasis: NSColor(hex: 0xFFBF00),
        currentLine: NSColor(hex: 0x2C2C31), selection: NSColor(hex: 0x3F638B),
        gutterBackground: NSColor(hex: 0x1A1A1E), gutterText: NSColor(hex: 0x70737A),
        gutterCurrent: NSColor(hex: 0xE6E6E8), gutterBorder: NSColor(hex: 0x2C2C31),
        indentGuide: NSColor(hex: 0x2E2E33), bracketHighlight: NSColor(hex: 0x474A57))

    static let monokai = EditorTheme(
        id: "monokai", name: "Monokai", isDark: true,
        background: NSColor(hex: 0x272822), text: NSColor(hex: 0xF8F8F2),
        keyword: NSColor(hex: 0xF92672), type: NSColor(hex: 0x66D9EF),
        string: NSColor(hex: 0xE6DB74), comment: NSColor(hex: 0x75715E),
        number: NSColor(hex: 0xAE81FF), function: NSColor(hex: 0xA6E22E),
        constant: NSColor(hex: 0xAE81FF), attribute: NSColor(hex: 0xA6E22E),
        tag: NSColor(hex: 0xF92672), attributeName: NSColor(hex: 0xA6E22E),
        key: NSColor(hex: 0x66D9EF), heading: NSColor(hex: 0xF92672),
        link: NSColor(hex: 0x66D9EF), emphasis: NSColor(hex: 0xE6DB74),
        currentLine: NSColor(hex: 0x3A3A31), selection: NSColor(hex: 0x49483E),
        gutterBackground: NSColor(hex: 0x1F201B), gutterText: NSColor(hex: 0x90908A),
        gutterCurrent: NSColor(hex: 0xF8F8F2), gutterBorder: NSColor(hex: 0x34352E),
        indentGuide: NSColor(hex: 0x3B3A32), bracketHighlight: NSColor(hex: 0x575744))

    static let solarized = EditorTheme(
        id: "solarized", name: "Solarized 浅色", isDark: false,
        background: NSColor(hex: 0xFDF6E3), text: NSColor(hex: 0x586E75),
        keyword: NSColor(hex: 0x859900), type: NSColor(hex: 0xB58900),
        string: NSColor(hex: 0x2AA198), comment: NSColor(hex: 0x93A1A1),
        number: NSColor(hex: 0xD33682), function: NSColor(hex: 0x268BD2),
        constant: NSColor(hex: 0xCB4B16), attribute: NSColor(hex: 0xB58900),
        tag: NSColor(hex: 0x268BD2), attributeName: NSColor(hex: 0xB58900),
        key: NSColor(hex: 0x268BD2), heading: NSColor(hex: 0xCB4B16),
        link: NSColor(hex: 0x268BD2), emphasis: NSColor(hex: 0xCB4B16),
        currentLine: NSColor(hex: 0xEEE8D5), selection: NSColor(hex: 0xDFE3C8),
        gutterBackground: NSColor(hex: 0xF7F0DD), gutterText: NSColor(hex: 0xA6A08C),
        gutterCurrent: NSColor(hex: 0x586E75), gutterBorder: NSColor(hex: 0xE6DFC8),
        indentGuide: NSColor(hex: 0xE6DFC8), bracketHighlight: NSColor(hex: 0xE3D9B8))

    static let github = EditorTheme(
        id: "github", name: "GitHub 深色", isDark: true,
        background: NSColor(hex: 0x0D1117), text: NSColor(hex: 0xC9D1D9),
        keyword: NSColor(hex: 0xFF7B72), type: NSColor(hex: 0xFFA657),
        string: NSColor(hex: 0xA5D6FF), comment: NSColor(hex: 0x8B949E),
        number: NSColor(hex: 0x79C0FF), function: NSColor(hex: 0xD2A8FF),
        constant: NSColor(hex: 0x79C0FF), attribute: NSColor(hex: 0xD2A8FF),
        tag: NSColor(hex: 0x7EE787), attributeName: NSColor(hex: 0x79C0FF),
        key: NSColor(hex: 0x7EE787), heading: NSColor(hex: 0xFF7B72),
        link: NSColor(hex: 0x58A6FF), emphasis: NSColor(hex: 0xFFA657),
        currentLine: NSColor(hex: 0x161B22), selection: NSColor(hex: 0x1F3A5F),
        gutterBackground: NSColor(hex: 0x010409), gutterText: NSColor(hex: 0x6E7681),
        gutterCurrent: NSColor(hex: 0xE6EDF3), gutterBorder: NSColor(hex: 0x21262D),
        indentGuide: NSColor(hex: 0x21262D), bracketHighlight: NSColor(hex: 0x2A3542))

    /// 菜单里的主题列表（第一项为跟随系统）
    static let all: [EditorTheme] = [light, dark, monokai, solarized, github]

    static func byID(_ id: String) -> EditorTheme? {
        all.first { $0.id == id }
    }

    /// 把 "auto" 解析成实际色板
    static func resolved(id: String, isDark: Bool) -> EditorTheme {
        if id == autoID { return isDark ? dark : light }
        return byID(id) ?? (isDark ? dark : light)
    }
}
