//
//  CrewMapView.swift
//  ConvoyWatch Watch App
//
//  Shows nearby crew riders and their relative pack locations via an ultra-glanceable radar
//  and tactile rider list designed for motorcycle riding.
//

import SwiftUI

public struct CrewMapView: View {
    @ObservedObject var rideManager: RideManager = .shared
    public var isEmbedded: Bool = false
    
    // Zoom range: 500m or 1500m max scale
    @State private var maxRangeMeters: Double = 1000.0
    @State private var selectedRider: CrewRider? = nil
    
    public init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }
    
    public var body: some View {
        if isEmbedded {
            content
        } else {
            ScrollView {
                content
            }
        }
    }
    
    private var content: some View {
        VStack(spacing: 10) {
            // MARK: - Header & Scale Control
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(W.amber)
                    Text("CREW RADAR")
                        .font(.system(size: 11, weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            maxRangeMeters = (maxRangeMeters == 1000.0) ? 500.0 : 1000.0
                        }
                    } label: {
                        Text("\(Int(maxRangeMeters))m")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(W.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(W.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                
                // MARK: - Glanceable Formation Radar
                radarView
                    .frame(width: 160, height: 160)
                    .padding(.vertical, 2)
                
                // MARK: - Selected Rider Callout (if tapped)
                if let rider = selectedRider {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(rider.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(rider.role.rawValue)
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(W.amber)
                            }
                            Text("\(rider.speedKmH) km/h · 🔋 \(rider.batteryLevel)% · \(rider.status.rawValue)")
                                .font(.system(size: 10))
                                .foregroundStyle(W.secondary)
                        }
                        
                        Spacer()
                        
                        Text(rider.distanceLabel)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(rider.status.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(W.card, in: RoundedRectangle(cornerRadius: 10))
                }
                
                // MARK: - Rider Pack List
                VStack(spacing: 5) {
                    ForEach(rideManager.riders) { rider in
                        riderRow(rider)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
    
    // MARK: - Radar Canvas
    
    private var radarView: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2
            
            ZStack {
                // Background & Range Rings
                Circle()
                    .fill(Color(white: 0.08))
                
                // 50% distance ring
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    .frame(width: radius * 1.0, height: radius * 1.0)
                
                // Outer distance ring
                Circle()
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.2)
                    .frame(width: radius * 2 - 4, height: radius * 2 - 4)
                
                // Heading / Direction Line (UP = Forward)
                Path { p in
                    p.move(to: CGPoint(x: center.x, y: 10))
                    p.addLine(to: CGPoint(x: center.x, y: center.y - 12))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .foregroundStyle(Color.white.opacity(0.35))
                
                // Forward Arrow
                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(W.amber)
                    .position(x: center.x, y: 6)
                
                // Render Each Rider on Radar
                ForEach(rideManager.riders) { rider in
                    let pos = pointForRider(rider, center: center, maxRadius: radius - 14)
                    riderRadarNode(rider: rider)
                        .position(pos)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedRider = (selectedRider?.id == rider.id) ? nil : rider
                            }
                        }
                }
            }
        }
    }
    
    private func pointForRider(_ rider: CrewRider, center: CGPoint, maxRadius: CGFloat) -> CGPoint {
        if rider.role == .self {
            return center
        }
        
        // Relative distance normalized
        let clampedDist = max(-maxRangeMeters, min(maxRangeMeters, Double(rider.distanceMeters)))
        let fraction = CGFloat(clampedDist / maxRangeMeters)
        
        // Y axis: positive distance is ahead (up = negative Y), negative distance is behind (down = positive Y)
        let offsetY = -fraction * maxRadius
        
        // Slight X staggering based on bearing or role so riders don't overlap vertically
        let lateralStagger: CGFloat
        switch rider.name {
        case "Arjun": lateralStagger = 0
        case "Kabir": lateralStagger = -22
        case "Rika": lateralStagger = 20
        case "Dev": lateralStagger = -16
        case "Meera": lateralStagger = 8
        default: lateralStagger = 0
        }
        
        return CGPoint(x: center.x + lateralStagger, y: center.y + offsetY)
    }
    
    private func riderRadarNode(rider: CrewRider) -> some View {
        ZStack {
            if rider.role == .self {
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                Image(systemName: "location.north.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.black)
            } else if rider.isFallingBehind || rider.isSeparated {
                // Warning Pulse
                Circle()
                    .stroke(rider.status.color.opacity(0.5), lineWidth: 2)
                    .frame(width: 22, height: 22)
                
                Circle()
                    .fill(rider.status.color)
                    .frame(width: 14, height: 14)
                
                Text(String(rider.name.prefix(1)))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.black)
            } else {
                Circle()
                    .fill(W.card)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
                
                Text(String(rider.name.prefix(1)))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
    
    // MARK: - Rider Row Item
    
    private func riderRow(_ rider: CrewRider) -> some View {
        HStack(spacing: 7) {
            // Avatar / Icon
            if let avatar = rider.avatarImageName {
                SenderAvatar(image: avatar, size: 24)
            } else {
                ZStack {
                    Circle()
                        .fill(rider.role == .self ? Color.white : W.button)
                        .frame(width: 24, height: 24)
                    
                    Text(String(rider.name.prefix(1)))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(rider.role == .self ? Color.black : .white)
                }
            }
            
            // Name & Role
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(rider.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text(rider.role.rawValue)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(rider.role == .lead ? W.amber : W.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(W.button, in: RoundedRectangle(cornerRadius: 3))
                }
                
                Text("\(rider.speedKmH) km/h")
                    .font(.system(size: 10))
                    .foregroundStyle(W.secondary)
            }
            
            Spacer()
            
            // Relative Distance Badge
            VStack(alignment: .trailing, spacing: 1) {
                Text(rider.distanceLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(rider.isFallingBehind ? W.amber : (rider.isSeparated ? W.red : .white))
                
                if rider.isFallingBehind {
                    Text("BEHIND")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(W.amber)
                } else if rider.isSeparated {
                    Text("LOST")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(W.red)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(W.card, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                selectedRider = rider
            }
        }
    }
}

#Preview {
    CrewMapView()
}
