// DestinationLiveTests.swift — live Apple Maps checks for the chatbot's destination resolver.
// Network-dependent, so off by default. Run with:
//   TEST_RUNNER_CONVOY_LIVE_TESTS=1 xcodebuild test -only-testing:ConvoyTests/DestinationLiveTests …
import Testing
import Foundation
@testable import Convoy

@MainActor
@Suite("Destination resolver · live Apple Maps",
       .enabled(if: ProcessInfo.processInfo.environment["CONVOY_LIVE_TESTS"] == "1"))
struct DestinationLiveTests {
    @Test(arguments: [
        ("Munnar", 10.09, 77.06), ("Ooty", 11.41, 76.70), ("Coorg", 12.42, 75.74), ("Mahabalipuram", 12.62, 80.19),
    ])
    func resolvesToTheRealPlaceInIndia(_ q: String, _ lat: Double, _ lon: Double) async {
        let options = await DestinationResolver.search(q, purpose: .destination)
        let decision = DestinationResolver.decide(query: q, options: options, purpose: .destination)
        print("LIVE \(q): \(options.count) options → \(options.prefix(5).map { "\($0.name) [\($0.address)] geo=\($0.isGeographic ?? true)" })")
        switch decision {
        case .unique(let p):
            print("LIVE \(q): picked \(p.name) (\(p.lat), \(p.lon))")
            let km = hypot((p.lat - lat) * 111, (p.lon - lon) * 109)
            #expect(km < 40, "\(q) resolved \(Int(km)) km away from the real place")
            #expect(p.isGeographic ?? true, "\(q) resolved to a business")
        case .choose(let list):
            print("LIVE \(q): asks the rider → \(list.map(\.name))")
            #expect(list.contains { hypot(($0.lat - lat) * 111, ($0.lon - lon) * 109) < 40 }, "real \(q) not among the choices")
        case .none:
            Issue.record("\(q): no results")
        }
    }
}
