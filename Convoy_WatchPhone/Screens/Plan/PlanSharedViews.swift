import SwiftUI

/// Inter-styled field label ("Ride name", "Route", "When").
struct FieldLabel: View {
    let text: String
    var body: some View { Text(text).cvText(14, .semibold, color: CV.cream.opacity(0.6), inter: true) }
}

/// From → (stops) → To summary card. Laid out on the 46pt row grid.
struct RouteSummaryCard: View {
    let draft: PlanDraft
    var numberedStops = true

    private enum Kind { case start, stop, end }

    private var rows: [(Kind, String, String)] {
        var r: [(Kind, String, String)] = [(.start, short(draft.from), "Start")]
        for (i, s) in draft.stops.enumerated() {
            r.append((.stop, s, numberedStops ? "Stop \(i + 1)" : "Stop"))
        }
        r.append((.end, short(draft.to), "End"))
        return r
    }

    private func short(_ s: String) -> String {
        s.components(separatedBy: ",").first ?? s
    }

    var body: some View {
        let rows = rows
        ZStack(alignment: .topLeading) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                let y = CGFloat(14 + 46 * i)
                marker(row.0).frame(width: 14, height: 14).offset(x: 16, y: y + 2)
                Text(row.1).cvText(16, .semibold, inter: true).lineLimit(1)
                    .frame(width: 236, alignment: .leading).offset(x: 44, y: y)
                Text(row.2).cvText(13, color: CV.cream.opacity(0.4), inter: true)
                    .frame(width: 60, alignment: .trailing).offset(x: 277, y: y + 1)
                if i < rows.count - 1 {
                    Circle().fill(CV.cream.opacity(0.35)).frame(width: 3, height: 3).offset(x: 21.5, y: y + 22)
                    Circle().fill(CV.cream.opacity(0.35)).frame(width: 3, height: 3).offset(x: 21.5, y: y + 30)
                    Rectangle().fill(Color.white.opacity(0.07)).frame(width: 293, height: 1).offset(x: 44, y: y + 32)
                }
            }
        }
        .frame(width: 353, height: CGFloat(46 * (rows.count - 1) + 46), alignment: .topLeading)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder private func marker(_ k: Kind) -> some View {
        switch k {
        case .start: Circle().strokeBorder(CV.cream, lineWidth: 3)
        case .stop:  RoundedRectangle(cornerRadius: 3).strokeBorder(CV.cream, lineWidth: 2).padding(1)
        case .end:   ZStack { Circle().fill(CV.red); Circle().fill(.white).frame(width: 4, height: 4) }
        }
    }
}
