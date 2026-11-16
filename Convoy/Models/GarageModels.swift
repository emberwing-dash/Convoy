import SwiftUI

// MARK: - Bike Model

struct GarageBike: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var make: String          // e.g. "Honda"
    var model: String         // e.g. "CBR-150R"
    var year: Int             // e.g. 2024
    var nickname: String?     // optional user label
    var regNumber: String?    // e.g. "KA 01 EK 1500"
    var odometer: Int?        // km
    var color: String?        // e.g. "Honda Racing Red"
    var category: String?     // e.g. "Sport"
    var engineCC: Int?
    var fuelType: String?     // "Petrol · PGM-FI"
    var powerBHP: Double?
    var torqueNM: Double?
    var weightKG: Int?
    var tankL: Double?
    var mileageKMPL: Double?
    var topSpeedKMH: Int?
    var aboutGeneration: String?
    var lineage: String?
    var availableColors: [String] = []
    var imageURL: String?
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
    var title: String          // e.g. "Engine Oil & Filter Change"
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
        case .helmet:  return "circle.hexagongrid.fill"
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

// MARK: - Popular Bikes Catalog (Motorcycles & Mopeds with Real Images - No Scooters)

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
    var imageURL: String? = nil
    var year: Int? = 2024

    var displayName: String { "\(make) \(model)" }
    var categoryAndCC: String { "\(category) · \(engineCC)cc" }
}

