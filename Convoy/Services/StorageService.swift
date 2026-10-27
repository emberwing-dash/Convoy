// StorageService.swift
import SwiftUI
import SwiftData
import CoreLocation

// MARK: - User Profile

@Model
final class UserProfileEntity {
    @Attribute(.unique) var id: String = "currentUser"
    var hasCompletedOnboarding: Bool = false
    var displayName: String = ""
    var handle: String = ""
    @Attribute(.externalStorage) var avatarImageData: Data? = nil
    var createdAt: Date = Date()

    init(id: String = "currentUser",
         hasCompletedOnboarding: Bool = false,
         displayName: String = "",
         handle: String = "",
         avatarImageData: Data? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.displayName = displayName
        self.handle = handle
        self.avatarImageData = avatarImageData
        self.createdAt = createdAt
    }
}

// MARK: - Ride

@Model
final class PersistedRideEntity {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var place: String = ""
    var subtitle: String = ""
    var tag: String = "Group ride"
    var departs: Date = Date()
    var distance: String = ""
    var duration: String = ""
    var displayDate: String = ""
    var displayTime: String = ""
    var organiser: String = "you"
    var isCompleted: Bool = false
    var code: String = ""

    var fromLocation: String = ""
    var toLocation: String = ""
    var stopsJSON: String = "[]"
    var styleRaw: String = "Fastest"
    var routeSet: Bool = false
    var startLat: Double = 0
    var startLon: Double = 0
    var endLat: Double = 0
    var endLon: Double = 0

    var routeCoordsJSON: String = "[]"
    var routeKm: Double = 0
    var routeMinutes: Int = 0

    var createdAt: Date = Date()
    var completedAt: Date?

    init(id: UUID = UUID(), title: String, place: String, subtitle: String,
         tag: String, departs: Date, distance: String, duration: String,
         displayDate: String, displayTime: String, organiser: String,
         isCompleted: Bool, code: String,
         fromLocation: String, toLocation: String, stopsJSON: String,
         styleRaw: String, routeSet: Bool,
         startLat: Double, startLon: Double, endLat: Double, endLon: Double) {
        self.id = id
        self.title = title
        self.place = place
        self.subtitle = subtitle
        self.tag = tag
        self.departs = departs
        self.distance = distance
        self.duration = duration
        self.displayDate = displayDate
        self.displayTime = displayTime
        self.organiser = organiser
        self.isCompleted = isCompleted
        self.code = code
        self.fromLocation = fromLocation
        self.toLocation = toLocation
        self.stopsJSON = stopsJSON
        self.styleRaw = styleRaw
        self.routeSet = routeSet
        self.startLat = startLat
        self.startLon = startLon
        self.endLat = endLat
        self.endLon = endLon
    }
}

// MARK: - Crew

@Model
final class CrewEntity {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var detail: String = ""
    var accentHex: UInt32 = 0xFF3B30
    @Attribute(.externalStorage) var avatarData: Data? = nil
    var membersJSON: String = "[]"
    var since: Date = Date()
    var code: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, detail: String, accentHex: UInt32,
         avatarData: Data?, membersJSON: String, since: Date, code: String) {
        self.id = id
        self.name = name
        self.detail = detail
        self.accentHex = accentHex
        self.avatarData = avatarData
        self.membersJSON = membersJSON
        self.since = since
        self.code = code
    }
}

// MARK: - Saved Route

@Model
final class SavedRouteEntity {
    @Attribute(.unique) var id: String = ""
    var title: String = ""
    var tag: String = ""
    var from: String = ""
    var to: String = ""
    var km: Int = 0
    var time: String = ""
    var style: String = ""
    var blurb: String = ""
    var startPlace: String = ""
    var finishPlace: String = ""
    var stops: Int = 0
    var startLat: Double = 0
    var startLon: Double = 0
    var endLat: Double = 0
    var endLon: Double = 0
    var categoriesRaw: String = ""
    var createdAt: Date = Date()
    var coordsJSON: String = "[]"

    init(id: String, title: String, tag: String, from: String, to: String,
         km: Int, time: String, style: String, blurb: String,
         startPlace: String, finishPlace: String, stops: Int,
         startLat: Double, startLon: Double, endLat: Double, endLon: Double,
         categoriesRaw: String) {
        self.id = id
        self.title = title
        self.tag = tag
        self.from = from
        self.to = to
        self.km = km
        self.time = time
        self.style = style
        self.blurb = blurb
        self.startPlace = startPlace
        self.finishPlace = finishPlace
        self.stops = stops
        self.startLat = startLat
        self.startLon = startLon
        self.endLat = endLat
        self.endLon = endLon
        self.categoriesRaw = categoriesRaw
    }
}

