import SwiftUI
import SwiftData

// MARK: - SwiftData Models

@Model
final class UserProfileEntity {
    @Attribute(.unique) var id: String = "currentUser"
    var hasCompletedOnboarding: Bool = false
    var displayName: String = ""
    var handle: String = ""
    var avatarName: String = "avatar_a"
    @Attribute(.externalStorage) var avatarImageData: Data? = nil
    var createdAt: Date = Date()

    init(
        id: String = "currentUser",
        hasCompletedOnboarding: Bool = false,
        displayName: String = "",
        handle: String = "",
        avatarName: String = "avatar_a",
        avatarImageData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.displayName = displayName
        self.handle = handle
        self.avatarName = avatarName
        self.avatarImageData = avatarImageData
        self.createdAt = createdAt
    }
}

@Model
final class PersistedRideEntity {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var place: String = ""
    var subtitle: String = ""
    var photo: String = "photo_nandi"
    var hero: String = "hero_nandi"
    var tag: String = "Group ride"
    var departs: Date = Date()
    var distance: String = "71 km"
    var duration: String = "1h 50m"
    var displayDate: String = ""
    var displayTime: String = ""
    var organiser: String = "you"
    var isCompleted: Bool = false
    var code: String = ""
    var fromLocation: String = ""
    var toLocation: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String,
        place: String,
        subtitle: String,
        photo: String = "photo_nandi",
        hero: String = "hero_nandi",
        tag: String = "Group ride",
        departs: Date,
        distance: String,
        duration: String,
        displayDate: String,
        displayTime: String,
        organiser: String = "you",
        isCompleted: Bool = false,
        code: String,
        fromLocation: String = "",
        toLocation: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.place = place
        self.subtitle = subtitle
        self.photo = photo
        self.hero = hero
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
        self.createdAt = createdAt
    }
}

// MARK: - Storage Service Helper

@MainActor
final class StorageService {
    static let shared = StorageService()

    var container: ModelContainer?

    init() {
        do {
            let schema = Schema([UserProfileEntity.self, PersistedRideEntity.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            print("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }

    var context: ModelContext? {
        container?.mainContext
    }

    // MARK: User Profile
    func loadUserProfile() -> UserProfileEntity? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<UserProfileEntity>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        return nil
    }

    func saveOnboardingCompleted(name: String, handle: String, avatar: String, imageData: Data? = nil) {
        guard let context else { return }
        if let existing = loadUserProfile() {
            existing.hasCompletedOnboarding = true
            existing.displayName = name
            existing.handle = handle
            existing.avatarName = avatar
            if let imageData {
                existing.avatarImageData = imageData
            }
        } else {
            let profile = UserProfileEntity(
                hasCompletedOnboarding: true,
                displayName: name,
                handle: handle,
                avatarName: avatar,
                avatarImageData: imageData
            )
            context.insert(profile)
        }
        try? context.save()
    }

    // MARK: Rides
    func loadActiveRides() -> [PersistedRideEntity] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<PersistedRideEntity>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\.departs, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func loadCompletedRides() -> [PersistedRideEntity] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<PersistedRideEntity>(
            predicate: #Predicate { $0.isCompleted },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func saveRide(_ ride: Ride) {
        guard let context else { return }
        let entity = PersistedRideEntity(
            id: ride.id,
            title: ride.title,
            place: ride.place,
            subtitle: ride.subtitle,
            photo: ride.photo,
            hero: ride.hero,
            tag: ride.tag,
            departs: ride.departs,
            distance: ride.distance,
            duration: ride.duration,
            displayDate: ride.displayDate,
            displayTime: ride.displayTime,
            organiser: ride.organiser,
            isCompleted: false,
            code: ride.code,
            fromLocation: ride.plan.from,
            toLocation: ride.plan.to
        )
        context.insert(entity)
        try? context.save()
    }

    func markRideCompleted(id: UUID) {
        guard let context else { return }
        let descriptor = FetchDescriptor<PersistedRideEntity>()
        if let all = try? context.fetch(descriptor) {
            for r in all where r.id == id {
                r.isCompleted = true
            }
            try? context.save()
        }
    }
}
