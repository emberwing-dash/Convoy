// ChatAnswerView.swift — renders Ellis's replies in an "answer" style: real paragraphs, and any
// list (places, route options, choices) as a tidy card with numbered badges, a bold name and a
// lighter detail line. Tapping an item sends it as the rider's reply (latest answer only).
//
// The model writes light Markdown ("1. **Marina Beach** – longest urban beach…"). SwiftUI's
// default Markdown rendering drops line breaks, which squashed lists into one run-on line; the
// formatter below keeps the structure and also removes sentences the model repeated.
import SwiftUI

// MARK: - Formatting (pure — unit tested)

struct ChatListItem: Equatable {
    var number: Int?
    var title: String
    var detail: String
}

enum ChatBlock: Equatable {
    case paragraph(String)
    case heading(String)
    case list([ChatListItem], numbered: Bool)
}

enum ChatTextFormatter {
    static func blocks(_ raw: String) -> [ChatBlock] {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [ChatBlock] = []
        var paragraph: [String] = []
        var items: [ChatListItem] = []
        var itemsNumbered = false
        var seen = Set<String>()

        func flushParagraph() {
            let text = dedupeSentences(paragraph.joined(separator: " ")).trimmingCharacters(in: .whitespaces)
            paragraph = []
            guard !text.isEmpty, !seen.contains(text.lowercased()) else { return }
            seen.insert(text.lowercased())
            blocks.append(.paragraph(text))
        }
        func flushList() {
            guard !items.isEmpty else { return }
            blocks.append(.list(items, numbered: itemsNumbered))
            items = []
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flushParagraph(); continue }       // a blank line between items keeps the list going

            if let (n, body) = numbered(line) {
                flushParagraph()
                if !items.isEmpty && !itemsNumbered { flushList() }
                itemsNumbered = true
                items.append(item(body, number: n))
            } else if let body = bullet(line) {
                flushParagraph()
                if !items.isEmpty && itemsNumbered { flushList() }
                itemsNumbered = false
                items.append(item(body, number: nil))
            } else if let h = heading(line) {
                flushParagraph(); flushList()
                blocks.append(.heading(h))
            } else {
                flushList()
                if paragraph.last != line { paragraph.append(line) }
            }
        }
        flushParagraph(); flushList()
        return blocks
    }

    static func numbered(_ line: String) -> (Int, String)? {
        guard let r = line.range(of: #"^(\d{1,2})[.)]\s+"#, options: .regularExpression) else { return nil }
        let n = Int(line[r].filter(\.isNumber)) ?? 0
        let body = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? nil : (n, body)
    }

    static func bullet(_ line: String) -> String? {
        guard let r = line.range(of: #"^[-*•]\s+"#, options: .regularExpression) else { return nil }
        let body = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? nil : body
    }

    static func heading(_ line: String) -> String? {
        if let r = line.range(of: #"^#{1,4}\s+"#, options: .regularExpression) {
            return String(line[r.upperBound...]).replacingOccurrences(of: "**", with: "")
        }
        // A line that is only bold text (optionally ending in ':') reads as a heading.
        if line.count < 60, line.range(of: #"^\*\*[^*]+\*\*:?$"#, options: .regularExpression) != nil {
            return line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        }
        return nil
    }

    /// "**Marina Beach** – one of the longest…" → title "Marina Beach", detail "one of the longest…".
    static func item(_ body: String, number: Int?) -> ChatListItem {
        if body.hasPrefix("**"), let close = body.dropFirst(2).range(of: "**") {
            let title = String(body[body.index(body.startIndex, offsetBy: 2)..<close.lowerBound])
            let rest = String(body[close.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " –—-:,·").union(.whitespaces))
            return ChatListItem(number: number, title: title, detail: rest)
        }
        for sep in [" – ", " — ", " - ", ": "] {
            if let r = body.range(of: sep), body.distance(from: body.startIndex, to: r.lowerBound) <= 60 {
                return ChatListItem(number: number,
                                    title: String(body[..<r.lowerBound]).replacingOccurrences(of: "**", with: ""),
                                    detail: String(body[r.upperBound...]))
            }
        }
        return ChatListItem(number: number, title: body.replacingOccurrences(of: "**", with: ""), detail: "")
    }

    /// Cleans a whole reply before it is stored: list and heading lines stay as they are, prose lines
    /// lose repeated or reworded sentences.
    static func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || numbered(t) != nil || bullet(t) != nil || heading(t) != nil { return line }
            return dedupeSentences(t)
        }.joined(separator: "\n")
    }

    /// Drops sentences that repeat earlier ones — exactly, or reworded (most of their meaningful
    /// words were already said in this paragraph). The kept text is returned unchanged, spacing and
    /// abbreviations such as "e.g." included.
    static func dedupeSentences(_ text: String) -> String {
        var out = ""
        var seenExact = Set<String>()
        var seenWords = Set<String>()
        for piece in sentences(text) {
            let s = piece.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            let key = s.lowercased()
            let words = contentWords(s)
            let repeated = words.filter { seenWords.contains($0) }.count
            let reworded = words.count >= 4 && Double(repeated) / Double(words.count) >= 0.5
            if seenExact.contains(key) || reworded { continue }
            seenExact.insert(key)
            seenWords.formUnion(words)
            out += piece
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Splits prose into sentences, each keeping its trailing spaces. A sentence ends at . ! or ?
    /// followed by a space; short tokens like "e.g." or "St." do not end one.
    static func sentences(_ text: String) -> [String] {
        let chars = Array(text)
        var result: [String] = []
        var current = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            current.append(ch)
            let nextIsSpace = i + 1 >= chars.count || chars[i + 1] == " "
            // Replies sometimes glue sentences together: "(future).When would…".
            let gluedSentence = i + 1 < chars.count && chars[i + 1].isUppercase && i > 0
                && (chars[i - 1] == ")" || current.dropLast().split(separator: " ").last.map { $0.count >= 3 && !$0.contains(".") } == true)
            if ".!?".contains(ch), nextIsSpace || gluedSentence {
                let lastToken = current.dropLast().split(separator: " ").last.map(String.init) ?? ""
                let letters = lastToken.filter(\.isLetter)
                let isAbbreviation = ch == "." && (lastToken.contains(".") || (letters.count <= 2 && !letters.isEmpty && letters.count == lastToken.count && lastToken.first?.isUppercase == true) || ["etc", "approx", "vs"].contains(lastToken.lowercased()))
                if !isAbbreviation {
                    while i + 1 < chars.count, chars[i + 1] == " " { i += 1; current.append(" ") }
                    if !nextIsSpace { current.append(" ") }   // put back the missing space
                    result.append(current)
                    current = ""
                }
            }
            i += 1
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "you", "your", "you're", "you'd", "you'll", "would", "could", "like", "just",
        "let", "know", "please", "tell", "share", "give", "what", "when", "where", "which", "that", "this",
        "with", "from", "are", "can", "will", "we'll", "i'll", "have", "has", "any", "want", "ready",
        "whenever", "decide", "here", "there", "then", "also", "some", "into", "about", "our", "it's",
    ]

    static func contentWords(_ s: String) -> Set<String> {
        let normalized = s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        let tokens = normalized.split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init)
        return Set(tokens.filter { $0.count >= 3 && !stopWords.contains($0) })
    }
}