let popularBikesCatalog: [CatalogBike] = [
    CatalogBike(
        make: "Hero",
        model: "Passion X-Pro 2018",
        category: "Commuter",
        engineCC: 110,
        powerBHP: 9.4,
        torqueNM: 9.0,
        weightKG: 119,
        tankL: 9.2,
        mileageKMPL: 65.0,
        topSpeedKMH: 90,
        fuelType: "Petrol",
        aboutGeneration: "110cc TOD (Torque on Demand) engine with i3S technology.",
        lineage: "Hero Passion Series",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Hero/Hero%20Passion%20X-Pro%202018.png",
        year: 2018
    ),
    CatalogBike(
        make: "Hero",
        model: "Xpulse 200 2019",
        category: "Adventure",
        engineCC: 199,
        powerBHP: 17.8,
        torqueNM: 16.45,
        weightKG: 154,
        tankL: 13.0,
        mileageKMPL: 40.0,
        topSpeedKMH: 115,
        fuelType: "Petrol",
        aboutGeneration: "Dual-purpose motorcycle with 220mm ground clearance and long travel suspension.",
        lineage: "Hero Impulse Heritage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Hero/Hero%20Xpulse%20200%202019.png",
        year: 2019
    ),
    CatalogBike(
        make: "Hero",
        model: "Xpulse 200 4V 2021",
        category: "Adventure",
        engineCC: 199,
        powerBHP: 19.1,
        torqueNM: 17.35,
        weightKG: 158,
        tankL: 13.0,
        mileageKMPL: 40.0,
        topSpeedKMH: 120,
        fuelType: "Petrol",
        aboutGeneration: "4-valve oil-cooled engine for superior mid and top-end grunt.",
        lineage: "Hero Xpulse Lineage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Hero/Hero%20Xpulse%20200%204V%202021.png",
        year: 2021
    ),
    CatalogBike(
        make: "Hero",
        model: "Xpulse 200T 2019",
        category: "Tourer",
        engineCC: 199,
        powerBHP: 17.8,
        torqueNM: 16.45,
        weightKG: 150,
        tankL: 13.0,
        mileageKMPL: 40.0,
        topSpeedKMH: 115,
        fuelType: "Petrol",
        aboutGeneration: "Touring-oriented road version with 17-inch alloy wheels and relaxed ergonomics.",
        lineage: "Hero Tourer Series",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Hero/Hero%20Xpulse%20200T%202019.png",
        year: 2019
    ),
    CatalogBike(
        make: "Hero",
        model: "Xtreme 160R 2020",
        category: "Naked / Street",
        engineCC: 163,
        powerBHP: 15.0,
        torqueNM: 14.0,
        weightKG: 138,
        tankL: 12.0,
        mileageKMPL: 48.0,
        topSpeedKMH: 115,
        fuelType: "Petrol",
        aboutGeneration: "Lightweight streetfighter with full LED lighting and inverted LCD cluster.",
        lineage: "Hero CBZ / Xtreme Heritage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Hero/Hero%20Xtreme%20160R%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "Hero",
        model: "Xtreme 200R 2018",
        category: "Naked / Street",
        engineCC: 199,
        powerBHP: 18.1,
        torqueNM: 17.1,
        weightKG: 148,
        tankL: 12.5,
        mileageKMPL: 40.0,
        topSpeedKMH: 118,
        fuelType: "Petrol",
        aboutGeneration: "City-focused 200cc commuter roadster with single-channel ABS.",
        lineage: "Hero Xtreme Heritage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Hero/Hero%20Xtreme%20200R%202018.png",
        year: 2018
    ),
    CatalogBike(
        make: "Hero",
        model: "Xtreme Sports 2015",
        category: "Commuter",
        engineCC: 149,
        powerBHP: 15.6,
        torqueNM: 13.5,
        weightKG: 146,
        tankL: 12.1,
        mileageKMPL: 50.0,
        topSpeedKMH: 107,
        fuelType: "Petrol",
        aboutGeneration: "Sporty variant of the CBZ Xtreme with sharp aerodynamic wolf-eye headlamp.",
        lineage: "Hero CBZ Heritage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Hero/Hero%20Xtreme%20Sports%202015.png",
        year: 2015
    ),
    CatalogBike(
        make: "Honda",
        model: "Africa Twin 2022 Adventure Sport DCT",
        category: "Adventure",
        engineCC: 1084,
        powerBHP: 98.0,
        torqueNM: 103.0,
        weightKG: 248,
        tankL: 24.8,
        mileageKMPL: 18.0,
        topSpeedKMH: 200,
        fuelType: "Petrol",
        aboutGeneration: "Dual Clutch Transmission (DCT), 6-axis IMU, Apple CarPlay & touch TFT screen.",
        lineage: "Honda Africa Twin Rally DNA",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Honda/Honda%20Africa%20Twin%202022%20Adventure%20Sport%20DCT.png",
        year: 2022
    ),
    CatalogBike(
        make: "Honda",
        model: "CB300F 2022 DLX PRO",
        category: "Naked / Street",
        engineCC: 293,
        powerBHP: 24.1,
        torqueNM: 25.6,
        weightKG: 153,
        tankL: 14.0,
        mileageKMPL: 32.0,
        topSpeedKMH: 135,
        fuelType: "Petrol",
        aboutGeneration: "Oil-cooled 4-valve engine, assist & slipper clutch, Honda Selectable Torque Control.",
        lineage: "Honda CB Street Series",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Honda/Honda%20CB300F%202022%20DLX%20PRO.png",
        year: 2022
    ),
    CatalogBike(
        make: "Honda",
        model: "CB300R 2022 STD",
        category: "Naked / Street",
        engineCC: 286,
        powerBHP: 31.1,
        torqueNM: 27.5,
        weightKG: 146,
        tankL: 9.7,
        mileageKMPL: 30.0,
        topSpeedKMH: 150,
        fuelType: "Petrol",
        aboutGeneration: "Featherweight naked café racer with 41mm Showa upside-down front forks.",
        lineage: "Honda Neo Sports Café",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Honda/Honda%20CB300R%202022%20STD.png",
        year: 2022
    ),
    CatalogBike(
        make: "Honda",
        model: "CB650R 2022 STD",
        category: "Naked / Street",
        engineCC: 649,
        powerBHP: 85.8,
        torqueNM: 57.5,
        weightKG: 206,
        tankL: 15.4,
        mileageKMPL: 20.0,
        topSpeedKMH: 210,
        fuelType: "Petrol",
        aboutGeneration: "Inline-4 cylinder engine with signature cascading header pipes and Neo Sports styling.",
        lineage: "Honda CB Four Cylinder Legacy",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Honda/Honda%20CB650R%202022%20STD.png",
        year: 2022
    ),
    CatalogBike(
        make: "Honda",
        model: "CBR650R 2022 STD",
        category: "Sports",
        engineCC: 649,
        powerBHP: 85.8,
        torqueNM: 57.5,
        weightKG: 211,
        tankL: 15.4,
        mileageKMPL: 20.0,
        topSpeedKMH: 220,
        fuelType: "Petrol",
        aboutGeneration: "Full-fairing inline-4 middleweight supersport with HSTC traction control.",
        lineage: "Honda Fireblade / CBR Lineage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Honda/Honda%20CBR650R%202022%20STD.png",
        year: 2022
    ),
    CatalogBike(
        make: "Royal Enfield",
        model: "Bullet 2013",
        category: "Retro / Classic",
        engineCC: 346,
        powerBHP: 19.8,
        torqueNM: 28.0,
        weightKG: 183,
        tankL: 13.5,
        mileageKMPL: 38.0,
        topSpeedKMH: 110,
        fuelType: "Petrol",
        aboutGeneration: "Cast-iron thumper heritage modernized with the Unit Construction Engine (UCE).",
        lineage: "Royal Enfield Bullet 1932 Legacy",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Royal%20Enfield/Royal%20Enfield%20Bullet%202013.png",
        year: 2013
    ),
    CatalogBike(
        make: "Royal Enfield",
        model: "Classic 350 2021",
        category: "Retro / Classic",
        engineCC: 349,
        powerBHP: 20.2,
        torqueNM: 27.0,
        weightKG: 195,
        tankL: 13.0,
        mileageKMPL: 35.0,
        topSpeedKMH: 125,
        fuelType: "Petrol",
        aboutGeneration: "J-series counterbalanced engine, revised chassis and optional Tripper navigation.",
        lineage: "Royal Enfield Classic Heritage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Royal%20Enfield/Royal%20Enfield%20Classic%20350%202021.png",
        year: 2021
    ),
    CatalogBike(
        make: "Royal Enfield",
        model: "Continental GT 650 2018",
        category: "Café Racer",
        engineCC: 648,
        powerBHP: 47.0,
        torqueNM: 52.0,
        weightKG: 198,
        tankL: 12.5,
        mileageKMPL: 25.0,
        topSpeedKMH: 165,
        fuelType: "Petrol",
        aboutGeneration: "Parallel twin 270-degree crankshaft, Harris Performance double cradle chassis.",
        lineage: "1960s British Café Racer",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Royal%20Enfield/Royal%20Enfield%20Continental%20GT%20650%202018.png",
        year: 2018
    ),
    CatalogBike(
        make: "Royal Enfield",
        model: "Himalayan 2021",
        category: "Adventure",
        engineCC: 411,
        powerBHP: 24.3,
        torqueNM: 32.0,
        weightKG: 199,
        tankL: 15.0,
        mileageKMPL: 32.0,
        topSpeedKMH: 125,
        fuelType: "Petrol",
        aboutGeneration: "Long travel 200mm suspension, switchable ABS, Tripper navigation pod.",
        lineage: "Royal Enfield Adventure Platform",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Royal%20Enfield/Royal%20Enfield%20Himalayan%202021.png",
        year: 2021
    ),
    CatalogBike(
        make: "Royal Enfield",
        model: "Hunter 350 2022",
        category: "Roadster",
        engineCC: 349,
        powerBHP: 20.2,
        torqueNM: 27.0,
        weightKG: 181,
        tankL: 13.0,
        mileageKMPL: 36.0,
        topSpeedKMH: 120,
        fuelType: "Petrol",
        aboutGeneration: "Agile compact roadster chassis with 17-inch alloy wheels and sharp rake angle.",
        lineage: "Royal Enfield J-Series",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Royal%20Enfield/Royal%20Enfield%20Hunter%20350%202022.png",
        year: 2022
    ),
    CatalogBike(
        make: "Royal Enfield",
        model: "Meteor 350 2020",
        category: "Cruiser",
        engineCC: 349,
        powerBHP: 20.2,
        torqueNM: 27.0,
        weightKG: 191,
        tankL: 15.0,
        mileageKMPL: 35.0,
        topSpeedKMH: 120,
        fuelType: "Petrol",
        aboutGeneration: "Dedicated highway cruiser platform with low seat height and relaxed ergonomics.",
        lineage: "Royal Enfield Thunderbird Lineage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Royal%20Enfield/Royal%20Enfield%20Meteor%20350%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "Royal Enfield",
        model: "Thunderbird 350X 2018",
        category: "Cruiser",
        engineCC: 346,
        powerBHP: 19.8,
        torqueNM: 28.0,
        weightKG: 195,
        tankL: 20.0,
        mileageKMPL: 35.0,
        topSpeedKMH: 115,
        fuelType: "Petrol",
        aboutGeneration: "Urban custom cruiser with tubeless tyres, bright color scheme and ",
        lineage: "Thunderbird Heritage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Royal%20Enfield/Royal%20Enfield%20Thunderbird%20350X%202018.png",
        year: 2018
    ),
    CatalogBike(
        make: "Suzuki",
        model: "Gixxer 2020",
        category: "Naked / Street",
        engineCC: 155,
        powerBHP: 13.4,
        torqueNM: 13.8,
        weightKG: 141,
        tankL: 12.0,
        mileageKMPL: 45.0,
        topSpeedKMH: 115,
        fuelType: "Petrol",
        aboutGeneration: "Sharp European design, LED headlamp and SEP (Suzuki Eco Performance) engine.",
        lineage: "Suzuki GSX-S Heritage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Suzuki/Suzuki%20Gixxer%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "Suzuki",
        model: "Gixxer 250 2020",
        category: "Naked / Street",
        engineCC: 249,
        powerBHP: 26.1,
        torqueNM: 22.2,
        weightKG: 156,
        tankL: 12.0,
        mileageKMPL: 35.0,
        topSpeedKMH: 145,
        fuelType: "Petrol",
        aboutGeneration: "SOCS (Suzuki Oil Cooling System) high-efficiency liquid/oil-cooled engine.",
        lineage: "Suzuki Gixxer 250 Platform",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Suzuki/Suzuki%20Gixxer%20250%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "Suzuki",
        model: "Gixxer SF 2020",
        category: "Sports",
        engineCC: 155,
        powerBHP: 13.4,
        torqueNM: 13.8,
        weightKG: 146,
        tankL: 12.0,
        mileageKMPL: 45.0,
        topSpeedKMH: 120,
        fuelType: "Petrol",
        aboutGeneration: "Aerodynamic clip-on sport fairing inspired by European design trends.",
        lineage: "Suzuki Hayabusa/GSX-R DNA",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Suzuki/Suzuki%20Gixxer%20SF%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "Suzuki",
        model: "GSX-S750 2018",
        category: "Naked / Street",
        engineCC: 749,
        powerBHP: 112.6,
        torqueNM: 81.0,
        weightKG: 215,
        tankL: 16.0,
        mileageKMPL: 18.0,
        topSpeedKMH: 225,
        fuelType: "Petrol",
        aboutGeneration: "Apex Predator inline-4 naked with 3-mode traction control and Nissin radial brakes.",
        lineage: "Suzuki GSX-R750 Heritage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Suzuki/Suzuki%20GSX-S750%202018.png",
        year: 2018
    ),
    CatalogBike(
        make: "Suzuki",
        model: "Intruder 150 2020",
        category: "Cruiser",
        engineCC: 155,
        powerBHP: 13.4,
        torqueNM: 13.8,
        weightKG: 152,
        tankL: 11.0,
        mileageKMPL: 44.0,
        topSpeedKMH: 110,
        fuelType: "Petrol",
        aboutGeneration: "Modern cruiser styling inspired by the flagship Intruder M1800R.",
        lineage: "Suzuki Intruder M1800R Lineage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Suzuki/Suzuki%20Intruder%20150%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "Suzuki",
        model: "Katana 2022",
        category: "Retro / Classic",
        engineCC: 999,
        powerBHP: 150.0,
        torqueNM: 106.0,
        weightKG: 215,
        tankL: 12.0,
        mileageKMPL: 16.0,
        topSpeedKMH: 245,
        fuelType: "Petrol",
        aboutGeneration: "Legendary Japanese sword design reborn with GSX-R1000 K5-derived engine.",
        lineage: "1981 Hans Muth Katana Legend",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Suzuki/Suzuki%20Katana%202022.png",
        year: 2022
    ),
    CatalogBike(
        make: "Suzuki",
        model: "V-Strom SX 2022",
        category: "Adventure",
        engineCC: 249,
        powerBHP: 26.1,
        torqueNM: 22.2,
        weightKG: 167,
        tankL: 12.0,
        mileageKMPL: 36.0,
        topSpeedKMH: 140,
        fuelType: "Petrol",
        aboutGeneration: "19-inch front wheel sports adventure tourer with high ground clearance.",
        lineage: "Suzuki V-Strom Dakar DNA",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Suzuki/Suzuki%20V-Strom%20SX%202022.png",
        year: 2022
    ),
    CatalogBike(
        make: "TVS",
        model: "Apache RTR 160 2020",
        category: "Naked / Street",
        engineCC: 159,
        powerBHP: 15.3,
        torqueNM: 13.9,
        weightKG: 139,
        tankL: 12.0,
        mileageKMPL: 47.0,
        topSpeedKMH: 110,
        fuelType: "Petrol",
        aboutGeneration: "Race-tuned fuel injection (RT-Fi) with Glide Through Technology (GTT).",
        lineage: "TVS Racing Heritage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/TVS/TVS%20Apache%20RTR%20160%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "TVS",
        model: "Apache RTR 180 2020",
        category: "Naked / Street",
        engineCC: 177,
        powerBHP: 16.5,
        torqueNM: 15.5,
        weightKG: 141,
        tankL: 12.0,
        mileageKMPL: 42.0,
        topSpeedKMH: 114,
        fuelType: "Petrol",
        aboutGeneration: "Beast-inspired LED headlamps with race-derived chassis and dual disc brakes.",
        lineage: "TVS Racing RTR",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/TVS/TVS%20Apache%20RTR%20180%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "TVS",
        model: "Apache RTR 200 2019",
        category: "Naked / Street",
        engineCC: 197,
        powerBHP: 20.2,
        torqueNM: 16.8,
        weightKG: 152,
        tankL: 12.0,
        mileageKMPL: 38.0,
        topSpeedKMH: 128,
        fuelType: "Petrol",
        aboutGeneration: "Oil-cooled 4-valve combustion chamber with slipper clutch.",
        lineage: "TVS Apache Platform",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/TVS/TVS%20Apache%20RTR%20200%202019.png",
        year: 2019
    ),
    CatalogBike(
        make: "TVS",
        model: "Apache RTR 200 4V 2020",
        category: "Naked / Street",
        engineCC: 197,
        powerBHP: 20.5,
        torqueNM: 17.25,
        weightKG: 153,
        tankL: 12.0,
        mileageKMPL: 38.0,
        topSpeedKMH: 130,
        fuelType: "Petrol",
        aboutGeneration: "Multiple ride modes (Sport/Urban/Rain), Showa adjustable suspension and SmartXonnect.",
        lineage: "TVS Racing RTR 4V",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/TVS/TVS%20Apache%20RTR%20200%204V%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "TVS",
        model: "Radeon 2020",
        category: "Commuter",
        engineCC: 109,
        powerBHP: 8.08,
        torqueNM: 8.7,
        weightKG: 116,
        tankL: 10.0,
        mileageKMPL: 65.0,
        topSpeedKMH: 90,
        fuelType: "Petrol",
        aboutGeneration: "Dura-Life 110cc engine with Synchronized Braking Technology (SBT).",
        lineage: "TVS Commuter Series",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/TVS/TVS%20Radeon%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "Yamaha",
        model: "Fazer 2019",
        category: "Tourer",
        engineCC: 149,
        powerBHP: 13.0,
        torqueNM: 12.8,
        weightKG: 137,
        tankL: 12.0,
        mileageKMPL: 45.0,
        topSpeedKMH: 110,
        fuelType: "Petrol",
        aboutGeneration: "Semi-faired aerodynamic windshield tourer with Blue Core fuel injection.",
        lineage: "Yamaha FZ / Fazer Series",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Yamaha/Yamaha%20Fazer%202019.png",
        year: 2019
    ),
    CatalogBike(
        make: "Yamaha",
        model: "FZ 2020",
        category: "Naked / Street",
        engineCC: 149,
        powerBHP: 12.2,
        torqueNM: 13.6,
        weightKG: 135,
        tankL: 13.0,
        mileageKMPL: 48.0,
        topSpeedKMH: 112,
        fuelType: "Petrol",
        aboutGeneration: "Iconic muscular fuel tank, negative LCD cluster and standard single-channel ABS.",
        lineage: "Yamaha Lord of the Streets",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Yamaha/Yamaha%20FZ%202020.png",
        year: 2020
    ),
    CatalogBike(
        make: "Yamaha",
        model: "FZ 25 2019",
        category: "Naked / Street",
        engineCC: 249,
        powerBHP: 20.5,
        torqueNM: 20.1,
        weightKG: 153,
        tankL: 14.0,
        mileageKMPL: 37.0,
        topSpeedKMH: 134,
        fuelType: "Petrol",
        aboutGeneration: "Torquey 250cc oil-cooled single cylinder with dual-channel ABS.",
        lineage: "Yamaha Quarter-Liter FZ",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Yamaha/Yamaha%20FZ%2025%202019.png",
        year: 2019
    ),
    CatalogBike(
        make: "Yamaha",
        model: "FZ-X 2021",
        category: "Scrambler / Retro",
        engineCC: 149,
        powerBHP: 12.2,
        torqueNM: 13.3,
        weightKG: 139,
        tankL: 10.0,
        mileageKMPL: 45.0,
        topSpeedKMH: 110,
        fuelType: "Petrol",
        aboutGeneration: "Tough neo-retro crossover styling with round bi-functional LED headlight.",
        lineage: "Yamaha Neo-Retro Platform",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Yamaha/Yamaha%20FZ-X%202021.png",
        year: 2021
    ),
    CatalogBike(
        make: "Yamaha",
        model: "MT-09 2018",
        category: "Naked / Street",
        engineCC: 847,
        powerBHP: 113.4,
        torqueNM: 87.5,
        weightKG: 193,
        tankL: 14.0,
        mileageKMPL: 19.0,
        topSpeedKMH: 225,
        fuelType: "Petrol",
        aboutGeneration: "847cc CP3 crossplane 3-cylinder engine, quickshifter and D-Mode traction control.",
        lineage: "Yamaha Dark Side of Japan",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Yamaha/Yamaha%20MT-09%202018.png",
        year: 2018
    ),
    CatalogBike(
        make: "Yamaha",
        model: "Saluto 125 2019",
        category: "Commuter",
        engineCC: 125,
        powerBHP: 8.2,
        torqueNM: 10.1,
        weightKG: 114,
        tankL: 7.6,
        mileageKMPL: 65.0,
        topSpeedKMH: 90,
        fuelType: "Petrol",
        aboutGeneration: "Ultra-lightweight 125cc commuter engineered for maximum city fuel economy.",
        lineage: "Yamaha Commuter Lineage",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Yamaha/Yamaha%20Saluto%20125%202019.png",
        year: 2019
    ),
    CatalogBike(
        make: "Yamaha",
        model: "XSR 900 2018",
        category: "Scrambler / Retro",
        engineCC: 847,
        powerBHP: 113.4,
        torqueNM: 87.5,
        weightKG: 195,
        tankL: 14.0,
        mileageKMPL: 19.0,
        topSpeedKMH: 225,
        fuelType: "Petrol",
        aboutGeneration: "Retro café roadster wrapping the CP3 triple motor in handcrafted brushed aluminum.",
        lineage: "Yamaha Faster Sons",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Yamaha/Yamaha%20XSR%20900%202018.png",
        year: 2018
    ),
    CatalogBike(
        make: "Yamaha",
        model: "YZF-R1 2018",
        category: "Sports",
        engineCC: 998,
        powerBHP: 197.2,
        torqueNM: 112.4,
        weightKG: 199,
        tankL: 17.0,
        mileageKMPL: 14.0,
        topSpeedKMH: 299,
        fuelType: "Petrol",
        aboutGeneration: "Crossplane CP4 inline-4 liter-class superbike with 6-axis IMU and slide control.",
        lineage: "Yamaha MotoGP YZR-M1 DNA",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Yamaha/Yamaha%20YZF-R1%202018.png",
        year: 2018
    ),
    CatalogBike(
        make: "Yamaha",
        model: "YZF-R15 V3.0 2020",
        category: "Sports",
        engineCC: 155,
        powerBHP: 18.3,
        torqueNM: 14.1,
        weightKG: 142,
        tankL: 11.0,
        mileageKMPL: 45.0,
        topSpeedKMH: 136,
        fuelType: "Petrol",
        aboutGeneration: "Variable Valve Actuation (VVA), assist & slipper clutch and Deltabox frame.",
        lineage: "Yamaha YZF Supersport Legacy",
        availableColors: ["Stock Finish"],
        imageURL: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/bike/Yamaha/Yamaha%20YZF-R15%20V3.0%202020.png",
        year: 2020
    ),
]
// swiftlint:enable line_length

