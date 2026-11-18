// RideCardRenderTests.swift — every card design renders in every format at export size (1080 px wide),
// transparent only for the sticker. Set CONVOY_CARD_DIR to also write the PNGs for a visual review.
import Testing
import SwiftUI
@testable import Convoy

@MainActor
@Suite("Share Studio · cards render")
struct RideCardRenderTests {
    static func demoData() -> RideCardData {
        // A winding 40 km coastal route (Kattankulathur → Mahabalipuram) for the line art.
        var path: [Coord] = []
        for i in 0...120 {
            let t = Double(i) / 120
            path.append(Coord(lat: 12.823 - 0.2 * t + 0.012 * sin(t * 18), lon: 80.044 + 0.15 * t + 0.01 * cos(t * 11)))
        }
        let log = RideLog(id: UUID(), rideId: nil, title: "Sunday run to Mahabalipuram", startName: "Kattankulathur, Chengalpattu",
                          endName: "Mahabalipuram, Tamil Nadu", startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                          endedAt: Date(timeIntervalSince1970: 1_800_006_060), distanceM: 62_400, movingS: 6_060,
                          maxSpeedKmh: 84, polyline: RideMath.encode(path), riderCount: 6, isHost: true)
        let names = ["Arjun", "Meera", "Rika", "Kabir", "Ananya", "Dev"]
        return RideCardData(log: log, place: "Mahabalipuram", riders: names.map { RiderRef(id: UUID(), name: $0, username: nil, avatarBase64: nil) },
                            crewName: "Weekend Wolves", rideNumber: 7, riderName: "Rika", riderAvatar: nil)
    }

    @Test(arguments: CardDesign.allCases)
    func rendersInEveryFormat(_ design: CardDesign) throws {
        let data = Self.demoData()
        for format in CardFormat.allCases {
            var o = CardOptions()
            o.photoLayout = .stacked
            let img = try #require(CardExporter.render(RideCardCanvas(design: design, data: data, options: o, format: format),
                                                       scale: format.exportScale, transparent: design.isTransparent),
                                   "\(design) \(format) did not render")
            #expect(Int(img.size.width * img.scale) == Int(format.canvas.width * 3))
            #expect(Int(img.size.height * img.scale) == Int(format.canvas.height * 3))
            if let dir = ProcessInfo.processInfo.environment["CONVOY_CARD_DIR"] {
                try? img.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(design.rawValue)-\(format.rawValue).png"))
            }
        }
    }

    @Test func privacyTrimRemovesBothEnds() {
        let data = Self.demoData()
        let trimmed = data.displayPath(trim: true)
        #expect(trimmed.count < data.path.count)
        #expect(trimmed.first != data.path.first && trimmed.last != data.path.last)
        #expect(data.displayPath(trim: false).count == data.path.count)
    }

    @Test func passCodesAreThreeLetters() {
        #expect(RideCardData.code("Hebbal") == "HBB" || RideCardData.code("Hebbal").count == 3)
        #expect(RideCardData.code("Nandi Hills").count == 3)
        #expect(RideCardData.code("") == "—")
    }
}
