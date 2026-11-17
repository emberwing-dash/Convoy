// DestinationResolver.swift — turns a typed place ("Munnar", "Ooty", "Coorg") into a real,
// confirmed place with coordinates for the chatbot's ride planner.
//
// Rules (fixes the "typed name saved as the destination" bug):
//   • A destination is never confirmed from text alone — only from a real search result.
//   • Ride destinations prefer geographic places (towns, cities, districts, regions, beaches,
//     parks) over businesses (hotels, restaurants, shops). Businesses are only offered when no
//     geographic place matches, and are never picked silently.
//   • Searches are biased to India, and Indian results win when there are any.
//   • A result is picked automatically only when it is unambiguous: exactly one plausible place,
//     or exactly one place whose name is the query itself. Otherwise the rider chooses.
import Foundation
import MapKit

enum DestinationResolver {
    enum Purpose { case destination, start }

    /// Outcome of a lookup.
    enum Decision: Equatable {
        case none
        case unique(LocationOption)
        case choose([LocationOption])
    }

    /// Whole of India (roughly 6°N–36°N, 68°E–98°E).
    static let indiaRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 22.0, longitude: 82.0),
        span: MKCoordinateSpan(latitudeDelta: 32, longitudeDelta: 32))

    // MARK: Search

    @MainActor
    static func resolve(_ query: String, purpose: Purpose) async -> Decision {
        decide(query: query, options: await search(query, purpose: purpose), purpose: purpose)
    }

    /// Runs Apple Maps search (places/areas first, then points of interest) and returns
    /// de-duplicated, classified options — Indian results only when any exist.
    @MainActor
    static func search(_ query: String, purpose: Purpose) async -> [LocationOption] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        let region: MKCoordinateRegion = {
            if purpose == .start, let here = LocationService.shared.currentLocation?.coordinate {
                return MKCoordinateRegion(center: here, span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5))
            }
            return indiaRegion
        }()

        async let areas = run(clean, types: .address, region: region)
        async let pois = run(clean, types: .pointOfInterest, region: region)
        let items = await areas + pois

        var options: [(LocationOption, String?)] = []   // option, country code
        for item in items {
            guard let name = item.name, !name.isEmpty else { continue }
            let pm = item.placemark
            let option = LocationOption(
                name: name,
                address: address(pm, purpose: purpose),
                lat: pm.coordinate.latitude, lon: pm.coordinate.longitude,
                isGeographic: isGeographic(item))
            // Same place returned twice (area + POI, or two POIs on top of each other).
            if options.contains(where: { $0.0.name.lowercased() == name.lowercased()
                && distanceKm($0.0, option) < 5 }) { continue }
            options.append((option, pm.isoCountryCode))
        }
        let indian = options.filter { $0.1 == "IN" }
        let pool = (indian.isEmpty ? options : indian).map(\.0)
        return Array(pool.prefix(8))
    }

    @MainActor
    private static func run(_ q: String, types: MKLocalSearch.ResultType, region: MKCoordinateRegion) async -> [MKMapItem] {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        req.resultTypes = types
        req.region = region
        return (try? await MKLocalSearch(request: req).start().mapItems) ?? []
    }

    /// Towns, districts, regions and natural places count as geographic; businesses don't.
    private static func isGeographic(_ item: MKMapItem) -> Bool {
        guard let category = item.pointOfInterestCategory else { return true }   // an address/area result
        let natural: Set<MKPointOfInterestCategory> = [.nationalPark, .park, .beach, .campground, .marina]
        return natural.contains(category)
    }

    private static func address(_ pm: MKPlacemark, purpose: Purpose) -> String {
        var parts: [String] = []
        if purpose == .start {
            if let t = pm.thoroughfare, !t.isEmpty { parts.append(t) }
            if let s = pm.subLocality, !s.isEmpty { parts.append(s) }
        }
        if let l = pm.locality, !l.isEmpty, l != pm.name { parts.append(l) }
        if let a = pm.administrativeArea, !a.isEmpty { parts.append(a) }
        if purpose == .destination, let c = pm.country, !c.isEmpty, pm.isoCountryCode != "IN" { parts.append(c) }
        return parts.joined(separator: ", ")
    }

    private static func distanceKm(_ a: LocationOption, _ b: LocationOption) -> Double {
        CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: b.lat, longitude: b.lon)) / 1000
    }

    // MARK: Decision (pure — unit tested)

    /// Picks a place only when it's unambiguous; otherwise asks the rider to choose.
    nonisolated static func decide(query: String, options: [LocationOption], purpose: Purpose) -> Decision {
        guard !options.isEmpty else { return .none }
        // For destinations, geographic places win; businesses are a last resort and never auto-picked.
        let geographic = options.filter { $0.isGeographic ?? true }
        if purpose == .destination {
            if geographic.isEmpty { return .choose(Array(options.prefix(5))) }
            let q = normalize(query)
            let exact = geographic.filter { normalize($0.name) == q }
            if geographic.count == 1 { return .unique(geographic[0]) }
            if exact.count == 1 { return .unique(exact[0]) }
            return .choose(Array(geographic.prefix(5)))
        }
        // Start points may be landmarks or businesses ("Phoenix Mall"), so every result counts.
        if options.count == 1 { return .unique(options[0]) }
        let q = normalize(query)
        let exact = options.filter { normalize($0.name) == q }
        if exact.count == 1 { return .unique(exact[0]) }
        return .choose(Array(options.prefix(5)))
    }

    nonisolated static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
            .folding(options: [.diacriticInsensitive], locale: .current)
            .components(separatedBy: ",").first ?? ""
        let kept = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(kept))
            .split(separator: " ").filter { $0 != "the" }.joined(separator: " ")
    }
}
