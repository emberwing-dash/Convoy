import SwiftUI

// MARK: - Bike Model

struct GarageBike: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var make: String          // e.g. "Honda"
    var model: String         // e.g. "Shine 125"
    var year: Int             // e.g. 2026
    var nickname: String?     // optional user label
    var regNumber: String?    // e.g. "KA 01 RK 3500"
    var odometer: Int?        // km
    var color: String?        // e.g. "Pearl Amazing White"
    var category: String?     // e.g. "Commuter"
    var engineCC: Int?
    var fuelType: String?     // "Petrol" / "Electric"
    var powerBHP: Double?
    var torqueNM: Double?
    var weightKG: Int?
    var tankL: Double?
    var mileageKMPL: Double?
    var topSpeedKMH: Int?
    var aboutGeneration: String?
    var lineage: String?
    var availableColors: [String] = []
    var addedDate: Date = Date()

    var displayName: String { "\(make) \(model)" }
    var displayYear: String { "\(year)" }
}

// MARK: - Document Model

enum DocType: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case insurance = "Insurance"
    case puc = "PUC Certificate"
    case rc = "RC (Registration Certificate)"
    case fitness = "Fitness Certificate"
    case pollution = "Pollution Certificate"
    case other = "Other"

    var icon: String {
        switch self {
        case .insurance: return "shield.fill"
        case .puc:       return "leaf.fill"
        case .rc:        return "doc.fill"
        case .fitness:   return "heart.fill"
        case .pollution: return "wind"
        case .other:     return "doc.text.fill"
        }
    }

    var color: Color {
        switch self {
        case .insurance: return .green
        case .puc:       return Color(hex: 0x34C759)
        case .rc:        return Color(hex: 0x007AFF)
        case .fitness:   return Color(hex: 0xFF9500)
        case .pollution: return Color(hex: 0x30D158)
        case .other:     return .gray
        }
    }
}

struct BikeDocument: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var bikeId: UUID
    var type: DocType
    var expiryDate: Date?
    var noExpiry: Bool = false
    var documentURL: String?
    var addedDate: Date = Date()

    var daysUntilExpiry: Int? {
        guard !noExpiry, let exp = expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: exp).day
    }
    var isExpiringSoon: Bool { (daysUntilExpiry ?? 999) < 60 }
    var isExpired: Bool { (daysUntilExpiry ?? 999) < 0 }
}

// MARK: - Service / Accessory Model

struct ServiceEntry: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var bikeId: UUID
    var title: String          // e.g. "Oil Change"
    var date: Date
    var odometerKM: Int?
    var cost: Double?
    var notes: String?
    var nextDueKM: Int?
    var nextDueDate: Date?
}

struct AccessoryItem: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var bikeId: UUID
    var name: String
    var brand: String?
    var cost: Double?
    var addedDate: Date = Date()
    var notes: String?
}

// MARK: - Gear Model

enum GearType: String, Codable, CaseIterable {
    case helmet = "Helmet"
    case jacket = "Jacket"
    case gloves = "Gloves"
    case boots  = "Boots"
    case pants  = "Pants"
    case suit   = "Suit"
    case other  = "Other"

    var icon: String {
        switch self {
        case .helmet:  return "helmet"       // SF or fallback
        case .jacket:  return "tshirt.fill"
        case .gloves:  return "hand.raised.fill"
        case .boots:   return "shoeprints.fill"
        case .pants:   return "rectangle.portrait.fill"
        case .suit:    return "figure.stand"
        case .other:   return "bag.fill"
        }
    }

    var sfIcon: String {
        switch self {
        case .helmet:  return "circle.hexagongrid.fill"
        case .jacket:  return "tshirt.fill"
        case .gloves:  return "hand.raised.fill"
        case .boots:   return "shoe.fill"
        case .pants:   return "rectangle.portrait.fill"
        case .suit:    return "figure.stand"
        case .other:   return "bag.fill"
        }
    }
}

enum GearCondition: String, Codable, CaseIterable {
    case new = "New"
    case likeNew = "Like New"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
}

struct GearItem: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var type: GearType
    var name: String
    var brand: String?
    var size: String?
    var condition: GearCondition = .new
    var cost: Double?
    var quantity: Int = 1
    var hasWarranty: Bool = false
    var warrantyExpiry: Date?
    var purchaseDate: Date = Date()
    var notes: String?
}

