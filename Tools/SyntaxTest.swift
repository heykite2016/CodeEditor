//
//  SyntaxTest.swift
//  语法引擎无头自检：token 正确性 / 语言识别 / 性能基线
//

import Foundation

var failures = 0
var passed = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        passed += 1
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)  \(detail)")
    }
}

let highlighter = SyntaxHighlighter()

/// 找到覆盖 needle 首次出现位置的 token，返回其 kind
func kindOf(_ text: NSString, language: Language, needle: String) -> TokenKind? {
    let tokens = highlighter.tokenize(text, language: language)
    let location = text.range(of: needle).location
    guard location != NSNotFound else { return nil }
    return tokens.first { NSLocationInRange(location, $0.range) }?.kind
}

// MARK: Swift

let swiftCode = """
import Foundation
/// 文档注释
struct Point {
    var x: Double = 0.5
    // 行注释
    func distance(to other: Point) -> Double { return x }
}
let name = "hello"
let flag = true
"""

check("Swift: import 是关键字", kindOf(swiftCode as NSString, language: .swift, needle: "import") == .keyword)
check("Swift: struct 是关键字", kindOf(swiftCode as NSString, language: .swift, needle: "struct") == .keyword)
check("Swift: Point 声明着色为类型", kindOf(swiftCode as NSString, language: .swift, needle: "Point") == .type)
check("Swift: Double 是类型", kindOf(swiftCode as NSString, language: .swift, needle: "Double") == .type)
check("Swift: distance 着色为函数", kindOf(swiftCode as NSString, language: .swift, needle: "distance") == .function)
check("Swift: 字符串", kindOf(swiftCode as NSString, language: .swift, needle: "\"hello\"") == .string)
check("Swift: 行注释", kindOf(swiftCode as NSString, language: .swift, needle: "// 行注释") == .comment)
check("Swift: 数字", kindOf(swiftCode as NSString, language: .swift, needle: "0.5") == .number)
check("Swift: true 是常量", kindOf(swiftCode as NSString, language: .swift, needle: "true") == .constant)

// MARK: Python

let pythonCode = """
# 顶部注释
import os

def greet(name):
    x = 3.14
    return f"hi {name}"
"""
check("Python: # 注释", kindOf(pythonCode as NSString, language: .python, needle: "# 顶部注释") == .comment)
check("Python: def 是关键字", kindOf(pythonCode as NSString, language: .python, needle: "def") == .keyword)
check("Python: greet 声明着色为函数", kindOf(pythonCode as NSString, language: .python, needle: "greet") == .function)
check("Python: 数字", kindOf(pythonCode as NSString, language: .python, needle: "3.14") == .number)

// MARK: JSON

let jsonCode = """
{
  "name": "demo",
  "count": 42,
  "ready": true,
  "note": "value string"
}
"""
check("JSON: 键着色", kindOf(jsonCode as NSString, language: .json, needle: "\"name\"") == .key)
check("JSON: 值字符串", kindOf(jsonCode as NSString, language: .json, needle: "\"value string\"") == .string)
check("JSON: 数字", kindOf(jsonCode as NSString, language: .json, needle: "42") == .number)
check("JSON: true 是常量", kindOf(jsonCode as NSString, language: .json, needle: "true") == .constant)

// MARK: HTML

let htmlCode = """
<!DOCTYPE html>
<!-- 注释 -->
<html lang="zh">
  <body class="main">
    <p>Hello</p>
  </body>
</html>
"""
check("HTML: 注释", kindOf(htmlCode as NSString, language: .html, needle: "<!-- 注释 -->") == .comment)
check("HTML: 标签名", kindOf(htmlCode as NSString, language: .html, needle: "body") == .tag)
check("HTML: 属性名", kindOf(htmlCode as NSString, language: .html, needle: "class") == .attributeName)
check("HTML: 属性值", kindOf(htmlCode as NSString, language: .html, needle: "\"main\"") == .string)

// MARK: CSS

