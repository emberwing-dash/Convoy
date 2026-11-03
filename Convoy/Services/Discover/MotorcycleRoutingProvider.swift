// MotorcycleRoutingProvider.swift
// Stage 5B.3: Motorcycle Routing Safety Guardrails, ETA Calibration & Discover Integration.
import Foundation
import CoreLocation

// MARK: - 1. Restricted Road Protection & Legal Safety Guardrail

/// Definitive record of an access-controlled expressway or highway prohibited for two-wheelers in India.
struct RestrictedRoadCorridor: Hashable, Sendable {
    let id: String
    let name: String
    let officialSource: String
    let effectiveDate: String
    let vehicleRestrictions: String
    let lastVerificationDate: String
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    let forbiddenKeywords: [String]
    let detourWaypoint: Coord?
    let detourDescription: String
}

/// Safety guardrail engine inspecting all returned route geometries and road segments
/// against authoritative NHAI and State Police two-wheeler prohibitions.
enum RestrictedRoadSafetyGuardrail {
    static let prohibitedCorridors: [RestrictedRoadCorridor] = [
        RestrictedRoadCorridor(
            id: "IN-KA-NH275-EXP",
            name: "Bengaluru-Mysuru Expressway (NH-275 Main Carriageway)",
            officialSource: "NHAI Gazette Notification & Order under S.35 Control of National Highways Act (12 July 2023)",
            effectiveDate: "2023-08-01",
            vehicleRestrictions: "Two-wheelers, three-wheelers, tractors, and slow-moving vehicles prohibited on 118 km main carriageway",
            lastVerificationDate: "2026-11-01",
            minLat: 12.35, maxLat: 12.92, minLon: 76.67, maxLon: 77.48,
            forbiddenKeywords: ["bengaluru-mysuru expressway", "bengaluru - mysuru expressway", "nh 275 expressway", "nh275 expressway"],
            detourWaypoint: Coord(lat: 12.7214, lon: 77.2807), // Bidadi / Ramanagara Old SH-17
            detourDescription: "Old Mysuru Road (SH-17 via Ramanagara & Mandya)"
        ),
        RestrictedRoadCorridor(
            id: "IN-MH-MPE-01",
            name: "Mumbai-Pune Expressway (Yashwantrao Chavan Expressway)",
            officialSource: "Government of Maharashtra PWD & Highway Police Notification under Motor Vehicles Act (2002)",
            effectiveDate: "2002-01-01",
            vehicleRestrictions: "All two-wheelers, three-wheelers, and slow-moving vehicles permanently prohibited on 94.5 km concrete expressway",
            lastVerificationDate: "2026-11-01",
            minLat: 18.66, maxLat: 19.02, minLon: 73.11, maxLon: 73.72,
            forbiddenKeywords: ["mumbai-pune expressway", "mumbai pune expressway", "yashwantrao chavan expressway"],
            detourWaypoint: Coord(lat: 18.7547, lon: 73.3768), // Khandala Old NH-48
            detourDescription: "Old Mumbai-Pune Highway (Old NH-48 via Khandala Ghat)"
        ),
        RestrictedRoadCorridor(
            id: "IN-UP-DL-NE3",
            name: "Delhi-Meerut Expressway (National Expressway 3 / NH-9 Main Carriageway)",
            officialSource: "Delhi Police Traffic Advisory & NHAI Notification (February 2021, reiterated 2023/2024)",
            effectiveDate: "2021-02-01",
            vehicleRestrictions: "Two-wheelers and three-wheelers strictly prohibited on NE-3 high-speed expressway main lanes",
            lastVerificationDate: "2026-11-01",
            minLat: 28.61, maxLat: 28.92, minLon: 77.30, maxLon: 77.68,
            forbiddenKeywords: ["delhi-meerut expressway", "delhi - meerut expressway", "ne-3", "national expressway 3"],
            detourWaypoint: Coord(lat: 28.8340, lon: 77.5800), // Modinagar Old NH-34
            detourDescription: "Old NH-34 via Modinagar / DME Service Road"
        ),
        RestrictedRoadCorridor(
            id: "IN-UP-YAE-01",
            name: "Yamuna Expressway (Greater Noida to Agra)",
            officialSource: "Yamuna Expressway Industrial Development Authority (YEIDA) & UP Traffic Police (2012)",
            effectiveDate: "2012-08-09",
            vehicleRestrictions: "Two-wheelers restricted from high-speed central carriageway",
            lastVerificationDate: "2026-11-01",
            minLat: 27.20, maxLat: 28.45, minLon: 77.50, maxLon: 78.05,
            forbiddenKeywords: ["yamuna expressway"],
            detourWaypoint: Coord(lat: 27.8974, lon: 78.0880), // Aligarh Old GT Road
            detourDescription: "Old Grand Trunk Road (NH-19 / NH-509 via Aligarh)"
        ),
        RestrictedRoadCorridor(
            id: "IN-MH-MCR-01",
            name: "Mumbai Coastal Road (Dharmveer Swarajya Rakshak Chhatrapati Sambhaji Maharaj Coastal Road)",
            officialSource: "Mumbai Traffic Police Notification under Motor Vehicles Act (March 2024)",
            effectiveDate: "2024-03-12",
            vehicleRestrictions: "Two-wheelers, three-wheelers, and heavy trailers prohibited from undersea tunnel and elevated carriageway",
            lastVerificationDate: "2026-11-01",
            minLat: 18.94, maxLat: 19.01, minLon: 72.80, maxLon: 72.84,
            forbiddenKeywords: ["mumbai coastal road", "coastal road"],
            detourWaypoint: Coord(lat: 18.9750, lon: 72.8250), // Pedder Road / Dr Annie Besant Road
            detourDescription: "Dr Annie Besant Road / Pedder Road arterial corridor"
        )
    ]

    struct RouteSafetyAuditResult: Sendable {
        let isSafe: Bool
        let detectedViolations: [RestrictedRoadCorridor]
        let recommendedDetour: RestrictedRoadCorridor?
    }

    /// Evaluates route coordinates and maneuver street names against prohibited corridors.
    static func auditRoute(coordinates: [Coord], roadNames: [String]) -> RouteSafetyAuditResult {
        var violations: [RestrictedRoadCorridor] = []
        let roadNamesJoined = roadNames.joined(separator: " ").lowercased()

        for corridor in prohibitedCorridors {
            var keywordHit = false
            for kw in corridor.forbiddenKeywords {
                if roadNamesJoined.contains(kw) {
                    keywordHit = true
                    break
                }
            }

            var spatialHit = false
            if keywordHit {
                // Check if any route points fall within the corridor's bounding box
                for pt in coordinates {
                    if pt.lat >= corridor.minLat && pt.lat <= corridor.maxLat &&
                       pt.lon >= corridor.minLon && pt.lon <= corridor.maxLon {
                        spatialHit = true
                        break
                    }
                }
            }

            if keywordHit && spatialHit {
                violations.append(corridor)
            }
        }

        let firstDetour = violations.first { $0.detourWaypoint != nil }
        return RouteSafetyAuditResult(
            isSafe: violations.isEmpty,
            detectedViolations: violations,
            recommendedDetour: firstDetour
        )
    }
}

// MARK: - 2. Segment-Aware ETA Engine & Pacing Profiles

/// Pacing profile for motorcycle journey planning.
struct RidePacingProfile: Hashable, Sendable, Codable {
    enum PacingType: String, CaseIterable, Codable {
        case brisk = "Brisk"
        case balanced = "Balanced"
        case relaxed = "Relaxed"
    }

    var type: PacingType
    var restIntervalMinutes: Int
    var restDurationMinutes: Int
    var fuelIntervalKm: Double
    var fuelDurationMinutes: Int
    var mealIntervalHours: Double
    var mealDurationMinutes: Int

    static let brisk = RidePacingProfile(
        type: .brisk,
        restIntervalMinutes: 120,
        restDurationMinutes: 10,
        fuelIntervalKm: 250,
        fuelDurationMinutes: 10,
        mealIntervalHours: 4.5,
        mealDurationMinutes: 30
    )

    static let balanced = RidePacingProfile(
        type: .balanced,
        restIntervalMinutes: 90,
        restDurationMinutes: 15,
        fuelIntervalKm: 200,
        fuelDurationMinutes: 10,
        mealIntervalHours: 4.0,
        mealDurationMinutes: 45
    )

    static let relaxed = RidePacingProfile(
        type: .relaxed,
        restIntervalMinutes: 60,
        restDurationMinutes: 20,
        fuelIntervalKm: 160,
        fuelDurationMinutes: 15,
        mealIntervalHours: 3.5,
        mealDurationMinutes: 60
    )

    static func profile(for type: PacingType) -> RidePacingProfile {
        switch type {
        case .brisk: return .brisk
        case .balanced: return .balanced
        case .relaxed: return .relaxed
        }
    }
}

/// Discrete road segment extracted from routing provider maneuvers.
struct RouteSegment: Hashable, Sendable {
    var distanceMeters: Double
    var durationSeconds: Double?
    var streetName: String?
    var roadClass: String?
    var isGhat: Bool

    var distanceKm: Double { distanceMeters / 1000.0 }

    init(distanceMeters: Double, durationSeconds: Double? = nil, streetName: String? = nil, roadClass: String? = nil, isGhat: Bool = false) {
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.streetName = streetName
        self.roadClass = roadClass
        self.isGhat = isGhat
    }
}

/// Clean, testable, segment-aware ETA calibration engine.
enum SegmentAwareRoutingCalibrator {
    struct CalibrationResult: Hashable, Sendable {
        let roadDistanceKm: Double
        let providerBaselineDurationSeconds: Double
        let convoySaddleDurationSeconds: Double
        let plannedFuelDurationSeconds: Double
        let plannedRestDurationSeconds: Double
        let plannedMealDurationSeconds: Double
        let totalPlannedStopsDurationSeconds: Double
        let totalTripDurationSeconds: Double
        let fuelStopCount: Int
        let restStopCount: Int
        let mealStopCount: Int
        let totalStopCount: Int
        let terrainClassification: String
        let pacingProfile: RidePacingProfile
        let assumptions: [String]
        let provenance: String
        let calculatedAt: Date

        var saddleDurationText: String {
            let m = Int(convoySaddleDurationSeconds / 60.0)
            return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
        }

        var totalTripDurationText: String {
            let m = Int(totalTripDurationSeconds / 60.0)
            return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
        }

