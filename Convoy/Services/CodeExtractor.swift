// CodeExtractor.swift
import Foundation

/// Pulls a Convoy join code out of whatever the rider pasted or scanned:
/// `convoy://ride/abc123`, `convoy://crew/dil904`, "Join Desert Riders on Convoy: convoy://crew/dil904",
/// or just the code itself.
enum CodeExtractor {
    /// Ride codes are always 6 characters.
    static func rideCode(from text: String) -> String? { extract(from: text, kind: "ride", lengths: 6...6) }

    /// Crew codes are 6 characters today; older crews have 7.
    static func crewCode(from text: String) -> String? { extract(from: text, kind: "crew", lengths: 4...10) }

    static func extract(from text: String, kind: String, lengths: ClosedRange<Int>) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        func clean(_ s: Substring) -> String { s.uppercased().filter { $0.isLetter || $0.isNumber } }

        // 1. A convoy:// link anywhere in the text — take the path after the host.
        if let range = trimmed.range(of: "convoy://", options: .caseInsensitive) {
            let tail = trimmed[range.upperBound...].split(whereSeparator: { $0.isWhitespace }).first ?? ""
            let parts = tail.split(separator: "/")
            if parts.count >= 2, parts[0].lowercased() == kind {
                let c = clean(parts[1])
                if lengths.contains(c.count) { return c }
            }
        }
        // 2. The whole text is the code.
        let whole = clean(Substring(trimmed))
        if lengths.contains(whole.count), !trimmed.contains(" ") { return whole }
        // 3. The last word that looks like a code (letters + digits).
        for word in trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).reversed() {
            let c = clean(word)
            if lengths.contains(c.count), c.contains(where: \.isNumber), c.contains(where: \.isLetter) { return c }
        }
        return nil
    }
}
