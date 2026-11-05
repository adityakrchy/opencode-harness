import Foundation
import SwiftUI

// MARK: - Markdown parser

enum MarkdownBlock: Identifiable {
    case heading(id: Int, level: Int, text: String)
    case paragraph(id: Int, text: String)
    case code(id: Int, language: String, code: String)
    case quote(id: Int, text: String)
    case listItem(id: Int, indent: Int, marker: String, text: String)
    case divider(id: Int)
    case table(id: Int, headers: [String], rows: [[String]])

    var id: Int {
        switch self {
        case .heading(let id, _, _), .paragraph(let id, _), .code(let id, _, _),
             .quote(let id, _), .listItem(let id, _, _, _), .divider(let id), .table(let id, _, _):
            return id
        }
    }
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0
        var blockID = 0

        func nextID() -> Int {
            defer { blockID += 1 }
            return blockID
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Fenced code
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }
                blocks.append(.code(id: nextID(), language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Headings
            if let heading = headingLevel(line) {
                let text = String(trimmed.dropFirst(heading + 1)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(id: nextID(), level: heading, text: text))
                index += 1
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider(id: nextID()))
                index += 1
                continue
            }

            // Tables
            if trimmed.contains("|"), index + 1 < lines.count,
               isTableSeparator(lines[index + 1]) {
                let headers = tableCells(line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard row.contains("|"), !row.isEmpty else { break }
                    rows.append(tableCells(row))
                    index += 1
                }
                blocks.append(.table(id: nextID(), headers: headers, rows: rows))
                continue
            }

            // Quotes
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoteLines.append(String(quoteLine.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(id: nextID(), text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Lists
            if let item = listItem(line) {
                blocks.append(.listItem(id: nextID(), indent: item.indent, marker: item.marker, text: item.text))
                index += 1
                continue
            }

            // Paragraph
            var paragraphLines: [String] = [line]
            index += 1
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty
                    || candidateTrimmed.hasPrefix("```")
                    || headingLevel(candidate) != nil
                    || candidateTrimmed.hasPrefix(">")
                    || listItem(candidate) != nil
                    || candidateTrimmed == "---"
                    || (candidateTrimmed.contains("|") && index + 1 < lines.count && isTableSeparator(lines[index + 1])) {
                    break
                }
                paragraphLines.append(candidate)
                index += 1
            }
            blocks.append(.paragraph(id: nextID(), text: paragraphLines.joined(separator: "\n")))
        }
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6, trimmed.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func listItem(_ line: String) -> (indent: Int, marker: String, text: String)? {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let marker: String
        let rest: Substring
        if let match = trimmed.range(of: #"^([-*+])\s+"#, options: .regularExpression) {
            marker = String(trimmed[trimmed.startIndex..<trimmed.index(before: match.upperBound)])
            rest = trimmed[match.upperBound...]
        } else if let match = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            marker = String(trimmed[trimmed.startIndex..<trimmed.index(before: match.upperBound)])
            rest = trimmed[match.upperBound...]
        } else {
            return nil
        }
        return (leading / 2, marker.trimmingCharacters(in: .whitespaces), String(rest))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") || trimmed.hasPrefix("-") else { return false }
        let allowed = CharacterSet(charactersIn: "|-: ")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Markdown view

struct MarkdownView: View {
    var markdown: String
    private let blocks: [MarkdownBlock]

    init(markdown: String) {
        self.markdown = markdown
        self.blocks = MarkdownParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(_, let level, let text):
            inline(text)
                .font(headingFont(level))
                .foregroundStyle(Color.ocTextPrimary)
                .padding(.top, level <= 2 ? 4 : 2)

        case .paragraph(_, let text):
            inline(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.ocTextPrimary)
                .lineSpacing(4.2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .code(_, let language, let code):
            CodeBlockView(code: code, language: language)

        case .quote(_, let text):
            inline(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.ocTextSecondary)
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 13)
                .padding(.vertical, 2)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.ocAccent.opacity(0.55))
                        .frame(width: 2.5)
                }

        case .listItem(_, let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .font(.ocMono(10.5, weight: .medium))
                    .foregroundStyle(Color.ocTextTertiary)
                    .frame(minWidth: 12, alignment: .trailing)
                inline(text)
                    .font(.system(size: 13.3))
                    .foregroundStyle(Color.ocTextPrimary)
                    .lineSpacing(3.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)

        case .divider:
            Rectangle()
                .fill(Color.ocBorder)
                .frame(height: 0.7)
                .padding(.vertical, 5)

        case .table(_, let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .ocRounded(21, weight: .bold)
        case 2: .ocRounded(18, weight: .bold)
        case 3: .ocRounded(15.5, weight: .semibold)
        default: .ocRounded(13.5, weight: .semibold)
        }
    }

    private func inline(_ text: String) -> Text {
        Text(InlineMarkdown.make(text, fontSize: 13.5))
    }
}

enum InlineMarkdown {
    static func make(_ text: String, fontSize: CGFloat) -> AttributedString {
        var value: AttributedString
        do {
            value = try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            value = AttributedString(text)
        }

        for run in value.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                value[run.range].font = .system(size: fontSize - 1.2, design: .monospaced)
                value[run.range].backgroundColor = Color.ocCodeBackground
            }
            if run.link != nil {
                value[run.range].foregroundColor = Color.ocAccent
            }
        }
        return value
    }
}