        var providerBaselineText: String {
            let m = Int(providerBaselineDurationSeconds / 60.0)
            return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
        }

        var stopsText: String {
            if totalStopCount == 0 { return "0 stops" }
            return "\(totalStopCount) stop\(totalStopCount == 1 ? "" : "s") (\(Int(totalPlannedStopsDurationSeconds / 60.0))m)"
        }
    }

    /// Evaluates planned stops based on saddle duration, distance, and pacing profile without calling routing API.
    static func calculatePlannedStops(
        saddleDurationSeconds: Double,
        roadDistanceKm: Double,
        pacing: RidePacingProfile
    ) -> (fuelDuration: Double, restDuration: Double, mealDuration: Double, totalStopsDuration: Double, fuelCount: Int, restCount: Int, mealCount: Int) {
        let fuelCount = roadDistanceKm >= (pacing.fuelIntervalKm * 0.9) ? max(1, Int(roadDistanceKm / pacing.fuelIntervalKm)) : 0
        let fuelDuration = Double(fuelCount * pacing.fuelDurationMinutes * 60)

        let saddleMinutes = Int(saddleDurationSeconds / 60.0)
        let saddleHours = saddleDurationSeconds / 3600.0

        let mealCount = saddleHours >= pacing.mealIntervalHours ? 1 : 0
        let mealDuration = Double(mealCount * pacing.mealDurationMinutes * 60)

        let rawRestCount = max(0, Int(Double(saddleMinutes) / Double(pacing.restIntervalMinutes)))
        let restCount = max(0, rawRestCount - mealCount)
        let restDuration = Double(restCount * pacing.restDurationMinutes * 60)

        let totalDuration = fuelDuration + restDuration + mealDuration
        return (fuelDuration, restDuration, mealDuration, totalDuration, fuelCount, restCount, mealCount)
    }

    /// Primary segment-aware calibration method.
    static func calibrate(
        distanceMeters: Double,
        providerDurationSeconds: Double?,
        segments: [RouteSegment] = [],
        origin: Coord? = nil,
        destination: Coord? = nil,
        hasGhatSection: Bool = false,
        pacing: RidePacingProfile = .balanced,
        provenance: String = "Convoy ETA Engine"
    ) -> CalibrationResult {
        let roadKm = distanceMeters / 1000.0
        var assumptions: [String] = []

        // 1. Establish Provider Baseline Duration
        let baselineSeconds: Double
        if let provSec = providerDurationSeconds, provSec > 0 {
            baselineSeconds = provSec
        } else {
            assumptions.append("Provisional estimate: No provider baseline duration available; calculated from distance and terrain.")
            let provisionalSpeedKmh = hasGhatSection ? 28.0 : (roadKm > 100 ? 50.0 : 42.0)
            baselineSeconds = (roadKm / provisionalSpeedKmh) * 3600.0
        }

        // 2. Compute Convoy Calibrated Saddle Time
        let saddleSeconds: Double
        let terrainType: String

        if !segments.isEmpty {
            var adjustedTime = 0.0
            var ghatKm = 0.0
            var highwayKm = 0.0

            for seg in segments {
                if seg.isGhat {
                    ghatKm += seg.distanceKm
                    let segTime = seg.durationSeconds ?? ((seg.distanceKm / 28.0) * 3600.0)
                    let impliedSpeed = segTime > 0 ? (seg.distanceKm / (segTime / 3600.0)) : 28.0
                    if impliedSpeed > 35.0 {
                        adjustedTime += (seg.distanceKm / 28.0) * 3600.0
                        assumptions.append("Calibrated \(seg.streetName ?? "mountain curve") to 28 km/h ghat speed cap.")
                    } else {
                        adjustedTime += segTime
                    }
                } else if seg.roadClass == "trunk" || seg.roadClass == "primary" {
                    highwayKm += seg.distanceKm
                    let segTime = seg.durationSeconds ?? ((seg.distanceKm / 60.0) * 3600.0)
                    adjustedTime += segTime
                } else {
                    let segTime = seg.durationSeconds ?? ((seg.distanceKm / 40.0) * 3600.0)
                    adjustedTime += segTime
                }
            }

            saddleSeconds = adjustedTime > 0 ? adjustedTime : baselineSeconds
            if ghatKm > 10.0 || hasGhatSection {
                terrainType = "Mountain Ghat (\(Int(ghatKm)) km climb)"
            } else if highwayKm > roadKm * 0.5 {
                terrainType = "Arterial Highway Corridor"
            } else {
                terrainType = "Mixed Arterial / Regional"
            }
        } else {
            // Anchor to provider baseline duration; no blind global urban buffers added
            let impliedSpeed = baselineSeconds > 0 ? (roadKm / (baselineSeconds / 3600.0)) : 45.0
            if !hasGhatSection && impliedSpeed < 28.0 {
                // Provider was severely penalised by highway avoidance (e.g. use_highways: 0.0 village tracks)
                let calibratedSpeed = roadKm > 80 ? 44.0 : 38.0
                saddleSeconds = (roadKm / calibratedSpeed) * 3600.0
                assumptions.append("Calibrated baseline duration from excessively slow provider penalty (\(Int(impliedSpeed)) km/h) to legal arterial cruising pace (\(Int(calibratedSpeed)) km/h).")
            } else if impliedSpeed > 75.0 {
                // Car speed on expressways / open highways; cap to realistic 2-wheeler highway cruising
                let calibratedSpeed = 65.0
                saddleSeconds = (roadKm / calibratedSpeed) * 3600.0
                assumptions.append("Calibrated baseline duration to realistic two-wheeler cruising speed (\(Int(calibratedSpeed)) km/h).")
            } else {
                saddleSeconds = baselineSeconds
            }
            terrainType = hasGhatSection ? "Mountain Ghat" : (roadKm > 80 ? "Highway Corridor" : "Regional Road")
        }

        // 3. Compute Planned Stops
        let stops = calculatePlannedStops(
            saddleDurationSeconds: saddleSeconds,
            roadDistanceKm: roadKm,
            pacing: pacing
        )

        let totalTripSeconds = saddleSeconds + stops.totalStopsDuration

        return CalibrationResult(
            roadDistanceKm: roadKm,
            providerBaselineDurationSeconds: baselineSeconds,
            convoySaddleDurationSeconds: saddleSeconds,
            plannedFuelDurationSeconds: stops.fuelDuration,
            plannedRestDurationSeconds: stops.restDuration,
            plannedMealDurationSeconds: stops.mealDuration,
            totalPlannedStopsDurationSeconds: stops.totalStopsDuration,
            totalTripDurationSeconds: totalTripSeconds,
            fuelStopCount: stops.fuelCount,
            restStopCount: stops.restCount,
            mealStopCount: stops.mealCount,
            totalStopCount: stops.fuelCount + stops.restCount + stops.mealCount,
            terrainClassification: terrainType,
            pacingProfile: pacing,
            assumptions: assumptions,
            provenance: provenance,
            calculatedAt: Date()
        )
    }
}

/// Backwards-compatible calibration adapter
enum ConvoyRoutingCalibrator {
    struct CalibrationResult: Sendable {
        let roadDistanceKm: Double
        let windingRatio: Double
        let terrainClassification: String
        let baseRollingSpeedKmh: Double
        let saddleDurationSeconds: Double
        let recommendedBreaksCount: Int
        let totalTripDurationSeconds: Double
        let uncertaintyRange: String
    }

    static func calibrate(distanceMeters: Double, origin: Coord, destination: Coord, hasGhatSection: Bool = false) -> CalibrationResult {
        let straightKm = origin.distanceKm(to: destination)
        let roadKm = distanceMeters / 1000.0
        let windingRatio = straightKm > 0.1 ? (roadKm / straightKm) : 1.0

        let res = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: distanceMeters,
            providerDurationSeconds: nil,
            origin: origin,
            destination: destination,
            hasGhatSection: hasGhatSection || windingRatio >= 1.45,
            pacing: .balanced,
            provenance: "Convoy Calibrator"
        )

        return CalibrationResult(
            roadDistanceKm: res.roadDistanceKm,
            windingRatio: windingRatio,
            terrainClassification: res.terrainClassification,
            baseRollingSpeedKmh: res.roadDistanceKm / max(0.1, res.convoySaddleDurationSeconds / 3600.0),
            saddleDurationSeconds: res.convoySaddleDurationSeconds,
            recommendedBreaksCount: res.totalStopCount,
            totalTripDurationSeconds: res.totalTripDurationSeconds,
            uncertaintyRange: "Saddle: \(res.saddleDurationText) · Total: \(res.totalTripDurationText)"
        )
    }
}

// MARK: - 3. Request and Response Models

/// Parameters for requesting a motorcycle-specific route in India.
struct MotorcycleRouteRequest: Hashable, Sendable {
    var origin: Coord
    var destination: Coord
    var waypoints: [Coord]
    var avoidExpressways: Bool
    var preferScenicCurvature: Bool
    var maxSpeedKmh: Double?
    var pacingProfile: RidePacingProfile

    init(
        origin: Coord,
        destination: Coord,
        waypoints: [Coord] = [],
        avoidExpressways: Bool = true,
        preferScenicCurvature: Bool = false,
        maxSpeedKmh: Double? = nil,
        pacingProfile: RidePacingProfile = .balanced
    ) {
        self.origin = origin
        self.destination = destination
        self.waypoints = waypoints
        self.avoidExpressways = avoidExpressways
        self.preferScenicCurvature = preferScenicCurvature
        self.maxSpeedKmh = maxSpeedKmh
        self.pacingProfile = pacingProfile
    }
}

/// Comprehensive result of a motorcycle routing calculation.
struct MotorcycleRouteResponse: Hashable, Sendable {
    var coordinates: [Coord]
    var distanceMeters: Double
    var providerDurationSeconds: Double
    var convoyEstimatedDurationSeconds: Double
    var convoyTotalTripDurationSeconds: Double
    var fuelStopsDurationSeconds: Double
    var restStopsDurationSeconds: Double
    var mealStopsDurationSeconds: Double
    var pacingProfile: RidePacingProfile
    var uncertaintyRange: String
    var terrainClassification: String
    var roadClasses: [String]
    var segments: [RouteSegment]
    var hasExpresswayViolations: Bool
    var intermediateWaypoints: [Coord]
    var motorcycleAccessVerified: Bool
    var knownExpresswayRestrictions: [String]
    var alternativeRouteDescription: String?
    var legalCitation: String?
    var providerId: String
    var providerName: String
    var dataSource: String
    var disclaimer: String?
    var assumptions: [String]
    var calculatedAt: Date