let cssCode = """
/* 注释 */
body {
  color: #333;
  font-size: 14px;
}
@media screen {
  .box { display: flex; }
}
"""
check("CSS: 注释", kindOf(cssCode as NSString, language: .css, needle: "/* 注释 */") == .comment)
check("CSS: 属性名", kindOf(cssCode as NSString, language: .css, needle: "font-size") == .attributeName)
check("CSS: 颜色数字", kindOf(cssCode as NSString, language: .css, needle: "#333") == .number)
check("CSS: @规则", kindOf(cssCode as NSString, language: .css, needle: "@media") == .keyword)

// MARK: YAML

let yamlCode = """
# 配置
name: demo
count: 12
ready: true
"""
check("YAML: 键", kindOf(yamlCode as NSString, language: .yaml, needle: "name") == .key)
check("YAML: 注释", kindOf(yamlCode as NSString, language: .yaml, needle: "# 配置") == .comment)
check("YAML: true 是常量", kindOf(yamlCode as NSString, language: .yaml, needle: "true") == .constant)

// MARK: C

let cCode = """
#include <stdio.h>
/* 块注释 */
int main(void) {
    unsigned long x = 0xFF; // 十六进制
    return 0;
}
"""
check("C: #include 指令", kindOf(cCode as NSString, language: .c, needle: "#include") == .attribute)
check("C: int 是关键字", kindOf(cCode as NSString, language: .c, needle: "int") == .keyword)
check("C: main 是函数", kindOf(cCode as NSString, language: .c, needle: "main") == .function)
check("C: 十六进制数字", kindOf(cCode as NSString, language: .c, needle: "0xFF") == .number)

// MARK: SQL（大小写不敏感）

let sqlCode = """
-- 注释
SELECT id, name FROM users WHERE age > 18;
"""
check("SQL: SELECT 关键字", kindOf(sqlCode as NSString, language: .sql, needle: "SELECT") == .keyword)
check("SQL: from 小写也是关键字", kindOf(sqlCode as NSString, language: .sql, needle: "FROM") == .keyword)
check("SQL: 注释", kindOf(sqlCode as NSString, language: .sql, needle: "-- 注释") == .comment)

// MARK: 语言识别

check("识别 .swift", Language.detect(fileName: "main.swift").id == "swift")
check("识别 .py", Language.detect(fileName: "run.py").id == "python")
check("识别 .tsx", Language.detect(fileName: "App.tsx").id == "typescript")
check("识别 .md", Language.detect(fileName: "README.md").id == "markdown")
check("识别 Dockerfile", Language.detect(fileName: "Dockerfile").id == "dockerfile")
check("识别 Makefile", Language.detect(fileName: "Makefile").id == "makefile")
check("识别 .yml", Language.detect(fileName: "ci.yml").id == "yaml")
check("未知扩展回退纯文本", Language.detect(fileName: "data.xyz").id == "plain")
check("无文件名回退纯文本", Language.detect(fileName: nil).id == "plain")

// MARK: 主题

check("主题解析 auto→浅色", EditorTheme.resolved(id: "auto", isDark: false).id == "light")
check("主题解析 auto→深色", EditorTheme.resolved(id: "auto", isDark: true).id == "dark")
check("主题解析 monokai", EditorTheme.resolved(id: "monokai", isDark: true).id == "monokai")

// MARK: 性能基线（1MB Swift 代码）

var big = ""
let chunk = """
func handler\(Int.random(in: 0...9))(request: Request) throws -> Response {
    // 处理请求 \(Int.random(in: 0...9))
    let payload = try JSONDecoder().decode(Payload.self, from: request.body)
    return Response(status: .ok, content: payload)
}

"""
for _ in 0..<2600 { big += chunk }
let bigNS = big as NSString
let start = Date()
let tokens = highlighter.tokenize(bigNS, language: .swift)
let elapsed = Date().timeIntervalSince(start)
print("INFO  1MB Swift 扫描: \(Int(elapsed * 1000))ms, tokens=\(tokens.count)")
check("1MB 扫描 < 300ms", elapsed < 0.3, "实际 \(elapsed)s")
check("大 token 数量合理", tokens.count > 5000, "实际 \(tokens.count)")

print("")
print("=== 语法引擎自检：\(passed) 通过, \(failures) 失败 ===")
exit(failures == 0 ? 0 : 1)