struct MarkdownTableView: View {
    var headers: [String]
    var rows: [[String]]

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(InlineMarkdown.make(header, fontSize: 11))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.ocTextSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(minWidth: 100, alignment: .leading)
                    }
                }
                .background(Color.ocSurfaceSunken)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(InlineMarkdown.make(cell, fontSize: 11))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ocTextPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(minWidth: 100, alignment: .leading)
                        }
                    }
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.ocHover.opacity(0.35))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ocBorder, lineWidth: 0.6))
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Code block

struct CodeBlockView: View {
    @EnvironmentObject private var model: AppModel
    var code: String
    var language: String
    var compact: Bool = false

    @State private var expanded = false
    @State private var copied = false

    private var isLong: Bool { code.count > 8_000 || code.components(separatedBy: "\n").count > 140 }
    private var shownCode: String {
        guard isLong, !expanded else {
            return code.count > 30_000 ? String(code.prefix(30_000)) : code
        }
        return String(code.prefix(8_000))
    }
    private var lineCount: Int {
        max(1, shownCode.components(separatedBy: "\n").count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(displayLanguage)
                    .font(.ocMono(8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.ocTextTertiary)
                Spacer()
                Text("\(lineCount) lines")
                    .font(.ocMono(8))
                    .foregroundStyle(Color.ocTextTertiary.opacity(0.7))
                Button {
                    model.copyText(code)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        copied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.ocMono(8.5))
                    .foregroundStyle(copied ? Color.ocSuccess : Color.ocTextTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, compact ? 9 : 11)
            .padding(.vertical, compact ? 6 : 7)
            .background(Color.ocCodeGutter)

            HStack(alignment: .top, spacing: 0) {
                Text((1...lineCount).map(String.init).joined(separator: "\n"))
                    .font(.ocMono(compact ? 9.5 : 10.5))
                    .foregroundStyle(Color.ocTextTertiary.opacity(0.55))
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, compact ? 7 : 9)
                    .padding(.vertical, compact ? 7 : 9)
                    .frame(minWidth: 30, alignment: .trailing)
                    .background(Color.ocCodeGutter)

                ScrollView(.horizontal) {
                    Text(SyntaxHighlighter.highlight(shownCode, language: language, fontSize: compact ? 10 : 11))
                        .font(.ocMono(compact ? 10 : 11))
                        .lineSpacing(2.2)
                        .textSelection(.enabled)
                        .padding(compact ? 8 : 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }
            .background(Color.ocCodeBackground)

            if isLong {
                Button {
                    withAnimation(Motion.smooth) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        Text(expanded ? "Show less" : "Show full output")
                    }
                    .font(.ocMono(8.5, weight: .medium))
                    .foregroundStyle(Color.ocTextTertiary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.ocCodeGutter)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 9))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 7 : 9)
                .strokeBorder(Color.ocBorder, lineWidth: 0.6)
        }
    }

    private var displayLanguage: String {
        let value = language.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return "CODE" }
        switch value.lowercased() {
        case "swift": return "SWIFT"
        case "js", "javascript": return "JAVASCRIPT"
        case "ts", "typescript": return "TYPESCRIPT"
        case "py", "python": return "PYTHON"
        case "sh", "bash", "zsh", "shell": return "SHELL"
        case "json": return "JSON"
        case "md", "markdown": return "MARKDOWN"
        default: return value.uppercased()
        }
    }
}

// MARK: - Syntax highlighting

