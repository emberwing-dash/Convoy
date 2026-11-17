import SwiftUI
import CoreLocation

// MARK: - Watch Home View
// Modern Apple Watch Home Screen:
// 1. User profile header linked via Supabase / Phone sync (avatar, display name, handle, online status)
// 2. Watch Live Location card with live lat/lon, speed, accuracy, and interactive broadcast button
// 3. Upcoming Rides section loaded from Supabase / RideManager
// 4. Quick Action to launch live Ride Telemetry

public struct WatchHomeView: View {
    public var onStartRide: () -> Void
    public var onOpenProfile: () -> Void
    public var onOpenWhisper: () -> Void
    
    @ObservedObject private var rideManager = RideManager.shared
    @ObservedObject private var locationManager = WatchLocationManager.shared
    @ObservedObject private var supabase = WatchSupabaseService.shared
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
    
    @State private var isBroadcastingNow: Bool = false
    
    public init(
        onStartRide: @escaping () -> Void,
        onOpenProfile: @escaping () -> Void,
        onOpenWhisper: @escaping () -> Void
    ) {
        self.onStartRide = onStartRide
        self.onOpenProfile = onOpenProfile
        self.onOpenWhisper = onOpenWhisper
    }
    
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // MARK: - 1. User Profile Header
                HStack(alignment: .center, spacing: 8) {
                    Button(action: onOpenProfile) {
                        ZStack(alignment: .bottomTrailing) {
                            if let img = rideManager.userAvatarImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [W.amber, W.red], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 32, height: 32)
                                    Text(String(rideManager.userDisplayName.prefix(1)).uppercased())
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                            }
                            
                            // Online Green Status Dot
                            Circle()
                                .fill(W.green)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        }
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(greeting.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(W.secondary)
                        
                        Text(rideManager.userDisplayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        if !rideManager.userHandle.isEmpty {
                            Text("@\(rideManager.userHandle)")
                                .font(.system(size: 9))
                                .foregroundStyle(W.amber)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Whisper Voice Button
                    Button(action: onOpenWhisper) {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(W.cyan)
                            .frame(width: 28, height: 28)
                            .background(Color(white: 0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                
                // MARK: - 2. Watch Live Location Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0))
                        
                        Text("WATCH LIVE LOCATION")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(W.secondary)
                        
                        Spacer()
                        
                        if locationManager.isStreamingLocation {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(W.green)
                                    .frame(width: 5, height: 5)
                                Text("LIVE")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(W.green)
                            }
                        }
                    }
                    
                    if let loc = locationManager.currentLocation {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("COORDINATES")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(W.secondary)
                                Text(String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("SPEED")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(W.secondary)
                                Text("\(Int(max(0, loc.speed * 3.6))) KM/H")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(W.amber)
                            }
                        }
                    } else {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                            Text("Acquiring Watch GPS...")
                                .font(.system(size: 10))
                                .foregroundStyle(W.secondary)
                        }
                    }
                    
                    // Share Location to iPhone / Convoy Button
                    Button {
                        isBroadcastingNow = true
                        locationManager.startLiveLocationUpdates()
                        locationManager.broadcastCurrentLocationNow()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isBroadcastingNow = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isBroadcastingNow ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isBroadcastingNow ? W.green : W.cyan)
                            Text(isBroadcastingNow ? "Location Broadcasted" : "Broadcast Location")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(W.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                
                // MARK: - 3. Quick Action: Live Ride Telemetry
                Button(action: onStartRide) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(W.amber.opacity(0.2))
                                .frame(width: 28, height: 28)
                            Image(systemName: "gauge.with.needle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(W.amber)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("LIVE CONVOY RIDE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Speed, formation & crew alerts")
                                .font(.system(size: 9))
                                .foregroundStyle(W.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(W.secondary)
                    }
                    .padding(10)
                    .background(Color(red: 0.16, green: 0.12, blue: 0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(W.amber.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                // MARK: - 4. Upcoming Rides Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("UPCOMING RIDES")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(W.secondary)
                        
                        Spacer()
                        
                        if supabase.isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                    }
                    
                    ForEach(supabase.upcomingRides) { ride in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(ride.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text("\(ride.ridersCount) riders")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(W.cyan)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(W.cyan.opacity(0.15), in: Capsule())
                            }
                            
                            HStack(spacing: 8) {
                                HStack(spacing: 3) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(W.amber)
                                    Text(ride.startLocation)
                                        .font(.system(size: 9))
                                        .foregroundStyle(W.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 3) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(W.secondary)
                                    Text(ride.departsAt.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 9))
                                        .foregroundStyle(W.secondary)
                                }
                            }
                        }
                        .padding(9)
                        .background(W.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8))
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            await supabase.fetchUpcomingRides()
        }
    }
}