// MARK: - Cost Tracking

struct CostEntry: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var bikeId: UUID
    var category: String       // "Fuel", "Service", "Insurance", "Accessories", "Other"
    var amount: Double
    var date: Date
    var notes: String?
}

// MARK: - Popular Bikes Catalog (static seed for Add Bike flow)

struct CatalogBike: Identifiable, Hashable {
    let id = UUID()
    let make: String
    let model: String
    let category: String
    let engineCC: Int
    let powerBHP: Double?
    let torqueNM: Double?
    let weightKG: Int?
    let tankL: Double?
    let mileageKMPL: Double?
    let topSpeedKMH: Int?
    let fuelType: String
    let aboutGeneration: String?
    let lineage: String?
    let availableColors: [String]

    var displayName: String { "\(make) \(model)" }
    var categoryAndCC: String { "\(category) · \(engineCC)cc" }
}

// swiftlint:disable line_length
let popularBikesCatalog: [CatalogBike] = [
    CatalogBike(make: "Honda",          model: "Shine 125",         category: "Commuter",   engineCC: 124,  powerBHP: 10.7, torqueNM: 11,   weightKG: 113, tankL: 10.5, mileageKMPL: 65,  topSpeedKMH: 95,  fuelType: "Petrol", aboutGeneration: "BS6 PGM-FI engine, ACG starter for silent start, sportier graphics. OBD2 from Apr 2023.", lineage: "Honda Shine (2006–2020, Original BS3/BS4)", availableColors: ["Athletic Blue Metallic", "Pearl Amazing White", "Decent Blue Metallic", "Imperial Red Metallic"]),
    CatalogBike(make: "Hero MotoCorp",  model: "Splendor Plus",     category: "Commuter",   engineCC: 97,   powerBHP: 8.0,  torqueNM: 8.05, weightKG: 112, tankL: 9.8,  mileageKMPL: 70,  topSpeedKMH: 85,  fuelType: "Petrol", aboutGeneration: "India's best-selling motorcycle for decades. OBD2B, i3S idle-stop system.", lineage: nil, availableColors: ["Black with Candy Blazing Red", "Heavy Grey"]),
    CatalogBike(make: "Honda",          model: "Activa 6G",         category: "Scooter",    engineCC: 110,  powerBHP: 7.68, torqueNM: 9.0,  weightKG: 108, tankL: 5.3,  mileageKMPL: 55,  topSpeedKMH: 80,  fuelType: "Petrol", aboutGeneration: "India's #1 scooter with ACG starter, OBD2B compliance and enhanced fuel efficiency.", lineage: nil, availableColors: ["Matte Maroon Metallic", "Pearl Precious White", "Rebel Red Metallic"]),
    CatalogBike(make: "Royal Enfield",  model: "Classic 350",       category: "Classic",    engineCC: 349,  powerBHP: 20.2, torqueNM: 27,   weightKG: 195, tankL: 13.0, mileageKMPL: 35,  topSpeedKMH: 130, fuelType: "Petrol", aboutGeneration: "Iconic retro design, air-cooled SOHC engine, tripper navigation pod available.", lineage: nil, availableColors: ["Marsh Grey", "Gunmetal Grey", "Halcyon Black"]),
    CatalogBike(make: "KTM",            model: "390 Adventure",     category: "Adventure",  engineCC: 373,  powerBHP: 43.5, torqueNM: 37,   weightKG: 177, tankL: 14.5, mileageKMPL: 28,  topSpeedKMH: 165, fuelType: "Petrol", aboutGeneration: "Long-travel suspension, cornering ABS, traction control, Quickshifter+.", lineage: nil, availableColors: ["Black", "White"]),
    CatalogBike(make: "Hero MotoCorp",  model: "HF Deluxe",         category: "Commuter",   engineCC: 97,   powerBHP: 8.0,  torqueNM: 8.05, weightKG: 109, tankL: 9.0,  mileageKMPL: 65,  topSpeedKMH: 80,  fuelType: "Petrol", aboutGeneration: "Budget commuter with i3S technology and 5-step adjustable suspension.", lineage: nil, availableColors: ["Black with Self Silver", "Heavy Grey"]),
    CatalogBike(make: "TVS",            model: "Jupiter",            category: "Scooter",    engineCC: 113,  powerBHP: 7.4,  torqueNM: 9.4,  weightKG: 103, tankL: 5.0,  mileageKMPL: 50,  topSpeedKMH: 80,  fuelType: "Petrol", aboutGeneration: "India's #2 scooter, Eco-Thrust fuel injection, voice assist and bluetooth connectivity.", lineage: nil, availableColors: ["Mystic Gold", "Titanium Grey", "Royal Wine"]),
    CatalogBike(make: "Bajaj",          model: "Pulsar NS200",      category: "Naked",      engineCC: 199,  powerBHP: 24.5, torqueNM: 18.74,weightKG: 160, tankL: 12.0, mileageKMPL: 35,  topSpeedKMH: 136, fuelType: "Petrol", aboutGeneration: "Liquid-cooled perimeter frame, slipper clutch, MRF Zapper rubber.", lineage: nil, availableColors: ["Burnt Red", "Pewter Grey"]),
    CatalogBike(make: "Yamaha",         model: "R15 V4",             category: "Sport",      engineCC: 155,  powerBHP: 18.4, torqueNM: 14.2, weightKG: 142, tankL: 11.0, mileageKMPL: 45,  topSpeedKMH: 135, fuelType: "Petrol", aboutGeneration: "Deltabox frame, YZF DNA styling, variable valve actuation (VVA), quick shifter.", lineage: nil, availableColors: ["Racing Blue", "Dark Night", "Metallic Red"]),
    CatalogBike(make: "BMW",            model: "G 310 R",            category: "Naked",      engineCC: 313,  powerBHP: 34.0, torqueNM: 28,   weightKG: 158, tankL: 11.0, mileageKMPL: 30,  topSpeedKMH: 143, fuelType: "Petrol", aboutGeneration: "Reverse-inclined engine for low center of gravity, ABS, and BMW brand prestige.", lineage: nil, availableColors: ["Racing Red", "Cosmic Black"]),
]
// swiftlint:enable line_length

