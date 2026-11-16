// CodeExtractor.swift
import Foundation

/// Shared parser for Convoy join codes. Works for both `convoy://ride/<code>`
/// and `convoy://crew/<code>` links, raw 6-character codes, and any free-form
/// text containing one.
enum CodeExtractor {
    static func extract(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Well-formed URL — take the last path component.
        if let url = URL(string: trimmed), url.scheme != nil {
            let clean = url.lastPathComponent
                .uppercased()
                .filter { $0.isLetter || $0.isNumber }
            if clean.count >= 6 { return String(clean.prefix(6)) }
        }

        // 2. Fallback — take the last 6 alphanumeric characters of the whole string.
        let clean = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        guard clean.count >= 6 else { return nil }
        return String(clean.suffix(6))
    }
}