// MARK: - Garage Store

@Observable
final class GarageStore {
    static let shared = GarageStore()

    var bikes: [GarageBike] = []
    var gearItems: [GearItem] = []
    var documents: [BikeDocument] = []
    var services: [ServiceEntry] = []
    var accessories: [AccessoryItem] = []
    var costs: [CostEntry] = []

    private let bikesKey        = "garage_bikes_v6"
    private let gearKey         = "garage_gear_v6"
    private let docsKey         = "garage_docs_v6"
    private let servicesKey     = "garage_services_v6"
    private let accessoriesKey  = "garage_accessories_v6"
    private let costsKey        = "garage_costs_v6"

    private init() { load() }

    // MARK: Persistence

    func load() {
        bikes        = decode([GarageBike].self,      key: bikesKey)       ?? []
        gearItems    = decode([GearItem].self,        key: gearKey)        ?? []
        documents    = decode([BikeDocument].self,    key: docsKey)        ?? []
        services     = decode([ServiceEntry].self,    key: servicesKey)    ?? []
        accessories  = decode([AccessoryItem].self,   key: accessoriesKey) ?? []
        costs        = decode([CostEntry].self,       key: costsKey)       ?? []

                // Garage starts empty
        // if empty, user adds bikes from the catalog

        if gearItems.isEmpty {
            gearItems = [
                GearItem(
                    type: .helmet,
                    name: "Shoei X-Fifteen",
                    brand: "Shoei",
                    size: "L",
                    condition: .new,
                    cost: 65000,
                    quantity: 1,
                    hasWarranty: true,
                    warrantyExpiry: Calendar.current.date(byAdding: .year, value: 5, to: Date())
                ),
                GearItem(
                    type: .jacket,
                    name: "Alpinestars Missile V2",
                    brand: "Alpinestars",
                    size: "XL",
                    condition: .likeNew,
                    cost: 38000,
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

    // MARK: - CRUD

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

    // MARK: - Helpers

    func docs(for bikeId: UUID) -> [BikeDocument]      { documents.filter { $0.bikeId == bikeId } }
    func services(for bikeId: UUID) -> [ServiceEntry]  { services.filter { $0.bikeId == bikeId } }
    func accessories(for bikeId: UUID) -> [AccessoryItem] { accessories.filter { $0.bikeId == bikeId } }
    func costs(for bikeId: UUID) -> [CostEntry]        { costs.filter { $0.bikeId == bikeId } }
}