// MARK: - Fill-up

@Model
final class FillUpEntity {
    @Attribute(.unique) var id: UUID = UUID()
    var odo: Int = 0
    var litres: Double = 0
    var price: Double = 0
    var filledAt: Date = Date()

    init(id: UUID = UUID(), odo: Int, litres: Double, price: Double, filledAt: Date = Date()) {
        self.id = id
        self.odo = odo
        self.litres = litres
        self.price = price
        self.filledAt = filledAt
    }
}

// MARK: - Service

@MainActor
final class StorageService {
    static let shared = StorageService()
    var container: ModelContainer?

    init() {
        let schema = Schema([
            UserProfileEntity.self,
            PersistedRideEntity.self,
            CrewEntity.self,
            SavedRouteEntity.self,
            FillUpEntity.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            print("⚠️ ModelContainer init failed: \(error). Resetting store.")
            Self.resetStore()
            container = try? ModelContainer(for: schema, configurations: config)
        }
    }

    private static func resetStore() {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for u in urls where u.pathExtension == "store"
            || u.pathExtension == "store-shm"
            || u.pathExtension == "store-wal" {
            try? fm.removeItem(at: u)
        }
    }

    var context: ModelContext? { container?.mainContext }

    // MARK: - User
    func loadUserProfile() -> UserProfileEntity? {
        guard let context else { return nil }
        return (try? context.fetch(FetchDescriptor<UserProfileEntity>()))?.first
    }

    func saveOnboardingCompleted(name: String, handle: String, imageData: Data? = nil) {
        guard let context else { return }
        if let existing = loadUserProfile() {
            existing.hasCompletedOnboarding = true
            existing.displayName = name
            existing.handle = handle
            if let imageData { existing.avatarImageData = imageData }
        } else {
            context.insert(UserProfileEntity(hasCompletedOnboarding: true,
                                             displayName: name, handle: handle,
                                             avatarImageData: imageData))
        }
        try? context.save()
    }

    /// Sign-out: wipes the local profile so onboarding runs fresh on next launch.
    func clearUserProfile() {
        guard let context else { return }
        let d = FetchDescriptor<UserProfileEntity>()
        if let all = try? context.fetch(d) {
            for p in all { context.delete(p) }
            try? context.save()
        }
    }

    // MARK: - Rides
    func loadActiveRides() -> [PersistedRideEntity] {
        guard let context else { return [] }
        let d = FetchDescriptor<PersistedRideEntity>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\.departs, order: .forward)])
        return (try? context.fetch(d)) ?? []
    }

    func loadCompletedRides() -> [PersistedRideEntity] {
        guard let context else { return [] }
        let d = FetchDescriptor<PersistedRideEntity>(
            predicate: #Predicate { $0.isCompleted },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func saveRide(_ ride: Ride) {
        guard let context else { return }
        let stopsData = (try? JSONEncoder().encode(ride.plan.stops)) ?? Data("[]".utf8)
        let stopsJSON = String(data: stopsData, encoding: .utf8) ?? "[]"

        let selected = ride.plan.selected
        let coordsPairs = (selected?.coords ?? []).map { [$0.lat, $0.lon] }
        let coordsData = (try? JSONSerialization.data(withJSONObject: coordsPairs)) ?? Data("[]".utf8)
        let coordsJSON = String(data: coordsData, encoding: .utf8) ?? "[]"

        let entity = PersistedRideEntity(
            id: ride.id,
            title: ride.title, place: ride.place, subtitle: ride.subtitle,
            tag: ride.tag, departs: ride.departs,
            distance: ride.distance, duration: ride.duration,
            displayDate: ride.displayDate, displayTime: ride.displayTime,
            organiser: ride.organiser, isCompleted: false, code: ride.code,
            fromLocation: ride.plan.from, toLocation: ride.plan.to,
            stopsJSON: stopsJSON, styleRaw: ride.plan.style.rawValue,
            routeSet: ride.plan.routeSet,
            startLat: ride.plan.startCoord?.lat ?? 0, startLon: ride.plan.startCoord?.lon ?? 0,
            endLat: ride.plan.endCoord?.lat ?? 0, endLon: ride.plan.endCoord?.lon ?? 0
        )
        entity.routeCoordsJSON = coordsJSON
        entity.routeKm = selected?.km ?? 0
        entity.routeMinutes = selected?.minutes ?? 0

        context.insert(entity)
        try? context.save()
    }

    func markRideCompleted(id: UUID) {
        guard let context else { return }
        let d = FetchDescriptor<PersistedRideEntity>()
        if let all = try? context.fetch(d) {
            for r in all where r.id == id {
                r.isCompleted = true
                r.completedAt = Date()
            }
            try? context.save()
        }
    }

    // MARK: - Crews
    func loadCrews() -> [CrewEntity] {
        guard let context else { return [] }
        let d = FetchDescriptor<CrewEntity>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        return (try? context.fetch(d)) ?? []
    }

    func saveCrew(_ crew: CrewGroup) {
        guard let context else { return }
        let memberPayload = crew.members.map { ["name": $0.name, "detail": $0.detail] }
        let data = (try? JSONSerialization.data(withJSONObject: memberPayload)) ?? Data("[]".utf8)
        let membersJSON = String(data: data, encoding: .utf8) ?? "[]"
        let entity = CrewEntity(
            id: crew.id, name: crew.name, detail: crew.detail,
            accentHex: crew.accentHex, avatarData: crew.avatarData,
            membersJSON: membersJSON, since: crew.since, code: crew.code
        )
        context.insert(entity)
        try? context.save()
    }

    func syncCrews(_ crews: [CrewGroup]) {
        guard let context else { return }
        let d = FetchDescriptor<CrewEntity>()
        if let existing = try? context.fetch(d) {
            for e in existing { context.delete(e) }
        }
        for crew in crews {
            let memberPayload = crew.members.map { ["name": $0.name, "detail": $0.detail] }
            let data = (try? JSONSerialization.data(withJSONObject: memberPayload)) ?? Data("[]".utf8)
            let membersJSON = String(data: data, encoding: .utf8) ?? "[]"
            let entity = CrewEntity(
                id: crew.id, name: crew.name, detail: crew.detail,
                accentHex: crew.accentHex, avatarData: crew.avatarData,
                membersJSON: membersJSON, since: crew.since, code: crew.code
            )
            context.insert(entity)
        }
        try? context.save()
    }

    func updateCrewAvatar(id: UUID, avatarData: Data?) {
        guard let context else { return }
        let d = FetchDescriptor<CrewEntity>()
        if let all = try? context.fetch(d) {
            for c in all where c.id == id { c.avatarData = avatarData }
            try? context.save()
        }
    }

    // MARK: - Notifications Cache
    func loadCachedNotifications() -> [AppNotification] {
        guard let data = UserDefaults.standard.data(forKey: "cached_notifications") else { return [] }
        return (try? JSONDecoder().decode([AppNotification].self, from: data)) ?? []
    }

    func saveNotifications(_ notifs: [AppNotification]) {
        if let data = try? JSONEncoder().encode(notifs) {
            UserDefaults.standard.set(data, forKey: "cached_notifications")
        }
    }

    // MARK: - Saved routes
    func loadSavedRoutes() -> [SavedRouteEntity] {
        guard let context else { return [] }
        let d = FetchDescriptor<SavedRouteEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func saveSavedRoute(_ route: DiscoverRoute) {
        guard let context else { return }
        let catsRaw = route.categories.map(\.rawValue).joined(separator: ",")

        let entity = SavedRouteEntity(
            id: route.id, title: route.title, tag: route.tag,
            from: route.from, to: route.to, km: route.km, time: route.time,
            style: route.style, blurb: route.blurb,
            startPlace: route.startPlace, finishPlace: route.finishPlace,
            stops: route.stops,
            startLat: route.startCoord.lat, startLon: route.startCoord.lon,
            endLat: route.endCoord.lat, endLon: route.endCoord.lon,
            categoriesRaw: catsRaw
        )

        let coordsPairs = route.coords.map { [$0.lat, $0.lon] }
        let coordsData = (try? JSONSerialization.data(withJSONObject: coordsPairs)) ?? Data("[]".utf8)
        entity.coordsJSON = String(data: coordsData, encoding: .utf8) ?? "[]"

        context.insert(entity)
        try? context.save()
    }

    func removeSavedRoute(id: String) {
        guard let context else { return }
        let d = FetchDescriptor<SavedRouteEntity>()
        if let all = try? context.fetch(d) {
            for r in all where r.id == id { context.delete(r) }
            try? context.save()
        }
    }

    // MARK: - Fill-ups
    func loadFillUps() -> [FillUpEntity] {
        guard let context else { return [] }
        let d = FetchDescriptor<FillUpEntity>(
            sortBy: [SortDescriptor(\.filledAt, order: .forward)]
        )
        return (try? context.fetch(d)) ?? []
    }

    func saveFillUp(odo: Int, litres: Double, price: Double) {
        guard let context else { return }
        context.insert(FillUpEntity(odo: odo, litres: litres, price: price))
        try? context.save()
    }
}