enum SyntaxHighlighter {
    static func highlight(_ code: String, language: String, fontSize: CGFloat) -> AttributedString {
        let baseFont = Font.system(size: fontSize, design: .monospaced)
        let base = Color.ocTextPrimary
        let nsCode = code as NSString
        var regions: [(NSRange, Color)] = []

        func add(_ pattern: String, options: NSRegularExpression.Options = [], color: Color) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: code, range: NSRange(location: 0, length: nsCode.length)) {
                if match.range.length == 0 { continue }
                let overlaps = regions.contains { NSIntersectionRange($0.0, match.range).length > 0 }
                if !overlaps {
                    regions.append((match.range, color))
                }
            }
        }

        let languageKey = language.lowercased()
        let shellLike = ["sh", "bash", "zsh", "shell", "console", "terminal"].contains(languageKey)

        // Strings first so comment markers inside strings stay strings.
        add(#"""(?:\\.|[^"\\])*""#, options: [.dotMatchesLineSeparators], color: .ocTeal)
        add(#"'(?:\\.|[^'\\])*'"#, options: [.dotMatchesLineSeparators], color: .ocTeal)
        add("`[^`]*`", color: .ocTeal)

        if shellLike {
            add(#"(?m)^\s*#.*$"#, color: .ocTextTertiary)
        } else if ["py", "python", "rb", "ruby", "yaml", "yml", "toml"].contains(languageKey) {
            add(#"(?m)#.*$"#, color: .ocTextTertiary)
        }
        add(#"//.*$"#, options: [.anchorsMatchLines], color: .ocTextTertiary)

        add(#"\b(0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b"#, color: .ocAccentSoft)

        let keywords = [
            "actor", "async", "await", "break", "case", "catch", "class", "const", "continue",
            "default", "defer", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
            "final", "for", "func", "guard", "if", "import", "in", "indirect", "init", "inout", "internal",
            "is", "lazy", "let", "mutating", "nil", "nonisolated", "open", "operator", "override", "private",
            "protocol", "public", "repeat", "required", "rethrows", "return", "self", "Self", "static",
            "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var",
            "where", "while", "willSet", "yield", "function", "export", "from", "new", "this", "typeof",
            "instanceof", "extends", "implements", "interface", "package", "def", "elif", "except", "finally",
            "global", "lambda", "None", "nonlocal", "not", "or", "and", "pass", "raise", "with", "assert",
            "match", "impl", "use", "pub", "mod", "fn", "mut", "ref", "type", "trait", "end", "then", "fi",
            "done", "esac", "local", "readonly", "select", "until"
        ]
        add("\\b(" + keywords.joined(separator: "|") + ")\\b", color: .ocViolet)

        add(#"\b(true|false|null|undefined|nil|None)\b"#, color: .ocAccentSoft)
        add(#"\b[A-Z][A-Za-z0-9_]*\b"#, color: .ocInfo)
        add(#"\b([A-Za-z_][A-Za-z0-9_]*)\s*(?=\()"#, color: .ocInfo)
        if languageKey == "json" {
            add(#""[^"]*"(?=\s*:)"#, color: .ocInfo)
        }

        let sorted = regions.sorted { $0.0.location < $1.0.location }
        var result = AttributedString()
        var cursor = 0
        for (range, color) in sorted {
            if range.location < cursor { continue }
            if range.location > cursor {
                let plainRange = NSRange(location: cursor, length: range.location - cursor)
                if let swiftRange = Range(plainRange, in: code) {
                    var piece = AttributedString(String(code[swiftRange]))
                    piece.font = baseFont
                    piece.foregroundColor = base
                    result.append(piece)
                }
            }
            if let swiftRange = Range(range, in: code) {
                var piece = AttributedString(String(code[swiftRange]))
                piece.font = baseFont
                piece.foregroundColor = color
                result.append(piece)
            }
            cursor = range.location + range.length
        }
        if cursor < nsCode.length, let swiftRange = Range(NSRange(location: cursor, length: nsCode.length - cursor), in: code) {
            var piece = AttributedString(String(code[swiftRange]))
            piece.font = baseFont
            piece.foregroundColor = base
            result.append(piece)
        }
        return result
    }
}

// MARK: - Diff

struct DiffPatchView: View {
    var patch: String
    var maxHeight: CGFloat? = 320

    private var lines: [String] {
        patch.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.ocMono(10.2))
                        .foregroundStyle(foreground(for: line))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1.2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(for: line))
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: maxHeight)
        .background(Color.ocCodeBackground)
    }

    private func foreground(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .ocSuccess }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .ocDanger }
        if line.hasPrefix("@@") { return .ocViolet }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") { return .ocTextTertiary }
        return .ocTextSecondary
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .ocSuccess.opacity(0.07) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .ocDanger.opacity(0.07) }
        if line.hasPrefix("@@") { return .ocViolet.opacity(0.06) }
        return .clear
    }
}