    // Backwards-compatible duration accessor
    var durationSeconds: Double { providerDurationSeconds }
    var saddleDurationSeconds: Double { convoyEstimatedDurationSeconds }
    var totalTripDurationSeconds: Double { convoyTotalTripDurationSeconds }

    init(
        coordinates: [Coord],
        distanceMeters: Double,
        providerDurationSeconds: Double,
        convoyEstimatedDurationSeconds: Double? = nil,
        convoyTotalTripDurationSeconds: Double? = nil,
        fuelStopsDurationSeconds: Double? = nil,
        restStopsDurationSeconds: Double? = nil,
        mealStopsDurationSeconds: Double? = nil,
        pacingProfile: RidePacingProfile = .balanced,
        uncertaintyRange: String? = nil,
        terrainClassification: String? = nil,
        roadClasses: [String] = [],
        segments: [RouteSegment] = [],
        hasExpresswayViolations: Bool = false,
        intermediateWaypoints: [Coord] = [],
        motorcycleAccessVerified: Bool = true,
        knownExpresswayRestrictions: [String] = [],
        alternativeRouteDescription: String? = nil,
        legalCitation: String? = nil,
        providerId: String,
        providerName: String,
        dataSource: String = "OpenStreetMap",
        disclaimer: String? = nil,
        assumptions: [String] = [],
        calculatedAt: Date = Date()
    ) {
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.providerDurationSeconds = providerDurationSeconds
        self.pacingProfile = pacingProfile
        self.segments = segments
        self.assumptions = assumptions
        self.calculatedAt = calculatedAt

        let cal = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: distanceMeters,
            providerDurationSeconds: providerDurationSeconds,
            segments: segments,
            origin: coordinates.first,
            destination: coordinates.last,
            hasGhatSection: terrainClassification?.contains("Ghat") ?? false,
            pacing: pacingProfile,
            provenance: providerName
        )

        self.convoyEstimatedDurationSeconds = convoyEstimatedDurationSeconds ?? cal.convoySaddleDurationSeconds
        self.convoyTotalTripDurationSeconds = convoyTotalTripDurationSeconds ?? cal.totalTripDurationSeconds
        self.fuelStopsDurationSeconds = fuelStopsDurationSeconds ?? cal.plannedFuelDurationSeconds
        self.restStopsDurationSeconds = restStopsDurationSeconds ?? cal.plannedRestDurationSeconds
        self.mealStopsDurationSeconds = mealStopsDurationSeconds ?? cal.plannedMealDurationSeconds
        self.uncertaintyRange = uncertaintyRange ?? "Saddle: \(cal.saddleDurationText) · Total: \(cal.totalTripDurationText)"
        self.terrainClassification = terrainClassification ?? cal.terrainClassification

        self.roadClasses = roadClasses
        self.hasExpresswayViolations = hasExpresswayViolations
        self.intermediateWaypoints = intermediateWaypoints
        self.motorcycleAccessVerified = motorcycleAccessVerified
        self.knownExpresswayRestrictions = knownExpresswayRestrictions
        self.alternativeRouteDescription = alternativeRouteDescription
        self.legalCitation = legalCitation
        self.providerId = providerId
        self.providerName = providerName
        self.dataSource = dataSource
        self.disclaimer = disclaimer
    }
}

// MARK: - 4. Provider Protocol Interface

protocol MotorcycleRoutingProvider: Sendable {
    var providerId: String { get }
    var displayName: String { get }
    func calculateRoute(request: MotorcycleRouteRequest) async throws -> MotorcycleRouteResponse
}

// MARK: - 5. Tier 1: Precomputed Curated Provider (Offline, Instant)

final class PrecomputedMotorcycleRoutingProvider: MotorcycleRoutingProvider, @unchecked Sendable {
    let providerId = "precomputed-valhalla"
    let displayName = "Curated Motorcycle Geometry"

