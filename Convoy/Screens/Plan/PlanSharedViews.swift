import SwiftUI

/// Inter-styled field label ("Ride name", "Route", "When").
struct FieldLabel: View {
    let text: String
    var body: some View { Text(text).cvText(14, .semibold, color: CV.text.opacity(0.6), inter: true) }
}

/// From → (stops) → To summary card. Fully dynamic & responsive to any iPhone screen size.
struct RouteSummaryCard: View {
    let draft: PlanDraft
    var numberedStops = true

    @State private var resolvedStart: String?

    private enum Kind { case start, stop, end }

    private var startTitle: String {
        if let resolvedStart, !resolvedStart.isEmpty {
            return resolvedStart
        }
        let from = draft.from.trimmingCharacters(in: .whitespaces)
        return from.isEmpty ? "Start point" : short(from)
    }

    private var rows: [(Kind, String, String)] {
        var r: [(Kind, String, String)] = [(.start, startTitle, "Start")]
        for (i, s) in draft.stops.enumerated() {
            r.append((.stop, short(s), numberedStops ? "Stop \(i + 1)" : "Stop"))
        }
        r.append((.end, short(draft.to), "End"))
        return r
    }

    private func short(_ s: String) -> String {
        s.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? s
    }

    var body: some View {
        let currentRows = rows
        VStack(spacing: 0) {
            ForEach(Array(currentRows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 14) {
                    marker(row.0)
                        .frame(width: 14, height: 14)

                    Text(row.1)
                        .cvText(16, .semibold, inter: true)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(row.2)
                        .cvText(13, color: CV.text.opacity(0.45), inter: true)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)

                if i < currentRows.count - 1 {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 44)
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                    }
                    .padding(.trailing, 16)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .task(id: draft.from) {
            await resolveStartingLocation()
        }
    }

    private func resolveStartingLocation() async {
        let from = draft.from.trimmingCharacters(in: .whitespaces)
        if !from.isEmpty && from.caseInsensitiveCompare("Current Location") != .orderedSame {
            return
        }

        let coord = draft.selected?.coords.first?.cl
            ?? draft.startCoord?.cl
            ?? LocationService.shared.currentLocation?.coordinate

        guard let targetCoord = coord else { return }

        let geocoded = await LocationService.shared.reverseGeocode(coordinate: targetCoord)
        let clean = geocoded.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty && !clean.contains("0.0000") {
            let primaryName = primaryPlaceName(clean)
            if !primaryName.isEmpty {
                resolvedStart = primaryName
            }
        }
    }

    @ViewBuilder private func marker(_ k: Kind) -> some View {
        switch k {
        case .start: Circle().strokeBorder(CV.text, lineWidth: 3)
        case .stop:  RoundedRectangle(cornerRadius: 3).strokeBorder(CV.text, lineWidth: 2).padding(1)
        case .end:   ZStack { Circle().fill(CV.accent); Circle().fill(.white).frame(width: 4, height: 4) }
        }
    }
}

/// First meaningful part of a reverse-geocoded address: skips house numbers and plot codes
/// ("141, Anna Salai, Kattankulathur" → "Anna Salai").
func primaryPlaceName(_ address: String) -> String {
    let parts = address.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    return parts.first { part in part.contains(where: \.isLetter) && part.filter(\.isLetter).count >= 3 } ?? parts.first ?? address
}