// MARK: - Garage Store (simple @Observable store for the garage)

@Observable
final class GarageStore {
    static let shared = GarageStore()

    var bikes: [GarageBike] = []
    var gearItems: [GearItem] = []
    var documents: [BikeDocument] = []
    var services: [ServiceEntry] = []
    var accessories: [AccessoryItem] = []
    var costs: [CostEntry] = []

    private let bikesKey        = "garage_bikes_v1"
    private let gearKey         = "garage_gear_v1"
    private let docsKey         = "garage_docs_v1"
    private let servicesKey     = "garage_services_v1"
    private let accessoriesKey  = "garage_accessories_v1"
    private let costsKey        = "garage_costs_v1"

    private init() { load() }

    // MARK: Persistence

    func load() {
        bikes        = decode([GarageBike].self,      key: bikesKey)       ?? []
        gearItems    = decode([GearItem].self,        key: gearKey)        ?? []
        documents    = decode([BikeDocument].self,    key: docsKey)        ?? []
        services     = decode([ServiceEntry].self,    key: servicesKey)    ?? []
        accessories  = decode([AccessoryItem].self,   key: accessoriesKey) ?? []
        costs        = decode([CostEntry].self,       key: costsKey)       ?? []

        if bikes.isEmpty {
            bikes = [
                GarageBike(
                    make: "Honda",
                    model: "Shine 125",
                    year: 2026,
                    nickname: "Daily Commute",
                    regNumber: "KA 01 RK 3500",
                    odometer: nil,
                    color: "Athletic Blue Metallic, Pearl Amazing White, Decent Blue Metallic",
                    category: "Commuter",
                    engineCC: 124,
                    fuelType: "Petrol · OBD2B",
                    powerBHP: 10.7,
                    torqueNM: 11,
                    weightKG: 113,
                    tankL: 10.5,
                    mileageKMPL: 65,
                    topSpeedKMH: 95,
                    aboutGeneration: "BS6 PGM-FI engine, optimized power delivery, ACG starter for silent start, sportier graphics. Outcells Activa 125 in many months. OBD2 from Apr 2023.",
                    lineage: "Honda Shine (2006-2020, Original BS3/BS4)",
                    availableColors: ["Athletic Blue Metallic", "Pearl Amazing White", "Decent Blue Metallic", "Imperial Red Metallic"]
                ),
                GarageBike(
                    make: "KTM",
                    model: "390 Adventure",
                    year: 2024,
                    nickname: "Adventure Beast",
                    regNumber: "KA 04 KT 0390",
                    odometer: 8400,
                    color: "Orange / White",
                    category: "Adventure",
                    engineCC: 373,
                    fuelType: "Petrol · OBD2B",
                    powerBHP: 43.5,
                    torqueNM: 37,
                    weightKG: 177,
                    tankL: 14.5,
                    mileageKMPL: 28,
                    topSpeedKMH: 165,
                    aboutGeneration: "Long-travel WP Apex suspension, cornering ABS, offroad mode, TFT display.",
                    lineage: "KTM Adventure Series",
                    availableColors: ["Orange", "White", "Dark Galvano"]
                ),
                GarageBike(
                    make: "Royal Enfield",
                    model: "Classic 350",
                    year: 2023,
                    nickname: "Bullet",
                    regNumber: "KA 05 RE 3500",
                    odometer: 18420,
                    color: "Signals Marsh Grey",
                    category: "Classic",
                    engineCC: 349,
                    fuelType: "Petrol",
                    powerBHP: 20.2,
                    torqueNM: 27,
                    weightKG: 195,
                    tankL: 13.0,
                    mileageKMPL: 35,
                    topSpeedKMH: 130,
                    aboutGeneration: "Iconic J-series engine, twin downtube spine frame, dual-channel ABS.",
                    lineage: "Royal Enfield Classic heritage since 1948",
                    availableColors: ["Marsh Grey", "Gunmetal Grey", "Halcyon Black"]
                )
            ]
            save()
        }

        if gearItems.isEmpty {
            gearItems = [
                GearItem(
                    type: .helmet,
                    name: "AGV Helmet",
                    brand: "AGV",
                    size: "L",
                    condition: .new,
                    cost: 32000,
                    quantity: 1,
                    hasWarranty: true,
                    warrantyExpiry: Calendar.current.date(byAdding: .year, value: 2, to: Date())
                )
            ]
            save()
        }
    }