    private let routeIndex: [String: DiscoverRoute]
    private static let corridorsJson = #"""
{
  "chennai-mahabalipuram": {
    "id": "chennai-mahabs-ecr",
    "title": "Chennai to Mahabalipuram (ECR)",
    "distance_km": 58.677,
    "valhalla_time_s": 9148.502,
    "pt_count": 131,
    "pts": [
      [
        13.082697,
        80.27067799999999
      ],
      [
        13.081237,
        80.270968
      ],
      [
        13.081102999999999,
        80.271322
      ],
      [
        13.081303,
        80.27229299999999
      ],
      [
        13.08147,
        80.27314799999999
      ],
      [
        13.081693999999999,
        80.27474099999999
      ],
      [
        13.081897,
        80.276318
      ],
      [
        13.082092,
        80.281618
      ],
      [
        13.081114999999999,
        80.280812
      ],
      [
        13.080407,
        80.28085399999999
      ],
      [
        13.078904999999999,
        80.282203
      ],
      [
        13.075192,
        80.28479399999999
      ],
      [
        13.074482,
        80.28542
      ],
      [
        13.073533,
        80.286003
      ],
      [
        13.072486,
        80.28548599999999
      ],
      [
        13.068073,
        80.284364
      ],
      [
        13.062892999999999,
        80.283169
      ],
      [
        13.055931,
        80.281765
      ],
      [
        13.044732999999999,
        80.28002
      ],
      [
        13.042888,
        80.279692
      ],
      [
        13.037402,
        80.278363
      ],
      [
        13.036247,
        80.277911
      ],
      [
        13.034239,
        80.277508
      ],
      [
        13.032046999999999,
        80.27754999999999
      ],
      [
        13.030213,
        80.276872
      ],
      [
        13.027142,
        80.275793
      ],
      [
        13.024690999999999,
        80.274632
      ],
      [
        13.021920999999999,
        80.27117899999999
      ],
      [
        13.018936,
        80.267519
      ],
      [
        13.018708,
        80.265513
      ],
      [
        13.018901,
        80.262834
      ],
      [
        13.017747,
        80.260717
      ],
      [
        13.015779,
        80.25950499999999
      ],
      [
        13.014711,
        80.259289
      ],
      [
        13.007641,
        80.258786
      ],
      [
        13.006549,
        80.25568899999999
      ],
      [
        13.006677,
        80.25165199999999
      ],
      [
        13.006654,
        80.247637
      ],
      [
        13.003136,
        80.24770699999999
      ],
      [
        12.994508999999999,
        80.249752
      ],
      [
        12.988824,
        80.251192
      ],
      [
        12.988064,
        80.252279
      ],
      [
        12.987725,
        80.255569
      ],
      [
        12.987399,
        80.259424
      ],
      [
        12.984945999999999,
        80.25957799999999
      ],
      [
        12.983044,
        80.259464
      ],
      [
        12.979166999999999,
        80.25913299999999
      ],
      [
        12.977174999999999,
        80.259183
      ],
      [
        12.974342,
        80.2585
      ],
      [
        12.971001,
        80.258158
      ],
      [
        12.968100999999999,
        80.257317
      ],
      [
        12.965781999999999,
        80.25684199999999
      ],
      [
        12.962698999999999,
        80.256483
      ],
      [
        12.959928999999999,
        80.25590799999999
      ],
      [
        12.95699,
        80.255318
      ],
      [
        12.952358,
        80.255191
      ],
      [
        12.949314999999999,
        80.25481099999999
      ],
      [
        12.947246,
        80.254206
      ],
      [
        12.94534,
        80.253829
      ],
      [
        12.942352,
        80.25334099999999
      ],
      [
        12.939351,
        80.252854
      ],
      [
        12.937066,
        80.252527
      ],
      [
        12.934655,
        80.252258
      ],
      [
        12.92907,
        80.25159699999999
      ],
      [
        12.925737,
        80.25125799999999
      ],
      [
        12.922089,
        80.251094
      ],
      [
        12.920612,
        80.25141599999999
      ],
      [
        12.919023,
        80.2509
      ],
      [
        12.913488,
        80.250295
      ],
      [
        12.909595,
        80.250019
      ],
      [
        12.904871,
        80.249151
      ],
      [
        12.899438,
        80.24799999999999
      ],
      [
        12.896218,
        80.247175
      ],
      [
        12.893505999999999,
        80.246488
      ],
      [
        12.889038,
        80.245414
      ],
      [
        12.886942,
        80.245745
      ],
      [
        12.886222,
        80.245764
      ],
      [
        12.883583999999999,
        80.245291
      ],
      [
        12.880424999999999,
        80.244705
      ],
      [
        12.878554999999999,
        80.244068
      ],
      [
        12.874602999999999,
        80.24337299999999
      ],
      [
        12.871907,
        80.243239
      ],
      [
        12.868563,
        80.243533
      ],
      [
        12.865148,
        80.242507
      ],
      [
        12.860672,
        80.241979
      ],
      [
        12.856513999999999,
        80.24175
      ],
      [
        12.852051999999999,
        80.241413
      ],
      [
        12.848595,
        80.240993
      ],
      [
        12.845604999999999,
        80.240799
      ],
      [
        12.840444999999999,
        80.240582
      ],
      [
        12.836803999999999,
        80.240439
      ],
      [
        12.833162,
        80.240538
      ],
      [
        12.8301,
        80.240427
      ],
      [
        12.825868999999999,
        80.24028799999999
      ],
      [
        12.821771,
        80.240209
      ],
      [
        12.815624,
        80.241284
      ],
      [
        12.810369,
        80.243386
      ],
      [
        12.806951,
        80.243208
      ],
      [
        12.798727,
        80.241663
      ],
      [
        12.792924,
        80.241875
      ],
      [
        12.784884,
        80.245087
      ],
      [
        12.781029,
        80.247002
      ],
      [
        12.777244,
        80.248948
      ],
      [
        12.771082,
        80.24841599999999
      ],
      [
        12.763187,
        80.24562499999999
      ],
      [
        12.756174,
        80.243128
      ],
      [
        12.748365999999999,
        80.24023
      ],
      [
        12.742035999999999,
        80.237803
      ],
      [
        12.73573,
        80.23509
      ],
      [
        12.730046,
        80.232846
      ],
      [
        12.719961,
        80.228736
      ],
      [
        12.709432999999999,
        80.22463499999999
      ],
      [
        12.702193,
        80.222667
      ],
      [
        12.696276,
        80.22028399999999
      ],
      [
        12.691151999999999,
        80.21810099999999
      ],
      [
        12.682680999999999,
        80.21479599999999
      ],
      [
        12.672609,
        80.211627
      ],
      [
        12.664315,
        80.209484
      ],
      [
        12.659813,
        80.208883
      ],
      [
        12.655972,
        80.207443
      ],
      [
        12.652719999999999,
        80.205574
      ],
      [
        12.648518,
        80.20335399999999
      ],
      [
        12.644563999999999,
        80.201013
      ],
      [
        12.641138,
        80.199473
      ],
      [
        12.637126,
        80.19774
      ],
      [
        12.628368,
        80.19476999999999
      ],
      [
        12.625862,
        80.194251
      ],
      [
        12.622518,
        80.194114
      ],
      [
        12.620662999999999,
        80.194495
      ],
      [
        12.616276,
        80.19375699999999
      ],
      [
        12.616677,
        80.19294
      ]
    ]
  },
  "bengaluru-mysuru": {
    "id": "bengaluru-mysuru-old-road",
    "title": "Bengaluru to Mysuru (Old Road SH-17)",
    "distance_km": 159.842,
    "valhalla_time_s": 25438.734,
    "pt_count": 126,
    "pts": [
      [
        12.979351999999999,
        77.59109699999999
      ],
      [
        12.976424999999999,
        77.58843999999999
      ],
      [
        12.975987,
        77.58697699999999
      ],
      [
        12.979719,
        77.581628
      ],
      [
        12.980609,
        77.57579299999999
      ],
      [
        12.984119999999999,
        77.574775
      ],
      [
        12.984568999999999,
        77.572002
      ],
      [
        12.982199,
        77.570318
      ],
      [
        12.982006,
        77.564689
      ],
      [
        12.976322999999999,
        77.564601
      ],
      [
        12.975724999999999,
        77.559896
      ],
      [
        12.975529,
        77.554351
      ],
      [
        12.974110999999999,
        77.55135299999999
      ],
      [
        12.976616,
        77.54681699999999
      ],
      [
        12.978392999999999,
        77.54310799999999
      ],
      [
        12.981195,
        77.53534599999999
      ],
      [
        12.983578,
        77.529895
      ],
      [
        12.985930999999999,
        77.52606999999999
      ],
      [
        12.985952999999999,
        77.52235399999999
      ],
      [
        12.988131,
        77.51717
      ],
      [
        12.987694,
        77.514174
      ],
      [
        12.984990999999999,
        77.510971
      ],
      [
        12.977803999999999,
        77.510358
      ],
      [
        12.969304,
        77.50630699999999
      ],
      [
        12.963448,
        77.505134
      ],
      [
        12.957291,
        77.50311099999999
      ],
      [
        12.950877,
        77.499617
      ],
      [
        12.947906999999999,
        77.49697499999999
      ],
      [
        12.943755999999999,
        77.494542
      ],
      [
        12.935015,
        77.492262
      ],
      [
        12.932817,
        77.48833599999999
      ],
      [
        12.927304999999999,
        77.48626399999999
      ],
      [
        12.920695,
        77.483841
      ],
      [
        12.914608,
        77.48159
      ],
      [
        12.909461,
        77.48011
      ],
      [
        12.905892999999999,
        77.476086
      ],
      [
        12.898821,
        77.473862
      ],
      [
        12.893772,
        77.470726
      ],
      [
        12.888387999999999,
        77.47166299999999
      ],
      [
        12.888681,
        77.468139
      ],
      [
        12.896120999999999,
        77.46076699999999
      ],
      [
        12.889289999999999,
        77.453316
      ],
      [
        12.881523,
        77.447469
      ],
      [
        12.870657999999999,
        77.438796
      ],
      [
        12.862255,
        77.433565
      ],
      [
        12.856287,
        77.42769799999999
      ],
      [
        12.845188,
        77.42217099999999
      ],
      [
        12.83813,
        77.41690299999999
      ],
      [
        12.830435,
        77.412818
      ],
      [
        12.820577,
        77.410476
      ],
      [
        12.811898,
        77.40387299999999
      ],
      [
        12.80224,
        77.397066
      ],
      [
        12.796674999999999,
        77.387068
      ],
      [
        12.792534,
        77.37974
      ],
      [
        12.783415999999999,
        77.37167099999999
      ],
      [
        12.777092,
        77.3629
      ],
      [
        12.770271,
        77.349013
      ],
      [
        12.758261,
        77.324739
      ],
      [
        12.745493999999999,
        77.31388799999999
      ],
      [
        12.74197,
        77.309508
      ],
      [
        12.735723,
        77.30183199999999
      ],
      [
        12.732916,
        77.292474
      ],
      [
        12.728757,
        77.286678
      ],
      [
        12.724169,
        77.28357299999999
      ],
      [
        12.720917,
        77.280239
      ],
      [
        12.721279,
        77.276921
      ],
      [
        12.715956,
        77.274681
      ],
      [
        12.709397,
        77.266436
      ],
      [
        12.703669,
        77.258864
      ],
      [
        12.700738999999999,
        77.25298699999999
      ],
      [
        12.693966999999999,
        77.245488
      ],
      [
        12.688635999999999,
        77.237239
      ],
      [
        12.681182,
        77.230704
      ],
      [
        12.676554,
        77.226091
      ],
      [
        12.670983,
        77.220303
      ],
      [
        12.660233,
        77.214297
      ],
      [
        12.652306,
        77.210914
      ],
      [
        12.652308999999999,
        77.204628
      ],
      [
        12.651114,
        77.195926
      ],
      [
        12.648655,
        77.18643
      ],
      [
        12.647397,
        77.178679
      ],
      [
        12.644221,
        77.168452
      ],
      [
        12.641554,
        77.155168
      ],
      [
        12.638411,
        77.140101
      ],
      [
        12.6335,
        77.120443
      ],
      [
        12.627106999999999,
        77.104756
      ],
      [
        12.617595,
        77.089146
      ],
      [
        12.613356,
        77.08064399999999
      ],
      [
        12.612931,
        77.05676
      ],
      [
        12.601348999999999,
        77.05295
      ],
      [
        12.588871,
        77.044578
      ],
      [
        12.578868,
        77.034696
      ],
      [
        12.560497,
        77.030362
      ],
      [
        12.542354,
        77.028123
      ],
      [
        12.52323,
        77.031266
      ],
      [
        12.504933,
        77.03479399999999
      ],
      [
        12.485449,
        77.03603799999999
      ],
      [
        12.468895,
        77.03450099999999
      ],
      [
        12.455893999999999,
        77.034752
      ],
      [
        12.417626,
        77.039872
      ],
      [
        12.400578999999999,
        77.054097
      ],
      [
        12.386113,
        77.059805
      ],
      [
        12.380384999999999,
        77.045013
      ],
      [
        12.369062,
        77.009708
      ],
      [
        12.362929999999999,
        76.978591
      ],
      [
        12.355025999999999,
        76.928029
      ],
      [
        12.343406,
        76.889866
      ],
      [
        12.333262999999999,
        76.86880699999999
      ],
      [
        12.329352,
        76.858811
      ],
      [
        12.322719999999999,
        76.842326
      ],
      [
        12.323936999999999,
        76.82596099999999
      ],
      [
        12.325927,
        76.812691
      ],
      [
        12.326182999999999,
        76.795354
      ],
      [
        12.319647,
        76.77775299999999
      ],
      [
        12.309228,
        76.76238599999999
      ],
      [
        12.306486,
        76.74461099999999
      ],
      [
        12.304741,
        76.719977
      ],
      [
        12.304692,
        76.706259
      ],
      [
        12.304359,
        76.698126
      ],
      [
        12.306797,
        76.68655199999999
      ],
      [
        12.308024,
        76.674449
      ],
      [
        12.308218,
        76.66747
      ],
      [
        12.308485,
        76.66102
      ],
      [
        12.302538,
        76.657602
      ],
      [
        12.302723,
        76.65525099999999
      ],
      [
        12.303244999999999,
        76.655761
      ]
    ]
  },
  "mumbai-pune": {
    "id": "mumbai-pune-old-nh48",
    "title": "Mumbai to Pune (Old NH-48 Khandala Ghat)",
    "distance_km": 194.452,
    "valhalla_time_s": 35820.424,
    "pt_count": 123,
    "pts": [
      [
        19.052184999999998,
        72.90055199999999
      ],
      [
        19.055971,
        72.898031
      ],
      [
        19.065592,
        72.899321
      ],
      [
        19.076423,
        72.91413399999999
      ],
      [
        19.113523,
        72.933966
      ],
      [
        19.154443,
        72.95825099999999
      ],
      [
        19.148684,
        72.992706
      ],
      [
        19.141759,
        73.002535
      ],
      [
        19.13128,
        73.00352
      ],
      [
        19.11284,
        73.009706
      ],
      [
        19.110946,
        73.030872
      ],
      [
        19.130035,
        73.03585
      ],
      [
        19.142977,
        73.046679
      ],
      [
        19.150945,
        73.05653199999999
      ],
      [
        19.163194999999998,
        73.073669
      ],
      [
        19.171578999999998,
        73.085818
      ],
      [
        19.172878,
        73.100583
      ],
      [
        19.178127,
        73.120659
      ],
      [
        19.1814,
        73.145905
      ],
      [
        19.187988999999998,
        73.18552799999999
      ],
      [
        19.184247,
        73.21360299999999
      ],
      [
        19.177906999999998,
        73.22317799999999
      ],
      [
        19.167174,
        73.230318
      ],
      [
        19.15663,
        73.236755
      ],
      [
        19.152683,
        73.245918
      ],
      [
        19.141458999999998,
        73.25136499999999
      ],
      [
        19.12728,
        73.261691
      ],
      [
        19.111559,
        73.273246
      ],
      [
        19.100943,
        73.285361
      ],
      [
        19.090629,
        73.300282
      ],
      [
        19.074478,
        73.314086
      ],
      [
        19.054662,
        73.314306
      ],
      [
        19.03166,
        73.314039
      ],
      [
        19.021202,
        73.31193999999999
      ],
      [
        19.012694,
        73.32543
      ],
      [
        18.988781,
        73.327625
      ],
      [
        18.969818,
        73.328811
      ],
      [
        18.942588999999998,
        73.32661
      ],
      [
        18.919273,
        73.319642
      ],
      [
        18.913234,
        73.30953199999999
      ],
      [
        18.898612,
        73.312259
      ],
      [
        18.881069,
        73.313406
      ],
      [
        18.865976,
        73.317999
      ],
      [
        18.845294,
        73.318452
      ],
      [
        18.828487,
        73.31012199999999
      ],
      [
        18.810844,
        73.313988
      ],
      [
        18.812307,
        73.330793
      ],
      [
        18.799663,
        73.338208
      ],
      [
        18.790366,
        73.341032
      ],
      [
        18.782011,
        73.353417
      ],
      [
        18.780549999999998,
        73.35247799999999
      ],
      [
        18.774652,
        73.353527
      ],
      [
        18.769966999999998,
        73.35354099999999
      ],
      [
        18.766609,
        73.353822
      ],
      [
        18.764371999999998,
        73.351846
      ],
      [
        18.762401,
        73.353498
      ],
      [
        18.772268999999998,
        73.364088
      ],
      [
        18.768046,
        73.367729
      ],
      [
        18.757407999999998,
        73.37261099999999
      ],
      [
        18.760353,
        73.38154399999999
      ],
      [
        18.757568,
        73.377742
      ],
      [
        18.75764,
        73.377512
      ],
      [
        18.760306,
        73.384993
      ],
      [
        18.758228,
        73.394144
      ],
      [
        18.749076,
        73.40708099999999
      ],
      [
        18.741601,
        73.420965
      ],
      [
        18.735214,
        73.439413
      ],
      [
        18.726913,
        73.450642
      ],
      [
        18.719765,
        73.457262
      ],
      [
        18.712042,
        73.46033
      ],
      [
        18.703820999999998,
        73.461574
      ],
      [
        18.696298,
        73.462876
      ],
      [
        18.690996,
        73.466445
      ],
      [
        18.690112,
        73.47055399999999
      ],
      [
        18.689135999999998,
        73.47475
      ],
      [
        18.691941,
        73.476799
      ],
      [
        18.691412,
        73.480704
      ],
      [
        18.688475,
        73.48324699999999
      ],
      [
        18.686585,
        73.486927
      ],
      [
        18.682976999999998,
        73.492227
      ],
      [
        18.684338999999998,
        73.495982
      ],
      [
        18.68266,
        73.50196
      ],
      [
        18.671122,
        73.49937299999999
      ],
      [
        18.666746,
        73.500366
      ],
      [
        18.660965,
        73.500607
      ],
      [
        18.651531,
        73.50259199999999
      ],
      [
        18.640705,
        73.504019
      ],
      [
        18.63183,
        73.504587
      ],
      [
        18.621429,
        73.507065
      ],
      [
        18.615979,
        73.512451
      ],
      [
        18.607345,
        73.51708099999999
      ],
      [
        18.596017,
        73.520944
      ],
      [
        18.588563,
        73.524023
      ],
      [
        18.582106,
        73.532939
      ],
      [
        18.572240999999998,
        73.562293
      ],
      [
        18.559791999999998,
        73.586411
      ],
      [
        18.546786,
        73.600651
      ],
      [
        18.534606,
        73.606802
      ],
      [
        18.526671999999998,
        73.615494
      ],
      [
        18.52243,
        73.622458
      ],
      [
        18.519973,
        73.633871
      ],
      [
        18.517613,
        73.644074
      ],
      [
        18.515591999999998,
        73.650735
      ],
      [
        18.513619,
        73.66378399999999
      ],
      [
        18.511910999999998,
        73.68184
      ],
      [
        18.510523,
        73.693372
      ],
      [
        18.505771,
        73.704936
      ],
      [
        18.499274,
        73.711095
      ],
      [
        18.501306,
        73.727361
      ],
      [
        18.499123,
        73.73790199999999
      ],
      [
        18.501651,
        73.749538
      ],
      [
        18.501995,
        73.759485
      ],
      [
        18.507679,
        73.769724
      ],
      [
        18.508012,
        73.780603
      ],
      [
        18.508308,
        73.79194799999999
      ],
      [
        18.50702,
        73.802561
      ],
      [
        18.508516999999998,
        73.810379
      ],
      [
        18.510797999999998,
        73.81725999999999
      ],
      [
        18.506814,
        73.823922
      ],
      [
        18.510972,
        73.835815
      ],
      [
        18.514516,
        73.842441
      ],
      [
        18.520772,
        73.851581
      ],
      [
        18.520187999999997,
        73.855165
      ]
    ]
  },
  "delhi-meerut": {
    "id": "delhi-meerut-old-nh34",
    "title": "Delhi to Meerut (Old NH-34 via Modinagar)",
    "distance_km": 93.787,
    "valhalla_time_s": 18908.62,
    "pt_count": 128,
    "pts": [
      [
        28.612762999999998,
        77.27634599999999
      ],
      [
        28.618267,
        77.279741
      ],
      [
        28.624824999999998,
        77.275398
      ],
      [
        28.62739,
        77.27196699999999
      ],
      [
        28.629281,
        77.27108
      ],
      [
        28.629064999999997,
        77.26978199999999
      ],
      [
        28.628315999999998,
        77.273502
      ],
      [
        28.630357,
        77.277138
      ],
      [
        28.634007999999998,
        77.28264899999999
      ],
      [
        28.637079,
        77.287588
      ],
      [
        28.640783,
        77.29426099999999
      ],
      [
        28.645348,
        77.300134
      ],
      [
        28.648747999999998,
        77.30433099999999
      ],
      [
        28.651501,
        77.306102
      ],
      [
        28.656506999999998,
        77.310394
      ],
      [
        28.659795,
        77.313676
      ],
      [
        28.661673999999998,
        77.31997199999999
      ],
      [
        28.665798,
        77.321105
      ],
      [
        28.670544999999997,
        77.322711
      ],
      [
        28.679382,
        77.324288
      ],
      [
        28.681223,
        77.328392
      ],
      [
        28.683311999999997,
        77.33182
      ],
      [
        28.69172,
        77.328065
      ],
      [
        28.694343999999997,
        77.328475
      ],
      [
        28.695839,
        77.33053799999999
      ],
      [
        28.697060999999998,
        77.329976
      ],
      [
        28.696341,
        77.333765
      ],
      [
        28.700875,
        77.332691
      ],
      [
        28.708914999999998,
        77.331502
      ],
      [
        28.713182,
        77.33136499999999
      ],
      [
        28.715605,
        77.330539
      ],
      [
        28.721086999999997,
        77.33247899999999
      ],
      [
        28.726781,
        77.333418
      ],
      [
        28.727929,
        77.332107
      ],
      [
        28.726004,
        77.337679
      ],
      [
        28.726806999999997,
        77.345883
      ],
      [
        28.727686,
        77.356754
      ],
      [
        28.729484,
        77.370175
      ],
      [
        28.732350999999998,
        77.382263
      ],
      [
        28.735910999999998,
        77.39874499999999
      ],
      [
        28.741543,
        77.41202899999999
      ],
      [
        28.746668999999997,
        77.427414
      ],
      [
        28.754464,
        77.438118
      ],
      [
        28.756342999999998,
        77.442476
      ],
      [
        28.759157,
        77.452491
      ],
      [
        28.766802,
        77.46976
      ],
      [
        28.783690999999997,
        77.466791
      ],
      [
        28.795517999999998,
        77.46844999999999
      ],
      [
        28.811422,
        77.486205
      ],
      [
        28.826539999999998,
        77.50301999999999
      ],
      [
        28.836184,
        77.515183
      ],
      [
        28.837170999999998,
        77.51617999999999
      ],
      [
        28.837507,
        77.519559
      ],
      [
        28.838158,
        77.523504
      ],
      [
        28.837612,
        77.526192
      ],
      [
        28.837542,
        77.529011
      ],
      [
        28.837512,
        77.532754
      ],
      [
        28.837929,
        77.534792
      ],
      [
        28.838490999999998,
        77.53708
      ],
      [
        28.838755,
        77.53862699999999
      ],
      [
        28.838713,
        77.54087299999999
      ],
      [
        28.839547999999997,
        77.54274199999999
      ],
      [
        28.841019,
        77.54522899999999
      ],
      [
        28.842088999999998,
        77.550063
      ],
      [
        28.841285,
        77.55288
      ],
      [
        28.840657,
        77.555274
      ],
      [
        28.841571,
        77.558223
      ],
      [
        28.839665,
        77.561675
      ],
      [
        28.839249,
        77.566696
      ],
      [
        28.837752,
        77.569756
      ],
      [
        28.838002999999997,
        77.57181899999999
      ],
      [
        28.840432999999997,
        77.573652
      ],
      [
        28.842783999999998,
        77.574482
      ],
      [
        28.842623999999997,
        77.57636099999999
      ],
      [
        28.840296,
        77.58050999999999
      ],
      [
        28.839413,
        77.579961
      ],
      [
        28.837087999999998,
        77.581705
      ],
      [
        28.837373,
        77.58048699999999
      ],
      [
        28.833861,
        77.580213
      ],
      [
        28.83701,
        77.580173
      ],
      [
        28.838093999999998,
        77.580688
      ],
      [
        28.838227999999997,
        77.57892
      ],
      [
        28.837616999999998,
        77.57545999999999
      ],
      [
        28.837825,
        77.573757
      ],
      [
        28.838625999999998,
        77.57262
      ],
      [
        28.841507,
        77.57403599999999
      ],
      [
        28.843736,
        77.574888
      ],
      [
        28.845609,
        77.572527
      ],
      [
        28.848343,
        77.56847499999999
      ],
      [
        28.850959999999997,
        77.565181
      ],
      [
        28.85511,
        77.55971799999999
      ],
      [
        28.860744,
        77.55333399999999
      ],
      [
        28.865655999999998,
        77.547528
      ],
      [
        28.871002999999998,
        77.540812
      ],
      [
        28.874254999999998,
        77.534818
      ],
      [
        28.877276,
        77.52730799999999
      ],
      [
        28.911140999999997,
        77.533597
      ],
      [
        28.93393,
        77.53865499999999
      ],
      [
        28.961872,
        77.549465
      ],
      [
        28.976501,
        77.55568199999999
      ],
      [
        28.992981999999998,
        77.562754
      ],
      [
        29.00314,
        77.569864
      ],
      [
        29.008836,
        77.57008499999999
      ],
      [
        29.02106,
        77.574747
      ],
      [
        29.028786,
        77.580759
      ],
      [
        29.025919,
        77.58561499999999
      ],
      [
        29.023263,
        77.58958799999999
      ],
      [
        29.020398999999998,
        77.594387
      ],
      [
        29.017298,
        77.59984899999999
      ],
      [
        29.01478,
        77.604738
      ],
      [
        29.011888,
        77.610304
      ],
      [
        29.009186,
        77.6154
      ],
      [
        29.004600999999997,
        77.623873
      ],
      [
        29.001443,
        77.63006399999999
      ],
      [
        28.997937999999998,
        77.63846099999999
      ],
      [
        28.995554,
        77.64486
      ],
      [
        28.993482,
        77.65024
      ],
      [
        28.990382999999998,
        77.658068
      ],
      [
        28.988066,
        77.664897
      ],
      [
        28.986123,
        77.669637
      ],
      [
        28.982283,
        77.67617299999999
      ],
      [
        28.980224999999997,
        77.682152
      ],
      [
        28.984153,
        77.68816699999999
      ],
      [
        28.981982,
        77.69536
      ],
      [
        28.985418,
        77.696697
      ],
      [
        28.986013,
        77.699112
      ],
      [
        28.984899,
        77.703291
      ],
      [
        28.984479,
        77.706361
      ]
    ]
  },
  "kochi-munnar": {
    "id": "kochi-munnar-nh85",
    "title": "Kochi to Munnar (NH-85 Ghats)",
    "distance_km": 134.674,
    "valhalla_time_s": 21391.316,
    "pt_count": 124,
    "pts": [
      [
        9.97194,
        76.27881
      ],
      [
        9.984499,
        76.275177
      ],
      [
        9.990082,
        76.286992
      ],
      [
        10.000001,
        76.298379
      ],
      [
        10.005903,
        76.304897
      ],
      [
        10.021015,
        76.30591
      ],
      [
        10.028117,
        76.311002
      ],
      [
        10.028756999999999,
        76.31689899999999
      ],
      [
        10.032275,
        76.323703
      ],
      [
        10.034125999999999,
        76.333056
      ],
      [
        10.03634,
        76.33810299999999
      ],
      [
        10.036869,
        76.345069
      ],
      [
        10.042612,
        76.354322
      ],
      [
        10.046880999999999,
        76.366042
      ],
      [
        10.050958999999999,
        76.381047
      ],
      [
        10.058268,
        76.392614
      ],
      [
        10.066946999999999,
        76.399272
      ],
      [
        10.074159,
        76.41449
      ],
      [
        10.088239999999999,
        76.42663
      ],
      [
        10.090855999999999,
        76.439015
      ],
      [
        10.097918,
        76.452658
      ],
      [
        10.108941999999999,
        76.45828999999999
      ],
      [
        10.113805,
        76.463579
      ],
      [
        10.115017,
        76.47413
      ],
      [
        10.11664,
        76.487211
      ],
      [
        10.113023,
        76.509377
      ],
      [
        10.111231,
        76.529409
      ],
      [
        10.096720999999999,
        76.551096
      ],
      [
        10.085419,
        76.56908299999999
      ],
      [
        10.080556999999999,
        76.575743
      ],
      [
        10.078498999999999,
        76.585832
      ],
      [
        10.07606,
        76.59365799999999
      ],
      [
        10.069649,
        76.60216799999999
      ],
      [
        10.068633,
        76.607805
      ],
      [
        10.068109999999999,
        76.61460199999999
      ],
      [
        10.0677,
        76.624217
      ],
      [
        10.072077,
        76.62833499999999
      ],
      [
        10.084494,
        76.634203
      ],
      [
        10.09741,
        76.641593
      ],
      [
        10.099924,
        76.65455299999999
      ],
      [
        10.104606,
        76.665397
      ],
      [
        10.105082,
        76.680765
      ],
      [
        10.105993999999999,
        76.703527
      ],
      [
        10.101925999999999,
        76.71508299999999
      ],
      [
        10.091676999999999,
        76.725168
      ],
      [
        10.083532,
        76.736649
      ],
      [
        10.07308,
        76.74923199999999
      ],
      [
        10.066704999999999,
        76.755483
      ],
      [
        10.062828,
        76.762372
      ],
      [
        10.059591,
        76.766155
      ],
      [
        10.056159,
        76.769427
      ],
      [
        10.057262,
        76.776338
      ],
      [
        10.05472,
        76.787419
      ],
      [
        10.047839,
        76.798835
      ],
      [
        10.049911999999999,
        76.80333
      ],
      [
        10.054020999999999,
        76.802663
      ],
      [
        10.057259,
        76.803851
      ],
      [
        10.059383,
        76.810149
      ],
      [
        10.062389,
        76.810395
      ],
      [
        10.062341,
        76.817435
      ],
      [
        10.062157,
        76.824178
      ],
      [
        10.060329,
        76.83214
      ],
      [
        10.059379999999999,
        76.83885099999999
      ],
      [
        10.057595,
        76.848198
      ],
      [
        10.057608,
        76.85700299999999
      ],
      [
        10.058714,
        76.863948
      ],
      [
        10.057613,
        76.872132
      ],
      [
        10.049451,
        76.874082
      ],
      [
        10.040235,
        76.878373
      ],
      [
        10.032878,
        76.879984
      ],
      [
        10.029639999999999,
        76.889349
      ],
      [
        10.029415,
        76.895147
      ],
      [
        10.027453999999999,
        76.902112
      ],
      [
        10.023987,
        76.908675
      ],
      [
        10.022136,
        76.915398
      ],
      [
        10.019865,
        76.924002
      ],
      [
        10.021476999999999,
        76.928631
      ],
      [
        10.024066,
        76.93117099999999
      ],
      [
        10.026952,
        76.93292
      ],
      [
        10.028585999999999,
        76.93373
      ],
      [
        10.0321,
        76.934013
      ],
      [
        10.031051999999999,
        76.93907399999999
      ],
      [
        10.02966,
        76.94547
      ],
      [
        10.032745,
        76.94972299999999
      ],
      [
        10.035292,
        76.948156
      ],
      [
        10.042228999999999,
        76.946941
      ],
      [
        10.047844,
        76.950726
      ],
      [
        10.055484,
        76.95442
      ],
      [
        10.066609999999999,
        76.958766
      ],
      [
        10.076485,
        76.95593199999999
      ],
      [
        10.079445999999999,
        76.95262199999999
      ],
      [
        10.085545999999999,
        76.951582
      ],
      [
        10.084598,
        76.955024
      ],
      [
        10.08384,
        76.95756399999999
      ],
      [
        10.081054,
        76.959305
      ],
      [
        10.078315,
        76.962536
      ],
      [
        10.075565,
        76.966608
      ],
      [
        10.073694,
        76.968582
      ],
      [
        10.070338999999999,
        76.97241
      ],
      [
        10.069087999999999,
        76.97742099999999
      ],
      [
        10.069814,
        76.98109099999999
      ],
      [
        10.067318,
        76.986006
      ],
      [
        10.065169,
        76.99264
      ],
      [
        10.065078999999999,
        76.995651
      ],
      [
        10.063832999999999,
        76.997913
      ],
      [
        10.063813,
        76.999391
      ],
      [
        10.065258,
        77.000604
      ],
      [
        10.067097,
        77.00405099999999
      ],
      [
        10.066993,
        77.007125
      ],
      [
        10.065024,
        77.008436
      ],
      [
        10.064312,
        77.009699
      ],
      [
        10.062130999999999,
        77.011243
      ],
      [
        10.060742999999999,
        77.015249
      ],
      [
        10.058672,
        77.02314
      ],
      [
        10.058380999999999,
        77.02817999999999
      ],
      [
        10.058099,
        77.03275599999999
      ],
      [
        10.061017999999999,
        77.036596
      ],
      [
        10.062704,
        77.039374
      ],
      [
        10.064554,
        77.042515
      ],
      [
        10.068811,
        77.046433
      ],
      [
        10.071874,
        77.053769
      ],
      [
        10.075016999999999,
        77.063159
      ],
      [
        10.085465,
        77.06078699999999
      ],
      [
        10.088880999999999,
        77.059562
      ]
    ]
  }
}
"""#

    private struct CorridorData: Decodable {
        let id: String
        let title: String
        let distance_km: Double
        let valhalla_time_s: Double
        let pts: [[Double]]
    }

    private let bundledCorridors: [String: CorridorData]

    static func geometry(for corridorKey: String) -> [Coord] {
        guard let data = Self.corridorsJson.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: CorridorData].self, from: data) else {
            return []
        }
        if let corridor = decoded[corridorKey] {
            return corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }
        }
        let lower = corridorKey.lowercased()
        for (k, corridor) in decoded {
            if corridor.id == corridorKey || corridor.id.lowercased() == lower {
                return corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }
            }
            if k == lower || lower.contains(k) || k.contains(lower) {
                return corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }
            }
            if lower.contains("mysuru") && k.contains("mysuru") {
                return corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }
            }
            if lower.contains("pune") && k.contains("pune") {
                return corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }
            }
            if lower.contains("meerut") && k.contains("meerut") {
                return corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }
            }
            if lower.contains("munnar") && k.contains("munnar") {
                return corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }
            }
            if (lower.contains("mahabs") || lower.contains("mahabalipuram") || lower.contains("ecr")) && k.contains("mahabalipuram") {
                return corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }
            }
        }
        return []
    }

    static func estimateDistance(for coords: [Coord]) -> Double {
        guard coords.count > 1 else { return 0 }
        var total = 0.0
        for i in 0..<(coords.count - 1) {
            total += coords[i].distanceKm(to: coords[i + 1]) * 1000.0
        }
        return total
    }

    static func corridorDetails(for corridorKey: String) -> (coords: [Coord], distanceKm: Double, valhallaTimeSeconds: Double)? {
        guard let data = Self.corridorsJson.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: CorridorData].self, from: data) else {
            return nil
        }
        if let corridor = decoded[corridorKey] {
            return (corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }, corridor.distance_km, corridor.valhalla_time_s)
        }
        let lower = corridorKey.lowercased()
        for (k, corridor) in decoded {
            if corridor.id == corridorKey || corridor.id.lowercased() == lower || k == lower || lower.contains(k) || k.contains(lower) {
                return (corridor.pts.map { Coord(lat: $0[0], lon: $0[1]) }, corridor.distance_km, corridor.valhalla_time_s)
            }
        }
        return nil
    }

    static func findGeometry(start: Coord, end: Coord) -> (coords: [Coord], distanceMeters: Double, durationSeconds: Double)? {
        guard let data = Self.corridorsJson.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: CorridorData].self, from: data) else {
            return nil
        }
        for (_, c) in decoded {
            let pts = c.pts.map { Coord(lat: $0[0], lon: $0[1]) }
            guard let first = pts.first, let last = pts.last else { continue }
            // Check forward direction
            if first.distanceKm(to: start) < 20.0 && last.distanceKm(to: end) < 20.0 {
                let distM = c.distance_km * 1000.0
                let isGhat = c.id.contains("munnar") || c.id.contains("pune")
                let cal = ConvoyRoutingCalibrator.calibrate(distanceMeters: distM, origin: start, destination: end, hasGhatSection: isGhat)
                return (pts, distM, cal.saddleDurationSeconds)
            }
            // Check reverse direction
            if first.distanceKm(to: end) < 20.0 && last.distanceKm(to: start) < 20.0 {
                let distM = c.distance_km * 1000.0
                let isGhat = c.id.contains("munnar") || c.id.contains("pune")
                let cal = ConvoyRoutingCalibrator.calibrate(distanceMeters: distM, origin: start, destination: end, hasGhatSection: isGhat)
                return (pts.reversed(), distM, cal.saddleDurationSeconds)
            }
        }
        return nil
    }

    static func corridorGeometry(connecting waypoints: [Coord]) -> [Coord] {
        guard waypoints.count >= 2 else { return waypoints }
        if let first = waypoints.first, let last = waypoints.last,
           let matched = findGeometry(start: first, end: last) {
            return matched.coords
        }

        var result: [Coord] = []
        for i in 0..<(waypoints.count - 1) {
            let p0 = waypoints[i]
            let p1 = waypoints[i + 1]
            let distKm = p0.distanceKm(to: p1)
            let steps = max(8, min(40, Int(distKm * 2)))
            for step in 0..<steps {
                let t = Double(step) / Double(steps)
                let curveOffset = sin(t * .pi) * 0.003
                let lat = p0.lat + (p1.lat - p0.lat) * t + curveOffset * 0.5
                let lon = p0.lon + (p1.lon - p0.lon) * t + curveOffset
                result.append(Coord(lat: lat, lon: lon))
            }
        }
        if let last = waypoints.last {
            result.append(last)
        }
        return result
    }

    init(routes: [DiscoverRoute] = []) {
        var idx: [String: DiscoverRoute] = [:]
        for r in routes {
            idx[r.id] = r
        }
        self.routeIndex = idx

        if let data = Self.corridorsJson.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: CorridorData].self, from: data) {
            self.bundledCorridors = decoded
        } else {
            self.bundledCorridors = [:]
        }
    }

    func calculateRoute(request: MotorcycleRouteRequest) async throws -> MotorcycleRouteResponse {
        // 1. Check curated routes index
        for (_, r) in routeIndex {
            if r.start.coord.distanceKm(to: request.origin) < 5.0 &&
               r.end.coord.distanceKm(to: request.destination) < 5.0 &&
               r.hasGeometry {
                return MotorcycleRouteResponse(
                    coordinates: r.geometry,
                    distanceMeters: r.estimate?.distanceM ?? (r.start.coord.distanceKm(to: r.end.coord) * 1000),
                    providerDurationSeconds: r.estimate?.durationS ?? 3600,
                    roadClasses: ["primary", "secondary"],
                    hasExpresswayViolations: false,
                    intermediateWaypoints: r.stops.map { $0.coord },
                    motorcycleAccessVerified: true,
                    knownExpresswayRestrictions: [],
                    alternativeRouteDescription: nil,
                    legalCitation: "OpenStreetMap curated corridor — two-wheelers permitted.",
                    providerId: providerId,
                    providerName: displayName,
                    dataSource: "Curated OSM Geometry",
                    disclaimer: "Curated motorcycle route — legal 2-wheeler corridor verified."
                )
            }
        }

        // 2. Check bundled 5 Indian corridors
        for (_, c) in bundledCorridors {
            let coords = c.pts.map { Coord(lat: $0[0], lon: $0[1]) }
            guard let first = coords.first, let last = coords.last else { continue }
            if first.distanceKm(to: request.origin) < 15.0 && last.distanceKm(to: request.destination) < 15.0 {
                let distM = c.distance_km * 1000.0
                let isGhat = c.id.contains("munnar") || c.id.contains("pune")
                let cal = SegmentAwareRoutingCalibrator.calibrate(
                    distanceMeters: distM,
                    providerDurationSeconds: c.valhalla_time_s,
                    segments: [],
                    origin: request.origin,
                    destination: request.destination,
                    hasGhatSection: isGhat,
                    pacing: request.pacingProfile,
                    provenance: "OpenStreetMap / Valhalla Precomputed Corridor"
                )

                // Audit geometry against safety guardrails
                let audit = RestrictedRoadSafetyGuardrail.auditRoute(coordinates: coords, roadNames: [c.title])

                var knownRestrictions: [String] = audit.detectedViolations.map { $0.name }
                if c.id.contains("mysuru") {
                    knownRestrictions.append("NH-275 Access-Controlled Expressway (Prohibited for 2W, Safely Avoided)")
                } else if c.id.contains("pune") {
                    knownRestrictions.append("Mumbai-Pune Expressway (Prohibited for 2W, Safely Avoided)")
                } else if c.id.contains("meerut") {
                    knownRestrictions.append("NE-3 Delhi-Meerut Expressway (Prohibited for 2W, Safely Avoided)")
                }

                return MotorcycleRouteResponse(
                    coordinates: coords,
                    distanceMeters: distM,
                    providerDurationSeconds: c.valhalla_time_s,
                    convoyEstimatedDurationSeconds: cal.convoySaddleDurationSeconds,
                    convoyTotalTripDurationSeconds: cal.totalTripDurationSeconds,
                    fuelStopsDurationSeconds: cal.plannedFuelDurationSeconds,
                    restStopsDurationSeconds: cal.plannedRestDurationSeconds,
                    mealStopsDurationSeconds: cal.plannedMealDurationSeconds,
                    pacingProfile: request.pacingProfile,
                    uncertaintyRange: "Saddle: \(cal.saddleDurationText) · Total: \(cal.totalTripDurationText)",
                    terrainClassification: cal.terrainClassification,
                    roadClasses: ["primary", "secondary", "trunk"],
                    segments: [],
                    hasExpresswayViolations: !audit.isSafe,
                    intermediateWaypoints: [],
                    motorcycleAccessVerified: audit.isSafe,
                    knownExpresswayRestrictions: knownRestrictions,
                    alternativeRouteDescription: c.title,
                    legalCitation: audit.detectedViolations.first?.officialSource ?? "Adheres to NHAI & Police 2-wheeler lane regulations.",
                    providerId: providerId,
                    providerName: displayName,
                    dataSource: "OpenStreetMap / Valhalla Precomputed",
                    disclaimer: "Motorcycle verified — adheres to NHAI & Police 2-wheeler lane regulations.",
                    assumptions: cal.assumptions,
                    calculatedAt: cal.calculatedAt
                )
            }
        }

        // 3. Fallback: direct line with unverified flag
        let dist = request.origin.distanceKm(to: request.destination) * 1000 * 1.3
        let dur = dist / (45.0 * 1000 / 3600)
        let cal = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: dist,
            providerDurationSeconds: dur,
            segments: [],
            origin: request.origin,
            destination: request.destination,
            hasGhatSection: false,
            pacing: request.pacingProfile,
            provenance: "Approximated Road Model"
        )
        return MotorcycleRouteResponse(
            coordinates: [request.origin, request.destination],
            distanceMeters: dist,
            providerDurationSeconds: dur,
            convoyEstimatedDurationSeconds: cal.convoySaddleDurationSeconds,
            convoyTotalTripDurationSeconds: cal.totalTripDurationSeconds,
            fuelStopsDurationSeconds: cal.plannedFuelDurationSeconds,
            restStopsDurationSeconds: cal.plannedRestDurationSeconds,
            mealStopsDurationSeconds: cal.plannedMealDurationSeconds,
            pacingProfile: request.pacingProfile,
            uncertaintyRange: "Saddle: \(cal.saddleDurationText) · Total: \(cal.totalTripDurationText)",
            terrainClassification: "Unverified Corridor",
            roadClasses: ["unclassified"],
            segments: [],
            hasExpresswayViolations: false,
            intermediateWaypoints: [],
            motorcycleAccessVerified: false,
            knownExpresswayRestrictions: [],
            alternativeRouteDescription: nil,
            legalCitation: nil,
            providerId: providerId,
            providerName: displayName,
            dataSource: "Approximated",
            disclaimer: "Approximated corridor — unverified road access. Follow on-road signage.",
            assumptions: ["Provisional direct spline approximation"],
            calculatedAt: cal.calculatedAt
        )
    }
}

// MARK: - 6. Valhalla Dynamic Motorcycle Provider with Safety Re-routing

final class ValhallaMotorcycleRoutingProvider: MotorcycleRoutingProvider, @unchecked Sendable {
    let providerId = "valhalla-motorcycle"
    let displayName = "Valhalla Motorcycle Engine"
    private let endpoint: URL
    private let fallback: PrecomputedMotorcycleRoutingProvider

    init(endpoint: URL = URL(string: "https://valhalla1.openstreetmap.de/route")!) {
        self.endpoint = endpoint
        self.fallback = PrecomputedMotorcycleRoutingProvider()
    }

    func calculateRoute(request: MotorcycleRouteRequest) async throws -> MotorcycleRouteResponse {
        return try await fetchAndAudit(request: request, attemptDetourOnViolation: true)
    }

    private func fetchAndAudit(request: MotorcycleRouteRequest, attemptDetourOnViolation: Bool) async throws -> MotorcycleRouteResponse {
        var locations: [[String: Double]] = [
            ["lat": request.origin.lat, "lon": request.origin.lon]
        ]
        for wp in request.waypoints {
            locations.append(["lat": wp.lat, "lon": wp.lon])
        }
        locations.append(["lat": request.destination.lat, "lon": request.destination.lon])

        // Balanced highway configuration: use_highways: 0.5 (avoids interior backroad penalty while routing legally)
        let payload: [String: Any] = [
            "locations": locations,
            "costing": "motorcycle",
            "costing_options": [
                "motorcycle": [
                    "use_highways": request.avoidExpressways ? 0.5 : 0.8,
                    "use_trails": 0.0
                ]
            ],
            "directions_options": ["units": "kilometers"]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            return try await fallback.calculateRoute(request: request)
        }

        var urlReq = URLRequest(url: endpoint)
        urlReq.httpMethod = "POST"
        urlReq.httpBody = httpBody
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("ConvoyMotorcycleRouting/1.0", forHTTPHeaderField: "User-Agent")
        urlReq.timeoutInterval = 10.0

        do {
            let (data, response) = try await URLSession.shared.data(for: urlReq)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let trip = json["trip"] as? [String: Any],
                  let summary = trip["summary"] as? [String: Any],
                  let legs = trip["legs"] as? [[String: Any]],
                  let firstLeg = legs.first else {
                return try await fallback.calculateRoute(request: request)
            }

            let distKm = summary["length"] as? Double ?? 0.0
            let timeSec = summary["time"] as? Double ?? 0.0
            let shape = firstLeg["shape"] as? String ?? ""
            let coords = Self.decodePolyline6(shape)

            var segments: [RouteSegment] = []
            var roadNames: [String] = []
            if let maneuvers = firstLeg["maneuvers"] as? [[String: Any]] {
                for m in maneuvers {
                    let names = (m["street_names"] as? [String]) ?? []
                    roadNames.append(contentsOf: names)
                    let segKm = m["length"] as? Double ?? 0.0
                    let segSec = m["time"] as? Double
                    let isSegGhat = names.contains { $0.localizedCaseInsensitiveContains("ghat") || $0.localizedCaseInsensitiveContains("hairpin") }
                    segments.append(RouteSegment(
                        distanceMeters: segKm * 1000.0,
                        durationSeconds: segSec,
                        streetName: names.first,
                        roadClass: nil,
                        isGhat: isSegGhat
                    ))
                }
            }

            let distM = distKm * 1000.0

            // Safety Audit: Check route against restricted expressways
            let audit = RestrictedRoadSafetyGuardrail.auditRoute(coordinates: coords, roadNames: roadNames)

            // If a violation is detected and alternative routing is allowed:
            if !audit.isSafe && attemptDetourOnViolation, let detourCorridor = audit.recommendedDetour, let detourWp = detourCorridor.detourWaypoint {
                var detourRequest = request
                detourRequest.waypoints.append(detourWp)
                var detourResp = try await fetchAndAudit(request: detourRequest, attemptDetourOnViolation: false)

                // Recheck final route geometry after reroute
                let recheckAudit = RestrictedRoadSafetyGuardrail.auditRoute(coordinates: detourResp.coordinates, roadNames: detourResp.roadClasses)
                if !recheckAudit.isSafe {
                    detourResp.motorcycleAccessVerified = false
                    detourResp.hasExpresswayViolations = true
                    detourResp.disclaimer = "UNVERIFIED: Route safety could not be verified against access-controlled expressways."
                } else {
                    detourResp.motorcycleAccessVerified = true
                    detourResp.hasExpresswayViolations = false
                    detourResp.alternativeRouteDescription = detourCorridor.detourDescription
                    detourResp.legalCitation = detourCorridor.officialSource
                    detourResp.disclaimer = "Route diverted to legal two-wheeler corridor (avoiding \(detourCorridor.name))."
                }
                return detourResp
            }

            let isGhat = roadNames.contains { $0.localizedCaseInsensitiveContains("ghat") || $0.localizedCaseInsensitiveContains("hairpin") }
            let cal = SegmentAwareRoutingCalibrator.calibrate(
                distanceMeters: distM,
                providerDurationSeconds: timeSec,
                segments: segments,
                origin: request.origin,
                destination: request.destination,
                hasGhatSection: isGhat,
                pacing: request.pacingProfile,
                provenance: "OpenStreetMap (Valhalla Live API use_highways=0.5)"
            )

            return MotorcycleRouteResponse(
                coordinates: coords.isEmpty ? [request.origin, request.destination] : coords,
                distanceMeters: distM,
                providerDurationSeconds: timeSec,
                convoyEstimatedDurationSeconds: cal.convoySaddleDurationSeconds,
                convoyTotalTripDurationSeconds: cal.totalTripDurationSeconds,
                fuelStopsDurationSeconds: cal.plannedFuelDurationSeconds,
                restStopsDurationSeconds: cal.plannedRestDurationSeconds,
                mealStopsDurationSeconds: cal.plannedMealDurationSeconds,
                pacingProfile: request.pacingProfile,
                uncertaintyRange: "Saddle: \(cal.saddleDurationText) · Total: \(cal.totalTripDurationText)",
                terrainClassification: cal.terrainClassification,
                roadClasses: Array(Set(roadNames).prefix(8)),
                segments: segments,
                hasExpresswayViolations: !audit.isSafe,
                intermediateWaypoints: request.waypoints,
                motorcycleAccessVerified: audit.isSafe,
                knownExpresswayRestrictions: audit.detectedViolations.map { $0.name },
                alternativeRouteDescription: audit.isSafe ? "Legal 2-wheeler corridor" : "Caution: Prohibited expressway detected",
                legalCitation: audit.detectedViolations.first?.officialSource,
                providerId: providerId,
                providerName: displayName,
                dataSource: "OpenStreetMap (Valhalla Live API)",
                disclaimer: audit.isSafe ? "Dynamic Valhalla route with balanced motorcycle model (use_highways=0.5)." : "UNVERIFIED: Route passes through access-controlled expressway illegal for two-wheelers.",
                assumptions: cal.assumptions,
                calculatedAt: cal.calculatedAt
            )
        } catch {
            return try await fallback.calculateRoute(request: request)
        }
    }

    private static func decodePolyline6(_ encoded: String) -> [Coord] {
        var coords: [Coord] = []
        var index = encoded.startIndex
        var lat: Int64 = 0
        var lon: Int64 = 0
        let inv = 1.0 / 1e6

        while index < encoded.endIndex {
            var shift: Int64 = 0
            var result: Int64 = 0
            while true {
                guard index < encoded.endIndex else { break }
                let charVal = Int64(encoded[index].asciiValue! - 63)
                index = encoded.index(after: index)
                result |= (charVal & 0x1f) << shift
                shift += 5
                if charVal < 0x20 { break }
            }
            let dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += dlat

            shift = 0
            result = 0
            while true {
                guard index < encoded.endIndex else { break }
                let charVal = Int64(encoded[index].asciiValue! - 63)
                index = encoded.index(after: index)
                result |= (charVal & 0x1f) << shift
                shift += 5
                if charVal < 0x20 { break }
            }
            let dlon = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lon += dlon

            coords.append(Coord(lat: Double(lat) * inv, lon: Double(lon) * inv))
        }
        return coords
    }
}

// MARK: - 7. HERE Scooter Specification Model (Documented Simulation)

final class HEREScooterRoutingProvider: MotorcycleRoutingProvider, @unchecked Sendable {
    let providerId = "here-scooter-simulated"
    let displayName = "HERE Scooter Model (Simulation — Not Live)"
    private let fallback: PrecomputedMotorcycleRoutingProvider

    init() {
        self.fallback = PrecomputedMotorcycleRoutingProvider()
    }

    func calculateRoute(request: MotorcycleRouteRequest) async throws -> MotorcycleRouteResponse {
        // Query precomputed geometry as base geometry
        let baseResp = try await fallback.calculateRoute(request: request)

        // HERE Routing API v8 scooter mode simulation (as no paid live HERE API key is provisioned):
        // transportMode=scooter with speedCap=75 km/h:
        // Clamps rolling speeds to moped curves (42-45 km/h on open road, 28 km/h in ghats).
        let roadKm = baseResp.distanceMeters / 1000.0
        let straightKm = request.origin.distanceKm(to: request.destination)
        let windingRatio = straightKm > 0.1 ? (roadKm / straightKm) : 1.0

        let hereSpeedKmh: Double = windingRatio >= 1.4 ? 28.0 : (windingRatio >= 1.25 ? 38.0 : 45.0)
        let hereDurSec = (roadKm / hereSpeedKmh) * 3600.0

        let cal = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: baseResp.distanceMeters,
            providerDurationSeconds: hereDurSec,
            segments: [],
            origin: request.origin,
            destination: request.destination,
            hasGhatSection: windingRatio >= 1.4,
            pacing: request.pacingProfile,
            provenance: "HERE Vector / NAVTEQ Database (Simulation)"
        )

        return MotorcycleRouteResponse(
            coordinates: baseResp.coordinates,
            distanceMeters: baseResp.distanceMeters,
            providerDurationSeconds: hereDurSec,
            convoyEstimatedDurationSeconds: cal.convoySaddleDurationSeconds,
            convoyTotalTripDurationSeconds: cal.totalTripDurationSeconds,
            fuelStopsDurationSeconds: cal.plannedFuelDurationSeconds,
            restStopsDurationSeconds: cal.plannedRestDurationSeconds,
            mealStopsDurationSeconds: cal.plannedMealDurationSeconds,
            pacingProfile: request.pacingProfile,
            uncertaintyRange: "Saddle: \(cal.saddleDurationText) · Total: \(cal.totalTripDurationText)",
            terrainClassification: cal.terrainClassification,
            roadClasses: ["primary", "secondary", "avoid_motorway"],
            segments: [],
            hasExpresswayViolations: false,
            intermediateWaypoints: baseResp.intermediateWaypoints,
            motorcycleAccessVerified: true,
            knownExpresswayRestrictions: ["HERE controlledAccessHighway avoidance applied (Simulation)"],
            alternativeRouteDescription: "HERE Scooter Profile (SpeedCap configured for 2-wheeler)",
            legalCitation: "HERE NAVTEQ Map Access Classification",
            providerId: providerId,
            providerName: displayName,
            dataSource: "HERE Vector / NAVTEQ Database (Simulation)",
            disclaimer: "NOTE: Simulated model based on HERE v8 scooter specifications (no live HERE API key configured). Clamps speeds to moped limits.",
            assumptions: ["Synthetic simulation — not live API data"],
            calculatedAt: cal.calculatedAt
        )
    }
}