// MARK: - View

struct ChatAnswerView: View {
    let text: String
    /// Called with an item's title when tapped; nil makes the list read-only (older answers).
    var onPick: ((String) -> Void)? = nil
    /// Colour of the list badges (the chat theme).
    var tint: Color = CV.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ChatTextFormatter.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let p):
                    Text(inline(p))
                        .cvText(15, lineHeight: 21, inter: true)
                        .fixedSize(horizontal: false, vertical: true)
                case .heading(let h):
                    Text(h).cvText(13, .bold, color: CV.text.opacity(0.7), tracking: 0.3, inter: true)
                        .textCase(.uppercase)
                        .padding(.top, 2)
                case .list(let items, let numbered):
                    listCard(items, numbered: numbered)
                }
            }
        }
    }

    private func listCard(_ items: [ChatListItem], numbered: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Rectangle().fill(CV.hairline).frame(height: 1).padding(.leading, 44) }
                row(item, index: i + 1, numbered: numbered)
            }
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CV.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func row(_ item: ChatListItem, index: Int, numbered: Bool) -> some View {
        let content = HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color(hex: 0x141418))
                Circle().fill(tint.opacity(0.24))
                Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1)
                if numbered {
                    Text("\(item.number ?? index)").cvText(12, .bold, color: tint, inter: true)
                } else {
                    Image(systemName: "mappin").font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(inline(item.title)).cvText(14, .semibold, color: CV.text, inter: true)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.detail.isEmpty {
                    Text(inline(item.detail)).cvText(12.5, color: CV.text.opacity(0.62), lineHeight: 17, inter: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if onPick != nil {
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.7)).padding(.top, 4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .contentShape(Rectangle())

        if let onPick {
            Button { onPick(item.title) } label: { content }
                .buttonStyle(.plain)
                .accessibilityHint("Sends \(item.title)")
        } else {
            content
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