    func save() {
        encode(bikes,       key: bikesKey)
        encode(gearItems,   key: gearKey)
        encode(documents,   key: docsKey)
        encode(services,    key: servicesKey)
        encode(accessories, key: accessoriesKey)
        encode(costs,       key: costsKey)
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: CRUD

    func addBike(_ bike: GarageBike)         { bikes.insert(bike, at: 0); save() }
    func removeBike(id: UUID)               { bikes.removeAll { $0.id == id }; save() }
    func updateBike(_ bike: GarageBike)     { if let i = bikes.firstIndex(where: { $0.id == bike.id }) { bikes[i] = bike; save() } }

    func addGear(_ item: GearItem)           { gearItems.insert(item, at: 0); save() }
    func removeGear(id: UUID)               { gearItems.removeAll { $0.id == id }; save() }

    func addDoc(_ doc: BikeDocument)         { documents.insert(doc, at: 0); save() }
    func removeDoc(id: UUID)                { documents.removeAll { $0.id == id }; save() }

    func addService(_ s: ServiceEntry)       { services.insert(s, at: 0); save() }
    func removeService(id: UUID)            { services.removeAll { $0.id == id }; save() }

    func addAccessory(_ a: AccessoryItem)    { accessories.insert(a, at: 0); save() }
    func removeAccessory(id: UUID)          { accessories.removeAll { $0.id == id }; save() }

    func addCost(_ c: CostEntry)             { costs.insert(c, at: 0); save() }
    func removeCost(id: UUID)               { costs.removeAll { $0.id == id }; save() }

    // MARK: Helpers

    func docs(for bikeId: UUID) -> [BikeDocument]      { documents.filter { $0.bikeId == bikeId } }
    func services(for bikeId: UUID) -> [ServiceEntry]  { services.filter { $0.bikeId == bikeId } }
    func accessories(for bikeId: UUID) -> [AccessoryItem] { accessories.filter { $0.bikeId == bikeId } }
    func costs(for bikeId: UUID) -> [CostEntry]        { costs.filter { $0.bikeId == bikeId } }
}

